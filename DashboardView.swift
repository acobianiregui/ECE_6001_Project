import SwiftUI

struct TodayView: View {
    @Environment(LearningStore.self) private var learning
    @Environment(CADModel.self) private var cad
    let openLesson: (Lesson) -> Void
    let openDestination: (LearningDestination) -> Void
    let review: () -> Void
    /// The starter shown on the studio card while the workplane is empty.
    private let featured = CADTemplate.shaftSupport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                StudyHeading(eyebrow: "A little progress, every day", title: "Make engineering click.", subtitle: "Design a real part. Understand why it works. See it come to life.")
                studioCard
                if let next = learning.nextLesson {
                    continueCard(next)
                } else {
                    StudyCard(tint: .mint) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("All nine lessons completed", systemImage: "checkmark.seal.fill").font(.title2.bold())
                            Text("Keep the ideas fresh with review, or take on a studio challenge.").foregroundStyle(.secondary)
                            Button("Open CAD studio") { openDestination(.cad) }.buttonStyle(.borderedProminent)
                        }
                    }
                }
                HStack(spacing: 14) {
                    MetricTile(value: "\(learning.completedCount)/9", label: "Lessons completed", symbol: "checkmark.circle")
                    MetricTile(value: "\(learning.streak)", label: learning.streak == 1 ? "Day of practice" : "Day practice streak", symbol: "flame", tint: .orange)
                    MetricTile(value: "\(learning.dueQuestions.count)", label: "Questions to revisit", symbol: "arrow.clockwise", tint: .indigo)
                }
                HStack {
                    Text("Choose your path").font(.title3.bold())
                    Spacer()
                    Button("All lessons", systemImage: "arrow.right") { openDestination(.lessons) }.font(.subheadline)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) { trackCards }
                    VStack(spacing: 14) { trackCards }
                }
                if !learning.dueQuestions.isEmpty {
                    StudyCard(tint: .orange) {
                        HStack(spacing: 20) {
                            Image(systemName: "brain").font(.largeTitle).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Bring an idea back.").font(.headline)
                                Text("A few questions from earlier practice are ready to revisit. Try recalling before looking at a hint.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button("Start review", action: review).buttonStyle(.bordered)
                        }
                    }
                }
                Text("Your progress, notes, and designs stay on this device. No account needed.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(30).frame(maxWidth: 1150)
        }
        .navigationTitle("Today")
        .toolbarTitleDisplayMode(.inline)
    }
    /// The CAD studio leads the page: a picture of the learner's own design, or of a starter to open.
    private var studioCard: some View {
        let visible = cad.shapes.filter { !$0.isHidden }
        let working = !visible.isEmpty
        let passed = CADChallenge.allCases.filter { $0.checks(in: cad.shapes).allSatisfy(\.1) }.count
        return HStack(spacing: 26) {
            CADPreviewImage(shapes: working ? visible : featured.shapes, pixels: 640)
                .frame(width: 300, height: 220)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 22))
            VStack(alignment: .leading, spacing: 12) {
                Text("CAD STUDIO").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(LearningStyle.teal)
                Text(working ? "Pick up your design." : "Design real parts in 3D.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(working
                     ? "\(visible.count) \(visible.count == 1 ? "part" : "parts") on your workplane, saved automatically. Measure them, change them, or view them at life size."
                     : "Start from a real mechanism such as this \(featured.title.lowercased()): bolts, bearings, gears and shafts at true size. Take it apart, measure it, and build your own.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button { openDestination(.cad) } label: {
                        Label(working ? "Continue designing" : "Open the studio", systemImage: "square.stack.3d.up")
                    }
                    .buttonStyle(.borderedProminent)
                    if !working {
                        Button("Start with this assembly") {
                            cad.loadTemplate(featured)
                            cad.select(nil)
                            openDestination(.cad)
                        }
                    }
                }
                Label("\(passed) of \(CADChallenge.allCases.count) build challenges passed", systemImage: "target")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [LearningStyle.teal.opacity(0.18), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(LearningStyle.teal.opacity(0.25)))
    }
    private func continueCard(_ lesson: Lesson) -> some View {
        HStack(spacing: 26) {
            VStack(alignment: .leading, spacing: 14) {
                Text(learning.lastLessonID == nil ? "START HERE" : "CONTINUE LEARNING")
                    .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(lesson.track.tint)
                Text(lesson.title).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(lesson.summary).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Button { openLesson(lesson) } label: {
                        Label(learning.lastLessonID == nil ? "Begin lesson" : "Continue lesson", systemImage: "arrow.right")
                    }.buttonStyle(.borderedProminent)
                    Label("\(lesson.minutes) min", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: lesson.track.symbol)
                .font(.system(size: 72, weight: .light)).foregroundStyle(lesson.track.tint)
                .frame(width: 130, height: 140)
                .background(lesson.track.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 30))
                .accessibilityHidden(true)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [lesson.track.tint.opacity(0.16), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(lesson.track.tint.opacity(0.2)))
    }
    @ViewBuilder private var trackCards: some View {
        // Design leads: it is the path the studio builds on.
        ForEach([LearningTrack.design, .mechanics, .circuits]) { track in
            let lessons = Curriculum.lessons.filter { $0.track == track }
            let completed = lessons.filter(learning.isComplete).count
            Button {
                if let lesson = lessons.first(where: { !learning.isComplete($0) }) ?? lessons.first { openLesson(lesson) }
            } label: {
                StudyCard(tint: track.tint) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: track.symbol).font(.title2).foregroundStyle(track.tint)
                        Text(track.title).font(.headline)
                        Text(track.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ProgressView(value: Double(completed), total: Double(max(1, lessons.count))).tint(track.tint)
                        Text("\(completed) of \(lessons.count) lessons").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                }
            }.buttonStyle(.plain)
        }
    }
}

struct LearningPathsView: View {
    @Environment(LearningStore.self) private var learning
    let openLesson: (Lesson) -> Void
    @State private var search = ""
    @State private var track: LearningTrack?
    @State private var bookmarksOnly = false
    @State private var showGlossary = false
    private var filtered: [Lesson] {
        Curriculum.lessons.filter { lesson in
            (track == nil || lesson.track == track) && (!bookmarksOnly || learning.progress(for: lesson).bookmarked)
            && (search.isEmpty || "\(lesson.title) \(lesson.summary) \(lesson.track.title)".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StudyHeading(eyebrow: "The learning library", title: "Build your foundations.", subtitle: "Nine short lessons. Three paths. Work at your pace and revisit any idea.")
                HStack {
                    Picker("Learning path", selection: $track) {
                        Text("All paths").tag(nil as LearningTrack?)
                        ForEach(LearningTrack.allCases) { Text($0.title).tag(Optional($0)) }
                    }.pickerStyle(.menu)
                    Toggle("Saved", isOn: $bookmarksOnly).toggleStyle(.button)
                    Spacer()
                    Button("Glossary", systemImage: "text.book.closed") { showGlossary = true }
                }
                if filtered.isEmpty {
                    ContentUnavailableView("No matching lessons", systemImage: "magnifyingglass", description: Text("Try another search, path, or saved filter."))
                }
                ForEach(LearningTrack.allCases) { current in
                    let group = filtered.filter { $0.track == current }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            TrackBadge(track: current)
                            ForEach(group) { lesson in
                                Button { openLesson(lesson) } label: { LessonRow(lesson: lesson) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(30).frame(maxWidth: 1150)
        }
        .navigationTitle("Learning paths").toolbarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search lessons")
        .sheet(isPresented: $showGlossary) { GlossaryView().frame(minWidth: 620, minHeight: 600) }
    }
}

struct LessonRow: View {
    @Environment(LearningStore.self) private var learning
    let lesson: Lesson
    var body: some View {
        let p = learning.progress(for: lesson)
        HStack(spacing: 18) {
            Image(systemName: learning.isComplete(lesson) ? "checkmark.circle.fill" : lesson.track.symbol)
                .font(.title3).foregroundStyle(lesson.track.tint)
                .frame(width: 50, height: 50).background(lesson.track.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(lesson.title).font(.headline)
                Text(lesson.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 12) {
                    Label("\(lesson.minutes) min", systemImage: "clock")
                    if p.quizRuns > 0 { Text("Best practice: \(p.bestCorrect)/\(lesson.practice.count)") }
                    if p.bookmarked { Image(systemName: "bookmark.fill") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(18).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}
