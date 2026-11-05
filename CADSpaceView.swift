import SwiftUI
import RealityKit

/// Immersive CAD workplane. Look + pinch to select, drag to move, pinch with both hands to resize.
struct CADSpaceView: View {
    @Environment(CADModel.self) private var cad

    @State private var grabOffset: SIMD3<Float>?
    @State private var baseScale: Float?

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "cad-root"
            root.position = [0, 1.0, -1.0]      // workplane ~1 m high, 1 m ahead
            root.addChild(Self.makeGrid())
            content.add(root)
        } update: { content in
            // Reads of `cad` here are observed, so this re-runs whenever the model changes.
            guard let root = content.entities.first(where: { $0.name == "cad-root" }) else { return }
            Self.sync(root, with: cad)
        }
        .gesture(tapGesture)
        .gesture(dragGesture)
        .gesture(magnifyGesture)
    }

    // MARK: Gestures

    private var tapGesture: some Gesture {
        TapGesture().targetedToAnyEntity().onEnded { value in
            if let id = UUID(uuidString: value.entity.name) { cad.select(id) }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture().targetedToAnyEntity()
            .onChanged { value in
                guard let id = UUID(uuidString: value.entity.name),
                      let root = value.entity.parent,
                      let shape = cad.shapes.first(where: { $0.id == id }) else { return }
                let p3 = value.convert(value.location3D, from: .local, to: root)
                let p = SIMD3<Float>(Float(p3.x), Float(p3.y), Float(p3.z))
                if grabOffset == nil {
                    cad.select(id)
                    cad.beginEdit()
                    grabOffset = shape.position - p
                }
                cad.setPosition(id, p + (grabOffset ?? .zero))
            }
            .onEnded { _ in grabOffset = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture().targetedToAnyEntity()
            .onChanged { value in
                guard let id = UUID(uuidString: value.entity.name),
                      let shape = cad.shapes.first(where: { $0.id == id }) else { return }
                if baseScale == nil { cad.beginEdit(); baseScale = shape.scale }
                cad.setScale(id, (baseScale ?? 1) * Float(value.magnification))
            }
            .onEnded { _ in baseScale = nil }
    }

    // MARK: Scene building

    static func makeGrid() -> Entity {
        let grid = Entity()
        grid.name = "grid"
        let line = SimpleMaterial(color: UIColor(white: 1, alpha: 0.35), isMetallic: false)
        let half: Float = 1.0, step: Float = 0.1
        var x = -half
        while x <= half + 0.001 {
            let a = ModelEntity(mesh: .generateBox(width: 0.002, height: 0.001, depth: half * 2), materials: [line])
            a.position = [x, 0, 0]
            let b = ModelEntity(mesh: .generateBox(width: half * 2, height: 0.001, depth: 0.002), materials: [line])
            b.position = [0, 0, x]
            grid.addChild(a)
            grid.addChild(b)
            x += step
        }
        return grid
    }

    @MainActor
    static func sync(_ root: Entity, with cad: CADModel) {
        let ids = Set(cad.shapes.map { $0.id.uuidString })
        for child in Array(root.children) where child.name != "grid" && !ids.contains(child.name) {
            child.removeFromParent()
        }
        for s in cad.shapes {
            let entity: ModelEntity
            if let existing = root.children.first(where: { $0.name == s.id.uuidString }) as? ModelEntity {
                entity = existing
            } else {
                entity = ModelEntity(mesh: s.kind.mesh(), materials: [])
                entity.name = s.id.uuidString
                entity.components.set(InputTargetComponent())
                entity.generateCollisionShapes(recursive: false)
                root.addChild(entity)
            }
            entity.position = s.position
            entity.scale = SIMD3(repeating: s.scale)
            let isSelected = s.id == cad.selectedID
            entity.model?.materials = [
                SimpleMaterial(color: CADPalette.color(s.colorIndex, selected: isSelected), isMetallic: isSelected)
            ]
        }
    }
}
