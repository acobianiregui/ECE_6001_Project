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

enum ShapeKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case box, sphere, cylinder, cone, tube, wedge, plate, gear, hexBolt, hexNut, bearingBlock
    var id: String { rawValue }
    var label: String {
        switch self {
        case .box: "Box"
        case .sphere: "Sphere"
        case .cylinder: "Cylinder"
        case .cone: "Cone"
        case .tube: "Tube"
        case .wedge: "Wedge"
        case .plate: "Plate"
        case .gear: "Gear"
        case .hexBolt: "Hex bolt"
        case .hexNut: "Hex nut"
        case .bearingBlock: "Bearing block"
        }
    }
    var icon: String {
        switch self {
        case .box: "cube"
        case .sphere: "circle"
        case .cylinder: "cylinder"
        case .cone: "cone"
        case .tube: "circle.circle"
        case .wedge: "righttriangle"
        case .plate: "circle.grid.2x2"
        case .gear: "gearshape"
        case .hexBolt: "screwdriver"
        case .hexNut: "hexagon"
        case .bearingBlock: "circle.square"
        }
    }
    /// One line on what the part is for, shown where a learner chooses what to add.
    var role: String {
        switch self {
        case .box: "Blocks, bars and supports"
        case .sphere: "Balls and knobs"
        case .cylinder: "Shafts, pins and rods"
        case .cone: "Tapers and points"
        case .tube: "Bushings, collars and washers"
        case .wedge: "Gussets and ramps"
        case .plate: "Mounting plate with four bolt holes"
        case .gear: "Spur gear with a keyed bore"
        case .hexBolt: "Threaded fastener with a hex head"
        case .hexNut: "Clamps a bolted joint"
        case .bearingBlock: "Pillow block that carries a shaft"
        }
    }
    /// Machine parts carry real features (holes, teeth, threads); solids are plain building blocks.
    var isMachinePart: Bool {
        switch self {
        case .box, .sphere, .cylinder, .cone, .tube, .wedge: false
        case .plate, .gear, .hexBolt, .hexNut, .bearingBlock: true
        }
    }
    /// Size of a newly added part, in meters. Solids start as the familiar 100 mm primitive.
    var defaultDimensions: SIMD3<Float> {
        switch self {
        case .box, .sphere, .cylinder, .cone, .tube: [0.1, 0.1, 0.1]
        case .wedge: [0.08, 0.08, 0.02]
        case .plate: [0.12, 0.008, 0.08]
        case .gear: [0.06, 0.012, 0.06]
        case .hexBolt: [0.015, 0.04, 0.013]
        case .hexNut: [0.015, 0.0065, 0.013]
        case .bearingBlock: [0.1, 0.06, 0.03]
        }
    }
    /// What the shared feature ratio controls for this kind, if anything.
    var featureLabel: String? {
        switch self {
        case .tube, .gear, .bearingBlock: "Bore ⌀"
        case .hexNut: "Thread ⌀"
        case .hexBolt: "Shank ⌀"
        case .plate: "Hole ⌀"
        case .box, .sphere, .cylinder, .cone, .wedge: nil
        }
    }
}

struct CADShape: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var kind: ShapeKind
    var position: SIMD3<Float>
    var colorIndex: Int
    var name: String
    var dimensions: SIMD3<Float>
    var rotationDegrees: SIMD3<Float>
    var isHidden: Bool
    var isLocked: Bool
    /// Feature size as a fraction of the largest it could be: a tube's inner/outer diameter ratio,
    /// a plate's hole size, a bolt's shank, and so on. See `featureFullDiameter`.
    var boreRatio: Float
    /// Tooth count; only gears use it.
    var teeth: Int

    init(id: UUID = UUID(), kind: ShapeKind, position: SIMD3<Float>, scale: Float = 1,
         colorIndex: Int = 0, name: String? = nil, dimensions: SIMD3<Float>? = nil,
         rotationDegrees: SIMD3<Float> = .zero, isHidden: Bool = false, isLocked: Bool = false,
         boreRatio: Float = 0.6, teeth: Int = 18) {
        self.teeth = teeth
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
        case id, kind, position, scale, colorIndex, name, dimensions, rotationDegrees, isHidden, isLocked, boreRatio, teeth
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
        teeth = try values.decodeIfPresent(Int.self, forKey: .teeth) ?? 18
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
        try values.encode(teeth, forKey: .teeth)
    }
}

/// Feature geometry derived from a part's bounding dimensions. The mesh builder, the inspector,
/// the starter assemblies and the challenges all read these, so a hole is in one place for all of them.
extension CADShape {
    /// Half the across-flats width of a hex bolt head or nut. Across-corners runs along local X.
    var hexFlatRadius: Float { min(dimensions.x / 2 * 0.8660254, dimensions.z / 2) }
    /// Root-circle radius of a gear as a fraction of its outside radius.
    var gearRootFraction: Float { (Float(teeth) - 2.5) / (Float(teeth) + 2) }
    /// Radius of the arch over a bearing block's bore.
    var blockArchRadius: Float { min(0.45 * dimensions.y, 0.3 * dimensions.x) }
    /// Height of a bearing block's bore axis above the part's center, along local Y.
    var blockBoreCenterY: Float { dimensions.y / 2 - blockArchRadius }
    /// Thickness of a bearing block's mounting feet.
    var blockFootThickness: Float { 0.2 * dimensions.y }

    /// The feature diameter a ratio of 1 would give, in meters; nil for kinds without a feature.
    var featureFullDiameter: Float? {
        switch kind {
        case .tube: dimensions.x
        case .gear: 0.75 * gearRootFraction * dimensions.x
        case .hexBolt, .hexNut: 2 * hexFlatRadius
        case .plate: 0.25 * min(dimensions.x, dimensions.z)
        case .bearingBlock: 2 * blockArchRadius
        case .box, .sphere, .cylinder, .cone, .wedge: nil
        }
    }
    /// Bore, hole, thread or shank diameter in meters.
    var featureDiameter: Float? { featureFullDiameter.map { $0 * boreRatio } }

    /// Gear module: the tooth-size number two gears must share to mesh. Outside ⌀ = module × (teeth + 2).
    var gearModule: Float? { kind == .gear ? dimensions.x / Float(teeth + 2) : nil }
    /// Pitch diameter: the circle on which meshing gears roll. Pitch ⌀ = module × teeth.
    var pitchDiameter: Float? { gearModule.map { $0 * Float(teeth) } }

    /// Height of a hex bolt's head; the rest of the length is shank.
    var boltHeadHeight: Float { min(0.7 * (featureDiameter ?? 0), 0.45 * dimensions.y) }

    /// Distance from each plate edge to its hole centers.
    var plateHoleInset: Float {
        let narrow = min(dimensions.x, dimensions.z)
        return min(max(1.6 * boreRatio * 0.25 * narrow, 0.12 * narrow), 0.25 * narrow)
    }
    /// Hole centers of a plate in its local frame (holes run along local Y).
    var plateHoleCenters: [SIMD3<Float>] {
        guard kind == .plate else { return [] }
        let x = dimensions.x / 2 - plateHoleInset, z = dimensions.z / 2 - plateHoleInset
        return [[x, 0, z], [-x, 0, z], [-x, 0, -z], [x, 0, -z]]
    }
    /// A local point in workspace coordinates.
    func worldPoint(_ local: SIMD3<Float>) -> SIMD3<Float> { rotationQuaternion.act(local) + position }
}

struct CADSavedDesign: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var date: Date
    var shapes: [CADShape]
}

/// A surface finish: a colour, how it reflects light, and the density used for mass estimates.
struct CADFinish {
    let name: String
    let material: String
    let red: Float, green: Float, blue: Float
    let isMetal: Bool
    let roughness: Float
    /// Grams per cubic centimeter.
    let density: Float
}

enum CADPalette {
    /// Hue and saturation at full brightness, as red, green and blue from 0 to 1.
    static func rgb(hue: Float, saturation: Float) -> SIMD3<Float> {
        let sector = (hue - hue.rounded(.down)) * 6, fraction = sector - sector.rounded(.down)
        let low = 1 - saturation, falling = 1 - saturation * fraction, rising = 1 - saturation * (1 - fraction)
        switch Int(sector) % 6 {
        case 0: return [1, rising, low]
        case 1: return [falling, 1, low]
        case 2: return [low, 1, rising]
        case 3: return [low, falling, 1]
        case 4: return [rising, low, 1]
        default: return [1, low, falling]
        }
    }
    private static func paint(_ name: String, hue: Float) -> CADFinish {
        // Saturation 0.8, brightness 1: the six colours earlier designs were saved with.
        let color = rgb(hue: hue, saturation: 0.8)
        return CADFinish(name: name, material: "Painted ABS plastic", red: color.x, green: color.y, blue: color.z,
                         isMetal: false, roughness: 0.45, density: 1.05)
    }
    private static func metal(_ name: String, _ material: String, _ red: Float, _ green: Float, _ blue: Float,
                              roughness: Float, density: Float) -> CADFinish {
        CADFinish(name: name, material: material, red: red, green: green, blue: blue,
                  isMetal: true, roughness: roughness, density: density)
    }
    /// Indices 0–5 are the original colours, so saved designs keep their look. Metals follow.
    static let finishes: [CADFinish] = [
        paint("Blue", hue: 0.58), paint("Coral", hue: 0.02), paint("Green", hue: 0.33),
        paint("Gold", hue: 0.12), paint("Violet", hue: 0.78), paint("Teal", hue: 0.5),
        metal("Steel", "Carbon steel", 0.72, 0.74, 0.77, roughness: 0.32, density: 7.85),
        metal("Aluminium", "6061 aluminium", 0.86, 0.87, 0.89, roughness: 0.42, density: 2.70),
        metal("Brass", "Brass", 0.86, 0.70, 0.36, roughness: 0.3, density: 8.50),
        metal("Bronze", "Bearing bronze", 0.74, 0.47, 0.26, roughness: 0.38, density: 8.80),
        metal("Cast iron", "Grey cast iron", 0.36, 0.38, 0.41, roughness: 0.62, density: 7.20),
        metal("Black oxide", "Black-oxide steel", 0.14, 0.15, 0.17, roughness: 0.5, density: 7.85)
    ]
    static let paintCount = 6
    static let steel = 6, aluminium = 7, brass = 8, bronze = 9, castIron = 10, blackOxide = 11
    static var count: Int { finishes.count }
    static func finish(_ index: Int) -> CADFinish { finishes[((index % count) + count) % count] }
    static func color(_ index: Int, selected: Bool) -> UIColor {
        let finish = finish(index)
        // A selected part is lifted toward white so it reads as picked without changing its finish.
        let lift: Float = selected ? 0.35 : 0
        func channel(_ value: Float) -> CGFloat { CGFloat(value + (1 - value) * lift) }
        return UIColor(red: channel(finish.red), green: channel(finish.green), blue: channel(finish.blue), alpha: 1)
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
        if shapes.isEmpty { return "Load a starter assembly to take a real mechanism apart, or add a part and build your own." }
        if selected == nil { return "Tap a part in the 3D view or in the Parts list to inspect and edit it." }
        if selected?.isLocked == true { return "This part is locked. Unlock it to change its size, position, or rotation." }
        return "Drag the part to move it, or type exact values in the inspector. Position is the part’s center."
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
        let dimensions = kind.defaultDimensions
        // Solids cycle through the paint colours; machine parts arrive in steel, as they would from a supplier.
        let finish = kind.isMachinePart ? CADPalette.steel : shapes.count % CADPalette.paintCount
        let shape = CADShape(kind: kind, position: [offset, dimensions.y / 2, 0], colorIndex: finish,
                             name: "\(kind.label) \(count)", dimensions: dimensions)
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
        guard value.isFinite, let index = editableIndex(id), shapes[index].kind.featureLabel != nil else { return }
        shapes[index].boreRatio = min(max(value, 0.1), 0.9)
    }
    func setTeeth(_ id: UUID, _ value: Int) {
        guard let index = editableIndex(id), shapes[index].kind == .gear else { return }
        shapes[index].teeth = min(max(value, 8), 60)
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
        shapes[index].colorIndex = ((color % CADPalette.count) + CADPalette.count) % CADPalette.count
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
            shape.teeth = min(max(shape.teeth, 8), 60)
            let trimmed = shape.name.trimmingCharacters(in: .whitespacesAndNewlines)
            shape.name = trimmed.isEmpty ? shape.kind.label : String(trimmed.prefix(60))
            return shape
        }
    }
}

enum CADChallenge: String, CaseIterable, Identifiable {
    case support, stack, twins, mesh, fasten
    var id: String { rawValue }
    var title: String {
        switch self {
        case .support: "01 · Make a support"
        case .stack: "02 · Build a two-part assembly"
        case .twins: "03 · Align matching parts"
        case .mesh: "04 · Mesh two gears"
        case .fasten: "05 · Seat a bolt in a hole"
        }
    }
    var objective: String {
        switch self {
        case .support: "Create a 200 × 200 × 200 mm box, unrotated, with its base on the plane. Explain why its center is 100 mm high."
        case .stack: "Center an unrotated 100 × 100 × 100 mm cylinder on that 200 mm box. Its center should be 250 mm high."
        case .twins: "Make two unrotated 100 mm boxes on the plane. Align Z centers and separate X centers by 150 mm."
        case .mesh: "Lay two gears flat at the same height so their teeth mesh. Gears mesh only when they share a module, and their centers must be half the sum of their pitch diameters apart."
        case .fasten: "Raise a plate off the workplane, then drop an upright hex bolt through one of its holes until the head rests on the plate."
        }
    }
    /// How to get there, for a learner who is stuck.
    var hint: String {
        switch self {
        case .support: "Add a Box, then type 200 mm for all three sizes. Rest on workplane puts its base at Y = 0, so its center sits at half its height."
        case .stack: "Add a Cylinder, pick the box as the reference part, and use Stack on reference. Center height = 200 + 100 ÷ 2."
        case .twins: "Add two Boxes. Give them the same Z, and X values 150 mm apart. New parts already arrive 150 mm apart."
        case .mesh: "Two new gears share module 3 mm and have 54 mm pitch diameters, so their centers go 54 mm apart. A 5 mm grid cannot land on 54: switch to the 1 mm grid."
        case .fasten: "Stack the plate on a box so the bolt has room below. The inspector lists the plate’s hole inset and the bolt’s head height. Bolt center Y = plate top + head height − length ÷ 2."
        }
    }
    func checks(in shapes: [CADShape]) -> [(String, Bool)] {
        let close: (Float, Float) -> Bool = { abs($0 - $1) < 0.001 }
        let fine: (Float, Float) -> Bool = { abs($0 - $1) < 0.0005 }
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
        case .mesh:
            let gears = visible.filter { $0.kind == .gear && unrotated($0) }
            var matched = false, level = false, meshed = false
            for first in gears {
                for second in gears where first.id != second.id {
                    guard let a = first.gearModule, let b = second.gearModule, abs(a - b) <= 0.01 * a,
                          let pitchA = first.pitchDiameter, let pitchB = second.pitchDiameter else { continue }
                    matched = true
                    guard fine(first.position.y, second.position.y) else { continue }
                    level = true
                    let offset = second.position - first.position
                    if fine((offset.x * offset.x + offset.z * offset.z).squareRoot(), (pitchA + pitchB) / 2) { meshed = true }
                }
            }
            return [("Two visible, flat gears share one module", matched),
                    ("Both gears sit at the same height", level),
                    ("Center distance is half the sum of the pitch diameters", meshed)]
        case .fasten:
            let plates = visible.filter { $0.kind == .plate && unrotated($0) }
            let bolts = visible.filter { $0.kind == .hexBolt && unrotated($0) }
            var onAxis = false, clear = false, seated = false
            for plate in plates {
                for bolt in bolts {
                    let centered = plate.plateHoleCenters.map(plate.worldPoint).contains {
                        fine($0.x, bolt.position.x) && fine($0.z, bolt.position.z)
                    }
                    guard centered else { continue }
                    onAxis = true
                    guard let shank = bolt.featureDiameter, let hole = plate.featureDiameter, shank < hole else { continue }
                    clear = true
                    let underHead = bolt.position.y + bolt.dimensions.y / 2 - bolt.boltHeadHeight
                    if fine(underHead, plate.position.y + plate.dimensions.y / 2) { seated = true }
                }
            }
            return [("An upright bolt’s axis passes through a hole center of a flat plate", onAxis),
                    ("The shank is narrower than the hole, leaving clearance", clear),
                    ("The underside of the bolt head touches the plate’s top face", seated)]
        }
    }
}
