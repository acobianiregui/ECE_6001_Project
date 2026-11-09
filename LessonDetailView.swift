import SwiftUI

struct LessonDetailView: View {
    enum Page: String, CaseIterable { case learn = "Learn", practice = "Practice", notes = "Notes" }
    @Environment(LearningStore.self) private var learning
    @Environment(\.dismiss) private var dismiss
    let lesson: Lesson
    let openActivity: (LearningActivity) -> Void
    @State private var page = Page.learn
    @State private var exampleExpanded = false
    @State private var questionIndex = 0
    @State private var selected: Int?
    @State private var showHint = false
    private var progress: LessonProgress { learning.progress(for: lesson) }
    private var finished: Bool { lesson.practice.allSatisfy { progress.draftAnswers[$0.id] != nil } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Lesson section", selection: $page) {
                    ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 28).padding(.bottom, 18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch page {
                        case .learn: reading
                        case .practice: practice
                        case .notes: notes
                        }
                    }.padding(28).frame(maxWidth: 860, alignment: .leading)
                }
            }
            .navigationTitle(lesson.title).toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { learning.toggleBookmark(lesson) } label: {
                        Image(systemName: progress.bookmarked ? "bookmark.fill" : "bookmark")
                    }.accessibilityLabel(progress.bookmarked ? "Remove saved lesson" : "Save lesson")
                }
            }
        }
        .tint(lesson.track.tint)
        .onAppear {
            learning.open(lesson)
            questionIndex = lesson.practice.firstIndex { progress.draftAnswers[$0.id] == nil } ?? 0
        }
    }
    private var reading: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { TrackBadge(track: lesson.track); Spacer(); Label("\(lesson.minutes) min", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
            Text(lesson.summary).font(.title3.weight(.medium))
            StudyCard(tint: lesson.track.tint) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Your goal", systemImage: "scope").font(.subheadline.bold()).foregroundStyle(lesson.track.tint)
                    Text(lesson.objective).font(.subheadline)
                }
            }
            ConceptDiagramView(visual: lesson.visual, tint: lesson.track.tint)
            ForEach(lesson.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title).font(.headline)
                    Text(section.text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let equation = lesson.equation {
                StudyCard(tint: lesson.track.tint) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(equation.name).font(.headline)
                        Text(equation.expression).font(.system(size: 26, weight: .medium, design: .monospaced)).minimumScaleFactor(0.6)
                        Text(equation.symbols).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            StudyCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(lesson.example.title, systemImage: "pencil.and.outline").font(.headline)
                    Text(lesson.example.prompt).font(.subheadline)
                    DisclosureGroup("See the worked example", isExpanded: $exampleExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(lesson.example.steps.enumerated()), id: \.offset) { step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(step.offset + 1)").font(.caption.bold()).foregroundStyle(lesson.track.tint)
                                    Text(step.element).font(.subheadline)
                                }
                            }
                            Text(lesson.example.takeaway).font(.subheadline.weight(.medium)).foregroundStyle(lesson.track.tint)
                        }.padding(.top, 12)
                    }.font(.subheadline)
                }
            }
            activityCard
            Button {
                learning.markRead(lesson)
                page = .practice
            } label: { Label(progress.hasRead ? "Go to practice" : "I’ve read this · Start practice", systemImage: "arrow.right") }
                .buttonStyle(.borderedProminent)
            Text("Completion is earned by reading and answering all three practice questions correctly in a run. You can revisit every lesson freely.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
    @ViewBuilder private var practice: some View {
        if finished {
            let correct = lesson.practice.filter { progress.draftAnswers[$0.id] == $0.correctIndex }.count
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: correct == lesson.practice.count ? "checkmark.seal.fill" : "arrow.clockwise.circle.fill")
                    .font(.system(size: 46)).foregroundStyle(lesson.track.tint)
                Text(correct == lesson.practice.count ? "You connected the ideas." : "A useful place to practice.").font(.title2.bold())
                Text("This run: \(correct) of \(lesson.practice.count) correct · Best: \(progress.bestCorrect) of \(lesson.practice.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !progress.hasRead {
                    Text("Read the lesson and its example to finish this learning step.").font(.subheadline)
                    Button("Read the lesson") { page = .learn }
                }
                ForEach(lesson.practice) { question in
                    let right = progress.draftAnswers[question.id] == question.correctIndex
                    StudyCard(tint: right ? .green : .orange) {
                        VStack(alignment: .leading, spacing: 9) {
                            Label(question.prompt, systemImage: right ? "checkmark.circle" : "arrow.uturn.backward.circle").font(.subheadline.bold())
                            Text(question.explanation).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Try a fresh run", systemImage: "arrow.clockwise") {
                    learning.restartQuiz(lesson)
                    questionIndex = 0
                    selected = nil
                    showHint = false
                }.buttonStyle(.borderedProminent)
                activityCard
            }
        } else if lesson.practice.indices.contains(questionIndex) {
            let question = lesson.practice[questionIndex]
            let submitted = progress.draftAnswers[question.id]
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Question \(questionIndex + 1) of \(lesson.practice.count)").font(.subheadline.bold())
                    Spacer()
                    Text("Take a moment to reason it out.").font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(progress.draftAnswers.count), total: Double(lesson.practice.count))
                PracticeQuestionCard(question: question, selected: $selected, submitted: submitted, showHint: $showHint) { index in
                    learning.submit(index, for: question, in: lesson)
                }
                if submitted != nil {
                    Button("Next question", systemImage: "arrow.right") {
                        questionIndex = lesson.practice.firstIndex { progress.draftAnswers[$0.id] == nil } ?? 0
                        selected = nil
                        showHint = false
                    }.buttonStyle(.borderedProminent)
                }
            }
        }
    }
    private var notes: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Explain it in your own words.").font(.title2.bold())
            Text("What changed your understanding? What would you like to test? Your notes save automatically on this device.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { progress.notes }, set: { learning.setNotes($0, for: lesson) }))
                .frame(minHeight: 260).padding(12)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Notes for \(lesson.title)")
            if !progress.notes.isEmpty { ShareLink(item: "\(lesson.title)\n\n\(progress.notes)") { Label("Share notes", systemImage: "square.and.arrow.up") } }
        }
    }
    private var activityCard: some View {
        StudyCard(tint: lesson.track.tint) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Put it to work", systemImage: "hand.draw").font(.headline)
                Text(lesson.activity.task).font(.subheadline).foregroundStyle(.secondary)
                Button(lesson.activity.activity.title) { openActivity(lesson.activity.activity) }.buttonStyle(.bordered)
            }
        }
    }
}

struct PracticeQuestionCard: View {
    let question: PracticeQuestion
    @Binding var selected: Int?
    let submitted: Int?
    @Binding var showHint: Bool
    let submit: (Int) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(question.prompt).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            ForEach(question.options.indices, id: \.self) { index in
                Button { selected = index } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: optionSymbol(index)).foregroundStyle(optionColor(index))
                        Text(question.options[index]).font(.subheadline).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(optionColor(index).opacity((selected == index || submitted == index) ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(optionColor(index).opacity(selected == index ? 0.5 : 0.1)))
                    .contentShape(RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain).disabled(submitted != nil)
                .accessibilityAddTraits(selected == index ? .isSelected : [])
            }
            if let answer = submitted {
                StudyCard(tint: answer == question.correctIndex ? .green : .orange) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(answer == question.correctIndex ? "That’s right." : "Let’s unpack it.", systemImage: answer == question.correctIndex ? "checkmark.circle" : "lightbulb").font(.headline)
                        Text(question.explanation).font(.subheadline)
                    }
                }
            } else {
                HStack {
                    Button("Check my reasoning") { if let selected { submit(selected) } }
                        .buttonStyle(.borderedProminent).disabled(selected == nil)
                    Button(showHint ? "Hide hint" : "Give me a hint") { showHint.toggle() }.font(.subheadline)
                }
                if showHint {
                    Label(question.hint, systemImage: "lightbulb").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func optionSymbol(_ index: Int) -> String {
        if let submitted {
            if index == question.correctIndex { return "checkmark.circle.fill" }
            if index == submitted { return "xmark.circle.fill" }
        }
        return selected == index ? "largecircle.fill.circle" : "circle"
    }
    private func optionColor(_ index: Int) -> Color {
        if let submitted {
            if index == question.correctIndex { return .green }
            if index == submitted { return .orange }
        }
        return selected == index ? LearningStyle.teal : .white.opacity(0.5)
    }
}
