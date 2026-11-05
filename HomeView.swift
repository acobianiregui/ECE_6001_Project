import SwiftUI

struct HomeView: View {
    enum Tab { case learn, cad, lab }
    @State private var tab: Tab = .learn

    @Environment(SpaceController.self) private var spaces
    @Environment(\.openImmersiveSpace) private var openSpace
    @Environment(\.dismissImmersiveSpace) private var dismissSpace

    var body: some View {
        TabView(selection: $tab) {
            LearnTab()
                .tabItem { Label("Explore", systemImage: "gearshape.2") }
                .tag(Tab.learn)
            CADPanel(toggleSpace: toggle)
                .tabItem { Label("CAD Studio", systemImage: "cube") }
                .tag(Tab.cad)
            LabPanel(toggleSpace: toggle)
                .tabItem { Label("Virtual Lab", systemImage: "flask") }
                .tag(Tab.lab)
        }
    }

    /// Enter or leave an immersive space. Only one can be open at a time.
    private func toggle(_ id: String) {
        Task {
            if spaces.active == id {
                await dismissSpace()
            } else {
                if spaces.active != nil { await dismissSpace() }
                await openSpace(id: id)
            }
        }
    }
}

// MARK: - Explore tab

struct LearnTab: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            List(EngSystem.library) { system in
                HStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.largeTitle)
                        .frame(width: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(system.title).font(.headline)
                        Text(system.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open in 3D") { openWindow(id: "system", value: system.id) }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("AVP Learn")
        }
    }
}

// MARK: - CAD tab

struct CADPanel: View {
    @Environment(CADModel.self) private var cad
    @Environment(SpaceController.self) private var spaces
    let toggleSpace: (String) -> Void

    var body: some View {
        @Bindable var cad = cad
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        toggleSpace("cad")
                    } label: {
                        Label(spaces.active == "cad" ? "Leave Workspace" : "Enter 3D Workspace",
                              systemImage: spaces.active == "cad" ? "xmark.circle" : "visionpro")
                    }
                    .buttonStyle(.borderedProminent)

                    // Coach
                    Label(cad.coachTip, systemImage: "lightbulb")
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    Text("Add a shape").font(.headline)
                    HStack {
                        ForEach(ShapeKind.allCases) { kind in
                            Button { cad.add(kind) } label: {
                                VStack { Image(systemName: kind.icon).font(.title2); Text(kind.label).font(.caption) }
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }

                    Toggle("Snap to 5 cm grid", isOn: $cad.snapEnabled)

                    if let s = cad.selected {
                        Text("Selected: \(s.kind.label)").font(.headline)
                        Text(String(format: "Size: %.1f cm   Height above plane: %.0f cm",
                                    s.sizeCM, s.position.y * 100))
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(get: { s.scale },
                                              set: { cad.setScale(s.id, $0) }),
                               in: 0.25...6) { editing in if editing { cad.beginEdit() } }
                        HStack {
                            ForEach(0..<CADPalette.hues.count, id: \.self) { i in
                                Button { cad.setColor(i) } label: {
                                    Circle().fill(Color(CADPalette.color(i, selected: false)))
                                        .frame(width: 28, height: 28)
                                }.buttonStyle(.plain)
                            }
                        }
                        HStack {
                            Button("Duplicate") { cad.duplicateSelected() }
                            Button("Delete", role: .destructive) { cad.deleteSelected() }
                        }
                    }

                    HStack {
                        Button("Undo") { cad.undo() }.disabled(!cad.canUndo)
                        Button("Clear All", role: .destructive) { cad.clear() }.disabled(cad.shapes.isEmpty)
                    }
                }
                .padding()
            }
            .navigationTitle("CAD Studio")
        }
    }
}

// MARK: - Lab tab

struct LabPanel: View {
    @Environment(LabModel.self) private var lab
    @Environment(SpaceController.self) private var spaces
    let toggleSpace: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Lab 1: Build a current-limited LED circuit").font(.title3)

                Button {
                    toggleSpace("lab")
                } label: {
                    Label(spaces.active == "lab" ? "Leave Lab" : "Enter Virtual Lab",
                          systemImage: spaces.active == "lab" ? "xmark.circle" : "visionpro")
                }
                .buttonStyle(.borderedProminent)

                if lab.finished {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lab complete").font(.title2)
                        Text("Score: \(lab.score)/100 · Mistakes: \(lab.mistakes)")
                        Text(lab.score >= 80 ? "You're ready for the physical lab." : "Run it again to tighten up your procedure.")
                            .foregroundStyle(.secondary)
                        Button("Restart") { lab.reset() }
                    }
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else if let step = lab.current {
                    Text("Step \(lab.stepIndex + 1) of \(LabModel.steps.count)").foregroundStyle(.secondary)
                    Text(step.instruction).font(.title2)
                    ProgressView(value: Double(lab.stepIndex), total: Double(LabModel.steps.count))
                }

                Text(lab.feedback)
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Spacer()
            }
            .padding()
            .navigationTitle("Virtual Lab")
        }
    }
}
