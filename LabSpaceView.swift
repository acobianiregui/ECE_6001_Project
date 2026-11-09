import SwiftUI
import RealityKit

/// The same guided procedure as the windowed bench, using spatial selection.
struct LabSpaceView: View {
    @Environment(LabModel.self) private var lab

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "lab-root"
            root.position = [0, 0, -1.0]
            let bench = ModelEntity(
                mesh: .generateBox(width: 1.6, height: 0.04, depth: 0.7),
                materials: [SimpleMaterial(color: UIColor(white: 0.2, alpha: 1), isMetallic: false)])
            bench.position = [0, 0.85, 0]
            root.addChild(bench)

            for component in LabModel.components {
                let entity = ModelEntity(
                    mesh: .generateBox(width: component.size.x, height: component.size.y,
                                       depth: component.size.z, cornerRadius: 0.005),
                    materials: [SimpleMaterial(color: UIColor(hue: component.hue, saturation: 0.7,
                                                             brightness: 0.95, alpha: 1), isMetallic: false)])
                entity.name = component.id
                entity.position = [component.position.x, 0.87 + component.size.y / 2, 0]
                entity.components.set(InputTargetComponent())
                entity.generateCollisionShapes(recursive: false)
                root.addChild(entity)

                let ring = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.085),
                                       materials: [SimpleMaterial(color: .orange, isMetallic: false)])
                ring.name = "hint-" + component.id
                ring.position = [component.position.x, 0.876, 0]
                root.addChild(ring)

                let label = ModelEntity(
                    mesh: .generateText(shortName(component.id), extrusionDepth: 0.0003,
                                        font: .systemFont(ofSize: 0.025), containerFrame: .zero,
                                        alignment: .center, lineBreakMode: .byWordWrapping),
                    materials: [UnlitMaterial(color: .white)])
                label.position = [component.position.x - 0.055, 1.08, 0]
                root.addChild(label)
            }
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "lab-root" }) else { return }
            for component in LabModel.components {
                guard let entity = root.children.first(where: { $0.name == component.id }) as? ModelEntity else { continue }
                let placed = lab.done.contains(component.id)
                let glowing = component.id == "led" && lab.guidedReading.isConducting
                let color: UIColor = glowing ? .systemRed : (placed ? .systemTeal :
                    UIColor(hue: component.hue, saturation: 0.7, brightness: 0.95, alpha: 1))
                if glowing { entity.model?.materials = [UnlitMaterial(color: color)] }
                else { entity.model?.materials = [SimpleMaterial(color: color, isMetallic: false)] }
                let next = component.id == lab.current?.targetID
                root.children.first(where: { $0.name == "hint-" + component.id })?.isEnabled = next
                entity.position.y = 0.87 + component.size.y / 2 + (next ? 0.025 : 0)
            }
        }
        .gesture(TapGesture().targetedToAnyEntity().onEnded { value in lab.attempt(value.entity.name) })
    }

    private func shortName(_ id: String) -> String {
        switch id {
        case "switch": "POWER"
        case "resistor": "470 Ω"
        case "led": "LED"
        case "battery": "9 V"
        default: "METER"
        }
    }
}
