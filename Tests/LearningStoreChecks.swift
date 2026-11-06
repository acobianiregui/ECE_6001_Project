import Foundation

private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
    func advance(days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date)!
    }
}

@main
struct LearningStoreTests {
    static func main() {
        let tests = TestRun()
        tests.run()
    }
}

private final class TestRun {
    private var count = 0
    private let calendar = Calendar.current
    private let archiveKey = "AVPLearn.learning.v1"

    private func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
        count += 1
        guard condition() else {
            print("FAIL [\(count)]: \(description)")
            exit(1)
        }
    }

    private func date(daysAfter start: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: start)!
    }

    func run() {
        let suite = "AVPLearn.LearningStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let initialDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        let clock = TestClock(initialDate)
        let store = LearningStore(defaults: defaults, now: { clock.date })
        let lesson = Curriculum.lessons[0]
        let first = lesson.practice[0]
        let wrong = (first.correctIndex + 1) % first.options.count
        let foreign = Curriculum.lessons[1].practice[0]

        expect(store.completedCount == 0, "Fresh store has no completed lessons")
        expect(store.completionFraction == 0, "Fresh completion fraction is zero")
        expect(store.dueQuestions.isEmpty, "Unseen questions are not marked due")
        expect(store.nextLesson?.id == lesson.id, "First lesson is recommended initially")
        store.submit(-1, for: first, in: lesson)
        store.submit(first.options.count, for: first, in: lesson)
        store.submit(0, for: foreign, in: lesson)
        expect(store.progress(for: lesson).draftAnswers.isEmpty, "Invalid options and foreign questions are rejected")
        expect(store.practicedQuestions == 0, "Rejected submissions do not create practice records")

        store.open(lesson)
        store.toggleBookmark(lesson)
        store.setNotes("Prediction: current stays fixed when voltage and resistance both double.", for: lesson)
        let reopened = LearningStore(defaults: defaults, now: { clock.date })
        expect(reopened.lastLessonID == lesson.id, "Last-opened lesson persists")
        expect(reopened.progress(for: lesson).bookmarked, "Bookmark persists")
        expect(reopened.progress(for: lesson).notes.hasPrefix("Prediction:"), "Notes persist")
        store.setNotes(String(repeating: "a", count: 20_100), for: lesson)
        expect(store.progress(for: lesson).notes.count == 20_000, "Notes are bounded to the documented limit")
        store.setNotes("A saved reflection.", for: lesson)

        store.submit(first.correctIndex, for: first, in: lesson)
        let firstProgress = store.progress(for: lesson)
        expect(firstProgress.questions[first.id]?.attempts == 1, "First submission records one attempt")
        expect(firstProgress.questions[first.id]?.correct == true, "Correct submission is recorded")
        expect(firstProgress.questions[first.id]?.streak == 1, "First correct answer starts question streak")
        expect(firstProgress.questions[first.id]?.due == date(daysAfter: initialDate, 1), "Correct answer is scheduled one day later")
        expect(store.dueQuestions.isEmpty, "Correct answer is not due immediately")
        store.submit(wrong, for: first, in: lesson)
        expect(store.progress(for: lesson).questions[first.id]?.attempts == 1, "Duplicate submission is idempotent in a run")
        expect(store.progress(for: lesson).draftAnswers[first.id] == first.correctIndex, "Duplicate submission cannot replace an answer")
        expect(store.progress(for: lesson).quizRuns == 0, "A partial run is not counted as a finished quiz")
        let partialReload = LearningStore(defaults: defaults, now: { clock.date })
        expect(partialReload.progress(for: lesson).draftAnswers.count == 1, "Partial quiz persists across reload")
        expect(partialReload.progress(for: lesson).draftAnswers[first.id] == first.correctIndex, "Partial quiz preserves the actual answer")
        expect(partialReload.progress(for: lesson).questions[first.id]?.attempts == 1, "Partial quiz preserves attempt count")

        for question in lesson.practice.dropFirst() {
            store.submit(question.correctIndex, for: question, in: lesson)
        }
        expect(store.progress(for: lesson).quizRuns == 1, "Finishing all questions counts one quiz run")
        expect(store.progress(for: lesson).bestCorrect == 3, "Perfect run records three correct answers")
        expect(!store.isComplete(lesson), "A perfect quiz alone does not mark unread lesson complete")
        store.markRead(lesson)
        expect(store.isComplete(lesson), "Reading plus all-correct run completes lesson")
        expect(store.completedCount == 1, "Completed count reflects exactly one lesson")
        expect(abs(store.completionFraction - 1.0 / 9.0) < 0.00001, "Completion fraction uses curriculum count")
        expect(store.nextLesson?.id == Curriculum.lessons[1].id, "Next lesson advances after completion")
        store.submit(first.correctIndex, for: first, in: lesson)
        expect(store.progress(for: lesson).quizRuns == 1, "Duplicate submission after completion does not add another run")

        store.restartQuiz(lesson)
        expect(store.progress(for: lesson).draftAnswers.isEmpty, "Restart clears only the current answer draft")
        expect(store.progress(for: lesson).bestCorrect == 3, "Restart retains best previous result")
        for question in lesson.practice {
            store.submit((question.correctIndex + 1) % question.options.count, for: question, in: lesson)
        }
        expect(store.progress(for: lesson).quizRuns == 2, "Second completed run increments the run count")
        expect(store.progress(for: lesson).bestCorrect == 3, "A worse run cannot lower best score")
        expect(store.isComplete(lesson), "Completion reflects the retained best result")
        expect(store.dueQuestions.count == 3, "Incorrect answers are due immediately")
        expect(store.practicedQuestions == 3, "Repeated attempts do not inflate distinct-question count")
        expect(store.progress(for: lesson).questions[first.id]?.streak == 0, "Incorrect answer resets question streak")

        store.review(first.correctIndex, question: first, lesson: lesson)
        expect(store.progress(for: lesson).questions[first.id]?.attempts == 3, "Review adds one real attempt")
        expect(store.progress(for: lesson).questions[first.id]?.streak == 1, "Correct review restarts streak after a mistake")
        expect(store.progress(for: lesson).questions[first.id]?.due == date(daysAfter: clock.date, 1), "First correct review is due tomorrow")
        expect(store.dueQuestions.count == 2, "Reviewed correct question leaves the current due list")
        clock.advance(days: 1)
        expect(store.dueQuestions.count == 3, "Question becomes due at the scheduled time")
        store.review(first.correctIndex, question: first, lesson: lesson)
        expect(store.progress(for: lesson).questions[first.id]?.streak == 2, "Consecutive correct review increments streak")
        expect(store.progress(for: lesson).questions[first.id]?.due == date(daysAfter: clock.date, 3), "Second consecutive correct answer schedules three days")
        clock.advance(days: 3)
        store.review(first.correctIndex, question: first, lesson: lesson)
        expect(store.progress(for: lesson).questions[first.id]?.due == date(daysAfter: clock.date, 7), "Third consecutive correct answer schedules seven days")
        clock.advance(days: 7)
        store.review(first.correctIndex, question: first, lesson: lesson)
        expect(store.progress(for: lesson).questions[first.id]?.due == date(daysAfter: clock.date, 14), "Fourth consecutive correct answer schedules fourteen days")
        clock.advance(days: 14)
        store.review(first.correctIndex, question: first, lesson: lesson)
        expect(store.progress(for: lesson).questions[first.id]?.due == date(daysAfter: clock.date, 14), "Review interval caps at fourteen days")
        let beforeInvalidReview = store.progress(for: lesson).questions[first.id]!.attempts
        store.review(-1, question: first, lesson: lesson)
        store.review(first.options.count, question: first, lesson: lesson)
        store.review(0, question: foreign, lesson: lesson)
        expect(store.progress(for: lesson).questions[first.id]?.attempts == beforeInvalidReview, "Invalid reviews do not add attempts")
        expect(store.progress(for: lesson).questions[foreign.id] == nil, "Foreign review question is rejected")
        store.review(wrong, question: first, lesson: lesson)
        expect(store.progress(for: lesson).questions[first.id]?.streak == 0, "Wrong review resets the correct streak")
        expect(store.progress(for: lesson).questions[first.id]?.due == clock.date, "Wrong review reschedules immediately")
        expect(store.progress(for: lesson).bestCorrect == 3, "Review does not rewrite best full-quiz result")

        store.recordActivity("circuit", score: 120)
        expect(store.activities["circuit"]?.bestScore == 100, "Activity score is clamped to 100")
        store.recordActivity("circuit", score: 20)
        expect(store.activities["circuit"]?.bestScore == 100, "Lower activity score retains best")
        expect(store.activities["circuit"]?.completions == 2, "Activity counts completed attempts")
        expect(store.activities["circuit"]?.lastCompleted == clock.date, "Activity records injected time")
        store.recordActivity("cad", score: -10)
        expect(store.activities["cad"]?.bestScore == 0, "Negative activity score clamps to zero")
        store.recordActivity("cad", score: 75)
        expect(store.activities["cad"]?.bestScore == 75, "Later improved activity score becomes best")
        let afterActivityReload = LearningStore(defaults: defaults, now: { clock.date })
        expect(afterActivityReload.activities["circuit"]?.completions == 2, "Activity count persists")
        expect(afterActivityReload.activities["cad"]?.bestScore == 75, "Activity best score persists")
        expect(store.exportText.contains("A saved reflection."), "Journal export includes actual saved notes")
        expect(store.exportText.contains("Best practice: 3/3"), "Journal export includes best practice score")

        store.resetLearningProgress()
        expect(store.lessons.isEmpty && store.activities.isEmpty && store.studyDays.isEmpty, "Reset clears all learning model collections")
        expect(store.lastLessonID == nil, "Reset clears resume lesson")
        expect(defaults.object(forKey: archiveKey) == nil, "Reset removes the archive from defaults")
        let emptyReload = LearningStore(defaults: defaults, now: { clock.date })
        expect(emptyReload.completedCount == 0 && emptyReload.activities.isEmpty, "Reload after reset stays empty")

        clock.date = initialDate
        let streakStore = LearningStore(defaults: defaults, now: { clock.date })
        streakStore.markRead(lesson)
        expect(streakStore.streak == 1, "First active day yields a one-day study streak")
        streakStore.recordActivity("circuit", score: 80)
        expect(streakStore.streak == 1 && streakStore.studyDays.count == 1, "Multiple actions on one day do not inflate day streak")
        clock.advance(days: 1)
        streakStore.markRead(lesson)
        expect(streakStore.streak == 2, "Activity on following day extends streak")
        clock.advance(days: 1)
        expect(streakStore.streak == 2, "Yesterday's streak remains available until today's activity")
        clock.advance(days: 1)
        expect(streakStore.streak == 0, "A full missed day breaks study streak")
        streakStore.markRead(lesson)
        expect(streakStore.streak == 1, "Activity after gap starts a new streak")
        let streakReload = LearningStore(defaults: defaults, now: { clock.date })
        expect(streakReload.streak == 1, "Study-day records and computed streak survive reload")

        defaults.set(Data("not valid JSON".utf8), forKey: archiveKey)
        let malformed = LearningStore(defaults: defaults, now: { clock.date })
        expect(malformed.lessons.isEmpty && malformed.activities.isEmpty, "Malformed archive loads safely as empty")
        malformed.markRead(lesson)
        expect(defaults.data(forKey: archiveKey) != Data("not valid JSON".utf8), "Normal progress replaces a malformed archive")
        let validArchive = defaults.data(forKey: archiveKey)!
        var unsupportedArchive = try! JSONSerialization.jsonObject(with: validArchive) as! [String: Any]
        unsupportedArchive["version"] = 999
        defaults.set(try! JSONSerialization.data(withJSONObject: unsupportedArchive), forKey: archiveKey)
        let unsupported = LearningStore(defaults: defaults, now: { clock.date })
        expect(unsupported.lessons.isEmpty, "Unsupported archive version loads safely as empty")

        let quickSuite = "AVPLearn.ImmediateRecallTests.\(UUID().uuidString)"
        let quickDefaults = UserDefaults(suiteName: quickSuite)!
        defer { quickDefaults.removePersistentDomain(forName: quickSuite) }
        let quickStore = LearningStore(defaults: quickDefaults, now: { initialDate })
        for _ in 0..<4 {
            quickStore.restartQuiz(lesson)
            quickStore.submit(first.correctIndex, for: first, in: lesson)
        }
        expect(quickStore.progress(for: lesson).questions[first.id]?.attempts == 4, "Immediate retries count actual attempts")
        expect(quickStore.progress(for: lesson).questions[first.id]?.streak == 1, "Immediate repeats do not count as spaced recall")
        expect(quickStore.progress(for: lesson).questions[first.id]?.due == date(daysAfter: initialDate, 1), "Immediate repeats preserve tomorrow's review")
        quickStore.review(first.correctIndex, question: first, lesson: lesson)
        expect(quickStore.progress(for: lesson).questions[first.id]?.streak == 1, "Early review also preserves the spaced interval")

        expect(Curriculum.lessons.count == 9, "Curriculum has nine lessons")
        expect(Set(Curriculum.lessons.map(\.id)).count == 9, "Lesson IDs are unique")
        for track in LearningTrack.allCases {
            expect(Curriculum.lessons.filter { $0.track == track }.count == 3, "Each track contains three lessons")
        }
        let questions = Curriculum.lessons.flatMap(\.practice)
        expect(questions.count == 27, "Curriculum includes 27 practice questions")
        expect(Set(questions.map(\.id)).count == 27, "Question IDs are globally unique")
        for item in Curriculum.lessons {
            expect(item.practice.count == 3 && item.sections.count == 2, "Every lesson has three questions and two concise sections")
            expect((2...3).contains(item.example.steps.count), "Worked examples have two or three steps")
        }
        for question in questions {
            expect(question.options.indices.contains(question.correctIndex), "Every correct index points to an answer")
            expect(Set(question.options).count == question.options.count, "Every question has distinct answer choices")
            expect(!question.hint.isEmpty && !question.explanation.isEmpty, "Every question has a hint and explanation")
        }
        print("PASS: \(count) learning-store and curriculum checks using actual application sources and isolated defaults.")
    }
}
