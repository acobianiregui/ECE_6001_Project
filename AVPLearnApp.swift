import SwiftUI

@main
struct AVPLearnApp: App {
    @State private var cad = CADModel()
    @State private var lab = LabModel()
    @State private var spaces = SpaceController()

    var body: some Scene {
        // Main control window
        WindowGroup(id: "home") {
            HomeView()
                .environment(cad)
                .environment(lab)
                .environment(spaces)
        }
        .defaultSize(width: 900, height: 700)

        // Volumetric window: explore a mechanical system in 3D
        WindowGroup(id: "system", for: String.self) { $systemID in
            SystemExplorerView(systemID: systemID ?? EngSystem.pistonAssembly.id)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.6, height: 0.6, depth: 0.6, in: .meters)

        // Immersive CAD workplane
        ImmersiveSpace(id: "cad") {
            CADSpaceView()
                .environment(cad)
                .onAppear { spaces.active = "cad" }
                .onDisappear { spaces.active = nil }
        }

        // Immersive virtual lab bench
        ImmersiveSpace(id: "lab") {
            LabSpaceView()
                .environment(lab)
                .onAppear { spaces.active = "lab" }
                .onDisappear { spaces.active = nil }
        }
    }
}
