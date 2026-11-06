import SwiftUI
import RealityKit
import simd

struct CADSpaceView: View {
    var body: some View { CADSceneView(immersive: true) }
}

enum CADViewAngle: String, CaseIterable, Identifiable {
    case isometric, front, top, right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    fileprivate var rotation: simd_quatf {
        switch self {
        case .isometric:
            return simd_quatf(angle: .pi / 6, axis: [1, 0, 0]) * simd_quatf(angle: -.pi / 5, axis: [0, 1, 0])
        case .front: return simd_quatf(angle: 0, axis: [0, 1, 0])
        case .top: return simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        case .right: return simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        }
    }
}

private struct CADRenderSignature: Component {
    var kind: String
    var bore: Float
}
private struct CADGridSignature: Component { var value: String }
private struct CADSelectionSignature: Component { var value: String }

/// Reference storage avoids mutating SwiftUI-observed state from a RealityView update.
private final class CADFramingState {
    var visibleIDs: Set<UUID> = []
    var angle: CADViewAngle?
    var request = Int.min
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
}

/// Shared life-size immersive workspace and auto-fitting window viewport.
struct CADSceneView: View {
    @Environment(CADModel.self) private var cad
    let immersive: Bool
    var angle: CADViewAngle = .isometric
    var zoom: Float = 1
    var showDimensions = true
    var fitRequest = 0
    @State private var framing = CADFramingState()
    @State private var grabOffset: SIMD3<Float>?
    @State private var baseScale: Float?
    @State private var isManipulating = false

    var body: some View {
        GeometryReader3D { geometry in
            RealityView { content in
                let root = Entity()
                root.name = "cad-root"
                Self.sync(root, with: cad, showDimensions: showDimensions, immersive: immersive)
                content.add(root)
                Self.frame(root, shapes: cad.shapes, immersive: immersive, angle: angle, zoom: zoom,
                           viewport: content.convert(geometry.frame(in: .local), from: .local, to: .scene),
                           framing: framing, fitRequest: fitRequest)
            } update: { content in
                guard let root = content.entities.first(where: { $0.name == "cad-root" }) else { return }
                Self.sync(root, with: cad, showDimensions: showDimensions, immersive: immersive)
                // Freeze framing while dragging so the coordinate system does not move under the hand.
                if !isManipulating {
                    Self.frame(root, shapes: cad.shapes, immersive: immersive, angle: angle, zoom: zoom,
                               viewport: content.convert(geometry.frame(in: .local), from: .local, to: .scene),
                           framing: framing, fitRequest: fitRequest)
                }
            }
            .gesture(TapGesture().targetedToAnyEntity().onEnded { value in
                if let id = UUID(uuidString: value.entity.name) { cad.select(id) }
            })
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
        }
        .overlay(alignment: .bottomLeading) {
            if !immersive, showDimensions, let shape = cad.selected, !shape.isHidden {
                VStack(alignment: .leading, spacing: 3) {
                    Label(shape.name, systemImage: shape.isLocked ? "lock.fill" : shape.kind.icon).font(.caption.bold())
                    Text(dimensionText(shape)).font(.caption2).monospacedDigit()
                    Text("Local X × Y × Z dimensions").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(12).allowsHitTesting(false)
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !immersive {
                let metrics = Self.gridMetrics(shapes: cad.shapes.filter { !$0.isHidden }, spacing: cad.gridSpacing)
                Text(String(format: "Grid lines %.3g mm · ", metrics.step * 1000)
                     + (cad.snapEnabled ? String(format: "Snap %.3g mm", cad.gridSpacing * 1000) : "Snap off"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(8).background(.ultraThinMaterial, in: Capsule()).padding(12)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(immersive ? "Life-size CAD workspace" : "\(angle.title) CAD viewport")
        .accessibilityHint("Select a visible part to inspect it. Unlocked parts can be dragged or resized; numeric controls provide precise placement.")
    }

    private var dragGesture: some Gesture {
        DragGesture().targetedToAnyEntity()
            .onChanged { value in
                guard let id = UUID(uuidString: value.entity.name),
                      let root = value.entity.parent,
                      let shape = cad.shapes.first(where: { $0.id == id && !$0.isHidden }) else { return }
                cad.select(id)
                guard !shape.isLocked else { return }
                let location = value.convert(value.location3D, from: .local, to: root)
                let point = SIMD3<Float>(Float(location.x), Float(location.y), Float(location.z))
                if grabOffset == nil {
                    cad.beginEdit()
                    isManipulating = true
                    grabOffset = shape.position - point
                }
                cad.setPosition(id, point + (grabOffset ?? .zero))
            }
            .onEnded { _ in grabOffset = nil; isManipulating = false }
    }
    private var magnifyGesture: some Gesture {
        MagnifyGesture().targetedToAnyEntity()
            .onChanged { value in
                guard let id = UUID(uuidString: value.entity.name),
                      let shape = cad.shapes.first(where: { $0.id == id && !$0.isHidden }) else { return }
                cad.select(id)
                guard !shape.isLocked else { return }
                if baseScale == nil {
                    cad.beginEdit()
                    isManipulating = true
                    baseScale = shape.scale
                }
                cad.setScale(id, (baseScale ?? 1) * Float(value.magnification))
            }
            .onEnded { _ in baseScale = nil; isManipulating = false }
    }

    private func dimensionText(_ shape: CADShape) -> String {
        let d = shape.dimensions * cad.units.unitsPerMeter
        return String(format: "%.1f × %.1f × %.1f %@", d.x, d.y, d.z, cad.units.suffix)
    }

    @MainActor
    static func sync(_ root: Entity, with cad: CADModel, showDimensions: Bool, immersive: Bool) {
        let visible = cad.shapes.filter { !$0.isHidden }
        let ids = Set(visible.map { $0.id.uuidString })
        for child in Array(root.children) where UUID(uuidString: child.name) != nil && !ids.contains(child.name) {
            child.removeFromParent()
        }
        for shape in visible {
            let entity: ModelEntity
            if let existing = root.children.first(where: { $0.name == shape.id.uuidString }) as? ModelEntity {
                entity = existing
            } else {
                entity = ModelEntity()
                entity.name = shape.id.uuidString
                entity.components.set(InputTargetComponent())
                root.addChild(entity)
            }
            let old = entity.components[CADRenderSignature.self]
            if old?.kind != shape.kind.rawValue || (shape.kind == .tube && old?.bore != shape.boreRatio) {
                entity.model = ModelComponent(mesh: CADMeshLibrary.mesh(for: shape), materials: [])
                if let shapes = CADMeshLibrary.collisionShapes(for: shape) {
                    entity.components.set(CollisionComponent(shapes: shapes))
                } else {
                    entity.generateCollisionShapes(recursive: false)
                }
                entity.components.set(CADRenderSignature(kind: shape.kind.rawValue, bore: shape.boreRatio))
            }
            entity.position = shape.position
            entity.scale = shape.dimensions / SIMD3<Float>(repeating: 0.1)
            entity.orientation = shape.rotationQuaternion
            let selected = shape.id == cad.selectedID
            entity.model?.materials = [SimpleMaterial(color: CADPalette.color(shape.colorIndex, selected: selected), isMetallic: false)]
        }
        updateGrid(root, shapes: visible, spacing: cad.gridSpacing)
        updateSelection(root, selected: cad.selected.flatMap { $0.isHidden ? nil : $0 },
                        showDimensions: showDimensions, immersive: immersive)
    }

    @MainActor
    private static func frame(_ root: Entity, shapes: [CADShape], immersive: Bool, angle: CADViewAngle,
                              zoom: Float, viewport: BoundingBox, framing: CADFramingState, fitRequest: Int) {
        if immersive {
            root.position = [0, 1, -1]
            root.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            root.scale = .one
            return
        }
        let rotation = angle.rotation
        let visible = shapes.filter { !$0.isHidden }
        let ids = Set(visible.map(\.id))
        if framing.bounds == nil || framing.visibleIDs != ids || framing.angle != angle || framing.request != fitRequest {
            framing.bounds = bounds(of: visible, rotatedBy: rotation)
            framing.visibleIDs = ids
            framing.angle = angle
            framing.request = fitRequest
        }
        // Keep camera framing stable through size/position/rotation edits, so the edit stays visible.
        guard let bounds = framing.bounds else { return }
        let extent = max(bounds.max - bounds.min, SIMD3<Float>(repeating: 0.005))
        let available = max(viewport.extents, SIMD3<Float>(repeating: 0.02))
        let fit = min(available.x / extent.x, available.y / extent.y) * 0.76
        let scale = max(0.001, fit * min(3, max(0.25, zoom)))
        let center = (bounds.min + bounds.max) / 2
        root.scale = .init(repeating: scale)
        root.orientation = rotation
        root.position = [viewport.center.x - center.x * scale,
                         viewport.center.y - center.y * scale,
                         viewport.center.z - bounds.max.z * scale + 0.005]
    }

    static func bounds(of shapes: [CADShape], rotatedBy rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        guard !shapes.isEmpty else { return ([-0.15, 0, -0.15], [0.15, 0.3, 0.15]) }
        var lower = SIMD3<Float>(repeating: .infinity), upper = SIMD3<Float>(repeating: -.infinity)
        for shape in shapes {
            let half = shape.dimensions / 2
            for x in [Float(-1), Float(1)] {
                for y in [Float(-1), Float(1)] {
                    for z in [Float(-1), Float(1)] {
                        let point = rotation.act(shape.rotationQuaternion.act(half * SIMD3<Float>(x, y, z)) + shape.position)
                        lower = min(lower, point)
                        upper = max(upper, point)
                    }
                }
            }
        }
        return (lower, upper)
    }

    private static func gridMetrics(shapes: [CADShape], spacing: Float) -> (min: SIMD2<Float>, max: SIMD2<Float>, step: Float) {
        let box = bounds(of: shapes)
        let span = max(box.max.x - box.min.x, box.max.z - box.min.z)
        let padding = max(0.005, min(0.1, span * 0.15))
        let quantum = max(spacing, max(0.005, min(0.5, span / 10)))
        let minimum = SIMD2<Float>(floor((box.min.x - padding) / quantum) * quantum, floor((box.min.z - padding) / quantum) * quantum)
        let maximum = SIMD2<Float>(ceil((box.max.x + padding) / quantum) * quantum, ceil((box.max.z + padding) / quantum) * quantum)
        let step = max(spacing, 0.001) * max(1, ceil(max(maximum.x - minimum.x, maximum.y - minimum.y) / max(spacing, 0.001) / 160))
        return (minimum, maximum, step)
    }

    @MainActor
    private static func updateGrid(_ root: Entity, shapes: [CADShape], spacing: Float) {
        let metrics = gridMetrics(shapes: shapes, spacing: spacing)
        let minimum = metrics.min, maximum = metrics.max
        let signature = "\(minimum)-\(maximum)-\(spacing)"
        if root.children.first(where: { $0.name == "grid" })?.components[CADGridSignature.self]?.value == signature { return }
        root.children.first(where: { $0.name == "grid" })?.removeFromParent()
        let grid = Entity()
        grid.name = "grid"
        grid.components.set(CADGridSignature(value: signature))
        // Thin grids are coarsened only for drawing, so very large designs remain responsive.
        let drawingStep = metrics.step
        var descriptor = MeshDescriptor(name: "CAD-workplane-grid")
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        func strip(_ low: SIMD3<Float>, _ high: SIMD3<Float>, alongX: Bool) {
            let thickness = drawingStep * 0.018
            let side: SIMD3<Float> = alongX ? [0, 0, thickness] : [thickness, 0, 0]
            let index = UInt32(positions.count)
            positions += [low - side, low + side, high + side, high - side]
            indices += alongX ? [index, index + 1, index + 2, index, index + 2, index + 3] : [index, index + 2, index + 1, index, index + 3, index + 2]
        }
        var x = ceil(minimum.x / drawingStep) * drawingStep
        while x <= maximum.x + drawingStep / 10 { strip([x,-0.001,minimum.y], [x,-0.001,maximum.y], alongX: false); x += drawingStep }
        var z = ceil(minimum.y / drawingStep) * drawingStep
        while z <= maximum.y + drawingStep / 10 { strip([minimum.x,-0.001,z], [maximum.x,-0.001,z], alongX: true); z += drawingStep }
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        if let mesh = try? MeshResource.generate(from: [descriptor]) {
            grid.addChild(ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: UIColor(white: 1, alpha: 0.24))]))
        }
        if minimum.y <= 0 && maximum.y >= 0 {
            let axis = ModelEntity(mesh: .generateBox(width: maximum.x - minimum.x, height: 0.001, depth: drawingStep * 0.07), materials: [UnlitMaterial(color: .systemRed)])
            axis.position = [(minimum.x + maximum.x) / 2, 0, 0]
            grid.addChild(axis)
        }
        if minimum.x <= 0 && maximum.x >= 0 {
            let axis = ModelEntity(mesh: .generateBox(width: drawingStep * 0.07, height: 0.001, depth: maximum.y - minimum.y), materials: [UnlitMaterial(color: .systemBlue)])
            axis.position = [0, 0, (minimum.y + maximum.y) / 2]
            grid.addChild(axis)
        }
        root.addChild(grid)
    }

    @MainActor private static let selectionMesh = MeshResource.generateBox(size: 1)

    @MainActor
    private static func updateSelection(_ root: Entity, selected: CADShape?, showDimensions: Bool, immersive: Bool) {
        let name = "cad-selection"
        guard let shape = selected else {
            root.children.first(where: { $0.name == name })?.removeFromParent()
            return
        }
        let signature = "\(shape.id)-\(shape.dimensions)-\(shape.rotationDegrees)-\(shape.isLocked)-\(showDimensions)-\(immersive)"
        if let existing = root.children.first(where: { $0.name == name }),
           existing.components[CADSelectionSignature.self]?.value == signature {
            existing.position = shape.position
            existing.orientation = shape.rotationQuaternion
            return
        }
        root.children.first(where: { $0.name == name })?.removeFromParent()
        let selection = Entity()
        selection.components.set(CADSelectionSignature(value: signature))
        selection.name = name
        selection.position = shape.position
        selection.orientation = shape.rotationQuaternion
        let pad = min(0.001, max(0.00002, max(shape.dimensions.x, max(shape.dimensions.y, shape.dimensions.z)) * 0.005))
        let half = shape.dimensions / 2 + SIMD3<Float>(repeating: pad)
        let thickness = min(0.002, max(0.00001, max(half.x, max(half.y, half.z)) * 0.012))
        let material = UnlitMaterial(color: shape.isLocked ? .systemOrange : .systemMint)
        for x in [Float(-1), Float(1)] {
            for y in [Float(-1), Float(1)] {
                let zEdge = ModelEntity(mesh: selectionMesh, materials: [material])
                zEdge.scale = [thickness, thickness, half.z * 2]
                zEdge.position = [x * half.x, y * half.y, 0]
                selection.addChild(zEdge)
            }
        }
        for x in [Float(-1), Float(1)] {
            for z in [Float(-1), Float(1)] {
                let yEdge = ModelEntity(mesh: selectionMesh, materials: [material])
                yEdge.scale = [thickness, half.y * 2, thickness]
                yEdge.position = [x * half.x, 0, z * half.z]
                selection.addChild(yEdge)
            }
        }
        for y in [Float(-1), Float(1)] {
            for z in [Float(-1), Float(1)] {
                let xEdge = ModelEntity(mesh: selectionMesh, materials: [material])
                xEdge.scale = [half.x * 2, thickness, thickness]
                xEdge.position = [0, y * half.y, z * half.z]
                selection.addChild(xEdge)
            }
        }
        if immersive && showDimensions {
            let d = shape.dimensions * 100
            let text = String(format: "X %.1f · Y %.1f · Z %.1f cm", d.x, d.y, d.z)
            let label = ModelEntity(mesh: .generateText(text, extrusionDepth: 0.0001, font: .systemFont(ofSize: 0.018)), materials: [UnlitMaterial(color: .white)])
            label.position = shape.rotationQuaternion.inverse.act([0, shape.worldHalfExtents.y + 0.025, 0])
            label.components.set(BillboardComponent())
            selection.addChild(label)
        }
        root.addChild(selection)
    }
}
