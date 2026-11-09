import SwiftUI

@main
struct AVPLearnApp: App {
    @State private var cad = CADModel()
    @State private var lab = LabModel()
    @State private var spaces = SpaceController()
    @State private var learning = LearningStore()

    var body: some Scene {
        // Main control window
        WindowGroup(id: "home") {
            HomeView()
                .environment(cad)
                .environment(lab)
                .environment(spaces)
                .environment(learning)
        }
        .defaultSize(width: 1180, height: 820)

        // Volumetric window: explore a mechanical system in 3D
        WindowGroup(id: "system", for: String.self) { $systemID in
            SystemExplorerView(systemID: systemID ?? EngSystem.pistonAssembly.id)
                .environment(learning)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.6, height: 0.6, depth: 0.6, in: .meters)

        // Immersive CAD workplane
        ImmersiveSpace(id: "cad") {
            CADSpaceView()
                .environment(cad)
                .onAppear { spaces.active = "cad" }
                .onDisappear { if spaces.active == "cad" { spaces.active = nil } }
        }

        // Immersive virtual lab bench
        ImmersiveSpace(id: "lab") {
            LabSpaceView()
                .environment(lab)
                .onAppear { spaces.active = "lab" }
                .onDisappear { if spaces.active == "lab" { spaces.active = nil } }
        }
    }
}
