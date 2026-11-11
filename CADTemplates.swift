import Foundation

/// Starter assemblies built from catalog-style machine parts with real dimensions.
/// Parts are separate solids placed in contact; nothing is fused or Boolean-cut.
enum CADTemplate: String, CaseIterable, Identifiable {
    case shaftSupport, gearReducer, angleBracket, boltedJoint
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shaftSupport: "Pillow-block shaft drive"
        case .gearReducer: "3:1 gear reducer"
        case .angleBracket: "Bolted angle bracket"
        case .boltedJoint: "Bolted plate joint"
        }
    }
    var subtitle: String {
        switch self {
        case .shaftSupport: "A 36 mm shaft runs in bronze sleeves inside two cast pillow blocks, bolted to a base plate and driving a 20-tooth gear."
        case .gearReducer: "A 12-tooth pinion drives a 36-tooth gear of the same 3 mm module. Their shafts sit exactly 72 mm apart."
        case .angleBracket: "Two drilled plates and a welded gusset make an L-bracket, held to a frame block by M8 bolts and washers."
        case .boltedJoint: "Four M10 bolts with washers and nuts clamp two plates through 11 mm clearance holes."
        }
    }
    var icon: String {
        switch self {
        case .shaftSupport: "circle.square"
        case .gearReducer: "gearshape.2"
        case .angleBracket: "righttriangle"
        case .boltedJoint: "hexagon"
        }
    }
    /// The idea this assembly is best at teaching.
    var concept: String {
        switch self {
        case .shaftSupport: "Fits and clearance"
        case .gearReducer: "Module and center distance"
        case .angleBracket: "Position from stacked dimensions"
        case .boltedJoint: "Clearance holes and grip length"
        }
    }
    var investigation: String {
        switch self {
        case .shaftSupport: "The sleeves are bored 37 mm for the 36 mm shaft. Predict the radial clearance. Then make the shaft 37.5 mm across (Width X and Depth Z) and decide whether it would still slide in."
        case .gearReducer: "Swap the 36-tooth gear for a 48-tooth gear of the same 3 mm module. What outside diameter does it need, and how far must its shaft move?"
        case .angleBracket: "Make the upright leg 200 mm tall. It stands on edge, so that is its Width X. What center height keeps it resting on the base leg?"
        case .boltedJoint: "Each M10 bolt passes through 11 mm holes. What is the radial clearance, and how much thread shows below the nut?"
        }
    }
    var reasoningTitle: String {
        switch self {
        case .shaftSupport: "Radial clearance of a shaft in a bore"
        case .gearReducer: "Gear size and spacing from the module"
        case .angleBracket: "Center height above a supporting surface"
        case .boltedJoint: "Clearance and thread protrusion"
        }
    }
    var reasoning: String {
        switch self {
        case .shaftSupport: "Radial clearance = (bore − shaft) ÷ 2 = (37 − 36) ÷ 2 = 0.5 mm. At 37.5 mm it becomes (37 − 37.5) ÷ 2 = −0.25 mm. Negative clearance is interference: the shaft would have to be pressed in."
        case .gearReducer: "Outside ⌀ = module × (teeth + 2) = 3 × 50 = 150 mm. Center distance = module × (12 + 48) ÷ 2 = 90 mm, so the gear shaft moves 18 mm further from the pinion."
        case .angleBracket: "Center height = top of the base leg + half the upright height = 38 + 200 ÷ 2 = 138 mm. Enter 138 mm as the upright’s Y position."
        case .boltedJoint: "Radial clearance = (11 − 10) ÷ 2 = 0.5 mm. The shank is 42 − 7 = 35 mm long; the washer, two plates and nut take 2 + 20 + 8 = 30 mm, so 5 mm of thread shows."
        }
    }

    var shapes: [CADShape] {
        switch self {
        case .shaftSupport: shaftDrive
        case .gearReducer: reducer
        case .angleBracket: bracket
        case .boltedJoint: joint
        }
    }

    private static let onAxisZ = SIMD3<Float>(90, 0, 0)

    private var shaftDrive: [CADShape] {
        let plateTop: Float = 0.012, blockZ: Float = 0.09
        let base = part(1, .plate, "Base plate", [0.22, plateTop, 0.24], [0, plateTop / 2, 0],
                        finish: CADPalette.aluminium, feature: 0.011 / 0.055)
        func block(_ number: Int, _ name: String, _ z: Float) -> CADShape {
            part(number, .bearingBlock, name, [0.14, 0.08, 0.04], [0, plateTop + 0.04, z],
                 finish: CADPalette.castIron, feature: 0.050 / 0.072)
        }
        let front = block(2, "Front pillow block", blockZ), rear = block(3, "Rear pillow block", -blockZ)
        let axisY = front.position.y + front.blockBoreCenterY
        func sleeve(_ number: Int, _ name: String, _ z: Float) -> CADShape {
            part(number, .tube, name, [0.05, 0.044, 0.05], [0, axisY, z], rotation: Self.onAxisZ,
                 finish: CADPalette.bronze, feature: 0.037 / 0.05)
        }
        var parts = [
            base, front, rear,
            sleeve(4, "Front bearing sleeve", blockZ), sleeve(5, "Rear bearing sleeve", -blockZ),
            part(6, .cylinder, "Shaft · 36 mm", [0.036, 0.29, 0.036], [0, axisY, 0.0075], rotation: Self.onAxisZ, finish: CADPalette.steel),
            part(7, .gear, "Drive gear · 20 teeth", [0.088, 0.02, 0.088], [0, axisY, 0.135], rotation: Self.onAxisZ,
                 finish: CADPalette.brass, feature: 0.036 / 0.0525, teeth: 20),
            part(8, .tube, "Shaft collar", [0.056, 0.014, 0.056], [0, axisY, -0.118], rotation: Self.onAxisZ,
                 finish: CADPalette.blackOxide, feature: 0.036 / 0.056)
        ]
        // M10 bolts stand on the feet, halfway between the housing and the end of each foot.
        let footTop = front.position.y - front.dimensions.y / 2 + front.blockFootThickness
        let boltX = (front.blockArchRadius + front.dimensions.x / 2) / 2
        var number = 9
        for z in [blockZ, -blockZ] {
            for x in [boltX, -boltX] {
                parts.append(bolt(number, "Mounting bolt \(number - 8)", size: [0.0185, 0.034, 0.016], shank: 0.010, x: x, z: z, seat: footTop))
                number += 1
            }
        }
        return parts
    }

    private var reducer: [CADShape] {
        let plateTop: Float = 0.01, pinionX: Float = -0.054, gearX: Float = 0.018, gearZ: Float = 0.046
        func block(_ number: Int, _ name: String, _ x: Float) -> CADShape {
            part(number, .bearingBlock, name, [0.068, 0.07, 0.03], [x, plateTop + 0.035, 0],
                 finish: CADPalette.castIron, feature: 0.028 / 0.0408)
        }
        let pinionBlock = block(2, "Pinion pillow block", pinionX), gearBlock = block(3, "Gear pillow block", gearX)
        let axisY = pinionBlock.position.y + pinionBlock.blockBoreCenterY
        var parts = [
            part(1, .plate, "Base plate", [0.17, plateTop, 0.07], [-0.018, plateTop / 2, 0],
                 finish: CADPalette.aluminium, feature: 0.0066 / 0.0175),
            pinionBlock, gearBlock,
            part(4, .tube, "Pinion bearing sleeve", [0.028, 0.034, 0.028], [pinionX, axisY, 0], rotation: Self.onAxisZ,
                 finish: CADPalette.bronze, feature: 0.0125 / 0.028),
            part(5, .tube, "Gear bearing sleeve", [0.028, 0.034, 0.028], [gearX, axisY, 0], rotation: Self.onAxisZ,
                 finish: CADPalette.bronze, feature: 0.0165 / 0.028),
            part(6, .cylinder, "Input shaft · 12 mm", [0.012, 0.11, 0.012], [pinionX, axisY, 0.015], rotation: Self.onAxisZ, finish: CADPalette.steel),
            part(7, .cylinder, "Output shaft · 16 mm", [0.016, 0.11, 0.016], [gearX, axisY, 0.015], rotation: Self.onAxisZ, finish: CADPalette.steel),
            // Turned half a tooth (15°) about its own axis, so its gaps receive the gear's teeth.
            part(8, .gear, "Pinion · 12 teeth", [0.042, 0.014, 0.042], [pinionX, axisY, gearZ], rotation: [90, 0, 15],
                 finish: CADPalette.steel, feature: 0.012 / 0.021375, teeth: 12),
            part(9, .gear, "Gear · 36 teeth", [0.114, 0.014, 0.114], [gearX, axisY, gearZ], rotation: Self.onAxisZ,
                 finish: CADPalette.brass, feature: 0.016 / 0.075375, teeth: 36),
            part(10, .tube, "Input shaft collar", [0.022, 0.01, 0.022], [pinionX, axisY, -0.023], rotation: Self.onAxisZ,
                 finish: CADPalette.blackOxide, feature: 0.012 / 0.022),
            part(11, .tube, "Output shaft collar", [0.028, 0.01, 0.028], [gearX, axisY, -0.023], rotation: Self.onAxisZ,
                 finish: CADPalette.blackOxide, feature: 0.016 / 0.028)
        ]
        let footTop = pinionBlock.position.y - pinionBlock.dimensions.y / 2 + pinionBlock.blockFootThickness
        let boltOffset = (pinionBlock.blockArchRadius + pinionBlock.dimensions.x / 2) / 2
        var number = 12
        for center in [pinionX, gearX] {
            for side: Float in [-1, 1] {
                parts.append(bolt(number, "Mounting bolt \(number - 11)", size: [0.0115, 0.026, 0.010], shank: 0.006,
                                  x: center + side * boltOffset, z: 0, seat: footTop))
                number += 1
            }
        }
        return parts
    }

    private var bracket: [CADShape] {
        let frameTop: Float = 0.03, thickness: Float = 0.008, legTop = frameTop + thickness
        let base = part(2, .plate, "Base leg", [0.14, thickness, 0.08], [0, frameTop + thickness / 2, 0],
                        finish: CADPalette.steel, feature: 0.009 / 0.02)
        let innerFace = -0.07 + thickness
        var parts = [
            part(1, .box, "Machine frame block", [0.18, frameTop, 0.11], [0, frameTop / 2, 0], finish: CADPalette.aluminium),
            base,
            // The same plate turned on edge: its 140 mm width now stands vertical.
            part(3, .plate, "Upright leg", [0.14, thickness, 0.08], [-0.07 + thickness / 2, legTop + 0.07, 0], rotation: [0, 0, 90],
                 finish: CADPalette.steel, feature: 0.009 / 0.02),
            part(4, .wedge, "Gusset", [0.06, 0.06, thickness], [innerFace + 0.03, legTop + 0.03, 0], finish: CADPalette.steel)
        ]
        let washer: Float = 0.0016
        let holes = base.plateHoleCenters.map(base.worldPoint).filter { $0.x > 0 }
        for (index, hole) in holes.enumerated() {
            parts.append(part(5 + index, .tube, "Washer \(index + 1)", [0.016, washer, 0.016], [hole.x, legTop + washer / 2, hole.z],
                              finish: CADPalette.brass, feature: 0.0084 / 0.016))
            parts.append(bolt(7 + index, "M8 bolt \(index + 1)", size: [0.015, 0.03, 0.013], shank: 0.008,
                              x: hole.x, z: hole.z, seat: legTop + washer))
        }
        return parts
    }

    private var joint: [CADShape] {
        let riserTop: Float = 0.04, thickness: Float = 0.01, washer: Float = 0.002, nut: Float = 0.008
        let lower = part(2, .plate, "Lower plate", [0.14, thickness, 0.10], [0, riserTop + thickness / 2, 0],
                         finish: CADPalette.aluminium, feature: 0.011 / 0.025)
        let stackTop = riserTop + 2 * thickness
        var parts = [
            part(1, .box, "Bench riser", [0.06, riserTop, 0.06], [0, riserTop / 2, 0], finish: 0),
            lower,
            part(3, .plate, "Upper plate", [0.14, thickness, 0.10], [0, riserTop + 1.5 * thickness, 0],
                 finish: CADPalette.steel, feature: 0.011 / 0.025)
        ]
        for (index, hole) in lower.plateHoleCenters.map(lower.worldPoint).enumerated() {
            parts.append(part(4 + index, .tube, "Washer \(index + 1)", [0.02, washer, 0.02], [hole.x, stackTop + washer / 2, hole.z],
                              finish: CADPalette.brass, feature: 0.0105 / 0.02))
            parts.append(bolt(8 + index, "M10 bolt \(index + 1)", size: [0.0185, 0.042, 0.016], shank: 0.010,
                              x: hole.x, z: hole.z, seat: stackTop + washer))
            parts.append(part(12 + index, .hexNut, "M10 nut \(index + 1)", [0.0185, nut, 0.016], [hole.x, riserTop - nut / 2, hole.z],
                              finish: CADPalette.steel, feature: 0.010 / 0.016))
        }
        return parts
    }

    /// An upright hex bolt whose head rests on the surface at height `seat`.
    private func bolt(_ number: Int, _ name: String, size: SIMD3<Float>, shank: Float, x: Float, z: Float, seat: Float) -> CADShape {
        var result = part(number, .hexBolt, name, size, .zero, finish: CADPalette.blackOxide)
        result.boreRatio = shank / (result.featureFullDiameter ?? shank)
        result.position = [x, seat + result.boltHeadHeight - size.y / 2, z]
        return result
    }

    private func part(_ number: Int, _ kind: ShapeKind, _ name: String, _ dimensions: SIMD3<Float>,
                      _ position: SIMD3<Float>, rotation: SIMD3<Float> = .zero, finish: Int = 0,
                      feature: Float = 0.6, teeth: Int = 18) -> CADShape {
        // Stable IDs make the sample assemblies reproducible while each loaded workspace remains independent.
        let family = CADTemplate.allCases.firstIndex(of: self)! + 1
        let identifier = UUID(uuidString: String(format: "60010000-0000-0000-%04d-%012d", family, number))!
        return CADShape(id: identifier, kind: kind, position: position, colorIndex: finish,
                        name: name, dimensions: dimensions, rotationDegrees: rotation, boreRatio: feature, teeth: teeth)
    }
}
