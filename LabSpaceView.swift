import SwiftUI
import RealityKit

/// Immersive virtual lab bench. Tap components in the order the procedure requires.
struct LabSpaceView: View {
    @Environment(LabModel.self) private var lab

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "lab-root"
            root.position = [0, 0, -1.0]

            // Bench top
            let bench = ModelEntity(
                mesh: .generateBox(width: 1.6, height: 0.04, depth: 0.7),
                materials: [SimpleMaterial(color: UIColor(white: 0.25, alpha: 1), isMetallic: false)])
            bench.position = [0, 0.85, 0]
            root.addChild(bench)

            for c in LabModel.components {
                let e = ModelEntity(
                    mesh: .generateBox(width: c.size.x, height: c.size.y, depth: c.size.z, cornerRadius: 0.005),
                    materials: [SimpleMaterial(color: UIColor(hue: c.hue, saturation: 0.7, brightness: 0.95, alpha: 1),
                                               isMetallic: false)])
                e.name = c.id
                e.position = [c.position.x, 0.87 + c.size.y / 2, 0]
                e.components.set(InputTargetComponent())
                e.generateCollisionShapes(recursive: false)
                root.addChild(e)
            }
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "lab-root" }) else { return }
            let nextTarget = lab.current?.targetID
            for c in LabModel.components {
                guard let e = root.children.first(where: { $0.name == c.id }) as? ModelEntity else { continue }
                let placed = lab.done.contains(c.id)
                let glowing = c.id == "led" && placed && lab.switchClosed
                let color: UIColor
                if glowing { color = UIColor(red: 1, green: 0.15, blue: 0.15, alpha: 1) }
                else if placed { color = UIColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1) }
                else { color = UIColor(hue: c.hue, saturation: 0.7, brightness: 0.95, alpha: 1) }
                e.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
                // Gentle lift on the component the procedure wants next
                e.position.y = 0.87 + c.size.y / 2 + (c.id == nextTarget ? 0.02 : 0)
            }
        }
        .gesture(
            TapGesture().targetedToAnyEntity().onEnded { value in
                lab.attempt(value.entity.name)
            }
        )
    }
}
