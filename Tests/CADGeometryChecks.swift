import Foundation
import AppKit
import simd

typealias UIColor = NSColor

@main struct IndependentCADReview {
 static func near(_ a: Float, _ b: Float, _ message: String) {
  precondition(abs(a-b) < 0.000002, "\(message): \(a) != \(b)")
 }
 static func main() throws {
  let suite = "AVPLearn.CAD.Independent.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let cad = CADModel(defaults: defaults)
  cad.add(.box)
  let id = cad.selected!.id
  cad.beginEdit()
  cad.setDimensions(id, [0.12345, 0.04321, 0.06789])
  near(cad.selected!.dimensions.x, 0.12345, "Typed dimensions must not snap")
  let beforeUnitChange = cad.shapes
  cad.units = .centimeters
  cad.units = .millimeters
  precondition(cad.shapes == beforeUnitChange, "Unit switching must preserve geometry")
  cad.beginEdit()
  cad.setDimensions(id, [0.2, 0.04, 0.08])
  cad.setRotation(id, [90,0,0])
  cad.setPosition(id, [0,-1,0])
  near(cad.selected!.position.y, 0.04, "Quarter-turn floor uses depth as height")
  cad.setRotation(id, [45,30,20])
  let rotated = cad.selected!
  var measured = SIMD3<Float>.zero
  for x: Float in [-1,1] { for y: Float in [-1,1] { for z: Float in [-1,1] {
   let corner = rotated.rotationQuaternion.act(rotated.dimensions/2 * SIMD3<Float>(x,y,z))
   measured = SIMD3(max(measured.x,abs(corner.x)),max(measured.y,abs(corner.y)),max(measured.z,abs(corner.z)))
  }}}
  near(rotated.worldHalfExtents.x, measured.x, "Rotated X half extent")
  near(rotated.worldHalfExtents.y, measured.y, "Rotated Y half extent")
  near(rotated.worldHalfExtents.z, measured.z, "Rotated Z half extent")
  precondition(rotated.position.y >= rotated.worldHalfExtents.y, "Rotated box stays above plane")
  cad.toggleLock(id)
  let locked = cad.selected!
  cad.setDimensions(id, [0.4,0.4,0.4]); cad.setPosition(id,[1,1,1]); cad.setRotation(id,[0,0,0]); cad.setScale(id,2)
  cad.placeOnPlane(); cad.deleteSelected()
  precondition(cad.selected == locked, "Geometry mutation and deletion must respect lock")
  cad.toggleVisibility(id)
  precondition(cad.selected?.isHidden == true, "Hidden part remains selected and in model")
  cad.saveDesign(named: "Independent review")
  let reopened = CADModel(defaults: defaults)
  precondition(reopened.shapes == cad.shapes, "Dimensions, rotation, lock and visibility persist")
  precondition(reopened.units == .millimeters, "Display units persist")
  precondition(reopened.savedDesigns.first?.shapes == cad.shapes, "Snapshot preserves full geometry")

  for template in CADTemplate.allCases {
   let shapes = template.shapes
   precondition(Set(shapes.map(\.id)).count == shapes.count, "Template IDs unique")
   for shape in shapes {
    precondition(shape.position.y + 0.000001 >= shape.worldHalfExtents.y, "Template part below plane")
   }
   try CADOBJDocument(shapes:shapes).text.write(toFile:"build/checks/cad-review-\(template.rawValue).obj",atomically:true,encoding:.utf8)
  }
  let drive = CADTemplate.shaftSupport.shapes
  let base = drive.first { $0.name == "Base plate" }!
  let block = drive.first { $0.name == "Front pillow block" }!
  let sleeve = drive.first { $0.name == "Front bearing sleeve" }!
  let shaft = drive.first { $0.kind == .cylinder }!
  near(base.position.y + base.halfHeight, block.position.y - block.halfHeight, "Pillow block touches base")
  near(block.position.y + block.blockBoreCenterY, shaft.position.y, "Housing bore and shaft axes align vertically")
  near(sleeve.position.y, shaft.position.y, "Sleeve and shaft axes align vertically")
  near(sleeve.position.x, shaft.position.x, "Sleeve and shaft axes align horizontally")
  near((sleeve.featureDiameter!-shaft.dimensions.x)/2,0.0005,"Radial clearance is 0.5mm")
  // The mesh is built at true size: a mesh's extent must equal the part's stated dimensions.
  for shape in CADTemplate.allCases.flatMap(\.shapes) {
   let mesh = CADMeshLibrary.geometry(for: shape)
   var low = SIMD3<Float>(repeating: .infinity), high = SIMD3<Float>(repeating: -.infinity)
   for point in mesh.positions { low = simd_min(low, point); high = simd_max(high, point) }
   // Gear teeth only reach the outside diameter where a tooth points along an axis.
   let slack: Float = shape.kind == .gear ? 0.02 : 0.00001
   for axis in 0..<3 {
    let size = (high-low)[axis], stated = shape.dimensions[axis]
    precondition(size <= stated + 0.000002 && size >= stated * (1 - slack), "\(shape.name) mesh extent \(size) != \(stated) on axis \(axis)")
   }
   precondition(mesh.volume > 0 && mesh.volume < shape.dimensions.x*shape.dimensions.y*shape.dimensions.z, "\(shape.name) volume lies inside its bounds")
  }
  let cube = CADMeshLibrary.geometry(for: CADShape(kind: .box, position: .zero, dimensions: [0.2,0.2,0.2]))
  precondition(abs(cube.volume - 0.008) < 0.008*0.002, "Bevels remove well under 1% of a 200 mm cube")
  let bar = CADMeshLibrary.geometry(for: CADShape(kind: .cylinder, position: .zero, dimensions: [0.036,0.29,0.036]))
  let round = Float.pi*0.018*0.018*0.29
  precondition(bar.volume < round && bar.volume > round*0.995, "A 64-sided, chamfered shaft is within 0.5% of a 36 mm round bar")
  cad.loadTemplate(.shaftSupport)
  let loaded = cad.shapes
  cad.undo()
  precondition(cad.shapes != loaded, "Template load can be undone")
  cad.redo()
  precondition(cad.shapes == loaded, "Template load can be redone")
  var customShapes: [CADShape] = []
  for (index, kind) in ShapeKind.allCases.enumerated() {
   let shape = CADShape(kind: kind, position: [Float(index) * 0.17 - 0.8, 0.20, -0.13], name: "Actual \(kind.rawValue)", dimensions: [0.12, 0.08, 0.06], rotationDegrees: [60,36,25.714285], boreRatio: 0.6)
   customShapes.append(shape)
   try CADOBJDocument(shapes:[shape]).text.write(toFile:"build/checks/cad-actual-\(kind.rawValue).obj",atomically:true,encoding:.utf8)
  }
  // Awkward proportions and feature limits must still give closed solids.
  var stress: [CADShape] = []
  let extremes: [(SIMD3<Float>, Float, Int)] = [([0.3,0.004,0.02],0.1,8), ([0.004,0.2,0.004],0.9,60), ([0.004,0.004,0.004],0.5,13), ([1,1,1],0.9,60), ([0.05,0.05,0.3],0.1,24)]
  for kind in ShapeKind.allCases {
   for (index, extreme) in extremes.enumerated() {
    stress.append(CADShape(kind: kind, position: [0,0.5,0], name: "Stress \(kind.rawValue) \(index)", dimensions: extreme.0, boreRatio: extreme.1, teeth: extreme.2))
   }
  }
  try CADOBJDocument(shapes:stress).text.write(toFile:"build/checks/cad-actual-stress.obj",atomically:true,encoding:.utf8)
  let hidden = CADShape(kind: .box, position: .zero, name: "hidden-must-not-export", isHidden: true)
  let combined = CADOBJDocument(shapes:customShapes+[hidden]).text
  precondition(!combined.contains("hidden_must_not_export"), "Hidden geometry must be excluded")
  try combined.write(toFile:"build/checks/cad-actual-combined.obj",atomically:true,encoding:.utf8)
  print("PASS independent actual-model review: arbitrary dimensions, display units, compound bounds/floor, locks/hide, persistence/snapshots, template contacts/clearance, true-size meshes and volumes, undo/redo.")
 }
}
