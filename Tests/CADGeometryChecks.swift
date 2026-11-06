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
  let support = CADTemplate.shaftSupport.shapes
  let base = support.first { $0.name == "Base plate" }!
  let pedestal = support.first { $0.name == "Front pedestal" }!
  let collar = support.first { $0.name == "Front hollow collar" }!
  let shaft = support.first { $0.kind == .cylinder }!
  near(base.position.y + base.halfHeight, pedestal.position.y - pedestal.halfHeight, "Pedestal touches base")
  near(pedestal.position.y + pedestal.halfHeight, collar.position.y - collar.halfHeight, "Collar touches pedestal")
  near(collar.position.y, shaft.position.y, "Collar and shaft axes align vertically")
  near(collar.position.x, shaft.position.x, "Collar and shaft axes align horizontally")
  near((collar.dimensions.x*collar.boreRatio-shaft.dimensions.x)/2,0.003,"Radial clearance is3mm")
  let bracket = CADTemplate.angleBracket.shapes
  let plate = bracket.first { $0.name == "Horizontal base plate" }!
  let upright = bracket.first { $0.name == "Upright plate" }!
  let gusset = bracket.first { $0.name == "Front reinforcing block" }!
  near(plate.position.y + plate.halfHeight, upright.position.y - upright.halfHeight, "Upright touches bracket base")
  near(plate.position.y + plate.halfHeight, gusset.position.y - gusset.halfHeight, "Block touches base")
  near(upright.position.x+upright.worldHalfExtents.x,gusset.position.x-gusset.worldHalfExtents.x,"Block touches upright")
  cad.loadTemplate(.shaftSupport)
  let loaded = cad.shapes
  cad.undo()
  precondition(cad.shapes != loaded, "Template load can be undone")
  cad.redo()
  precondition(cad.shapes == loaded, "Template load can be redone")
  var customShapes: [CADShape] = []
  for (index, kind) in ShapeKind.allCases.enumerated() {
   let shape = CADShape(kind: kind, position: [Float(index) * 0.17, 0.20, -0.13], name: "Actual \(kind.rawValue)", dimensions: [0.12, 0.08, 0.06], rotationDegrees: [60,36,25.714285], boreRatio: 0.6)
   customShapes.append(shape)
   try CADOBJDocument(shapes:[shape]).text.write(toFile:"build/checks/cad-actual-\(kind.rawValue).obj",atomically:true,encoding:.utf8)
  }
  let hidden = CADShape(kind: .box, position: .zero, name: "hidden-must-not-export", isHidden: true)
  let combined = CADOBJDocument(shapes:customShapes+[hidden]).text
  precondition(!combined.contains("hidden_must_not_export"), "Hidden geometry must be excluded")
  try combined.write(toFile:"build/checks/cad-actual-combined.obj",atomically:true,encoding:.utf8)
  print("PASS independent actual-model review: arbitrary dimensions, display units, compound bounds/floor, locks/hide, persistence/snapshots, template contacts/clearance, undo/redo.")
 }
}
