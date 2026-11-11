import Foundation
import AppKit
import simd
// Compile the app's actual model on macOS without changing its UIKit color implementation.
typealias UIColor = NSColor

private struct LegacyShape: Codable {
    var id: UUID
    var kind: String
    var position: SIMD3<Float>
    var scale: Float
    var colorIndex: Int
}
private struct LegacyDesign: Codable {
    var id: UUID
    var name: String
    var date: Date
    var shapes: [LegacyShape]
}
private struct LegacyArchive: Codable {
    var shapes: [LegacyShape]
    var selectedID: UUID?
    var snapEnabled: Bool
    var savedDesigns: [LegacyDesign]
}

@main struct CADModelTests {
    static func near(_ actual: Float, _ expected: Float, _ message: String = "", tolerance: Float = 0.00001) {
        assert(abs(actual - expected) < tolerance, "\(message): expected \(expected), got \(actual)")
    }
    static func near(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, _ message: String = "") {
        near(actual.x, expected.x, message + " X"); near(actual.y, expected.y, message + " Y"); near(actual.z, expected.z, message + " Z")
    }
    static func withModel(_ run: (CADModel, UserDefaults) throws -> Void) rethrows {
        let suite = "AVPLearn.CAD.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try run(CADModel(defaults: defaults), defaults)
    }
    static func main() throws {
        try legacyMigration()
        sizingRotationAndFloor()
        locksVisibilityAndUndo()
        alignmentAndStacking()
        withModel { cad, _ in
            cad.add(.box)
            let id = cad.selected!.id
            cad.beginEdit(); cad.setDimensions(id, [0.2, 0.1, 0.1])
            cad.beginEdit(); cad.setDimensions(id, [0.2, 0.1, 0.1])
            cad.undo()
            near(cad.selected!.dimensions, [0.1, 0.1, 0.1], "No-op Apply must not swallow a real undo")
            cad.redo(); near(cad.selected!.dimensions, [0.2, 0.1, 0.1])
        }
        try persistenceAndSnapshots()
        templatesAreCoherent()
        try machinePartsAndFeatures()
        challengesUseDimensions()
        corruptAndBounds()
        print("CAD checks passed: v2 workplane + snapshot migration, XYZ dimensions/rotation, rotated floor/stack bounds, units/grid, locks/visibility, alignment, starter-assembly contacts and fits, machine-part features, bore limits, undo/redo, persistence, and dimension-aware challenges.")
    }

    static func legacyMigration() throws {
        try withModel { _, defaults in
            let id = UUID()
            let old = LegacyShape(id: id, kind: "box", position: [0.15, 0.1, -0.05], scale: 2, colorIndex: 3)
            let oldDesign = LegacyDesign(id: UUID(), name: "Existing design", date: Date(timeIntervalSinceReferenceDate: 1234), shapes: [old])
            let data = try JSONEncoder().encode(LegacyArchive(shapes: [old], selectedID: id, snapEnabled: true, savedDesigns: [oldDesign]))
            defaults.set(data, forKey: "AVPLearn.cad.v2")
            let migrated = CADModel(defaults: defaults)
            assert(migrated.shapes.count == 1 && migrated.selectedID == id)
            near(migrated.selected!.dimensions, .init(repeating: 0.2), "Legacy uniform scale")
            near(migrated.selected!.position, old.position)
            near(migrated.selected!.rotationDegrees, .zero)
            assert(migrated.selected!.name == "Box" && !migrated.selected!.isHidden && !migrated.selected!.isLocked)
            assert(migrated.units == .centimeters)
            near(migrated.gridSpacing, 0.05)
            assert(migrated.savedDesigns.first!.id == oldDesign.id)
            near(migrated.savedDesigns.first!.shapes.first!.dimensions, .init(repeating: 0.2))
            migrated.beginEdit()
            migrated.rename(id, "Migrated support")
            let reopened = CADModel(defaults: defaults)
            assert(reopened.selected!.name == "Migrated support")
            assert(reopened.savedDesigns.first!.shapes.first!.name == "Box")
        }
    }

    static func sizingRotationAndFloor() {
        withModel { cad, _ in
            cad.add(.box)
            let id = cad.selected!.id
            cad.beginEdit()
            cad.setDimensions(id, [0.312, 0.042, 0.106])
            near(cad.selected!.dimensions, [0.312, 0.042, 0.106], "Typed lengths must not snap")
            let originalMeters = cad.selected!.dimensions
            cad.beginEdit(); cad.units = .centimeters
            near(cad.selected!.dimensions, originalMeters, "Unit change preserves meters")
            near(CADUnit.centimeters.unitsPerMeter, 100)
            near(CADUnit.millimeters.unitsPerMeter, 1000)
            cad.beginEdit(); cad.setPosition(id, [0.012, 0.3, 0.018])
            near(cad.selected!.position, [0.01, 0.3, 0.02], "Default 5 mm position grid")
            cad.beginEdit(); cad.gridSpacing = 0.001
            cad.setPosition(id, [0.0124, 0.3, 0.0184])
            near(cad.selected!.position, [0.012, 0.3, 0.018])
            cad.beginEdit(); cad.setDimensions(id, [0.3, 0.02, 0.04])
            cad.placeOnPlane()
            near(cad.selected!.position.y, 0.01)
            cad.beginEdit(); cad.setRotation(id, [0, 0, 90])
            near(cad.selected!.worldHalfExtents, [0.01, 0.15, 0.02])
            near(cad.selected!.position.y, 0.15, "Rotation raises the part above the workplane")
            cad.beginEdit(); cad.setPosition(id, [0, -1, 0])
            near(cad.selected!.position.y, 0.15)
            cad.beginEdit(); cad.setRotation(id, [0, 0, 45])
            near(cad.selected!.halfHeight, (0.3 + 0.02) / (2 * sqrt(2)), "45 degree extent")
            cad.placeOnPlane()
            near(cad.selected!.position.y, cad.selected!.halfHeight)
            let beforeScale = cad.selected!.dimensions
            let oldScale = cad.selected!.scale
            cad.beginEdit(); cad.setScale(id, oldScale * 1.5)
            near(cad.selected!.dimensions, beforeScale * 1.5, "Legacy scale preserves proportions")
            cad.beginEdit(); cad.setRotation(id, [450, -450, 720])
            near(cad.selected!.rotationDegrees, [90, -90, 0])
            let rotated = cad.selected!
            for x: Float in [-1, 1] { for y: Float in [-1, 1] { for z: Float in [-1, 1] {
                let point = rotated.rotationQuaternion.act(rotated.dimensions / 2 * SIMD3(x, y, z))
                assert(abs(point.x) <= rotated.worldHalfExtents.x + 0.00001)
                assert(abs(point.y) <= rotated.worldHalfExtents.y + 0.00001)
                assert(abs(point.z) <= rotated.worldHalfExtents.z + 0.00001)
            } } }
        }
    }

    static func locksVisibilityAndUndo() {
        withModel { cad, _ in
            cad.add(.tube)
            let id = cad.selected!.id
            cad.beginEdit(); cad.rename(id, "Bearing collar")
            cad.beginEdit(); cad.setBoreRatio(id, 0.7)
            cad.toggleVisibility(id)
            assert(cad.selected!.isHidden)
            cad.undo(); assert(!cad.selected!.isHidden)
            cad.redo(); assert(cad.selected!.isHidden)
            cad.toggleLock(id)
            let locked = cad.selected!
            cad.beginEdit(); cad.setDimensions(id, [0.2, 0.03, 0.2])
            cad.setRotation(id, [90, 0, 0]); cad.setPosition(id, [0.3, 0.3, 0.3]); cad.setScale(id, 3)
            cad.setBoreRatio(id, 0.4); cad.placeOnPlane(); cad.deleteSelected()
            assert(cad.selected! == locked, "Locked geometry and deletion must reject edits")
            cad.add(.box)
            let secondID = cad.selected!.id
            cad.select(id)
            cad.alignSelected(to: secondID, axis: 0); cad.stackSelected(on: secondID)
            assert(cad.selected! == locked)
            cad.clear()
            assert(cad.shapes.count == 1 && cad.shapes.first!.id == id, "Clear preserves locked parts")
            cad.toggleLock(id); assert(!cad.selected!.isLocked)
            cad.undo(); assert(cad.selected!.isLocked)
            cad.redo(); assert(!cad.selected!.isLocked)
            cad.duplicateSelected()
            assert(cad.selected!.name == "Bearing collar copy" && !cad.selected!.isLocked && !cad.selected!.isHidden)
            cad.undo(); assert(cad.canRedo)
            cad.beginEdit(); cad.rename(id, "New edit")
            assert(!cad.canRedo)
        }
    }

    static func alignmentAndStacking() {
        withModel { cad, _ in
            cad.snapEnabled = false
            cad.add(.box)
            let baseID = cad.selected!.id
            cad.beginEdit(); cad.setDimensions(baseID, [0.3, 0.02, 0.1]); cad.setRotation(baseID, [0, 0, 30])
            cad.placeOnPlane()
            cad.beginEdit(); cad.setPosition(baseID, [0.123, cad.selected!.halfHeight, -0.087])
            let base = cad.selected!
            cad.add(.cylinder)
            let topID = cad.selected!.id
            cad.beginEdit(); cad.setDimensions(topID, [0.05, 0.2, 0.05]); cad.setRotation(topID, [90, 0, 0])
            cad.alignSelected(to: baseID, axis: 0)
            near(cad.selected!.position.x, 0.123)
            cad.alignSelected(to: baseID, axis: 2)
            near(cad.selected!.position.z, -0.087)
            let beforeStack = cad.selected!
            cad.stackSelected(on: baseID)
            near(cad.selected!.position.y - cad.selected!.halfHeight, base.position.y + base.halfHeight, "Rotated bounding boxes touch")
            near(cad.selected!.position.x, base.position.x)
            near(cad.selected!.position.z, base.position.z)
            cad.undo(); assert(cad.selected! == beforeStack)
            cad.redo(); near(cad.selected!.position.y - cad.selected!.halfHeight, base.position.y + base.halfHeight)
            let unchanged = cad.selected!
            cad.alignSelected(to: topID, axis: 0); cad.alignSelected(to: baseID, axis: 4); cad.stackSelected(on: topID)
            assert(cad.selected! == unchanged, "Self and invalid-axis operations do nothing")
        }
    }

    static func persistenceAndSnapshots() throws {
        try withModel { cad, defaults in
            cad.loadTemplate(.shaftSupport)
            let collarID = cad.shapes.first { $0.kind == .tube }!.id
            cad.select(collarID)
            cad.beginEdit(); cad.setDimensions(collarID, [0.08, 0.032, 0.08]); cad.setBoreRatio(collarID, 0.65)
            cad.toggleVisibility(collarID); cad.toggleLock(collarID)
            cad.beginEdit(); cad.units = .centimeters; cad.gridSpacing = 0.01
            cad.saveDesign(named: "  Upgraded assembly  ")
            let reopened = CADModel(defaults: defaults)
            assert(reopened.shapes == cad.shapes && reopened.selectedID == collarID)
            assert(reopened.units == .centimeters && reopened.gridSpacing == 0.01)
            assert(reopened.savedDesigns == cad.savedDesigns)
            assert(reopened.selected!.isHidden && reopened.selected!.isLocked)
            let encoded = try JSONEncoder().encode(reopened.selected!)
            let decoded = try JSONDecoder().decode(CADShape.self, from: encoded)
            assert(decoded == reopened.selected!)
            let originalShapes = cad.shapes
            cad.loadTemplate(.angleBracket)
            assert(cad.shapes != originalShapes)
            cad.undo(); assert(cad.shapes == originalShapes && cad.selectedID == collarID)
            cad.redo(); assert(cad.shapes.count == CADTemplate.angleBracket.shapes.count)
            cad.loadDesign(cad.savedDesigns.first!)
            assert(cad.shapes == originalShapes)
            let savedID = cad.savedDesigns.first!.id
            cad.deleteDesign(savedID); assert(cad.savedDesigns.isEmpty)
            cad.undo(); assert(cad.savedDesigns.count == 1)
        }
    }

    static func templatesAreCoherent() {
        for template in CADTemplate.allCases {
            let shapes = template.shapes
            assert(shapes == template.shapes, "Template IDs and geometry are deterministic")
            assert(Set(shapes.map(\.id)).count == shapes.count)
            assert(Set(shapes.map(\.name)).count == shapes.count)
            for shape in shapes { assert(shape.position.y - shape.halfHeight >= -0.00001, "\(shape.name) is below the workplane") }
            withModel { cad, _ in
                cad.loadTemplate(template)
                assert(cad.shapes == shapes, "\(template.title) must load without being clamped or moved")
            }
        }
        func part(_ shapes: [CADShape], _ name: String) -> CADShape { shapes.first { $0.name == name }! }
        func top(_ shape: CADShape) -> Float { shape.position.y + shape.halfHeight }
        func bottom(_ shape: CADShape) -> Float { shape.position.y - shape.halfHeight }
        func underHead(_ bolt: CADShape) -> Float { bolt.position.y + bolt.dimensions.y / 2 - bolt.boltHeadHeight }
        func onHole(_ bolt: CADShape, of plate: CADShape) -> Bool {
            plate.plateHoleCenters.map(plate.worldPoint).contains { abs($0.x - bolt.position.x) < 0.00001 && abs($0.z - bolt.position.z) < 0.00001 }
        }

        let drive = CADTemplate.shaftSupport.shapes
        let shaft = drive.first { $0.kind == .cylinder }!
        let base = part(drive, "Base plate")
        for side in ["Front", "Rear"] {
            let block = part(drive, "\(side) pillow block"), sleeve = part(drive, "\(side) bearing sleeve")
            near(bottom(block), top(base), "Pillow block rests on the base plate")
            let axis = block.worldPoint([0, block.blockBoreCenterY, 0])
            near(axis.x, shaft.position.x); near(axis.y, shaft.position.y, "Shaft runs on the housing bore axis")
            near(sleeve.position.x, axis.x); near(sleeve.position.y, axis.y); near(sleeve.position.z, block.position.z)
            near(sleeve.rotationQuaternion.act([0, 1, 0]), [0, 0, 1], "Sleeve axis is Z")
            near(sleeve.dimensions.x, block.featureDiameter!, "Sleeve fills the housing bore")
            near((sleeve.featureDiameter! - shaft.dimensions.x) / 2, 0.0005, "Radial shaft clearance")
            assert(abs(sleeve.position.z - shaft.position.z) + sleeve.worldHalfExtents.z < shaft.worldHalfExtents.z, "Shaft passes through the sleeve")
        }
        let frontBlock = part(drive, "Front pillow block")
        let driveBolts = drive.filter { $0.kind == .hexBolt }
        assert(driveBolts.count == 4)
        for bolt in driveBolts {
            near(underHead(bolt), bottom(frontBlock) + frontBlock.blockFootThickness, "Bolt head sits on the foot")
            near(bolt.featureDiameter!, 0.010, "M10 shank")
            assert(abs(bolt.position.x) - bolt.dimensions.x / 2 > frontBlock.blockArchRadius, "Bolt head clears the housing")
            assert(abs(bolt.position.x) + bolt.dimensions.x / 2 < frontBlock.dimensions.x / 2, "Bolt head stays on the foot")
        }
        let driveGear = drive.first { $0.kind == .gear }!
        near(driveGear.gearModule!, 0.004, "Drive gear module")
        near(driveGear.featureDiameter!, shaft.dimensions.x, "Gear bore matches the shaft")

        let reducer = CADTemplate.gearReducer.shapes
        let pinion = part(reducer, "Pinion · 12 teeth"), wheel = part(reducer, "Gear · 36 teeth")
        near(pinion.gearModule!, 0.003, "Pinion module"); near(wheel.gearModule!, 0.003, "Gear module")
        near(abs(wheel.position.x - pinion.position.x), (pinion.pitchDiameter! + wheel.pitchDiameter!) / 2, "Pitch circles touch")
        near(abs(wheel.position.x - pinion.position.x), 0.072, "72 mm center distance")
        near(wheel.position.y, pinion.position.y); near(wheel.position.z, pinion.position.z)
        assert(wheel.teeth == 3 * pinion.teeth, "3:1 ratio")
        near(pinion.featureDiameter!, part(reducer, "Input shaft · 12 mm").dimensions.x, "Pinion bore matches its shaft")
        near(wheel.featureDiameter!, part(reducer, "Output shaft · 16 mm").dimensions.x, "Gear bore matches its shaft")
        for block in reducer.filter({ $0.kind == .bearingBlock }) {
            near(bottom(block), top(part(reducer, "Base plate")))
            near(block.worldPoint([0, block.blockBoreCenterY, 0]).y, pinion.position.y, "Shafts run on the bore axis")
        }

        let bracket = CADTemplate.angleBracket.shapes
        let frame = part(bracket, "Machine frame block"), leg = part(bracket, "Base leg")
        let upright = part(bracket, "Upright leg"), gusset = part(bracket, "Gusset")
        near(bottom(leg), top(frame)); near(bottom(upright), top(leg), "Upright stands on the base leg")
        near(upright.position.x - upright.worldHalfExtents.x, leg.position.x - leg.worldHalfExtents.x, "Outer faces are flush")
        near(gusset.position.x - gusset.worldHalfExtents.x, upright.position.x + upright.worldHalfExtents.x, "Gusset touches the upright")
        near(bottom(gusset), top(leg), "Gusset touches the base leg")
        let bracketBolts = bracket.filter { $0.kind == .hexBolt }, washers = bracket.filter { $0.kind == .tube }
        assert(bracketBolts.count == 2 && washers.count == 2)
        for bolt in bracketBolts {
            assert(onHole(bolt, of: leg), "Bolt axis is on a hole center")
            let washer = washers.first { abs($0.position.x - bolt.position.x) < 0.00001 && abs($0.position.z - bolt.position.z) < 0.00001 }!
            near(bottom(washer), top(leg)); near(underHead(bolt), top(washer), "Head clamps the washer")
            assert(bolt.featureDiameter! < leg.featureDiameter!, "Clearance hole")
            assert(bottom(bolt) > bottom(frame), "Bolt ends inside the frame block")
        }

        let joint = CADTemplate.boltedJoint.shapes
        let lower = part(joint, "Lower plate"), upper = part(joint, "Upper plate")
        near(bottom(upper), top(lower)); near(bottom(lower), top(part(joint, "Bench riser")))
        let nuts = joint.filter { $0.kind == .hexNut }
        assert(nuts.count == 4)
        for bolt in joint.filter({ $0.kind == .hexBolt }) {
            assert(onHole(bolt, of: lower) && onHole(bolt, of: upper))
            near((lower.featureDiameter! - bolt.featureDiameter!) / 2, 0.0005, "Radial hole clearance")
            let nut = nuts.first { abs($0.position.x - bolt.position.x) < 0.00001 && abs($0.position.z - bolt.position.z) < 0.00001 }!
            near(top(nut), bottom(lower), "Nut bears on the lower plate")
            near(bottom(nut) - bottom(bolt), 0.005, "5 mm of thread shows below the nut")
            near(underHead(bolt), top(upper) + 0.002, "Head clamps a 2 mm washer")
        }
    }

    static func machinePartsAndFeatures() throws {
        try withModel { cad, defaults in
            cad.add(.gear)
            let gearID = cad.selected!.id
            near(cad.selected!.gearModule!, 0.003, "Default gear module")
            near(cad.selected!.pitchDiameter!, 0.054, "Default pitch diameter")
            near(cad.selected!.position.y, cad.selected!.dimensions.y / 2, "New parts rest on the workplane")
            assert(cad.selected!.colorIndex == CADPalette.steel, "Machine parts arrive in steel")
            cad.beginEdit(); cad.setTeeth(gearID, 200); assert(cad.selected!.teeth == 60)
            cad.setTeeth(gearID, 1); assert(cad.selected!.teeth == 8)
            cad.setTeeth(gearID, 36); cad.setDimensions(gearID, [0.114, 0.012, 0.114])
            near(cad.selected!.gearModule!, 0.003, "Module follows outside diameter and tooth count")
            near(cad.selected!.pitchDiameter!, 0.108)
            cad.setBoreRatio(gearID, 0.016 / cad.selected!.featureFullDiameter!)
            near(cad.selected!.featureDiameter!, 0.016, "Bore diameter round-trips through the ratio")
            let reopened = CADModel(defaults: defaults)
            assert(reopened.selected! == cad.selected! && reopened.selected!.teeth == 36, "Tooth count persists")
            let legacy = try JSONDecoder().decode(CADShape.self, from: Data(#"{"kind":"box","position":[0,0.05,0]}"#.utf8))
            assert(legacy.teeth == 18 && legacy.boreRatio == 0.6, "Older saves decode with default features")

            cad.add(.box)
            let boxID = cad.selected!.id, box = cad.selected!
            cad.beginEdit(); cad.setTeeth(boxID, 30); cad.setBoreRatio(boxID, 0.3)
            assert(cad.selected! == box && box.featureDiameter == nil, "Solids have no feature to edit")

            cad.add(.plate)
            let plate = cad.selected!
            near(plate.featureDiameter!, 0.012, "Default plate hole")
            near(plate.plateHoleInset, 0.0192, "Hole inset")
            assert(plate.plateHoleCenters.count == 4)
            for hole in plate.plateHoleCenters {
                assert(abs(hole.x) + plate.featureDiameter! / 2 < plate.dimensions.x / 2 && abs(hole.z) + plate.featureDiameter! / 2 < plate.dimensions.z / 2, "Holes stay inside the plate")
            }
            cad.add(.hexBolt)
            let bolt = cad.selected!
            near(bolt.hexFlatRadius, 0.0064951905, "Across-flats from across-corners")
            near(bolt.boltHeadHeight, 0.7 * bolt.featureDiameter!)
            cad.add(.bearingBlock)
            let block = cad.selected!
            near(block.blockArchRadius, 0.027); near(block.blockBoreCenterY, 0.003); near(block.featureDiameter!, 0.0324)
            assert(CADPalette.finishes.count == 12 && CADPalette.finish(-1).name == "Black oxide" && CADPalette.finish(12).name == "Blue")
        }
    }

    static func challengesUseDimensions() {
        withModel { cad, _ in
            cad.add(.box)
            let boxID = cad.selected!.id
            cad.beginEdit(); cad.setDimensions(boxID, [0.2, 0.02, 0.2]); cad.placeOnPlane()
            assert(!CADChallenge.support.checks(in: cad.shapes).allSatisfy { $0.1 }, "Longest dimension alone cannot satisfy a cube challenge")
            cad.beginEdit(); cad.setDimensions(boxID, [0.2, 0.2, 0.2]); cad.placeOnPlane()
            assert(CADChallenge.support.checks(in: cad.shapes).allSatisfy { $0.1 })
            cad.beginEdit(); cad.setRotation(boxID, [0, 45, 0])
            assert(!CADChallenge.support.checks(in: cad.shapes).allSatisfy { $0.1 })
            cad.beginEdit(); cad.setRotation(boxID, .zero)
            cad.add(.cylinder)
            cad.stackSelected(on: boxID)
            assert(CADChallenge.stack.checks(in: cad.shapes).allSatisfy { $0.1 })
            cad.toggleVisibility(cad.selected!.id)
            assert(!CADChallenge.stack.checks(in: cad.shapes).allSatisfy { $0.1 })
            cad.clear(); cad.add(.box); cad.add(.box)
            assert(CADChallenge.twins.checks(in: cad.shapes).allSatisfy { $0.1 })
        }
        withModel { cad, _ in
            cad.add(.gear)
            let firstID = cad.selected!.id
            cad.add(.gear)
            let secondID = cad.selected!.id
            assert(CADChallenge.mesh.checks(in: cad.shapes).map(\.1) == [true, true, false], "Unplaced gears share a module but do not mesh")
            cad.beginEdit(); cad.setPosition(secondID, [0.054, 0.006, 0])
            assert(!CADChallenge.mesh.checks(in: cad.shapes).allSatisfy { $0.1 }, "A 5 mm grid rounds 54 mm away")
            cad.beginEdit(); cad.gridSpacing = 0.001; cad.setPosition(secondID, [0.054, 0.006, 0])
            assert(CADChallenge.mesh.checks(in: cad.shapes).allSatisfy { $0.1 }, "Pitch circles touch at 54 mm")
            cad.beginEdit(); cad.setTeeth(firstID, 36)
            assert(CADChallenge.mesh.checks(in: cad.shapes).map(\.1) == [false, false, false], "Changing the tooth count alone changes the module")
            cad.beginEdit(); cad.setDimensions(firstID, [0.114, 0.012, 0.114]); cad.setPosition(secondID, [0.081, 0.006, 0])
            assert(CADChallenge.mesh.checks(in: cad.shapes).allSatisfy { $0.1 }, "36 and 18 teeth at module 3 mesh at 81 mm")
        }
        withModel { cad, _ in
            cad.snapEnabled = false
            cad.add(.box)
            let boxID = cad.selected!.id
            cad.add(.plate)
            let plateID = cad.selected!.id
            cad.add(.hexBolt)
            let boltID = cad.selected!.id
            assert(CADChallenge.fasten.checks(in: cad.shapes).map(\.1) == [false, false, false])
            cad.select(plateID); cad.stackSelected(on: boxID)
            let plate = cad.selected!, bolt = cad.shapes.first { $0.id == boltID }!
            let hole = plate.worldPoint(plate.plateHoleCenters[0])
            let seatY = plate.position.y + plate.dimensions.y / 2 + bolt.boltHeadHeight - bolt.dimensions.y / 2
            cad.beginEdit(); cad.setPosition(boltID, [hole.x, 0.2, hole.z])
            assert(CADChallenge.fasten.checks(in: cad.shapes).map(\.1) == [true, true, false], "On axis but hovering")
            cad.beginEdit(); cad.setPosition(boltID, [hole.x, seatY, hole.z])
            assert(CADChallenge.fasten.checks(in: cad.shapes).allSatisfy { $0.1 }, "Bolt seated in the hole")
            cad.beginEdit(); cad.setPosition(boltID, [hole.x + 0.002, seatY, hole.z])
            assert(!CADChallenge.fasten.checks(in: cad.shapes)[0].1, "Off the hole axis")
            cad.beginEdit(); cad.setPosition(boltID, [hole.x, seatY, hole.z]); cad.setBoreRatio(plateID, 0.1)
            assert(CADChallenge.fasten.checks(in: cad.shapes).map(\.1)[1] == false, "A hole narrower than the shank has no clearance")
        }
    }

    static func corruptAndBounds() {
        withModel { cad, defaults in
            cad.add(.tube)
            let id = cad.selected!.id
            let baseline = cad.selected!
            cad.beginEdit(); cad.setDimensions(id, [.nan, 0.1, 0.1]); cad.setRotation(id, [.infinity, 0, 0]); cad.setPosition(id, [0, .nan, 0])
            assert(cad.selected! == baseline)
            cad.beginEdit(); cad.setDimensions(id, [-1, 5, 0])
            near(cad.selected!.dimensions, [0.001, 1, 0.001])
            cad.beginEdit(); cad.setBoreRatio(id, 2); near(cad.selected!.boreRatio, 0.9)
            cad.beginEdit(); cad.setBoreRatio(id, -1); near(cad.selected!.boreRatio, 0.1)
            cad.gridSpacing = -1; near(cad.gridSpacing, 0.005)
            defaults.set(Data("not JSON".utf8), forKey: "AVPLearn.cad.v2")
            assert(CADModel(defaults: defaults).shapes.isEmpty)
        }
    }
}
