import SwiftUI

enum LearningDestination: String, CaseIterable, Identifiable {
    case today, lessons, explorer, cad, lab, progress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .lessons: "Learning paths"
        case .explorer: "3D explorer"
        case .cad: "CAD studio"
        case .lab: "Circuit lab"
        case .progress: "My progress"
        }
    }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .lessons: "books.vertical"
        case .explorer: "cube.transparent"
        case .cad: "square.stack.3d.up"
        case .lab: "bolt.horizontal.circle"
        case .progress: "chart.bar.xaxis"
        }
    }
}

struct HomeView: View {
    @Environment(LearningStore.self) private var learning
    @Environment(SpaceController.self) private var spaces
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace
    @State private var destination: LearningDestination = .today
    @State private var selectedLesson: Lesson?
    @State private var reviewing = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
        } detail: {
            NavigationStack {
                switch destination {
                case .today:
                    TodayView(openLesson: { selectedLesson = $0 }, openDestination: { destination = $0 }, review: { reviewing = true })
                case .lessons:
                    LearningPathsView(openLesson: { selectedLesson = $0 })
                case .explorer:
                    MechanicsExplorerView()
                case .cad:
                    CADStudioView(toggleSpace: toggle)
                case .lab:
                    CircuitLabView(toggleSpace: toggle)
                case .progress:
                    LearningProgressView(openLesson: { selectedLesson = $0 }, review: { reviewing = true })
                }
            }
        }
        .tint(LearningStyle.teal)
        .preferredColorScheme(.dark)
        .frame(minWidth: 960, minHeight: 650)
        .sheet(item: $selectedLesson) { lesson in
            LessonDetailView(lesson: lesson, openActivity: launchActivity)
                .frame(minWidth: 720, idealWidth: 800, minHeight: 620, idealHeight: 760)
        }
        .sheet(isPresented: $reviewing) {
            ReviewSessionView().frame(minWidth: 680, idealWidth: 740, minHeight: 600, idealHeight: 700)
        }
        .alert("Couldn’t open the workspace", isPresented: Binding(get: { spaces.error != nil }, set: { if !$0 { spaces.error = nil } })) {
            Button("OK") { spaces.error = nil }
        } message: { Text(spaces.error ?? "Please try again.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.title2).foregroundStyle(LearningStyle.teal)
                    .frame(width: 46, height: 46)
                    .background(LearningStyle.teal.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVP Learn").font(.title3.bold())
                    Text("ENGINEERING STUDIO").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 12)
            VStack(spacing: 6) {
                ForEach(LearningDestination.allCases) { item in
                    Button { destination = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol).frame(width: 22)
                            Text(item.title).font(.subheadline.weight(destination == item ? .semibold : .regular))
                            Spacer(minLength: 0)
                            if item == .progress && !learning.dueQuestions.isEmpty {
                                Text("\(learning.dueQuestions.count)").font(.caption2.bold()).padding(5).background(.orange.opacity(0.2), in: Circle())
                            }
                        }
                        .foregroundStyle(destination == item ? LearningStyle.teal : .white.opacity(0.75))
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .background(destination == item ? LearningStyle.teal.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 13))
                        .contentShape(RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(destination == item ? .isSelected : [])
                }
            }
            Spacer(minLength: 12)
            if let active = spaces.active {
                Button { toggle(active) } label: {
                    Label(spaces.isTransitioning ? "Changing workspace…" : "Leave \(active == "cad" ? "CAD space" : "lab space")", systemImage: "visionpro")
                        .font(.caption)
                }.disabled(spaces.isTransitioning)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Your learning journey").font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(learning.completedCount)/9").font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: learning.completionFraction)
                Text("Learn a little. Build something.").font(.caption2).foregroundStyle(.secondary)
            }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(18)
    }

    private func launchActivity(_ activity: LearningActivity) {
        selectedLesson = nil
        switch activity {
        case .circuit: destination = .lab
        case .cad: destination = .cad
        case .piston: openWindow(id: "system", value: "piston")
        case .gears: openWindow(id: "system", value: "gears")
        }
    }
    private func toggle(_ id: String) {
        guard !spaces.isTransitioning else { return }
        spaces.isTransitioning = true
        Task { @MainActor in
            defer { spaces.isTransitioning = false }
            if spaces.active == id {
                await dismissSpace()
                spaces.active = nil
                return
            }
            if spaces.active != nil {
                await dismissSpace()
                spaces.active = nil
            }
            switch await openSpace(id: id) {
            case .opened: spaces.active = id
            case .userCancelled: break
            case .error: spaces.error = "The immersive workspace isn’t available right now. You can keep using the window tools and try again later."
            @unknown default: spaces.error = "Xcode or visionOS returned an unexpected result. Please try again."
            }
        }
    }
}
