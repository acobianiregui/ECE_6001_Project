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
        challengesUseDimensions()
        corruptAndBounds()
        print("CAD checks passed: v2 workplane + snapshot migration, XYZ dimensions/rotation, rotated floor/stack bounds, units/grid, locks/visibility, alignment, template geometry, bore limits, undo/redo, persistence, and dimension-aware challenges.")
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
            cad.redo(); assert(cad.shapes.count == 4)
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
            for shape in shapes { assert(shape.position.y - shape.halfHeight >= -0.00001) }
        }
        let support = CADTemplate.shaftSupport.shapes
        let shaft = support.first { $0.kind == .cylinder }!
        let collars = support.filter { $0.kind == .tube }
        assert(collars.count == 2)
        for collar in collars {
            near(collar.rotationQuaternion.act([0, 1, 0]), [0, 0, 1], "Collar axis is Z")
            near(collar.position.x, shaft.position.x); near(collar.position.y, shaft.position.y)
            near((collar.dimensions.x * collar.boreRatio - shaft.dimensions.x) / 2, 0.003, "Radial shaft clearance")
            assert(abs(collar.position.z) + collar.worldHalfExtents.z < shaft.worldHalfExtents.z)
            let pedestal = support.first { $0.kind == .box && $0.name.contains("pedestal") && abs($0.position.z - collar.position.z) < 0.00001 }!
            near(pedestal.position.y + pedestal.halfHeight, collar.position.y - collar.halfHeight, "Pedestal touches collar outer bound")
            let base = support.first { $0.name == "Base plate" }!
            near(pedestal.position.y - pedestal.halfHeight, base.position.y + base.halfHeight)
        }
        let bracket = CADTemplate.angleBracket.shapes
        let base = bracket.first { $0.name == "Horizontal base plate" }!
        let upright = bracket.first { $0.name == "Upright plate" }!
        near(upright.position.y - upright.halfHeight, base.position.y + base.halfHeight)
        for block in bracket.filter({ $0.name.contains("reinforcing") }) {
            near(block.position.y - block.halfHeight, base.position.y + base.halfHeight)
            near(block.position.x - block.worldHalfExtents.x, upright.position.x + upright.worldHalfExtents.x)
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
