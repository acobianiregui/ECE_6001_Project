import Foundation
import Observation

struct QuestionProgress: Codable {
    var attempts = 0
    var correct = false
    var streak = 0
    var due = Date.distantPast
}

struct LessonProgress: Codable {
    var hasRead = false
    var bookmarked = false
    var notes = ""
    var draftAnswers: [String: Int] = [:]
    var questions: [String: QuestionProgress] = [:]
    var bestCorrect = 0
    var quizRuns = 0
}

struct ActivityProgress: Codable {
    var completions = 0
    var bestScore = 0
    var lastCompleted = Date.distantPast
}

private struct StudyArchive: Codable {
    var version = 1
    var lessons: [String: LessonProgress] = [:]
    var activities: [String: ActivityProgress] = [:]
    var days: Set<String> = []
    var lastLessonID: String?
}

/// Device-local progress. Practice records describe app performance, not lab certification.
@Observable
final class LearningStore {
    private(set) var lessons: [String: LessonProgress] = [:]
    private(set) var activities: [String: ActivityProgress] = [:]
    private(set) var studyDays: Set<String> = []
    private(set) var lastLessonID: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private static let key = "AVPLearn.learning.v1"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.key),
           let archive = try? JSONDecoder().decode(StudyArchive.self, from: data), archive.version == 1 {
            lessons = archive.lessons
            activities = archive.activities
            studyDays = archive.days
            lastLessonID = archive.lastLessonID
        }
    }

    func progress(for lesson: Lesson) -> LessonProgress { lessons[lesson.id] ?? LessonProgress() }
    func isComplete(_ lesson: Lesson) -> Bool {
        let p = progress(for: lesson)
        return p.hasRead && !lesson.practice.isEmpty && p.bestCorrect == lesson.practice.count
    }
    var completedCount: Int { Curriculum.lessons.filter(isComplete).count }
    var completionFraction: Double { Double(completedCount) / Double(max(1, Curriculum.lessons.count)) }
    var practicedQuestions: Int { lessons.values.reduce(0) { $0 + $1.questions.count } }
    var nextLesson: Lesson? {
        if let id = lastLessonID, let lesson = Curriculum.lessons.first(where: { $0.id == id }), !isComplete(lesson) {
            return lesson
        }
        return Curriculum.lessons.first { !isComplete($0) }
    }
    var dueQuestions: [(lesson: Lesson, question: PracticeQuestion)] {
        Curriculum.lessons.flatMap { lesson in
            lesson.practice.compactMap { question in
                guard let p = lessons[lesson.id]?.questions[question.id], p.due <= now() else { return nil }
                return (lesson: lesson, question: question)
            }
        }
    }
    var streak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        var date = studyDays.contains(dayKey(today)) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        var result = 0
        while studyDays.contains(dayKey(date)) {
            result += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return result
    }

    func open(_ lesson: Lesson) {
        lastLessonID = lesson.id
        persist()
    }
    func markRead(_ lesson: Lesson) {
        var p = progress(for: lesson)
        p.hasRead = true
        lessons[lesson.id] = p
        touch()
    }
    func toggleBookmark(_ lesson: Lesson) {
        var p = progress(for: lesson)
        p.bookmarked.toggle()
        lessons[lesson.id] = p
        persist()
    }
    func setNotes(_ notes: String, for lesson: Lesson) {
        var p = progress(for: lesson)
        p.notes = String(notes.prefix(20_000))
        lessons[lesson.id] = p
        persist()
    }

    /// One submission per question per run; a new run keeps the best previous result.
    func submit(_ index: Int, for question: PracticeQuestion, in lesson: Lesson) {
        guard lesson.practice.contains(where: { $0.id == question.id }), question.options.indices.contains(index) else { return }
        var p = progress(for: lesson)
        guard p.draftAnswers[question.id] == nil else { return }
        p.draftAnswers[question.id] = index
        p.questions[question.id] = updatedQuestion(p.questions[question.id], correct: index == question.correctIndex)
        if lesson.practice.allSatisfy({ p.draftAnswers[$0.id] != nil }) {
            let correct = lesson.practice.filter { p.draftAnswers[$0.id] == $0.correctIndex }.count
            p.bestCorrect = max(p.bestCorrect, correct)
            p.quizRuns += 1
        }
        lessons[lesson.id] = p
        touch()
    }
    func restartQuiz(_ lesson: Lesson) {
        var p = progress(for: lesson)
        p.draftAnswers = [:]
        lessons[lesson.id] = p
        persist()
    }
    func review(_ index: Int, question: PracticeQuestion, lesson: Lesson) {
        guard question.options.indices.contains(index), lesson.practice.contains(where: { $0.id == question.id }) else { return }
        var p = progress(for: lesson)
        p.questions[question.id] = updatedQuestion(p.questions[question.id], correct: index == question.correctIndex)
        lessons[lesson.id] = p
        touch()
    }
    func recordActivity(_ id: String, score: Int) {
        var p = activities[id] ?? ActivityProgress()
        p.completions += 1
        p.bestScore = max(p.bestScore, min(100, max(0, score)))
        p.lastCompleted = now()
        activities[id] = p
        touch()
    }
    func resetLearningProgress() {
        lessons = [:]
        activities = [:]
        studyDays = []
        lastLessonID = nil
        defaults.removeObject(forKey: Self.key)
    }
    var exportText: String {
        var lines = ["AVP Learn — study journal", "Completed lessons: \(completedCount)/\(Curriculum.lessons.count)", ""]
        for lesson in Curriculum.lessons {
            let p = progress(for: lesson)
            guard p.hasRead || p.quizRuns > 0 || !p.notes.isEmpty else { continue }
            lines += [lesson.title, "Best practice: \(p.bestCorrect)/\(lesson.practice.count)"]
            if !p.notes.isEmpty { lines.append(p.notes) }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
    private func updatedQuestion(_ previous: QuestionProgress?, correct: Bool) -> QuestionProgress {
        var record = previous ?? QuestionProgress()
        let date = now()
        let wasDue = record.due <= date
        let previouslyCorrect = record.correct
        record.attempts += 1
        record.correct = correct
        if !correct {
            record.streak = 0
            record.due = date
        } else if previous == nil || wasDue || !previouslyCorrect {
            record.streak += 1
            let interval = [1, 3, 7, 14][min(record.streak - 1, 3)]
            record.due = Calendar.current.date(byAdding: .day, value: interval, to: date) ?? date
        }
        // Immediate repeats still count as attempts, but don't replace spaced recall.
        return record
    }
    private func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    private func touch() {
        studyDays.insert(dayKey(now()))
        persist()
    }
    private func persist() {
        let archive = StudyArchive(lessons: lessons, activities: activities, days: studyDays, lastLessonID: lastLessonID)
        if let data = try? JSONEncoder().encode(archive) { defaults.set(data, forKey: Self.key) }
    }
}
