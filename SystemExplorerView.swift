import SwiftUI
import RealityKit

/// Volumetric window: an exploded-view 3D model students can inspect by tapping parts.
struct SystemExplorerView: View {
    let systemID: String
    @State private var explode: Float = 0
    @State private var selectedID: String?

    private var system: EngSystem {
        EngSystem.library.first { $0.id == systemID } ?? .pistonAssembly
    }
    private var selectedPart: SystemPart? { system.parts.first { $0.id == selectedID } }

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "sys-root"
            for part in system.parts {
                let material: RealityKit.Material
                if part.transparent {
                    var m = PhysicallyBasedMaterial()
                    m.baseColor = .init(tint: UIColor(hue: part.hue, saturation: 0.3, brightness: 1, alpha: 1))
                    m.blending = .transparent(opacity: 0.25)
                    material = m
                } else {
                    material = SimpleMaterial(color: UIColor(hue: part.hue, saturation: 0.7, brightness: 0.95, alpha: 1),
                                              isMetallic: true)
                }
                let e = ModelEntity(mesh: part.mesh(), materials: [material])
                e.name = part.id
                e.position = part.home
                if part.tiltedOnX { e.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) }
                e.components.set(InputTargetComponent())
                e.generateCollisionShapes(recursive: false)
                root.addChild(e)
            }
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "sys-root" }) else { return }
            for part in system.parts {
                guard let e = root.children.first(where: { $0.name == part.id }) else { continue }
                e.position = part.home + explode * part.explode
                e.scale = SIMD3(repeating: part.id == selectedID ? 1.08 : 1.0)
            }
        }
        .gesture(
            TapGesture().targetedToAnyEntity().onEnded { value in
                selectedID = (selectedID == value.entity.name) ? nil : value.entity.name
            }
        )
        .ornament(attachmentAnchor: .scene(.bottom)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(system.title).font(.headline)
                HStack {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Slider(value: $explode, in: 0...1)
                        .frame(width: 280)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                if let p = selectedPart {
                    Text(p.name).font(.subheadline.bold())
                    Text(p.detail).font(.footnote).frame(width: 340, alignment: .leading)
                } else {
                    Text("Tap a part to learn what it does.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
            .glassBackgroundEffect()
        }
    }
}
