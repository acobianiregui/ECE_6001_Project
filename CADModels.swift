import SwiftUI
import RealityKit
import Observation
import simd

// Canonical dimensions and positions are meters. Primitive cylinder/tube axes are local Y.
enum CADUnit: String, CaseIterable, Codable, Identifiable {
    case millimeters, centimeters
    var id: String { rawValue }
    var title: String { self == .millimeters ? "Millimeters" : "Centimeters" }
    var suffix: String { self == .millimeters ? "mm" : "cm" }
    var unitsPerMeter: Float { self == .millimeters ? 1000 : 100 }
}

enum ShapeKind: String, CaseIterable, Identifiable, Codable {
    case box, sphere, cylinder, cone, tube
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .box: "cube"
        case .sphere: "circle"
        case .cylinder: "cylinder"
        case .cone: "triangle"
        case .tube: "circle.circle"
        }
    }
    /// Legacy fallback. CADMeshLibrary supplies the tube's actual annular geometry.
    func mesh() -> MeshResource {
        switch self {
        case .box: .generateBox(size: 0.1)
        case .sphere: .generateSphere(radius: 0.05)
        case .cylinder, .tube: .generateCylinder(height: 0.1, radius: 0.05)
        case .cone: .generateCone(height: 0.1, radius: 0.05)
        }
    }
}

struct CADShape: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ShapeKind
    var position: SIMD3<Float>
    var colorIndex: Int
    var name: String
    var dimensions: SIMD3<Float>
    var rotationDegrees: SIMD3<Float>
    var isHidden: Bool
    var isLocked: Bool
    /// Inner/outer diameter ratio, shared by the local X and Z elliptical cross-section axes.
    var boreRatio: Float

    init(id: UUID = UUID(), kind: ShapeKind, position: SIMD3<Float>, scale: Float = 1,
         colorIndex: Int = 0, name: String? = nil, dimensions: SIMD3<Float>? = nil,
         rotationDegrees: SIMD3<Float> = .zero, isHidden: Bool = false, isLocked: Bool = false,
         boreRatio: Float = 0.6) {
        self.id = id
        self.kind = kind
        self.position = position
        self.colorIndex = colorIndex
        self.name = name ?? kind.label
        self.dimensions = dimensions ?? .init(repeating: 0.1 * scale)
        self.rotationDegrees = rotationDegrees
        self.isHidden = isHidden
        self.isLocked = isLocked
        self.boreRatio = boreRatio
    }

    /// Legacy size API: longest local dimension relative to the original 10 cm primitive.
    /// Setting it scales proportionally, preserving independently edited dimensions.
    var scale: Float {
        get { max(dimensions.x, max(dimensions.y, dimensions.z)) / 0.1 }
        set {
            let old = scale
            dimensions = old > 0 ? dimensions * (newValue / old) : .init(repeating: newValue * 0.1)
        }
    }
    var sizeCM: Float { max(dimensions.x, max(dimensions.y, dimensions.z)) * 100 }
    /// Apply local X, then Y, then Z rotations. Shared with scene rendering and OBJ export.
    var rotationQuaternion: simd_quatf {
        let radians = rotationDegrees * (.pi / 180)
        return simd_quatf(angle: radians.z, axis: [0, 0, 1])
            * simd_quatf(angle: radians.y, axis: [0, 1, 0])
            * simd_quatf(angle: radians.x, axis: [1, 0, 0])
    }
    /// Conservative world-axis bounding half extents; not a solid collision test.
    var worldHalfExtents: SIMD3<Float> {
        let matrix = simd_float3x3(rotationQuaternion)
        let half = dimensions / 2
        func absolute(_ vector: SIMD3<Float>) -> SIMD3<Float> { [abs(vector.x), abs(vector.y), abs(vector.z)] }
        return absolute(matrix.columns.0) * half.x
            + absolute(matrix.columns.1) * half.y
            + absolute(matrix.columns.2) * half.z
    }
    var halfHeight: Float { worldHalfExtents.y }

    private enum CodingKeys: String, CodingKey {
        case id, kind, position, scale, colorIndex, name, dimensions, rotationDegrees, isHidden, isLocked, boreRatio
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try values.decode(ShapeKind.self, forKey: .kind)
        position = try values.decode(SIMD3<Float>.self, forKey: .position)
        colorIndex = try values.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? kind.label
        let oldScale = try values.decodeIfPresent(Float.self, forKey: .scale) ?? 1
        dimensions = try values.decodeIfPresent(SIMD3<Float>.self, forKey: .dimensions) ?? .init(repeating: oldScale * 0.1)
        rotationDegrees = try values.decodeIfPresent(SIMD3<Float>.self, forKey: .rotationDegrees) ?? .zero
        isHidden = try values.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        isLocked = try values.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        boreRatio = try values.decodeIfPresent(Float.self, forKey: .boreRatio) ?? 0.6
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(position, forKey: .position)
        try values.encode(scale, forKey: .scale)
        try values.encode(colorIndex, forKey: .colorIndex)
        try values.encode(name, forKey: .name)
        try values.encode(dimensions, forKey: .dimensions)
        try values.encode(rotationDegrees, forKey: .rotationDegrees)
        try values.encode(isHidden, forKey: .isHidden)
        try values.encode(isLocked, forKey: .isLocked)
        try values.encode(boreRatio, forKey: .boreRatio)
    }
}

struct CADSavedDesign: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var date: Date
    var shapes: [CADShape]
}

enum CADPalette {
    static let names = ["Blue", "Coral", "Green", "Gold", "Violet", "Teal"]
    static let hues: [CGFloat] = [0.58, 0.02, 0.33, 0.12, 0.78, 0.5]
    static func color(_ index: Int, selected: Bool) -> UIColor {
        let safeIndex = ((index % hues.count) + hues.count) % hues.count
        return UIColor(hue: hues[safeIndex], saturation: selected ? 0.45 : 0.8, brightness: 1, alpha: 1)
    }
}

@Observable
final class CADModel {
    static let gridSpacings: [Float] = [0.001, 0.005, 0.01, 0.05]
    var shapes: [CADShape] = [] { didSet { persist() } }
    var selectedID: UUID? { didSet { persist() } }
    var snapEnabled = true { didSet { persist() } }
    var gridSpacing: Float = 0.005 {
        didSet {
            if !Self.gridSpacings.contains(where: { abs($0 - gridSpacing) < 0.0000001 }) { gridSpacing = 0.005 }
            persist()
        }
    }
    var units: CADUnit = .millimeters { didSet { persist() } }
    private(set) var savedDesigns: [CADSavedDesign] = [] { didSet { persist() } }
    var gridStep: Float { gridSpacing }
    @ObservationIgnored private let defaults: UserDefaults
    // Keep the existing key so current workplanes and old saved snapshots migrate in place.
    @ObservationIgnored private let storageKey = "AVPLearn.cad.v2"
    private var history: [Snapshot] = []
    private var future: [Snapshot] = []

    private struct Snapshot: Equatable {
        var shapes: [CADShape]
        var selectedID: UUID?
        var snapEnabled: Bool
        var gridSpacing: Float
        var units: CADUnit
        var savedDesigns: [CADSavedDesign]
    }
    private struct Archive: Codable {
        var version = 3
        var shapes: [CADShape]
        var selectedID: UUID?
        var snapEnabled: Bool
        var gridSpacing: Float
        var units: CADUnit
        var savedDesigns: [CADSavedDesign]
        private enum CodingKeys: String, CodingKey { case version, shapes, selectedID, snapEnabled, gridSpacing, units, savedDesigns }
        init(snapshot: Snapshot) {
            shapes = snapshot.shapes; selectedID = snapshot.selectedID; snapEnabled = snapshot.snapEnabled
            gridSpacing = snapshot.gridSpacing; units = snapshot.units; savedDesigns = snapshot.savedDesigns
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 2
            shapes = try values.decode([CADShape].self, forKey: .shapes)
            selectedID = try values.decodeIfPresent(UUID.self, forKey: .selectedID)
            snapEnabled = try values.decodeIfPresent(Bool.self, forKey: .snapEnabled) ?? true
            gridSpacing = try values.decodeIfPresent(Float.self, forKey: .gridSpacing) ?? 0.05
            units = try values.decodeIfPresent(CADUnit.self, forKey: .units) ?? .centimeters
            savedDesigns = try values.decodeIfPresent([CADSavedDesign].self, forKey: .savedDesigns) ?? []
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey), let archive = try? JSONDecoder().decode(Archive.self, from: data) {
            shapes = Self.validated(archive.shapes)
            selectedID = shapes.contains(where: { $0.id == archive.selectedID }) ? archive.selectedID : nil
            snapEnabled = archive.snapEnabled
            gridSpacing = Self.gridSpacings.contains(archive.gridSpacing) ? archive.gridSpacing : 0.005
            units = archive.units
            savedDesigns = archive.savedDesigns.prefix(6).map {
                CADSavedDesign(id: $0.id, name: $0.name, date: $0.date, shapes: Self.validated($0.shapes))
            }
        }
    }

    var selected: CADShape? { shapes.first { $0.id == selectedID } }
    var canUndo: Bool { history.contains { $0 != snapshot } }
    var canRedo: Bool { future.contains { $0 != snapshot } }
    var canAdd: Bool { shapes.count < 80 }
    var coachTip: String {
        if shapes.isEmpty { return "Start from an engineering assembly or add a primitive. Dimensions are local X/Y/Z; position is the center in world coordinates." }
        if selected == nil { return "Select a part in the scene or object list. Hidden parts can still be selected from the list." }
        if selected?.isLocked == true { return "This part is locked. Unlock it to change its geometry, position, or rotation." }
        return "Apply precise dimensions and rotation, then align centers or stack bounding boxes. Units change the readout; the model stays in meters."
    }
    private var snapshot: Snapshot {
        Snapshot(shapes: shapes, selectedID: selectedID, snapEnabled: snapEnabled, gridSpacing: gridSpacing, units: units, savedDesigns: savedDesigns)
    }
    func snap(_ value: SIMD3<Float>) -> SIMD3<Float> {
        snapEnabled ? (value / gridSpacing).rounded(.toNearestOrAwayFromZero) * gridSpacing : value
    }
    func beginEdit() {
        let current = snapshot
        if history.last != current { history.append(current) }
        if history.count > 50 { history.removeFirst() }
        future.removeAll()
    }
    func add(_ kind: ShapeKind) {
        guard canAdd else { return }
        beginEdit()
        let offset = Float(shapes.count % 5) * 0.15
        let count = shapes.filter { $0.kind == kind }.count + 1
        let shape = CADShape(kind: kind, position: [offset, 0.05, 0], colorIndex: shapes.count % CADPalette.hues.count, name: "\(kind.label) \(count)")
        shapes.append(shape)
        selectedID = shape.id
    }
    func select(_ id: UUID?) { selectedID = shapes.contains(where: { $0.id == id }) ? id : nil }

    // Numeric transforms and rename use the caller's beginEdit(), allowing one undo per Apply or gesture.
    func setPosition(_ id: UUID, _ value: SIMD3<Float>) {
        guard Self.isFinite(value), let index = editableIndex(id) else { return }
        var shape = shapes[index]
        shape.position = snap(value)
        shape.position = Self.boundedPosition(shape.position, halfHeight: shape.halfHeight)
        shapes[index] = shape
    }
    func setDimensions(_ id: UUID, _ meters: SIMD3<Float>) {
        guard Self.isFinite(meters), let index = editableIndex(id) else { return }
        var shape = shapes[index]
        shape.dimensions = Self.boundedDimensions(meters)
        shape.position = Self.boundedPosition(shape.position, halfHeight: shape.halfHeight)
        shapes[index] = shape
    }
    func setRotation(_ id: UUID, _ degrees: SIMD3<Float>) {
        guard Self.isFinite(degrees), let index = editableIndex(id) else { return }
        var shape = shapes[index]
        shape.rotationDegrees = Self.normalizedRotation(degrees)
        shape.position = Self.boundedPosition(shape.position, halfHeight: shape.halfHeight)
        shapes[index] = shape
    }
    func setScale(_ id: UUID, _ value: Float) {
        guard value.isFinite, let index = editableIndex(id) else { return }
        var shape = shapes[index]
        shape.scale = min(max(value, 0.01), 10)
        shape.dimensions = Self.boundedDimensions(shape.dimensions)
        shape.position = Self.boundedPosition(shape.position, halfHeight: shape.halfHeight)
        shapes[index] = shape
    }
    func rename(_ id: UUID, _ name: String) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        shapes[index].name = cleaned.isEmpty ? shapes[index].kind.label : String(cleaned.prefix(60))
    }
    func setBoreRatio(_ id: UUID, _ value: Float) {
        guard value.isFinite, let index = editableIndex(id), shapes[index].kind == .tube else { return }
        shapes[index].boreRatio = min(max(value, 0.1), 0.9)
    }
    func toggleVisibility(_ id: UUID) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        beginEdit()
        shapes[index].isHidden.toggle()
    }
    func toggleLock(_ id: UUID) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        beginEdit()
        shapes[index].isLocked.toggle()
    }
    func setColor(_ color: Int) {
        guard let id = selectedID, let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        beginEdit()
        shapes[index].colorIndex = ((color % CADPalette.hues.count) + CADPalette.hues.count) % CADPalette.hues.count
    }
    func placeOnPlane() {
        guard let shape = selected, !shape.isLocked, let index = editableIndex(shape.id) else { return }
        beginEdit()
        shapes[index].position.y = shape.halfHeight
    }
    func alignSelected(to referenceID: UUID, axis: Int) {
        guard (0...2).contains(axis), let shape = selected, shape.id != referenceID,
              let index = editableIndex(shape.id), let reference = shapes.first(where: { $0.id == referenceID }) else { return }
        beginEdit()
        var position = shape.position
        position[axis] = reference.position[axis]
        shapes[index].position = Self.boundedPosition(position, halfHeight: shape.halfHeight)
    }
    /// Align X/Z centers and make conservative world-axis bounding boxes touch; not a contact solver.
    func stackSelected(on referenceID: UUID) {
        guard let shape = selected, shape.id != referenceID, let index = editableIndex(shape.id),
              let reference = shapes.first(where: { $0.id == referenceID }) else { return }
        let centerY = reference.position.y + reference.halfHeight + shape.halfHeight
        guard centerY <= 1.5 else { return }
        beginEdit()
        shapes[index].position = [reference.position.x, centerY, reference.position.z]
    }
    func duplicateSelected() {
        guard canAdd, var shape = selected else { return }
        beginEdit()
        shape.id = UUID()
        shape.name = String((shape.name + " copy").prefix(60))
        shape.isLocked = false
        shape.isHidden = false
        shape.position.x = min(shape.position.x + max(gridSpacing, shape.worldHalfExtents.x * 2), 0.9)
        shapes.append(shape)
        selectedID = shape.id
    }
    func deleteSelected() {
        guard let id = selectedID, editableIndex(id) != nil else { return }
        beginEdit()
        shapes.removeAll { $0.id == id }
        selectedID = shapes.last?.id
    }
    func undo() {
        let current = snapshot
        while let previous = history.popLast() {
            guard previous != current else { continue }
            future.append(current)
            restore(previous)
            return
        }
    }
    func redo() {
        let current = snapshot
        while let next = future.popLast() {
            guard next != current else { continue }
            history.append(current)
            restore(next)
            return
        }
    }
    /// Local clear respects part locks. Explicit project/template loads replace the whole workspace with undo.
    func clear() {
        guard shapes.contains(where: { !$0.isLocked }) else { return }
        beginEdit()
        shapes.removeAll { !$0.isLocked }
        selectedID = shapes.first?.id
    }
    func loadTemplate(_ template: CADTemplate) {
        beginEdit()
        shapes = Self.validated(template.shapes)
        selectedID = shapes.first?.id
        gridSpacing = 0.005
        units = .millimeters
    }
    func saveDesign(named name: String) {
        guard !shapes.isEmpty else { return }
        beginEdit()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        savedDesigns.insert(CADSavedDesign(name: trimmed.isEmpty ? "Design \(savedDesigns.count + 1)" : String(trimmed.prefix(50)), date: Date(), shapes: shapes), at: 0)
        if savedDesigns.count > 6 { savedDesigns.removeLast() }
    }
    func loadDesign(_ design: CADSavedDesign) {
        beginEdit()
        shapes = Self.validated(design.shapes)
        selectedID = shapes.first?.id
    }
    func deleteDesign(_ id: UUID) {
        guard savedDesigns.contains(where: { $0.id == id }) else { return }
        beginEdit()
        savedDesigns.removeAll { $0.id == id }
    }
    private func editableIndex(_ id: UUID) -> Int? { shapes.firstIndex { $0.id == id && !$0.isLocked } }
    private func restore(_ state: Snapshot) {
        shapes = state.shapes
        selectedID = shapes.contains(where: { $0.id == state.selectedID }) ? state.selectedID : nil
        snapEnabled = state.snapEnabled
        gridSpacing = state.gridSpacing
        units = state.units
        savedDesigns = state.savedDesigns
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(Archive(snapshot: snapshot)) { defaults.set(data, forKey: storageKey) }
    }
    private static func isFinite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
    private static func boundedDimensions(_ value: SIMD3<Float>) -> SIMD3<Float> {
        [min(max(value.x, 0.001), 1), min(max(value.y, 0.001), 1), min(max(value.z, 0.001), 1)]
    }
    private static func boundedPosition(_ value: SIMD3<Float>, halfHeight: Float) -> SIMD3<Float> {
        [min(max(value.x, -0.9), 0.9), min(max(value.y, halfHeight), 1.5), min(max(value.z, -0.9), 0.9)]
    }
    private static func normalizedRotation(_ value: SIMD3<Float>) -> SIMD3<Float> {
        func wrap(_ angle: Float) -> Float {
            let remainder = angle.truncatingRemainder(dividingBy: 360)
            return remainder > 180 ? remainder - 360 : remainder < -180 ? remainder + 360 : remainder
        }
        return [wrap(value.x), wrap(value.y), wrap(value.z)]
    }
    private static func validated(_ input: [CADShape]) -> [CADShape] {
        var seen: Set<UUID> = []
        return input.prefix(80).compactMap { original in
            guard seen.insert(original.id).inserted, isFinite(original.position), isFinite(original.dimensions), isFinite(original.rotationDegrees), original.boreRatio.isFinite else { return nil }
            var shape = original
            shape.dimensions = boundedDimensions(shape.dimensions)
            shape.rotationDegrees = normalizedRotation(shape.rotationDegrees)
            shape.position = boundedPosition(shape.position, halfHeight: shape.halfHeight)
            shape.boreRatio = min(max(shape.boreRatio, 0.1), 0.9)
            let trimmed = shape.name.trimmingCharacters(in: .whitespacesAndNewlines)
            shape.name = trimmed.isEmpty ? shape.kind.label : String(trimmed.prefix(60))
            return shape
        }
    }
}

enum CADChallenge: String, CaseIterable, Identifiable {
    case support, stack, twins
    var id: String { rawValue }
    var title: String {
        switch self {
        case .support: "01 · Make a support"
        case .stack: "02 · Build a two-part assembly"
        case .twins: "03 · Align matching parts"
        }
    }
    var objective: String {
        switch self {
        case .support: "Create a 200 × 200 × 200 mm box, unrotated, with its base on the plane. Explain why its center is 100 mm high."
        case .stack: "Center an unrotated 100 × 100 × 100 mm cylinder on that 200 mm box. Its center should be 250 mm high."
        case .twins: "Make two unrotated 100 mm boxes on the plane. Align Z centers and separate X centers by 150 mm."
        }
    }
    func checks(in shapes: [CADShape]) -> [(String, Bool)] {
        let close: (Float, Float) -> Bool = { abs($0 - $1) < 0.001 }
        let visible = shapes.filter { !$0.isHidden }
        func sized(_ shape: CADShape, _ meters: Float) -> Bool {
            close(shape.dimensions.x, meters) && close(shape.dimensions.y, meters) && close(shape.dimensions.z, meters)
        }
        func unrotated(_ shape: CADShape) -> Bool {
            abs(shape.rotationQuaternion.real) > 0.99999
        }
        let supports = visible.filter { $0.kind == .box && sized($0, 0.2) && unrotated($0) && close($0.position.y, 0.1) }
        switch self {
        case .support:
            return [("Visible, unrotated box measures 200 mm on every axis", visible.contains { $0.kind == .box && sized($0, 0.2) && unrotated($0) }),
                    ("Box base touches the plane", !supports.isEmpty)]
        case .stack:
            let stacked = supports.contains { base in
                visible.contains { $0.kind == .cylinder && sized($0, 0.1) && unrotated($0) && close($0.position.x, base.position.x) && close($0.position.z, base.position.z) && close($0.position.y, 0.25) }
            }
            return [("200 mm support box rests on the plane", !supports.isEmpty), ("100 mm upright cylinder is centered on the box", stacked)]
        case .twins:
            let boxes = visible.filter { $0.kind == .box && sized($0, 0.1) && unrotated($0) && close($0.position.y, 0.05) }
            let aligned = boxes.contains { first in boxes.contains { second in
                first.id != second.id && close(first.position.z, second.position.z) && close(abs(first.position.x - second.position.x), 0.15)
            } }
            return [("Two visible 100 mm boxes rest unrotated on the plane", boxes.count >= 2), ("Z centers match; X centers are 150 mm apart", aligned)]
        }
    }
}
