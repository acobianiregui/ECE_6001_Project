import SwiftUI

struct LearningProgressView: View {
    @Environment(LearningStore.self) private var learning
    let openLesson: (Lesson) -> Void
    let review: () -> Void
    @State private var resetting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                StudyHeading(eyebrow: "Evidence of your effort", title: "See how far you’ve come.", subtitle: "Track lesson practice, revisit ideas, and keep your own study journal.")
                HStack(spacing: 14) {
                    MetricTile(value: "\(learning.completedCount)", label: "Lessons completed", symbol: "checkmark.seal")
                    MetricTile(value: "\(learning.practicedQuestions)", label: "Questions attempted", symbol: "questionmark.bubble", tint: .indigo)
                    MetricTile(value: "\(learning.studyDays.count)", label: "Days with practice", symbol: "calendar", tint: .orange)
                }
                StudyCard(tint: .mint) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("Your three learning paths").font(.headline)
                            Spacer()
                            Text("\(Int(learning.completionFraction * 100))%").font(.headline).foregroundStyle(LearningStyle.teal)
                        }
                        ForEach(LearningTrack.allCases) { track in
                            let lessons = Curriculum.lessons.filter { $0.track == track }
                            let count = lessons.filter(learning.isComplete).count
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Label(track.title, systemImage: track.symbol); Spacer(); Text("\(count)/\(lessons.count)").foregroundStyle(.secondary) }.font(.subheadline)
                                ProgressView(value: Double(count), total: Double(max(1, lessons.count))).tint(track.tint)
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    milestone("First connection", detail: "Complete your first lesson", symbol: "sparkles", earned: learning.completedCount > 0)
                    milestone("Circuit investigator", detail: "Finish the guided circuit lab", symbol: "bolt.fill", earned: learning.activities["circuit"] != nil)
                    milestone("Spatial thinker", detail: "Pass a CAD design challenge", symbol: "cube.fill", earned: learning.activities["cad"] != nil)
                }
                if !learning.dueQuestions.isEmpty {
                    StudyCard(tint: .orange) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(learning.dueQuestions.count) questions ready for review").font(.headline)
                                Text("Correct recall when due returns after 1, 3, 7, then 14 days. Immediate repeats keep the existing date. Missed ideas stay available.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Review now", action: review).buttonStyle(.borderedProminent)
                        }
                    }
                }
                Text("Lesson record").font(.title3.bold())
                ForEach(Curriculum.lessons) { lesson in
                    Button { openLesson(lesson) } label: { LessonRow(lesson: lesson) }.buttonStyle(.plain)
                }
                StudyCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Your study journal").font(.headline)
                        Text("Share your notes and practice results as text. Learning records are stored locally and describe practice inside this app.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            ShareLink(item: learning.exportText) { Label("Share journal", systemImage: "square.and.arrow.up") }
                            Spacer()
                            Button("Reset learning progress", role: .destructive) { resetting = true }.font(.caption)
                        }
                    }
                }
            }.padding(30).frame(maxWidth: 1150)
        }
        .navigationTitle("My progress").toolbarTitleDisplayMode(.inline)
        .confirmationDialog("Reset your learning progress?", isPresented: $resetting, titleVisibility: .visible) {
            Button("Reset progress and notes", role: .destructive) { learning.resetLearningProgress() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes lesson scores, bookmarks, notes, and activity records on this device. Your CAD designs stay saved.") }
    }
    private func milestone(_ title: String, detail: String, symbol: String, earned: Bool) -> some View {
        StudyCard(tint: earned ? .mint : .white) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: earned ? symbol : "lock").font(.title2).foregroundStyle(earned ? LearningStyle.teal : .secondary)
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Text(earned ? "Earned" : "In progress").font(.caption2.weight(.semibold)).foregroundStyle(earned ? LearningStyle.teal : .secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReviewItem: Identifiable {
    var id: String { question.id }
    let lesson: Lesson
    let question: PracticeQuestion
}

struct ReviewSessionView: View {
    @Environment(LearningStore.self) private var learning
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReviewItem] = []
    @State private var loaded = false
    @State private var index = 0
    @State private var selected: Int?
    @State private var submitted: Int?
    @State private var showHint = false
    @State private var correct = 0
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if index < items.count {
                        let item = items[index]
                        TrackBadge(track: item.lesson.track)
                        Text("Bring it back from memory.").font(.title2.bold())
                        HStack {
                            Text(item.lesson.title).font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(index + 1)/\(items.count)").font(.caption)
                        }
                        ProgressView(value: Double(index), total: Double(items.count))
                        PracticeQuestionCard(question: item.question, selected: $selected, submitted: submitted, showHint: $showHint) { answer in
                            guard submitted == nil else { return }
                            submitted = answer
                            if answer == item.question.correctIndex { correct += 1 }
                            learning.review(answer, question: item.question, lesson: item.lesson)
                        }
                        if submitted != nil {
                            Button(index + 1 == items.count ? "Finish review" : "Next idea", systemImage: "arrow.right") {
                                index += 1
                                selected = nil
                                submitted = nil
                                showHint = false
                            }.buttonStyle(.borderedProminent)
                        }
                    } else if loaded {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 50)).foregroundStyle(LearningStyle.teal)
                        Text(items.isEmpty ? "You’re up to date." : "Review complete.").font(.title.bold())
                        Text(items.isEmpty ? "Practice a lesson to begin building your review queue." : "\(correct) of \(items.count) recalled correctly. Missed ideas remain available, and correct answers are scheduled for later.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                }.padding(30)
            }
            .navigationTitle("Quick review").toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .tint(LearningStyle.teal)
        .onAppear {
            guard !loaded else { return }
            items = Array(learning.dueQuestions.prefix(6)).map { ReviewItem(lesson: $0.lesson, question: $0.question) }
            loaded = true
        }
    }
}

struct GlossaryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(LearningTrack.allCases) { track in
                    let terms = Curriculum.glossary.filter { $0.track == track && (search.isEmpty || "\($0.term) \($0.definition)".localizedCaseInsensitiveContains(search)) }
                    if !terms.isEmpty {
                        Section(track.title) {
                            ForEach(terms) { term in
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(term.term).font(.headline)
                                    Text(term.definition).font(.subheadline).foregroundStyle(.secondary)
                                }.padding(.vertical, 6)
                            }
                        }
                    }
                }
                if search.isEmpty {
                    Section("Further reading") {
                        ForEach(Curriculum.references) { reference in
                            if let url = URL(string: reference.url) {
                                Link(destination: url) { Label(reference.title, systemImage: "arrow.up.right.square").font(.subheadline) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find a word or idea")
            .navigationTitle("Engineering glossary").toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
