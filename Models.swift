import SwiftUI
import RealityKit
import Observation

// MARK: - Shared app state

@Observable
final class SpaceController {
    var active: String?   // "cad", "lab", or nil
    var isTransitioning = false
    var error: String?
}

// MARK: - 3D system explorer

struct SystemPart: Identifiable, Sendable {
    let id: String
    let name: String
    let detail: String
    let home: SIMD3<Float>
    let explode: SIMD3<Float>     // displacement at full explosion
    let hue: CGFloat
    var transparent = false
    var tiltedOnX = false          // rotate 90° so the part's local Y axis lies along Z
    /// The part's shape in meters, centered on its own origin.
    let geometry: @Sendable () -> CADMeshGeometry

    @MainActor
    func mesh() -> MeshResource { CADMeshLibrary.resource(geometry(), name: "system-\(id)") }
}

struct EngSystem: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let parts: [SystemPart]

    /// The assembled parts as a shaded picture. See-through housings are left out so the mechanism shows.
    var previewItems: [CADPreviewRenderer.Item] {
        parts.filter { !$0.transparent }.map { part in
            CADPreviewRenderer.Item(geometry: part.geometry(),
                                    rotation: simd_quatf(angle: part.tiltedOnX ? .pi / 2 : 0, axis: [1, 0, 0]),
                                    position: part.home, color: CADPalette.rgb(hue: Float(part.hue), saturation: 0.55), isMetal: true)
        }
    }

    // Slider-crank layout, shared with MechanismDriver: a 25 mm crank throw and a 200 mm rod.
    // At top dead centre the crank pin is 25 mm above the crank axis and the wrist pin 200 mm above that.
    private static let crankAxisY: Float = -0.17
    private static let wristPinY: Float = crankAxisY + 0.025 + 0.2

    static let pistonAssembly = EngSystem(
        id: "piston",
        title: "Piston & Crank Assembly",
        summary: "How reciprocating motion becomes rotation. Drag the slider to explode the assembly.",
        parts: [
            SystemPart(id: "block", name: "Cylinder Block",
                       detail: "Houses the piston and contains combustion pressure. The fins shed heat to the air. Shown transparent so you can see inside.",
                       home: [0, 0.06, 0], explode: [0, 0, 0], hue: 0.6, transparent: true) {
                // A finned, air-cooled cylinder with its head, lathed as one closed section.
                var section: [SIMD2<Float>] = [[0.0725, -0.11], [0.082, -0.11]]
                for fin in 0..<6 {
                    let y = -0.06 + Float(fin) * 0.02
                    section += [[0.082, y], [0.105, y], [0.105, y + 0.008], [0.082, y + 0.008]]
                }
                section += [[0.082, 0.09], [0.0075, 0.09], [0.0075, 0.065], [0.0725, 0.065]]
                return CADMeshLibrary.lathe(section, closed: true)
            },
            SystemPart(id: "plug", name: "Spark Plug",
                       detail: "Ignites the air-fuel mixture at the top of the compression stroke. The ribbed ceramic insulates the high-voltage terminal.",
                       home: [0, 0.165, 0], explode: [0, 0.2, 0], hue: 0.12) {
                var section: [SIMD2<Float>] = [[0, -0.05], [0.002, -0.05], [0.002, -0.045], [0.007, -0.045], [0.007, -0.015],
                                               [0.012, -0.015], [0.012, -0.003], [0.009, 0], [0.008, 0.004]]
                for rib in 0..<4 {
                    let y = 0.006 + Float(rib) * 0.006
                    section += [[0.0086, y], [0.0086, y + 0.002], [0.0068, y + 0.003], [0.0068, y + 0.005]]
                }
                section += [[0.006, 0.032], [0.004, 0.034], [0.004, 0.043], [0.0048, 0.044], [0.0048, 0.047], [0, 0.047]]
                return CADMeshLibrary.lathe(section)
            },
            SystemPart(id: "piston", name: "Piston",
                       detail: "Moves up and down in the cylinder. Gas pressure on its crown produces linear force; the three grooves hold sealing rings.",
                       home: [0, wristPinY, 0], explode: [0, 0.1, 0], hue: 0.02) {
                // A hollow cup: crown on top, three ring grooves, open skirt below. The origin is the wrist-pin axis.
                var section: [SIMD2<Float>] = [[0.058, -0.035], [0.07, -0.035]]
                for groove in [Float(0.016), 0.027, 0.038] {
                    section += [[0.07, groove], [0.066, groove], [0.066, groove + 0.004], [0.07, groove + 0.004]]
                }
                section += [[0.07, 0.048], [0.068, 0.05], [0, 0.05], [0, 0.03], [0.058, 0.03]]
                return CADMeshLibrary.lathe(section, closed: true)
            },
            SystemPart(id: "pin", name: "Wrist Pin",
                       detail: "A hollow steel pin: the pivot joint connecting the piston to the connecting rod.",
                       home: [0, wristPinY, 0], explode: [0, 0.03, 0], hue: 0.15) {
                var pin = CADMeshGeometry()
                pin.append(CADMeshLibrary.geometry(for: CADShape(kind: .tube, position: .zero, dimensions: [0.02, 0.11, 0.02], boreRatio: 0.55)),
                           rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
                return pin
            },
            SystemPart(id: "rod", name: "Connecting Rod",
                       detail: "Transfers force from the piston to the crankshaft; experiences both tension and compression. The big end rides on the crank pin.",
                       home: [0, wristPinY - 0.1, 0], explode: [0, -0.05, 0], hue: 0.5) {
                CADMeshLibrary.connectingRod(length: 0.2, bigRadius: 0.024, bigBore: 0.0135, smallRadius: 0.0155,
                                             smallBore: 0.0102, thickness: 0.014)
            },
            SystemPart(id: "crank", name: "Crankshaft",
                       detail: "Converts the rod's linear push into rotation. The offset crank pin sets the stroke length; the counterweights balance it.",
                       home: [0, crankAxisY, 0], explode: [0, -0.15, 0], hue: 0.08, tiltedOnX: true) {
                // Local Y is the shaft axis. Local −Z is "up" at top dead centre, so the crank pin sits at z = −25 mm.
                func bar(_ diameter: Float, from: Float, to: Float, z: Float = 0) -> (CADMeshGeometry, SIMD3<Float>) {
                    (CADMeshLibrary.geometry(for: CADShape(kind: .cylinder, position: .zero, dimensions: [diameter, to - from, diameter])),
                     [0, (from + to) / 2, z])
                }
                var web: [SIMD2<Float>] = []
                for step in 0...24 {      // counterweight arc, opposite the pin
                    let angle = (15 + 150 * Float(step) / 24) * .pi / 180
                    web.append([0.048 * cos(angle), 0.048 * sin(angle)])
                }
                for step in 0...16 {      // rounded end around the pin
                    let angle = Float.pi + Float.pi * Float(step) / 16
                    web.append([0.019 * cos(angle), -0.025 + 0.019 * sin(angle)])
                }
                let cheek = CADMeshLibrary.slab(web, center: [0, 0.005], thickness: 0.009)
                var crank = CADMeshGeometry()
                for (solid, offset) in [bar(0.026, from: -0.011, to: 0.011, z: -0.025), bar(0.028, from: 0.016, to: 0.118), bar(0.028, from: -0.085, to: -0.016)] {
                    crank.append(solid, translation: offset)
                }
                crank.append(cheek, translation: [0, 0.0135, 0])
                crank.append(cheek, translation: [0, -0.0135, 0])
                return crank
            },
            SystemPart(id: "flywheel", name: "Flywheel",
                       detail: "Stores rotational energy to smooth out the pulses between power strokes. Most of its mass sits in the heavy rim, far from the axis.",
                       home: [0, crankAxisY, 0.1], explode: [0, -0.15, 0.15], hue: 0.78, tiltedOnX: true) {
                var wheel = CADMeshLibrary.lathe([[0, -0.015], [0.025, -0.015], [0.025, -0.006], [0.08, -0.006], [0.08, -0.015], [0.098, -0.015],
                                                  [0.1, -0.013], [0.1, 0.013], [0.098, 0.015], [0.08, 0.015], [0.08, 0.006], [0.025, 0.006],
                                                  [0.025, 0.015], [0, 0.015]])
                // Three bosses on the web make the rotation visible; a plain disc looks still while it spins.
                let boss = CADMeshLibrary.geometry(for: CADShape(kind: .cylinder, position: .zero, dimensions: [0.022, 0.02, 0.022]))
                for turn in 0..<3 {
                    let angle = Float(turn) * 2 * .pi / 3
                    wheel.append(boss, translation: [0.053 * cos(angle), 0, 0.053 * sin(angle)])
                }
                return wheel
            }
        ]
    )

    // A 12-tooth pinion and a 36-tooth gear with 80 mm and 240 mm pitch diameters, 160 mm apart.
    private static func shaft(_ diameter: Float) -> CADMeshGeometry {
        CADMeshLibrary.geometry(for: CADShape(kind: .cylinder, position: .zero, dimensions: [diameter, 0.3, diameter]))
    }
    private static func gear(teeth: Int, pitchRadius: Float, shaftRadius: Float, phase: Float) -> CADMeshGeometry {
        let outside = pitchRadius * Float(teeth + 2) / Float(teeth)
        return CADMeshLibrary.spurGear(teeth: teeth, radii: [outside, outside], thickness: 0.03,
                                       boreFraction: shaftRadius / outside, phase: phase)
    }

    static let gearTrain = EngSystem(
        id: "gears",
        title: "3:1 Gear Pair",
        summary: "See how gear ratio trades speed for torque.",
        parts: [
            SystemPart(id: "in", name: "Input Shaft",
                       detail: "Receives torque from the motor.",
                       home: [-0.08, 0, 0], explode: [-0.1, 0, 0], hue: 0.58, tiltedOnX: true) { shaft(0.02) },
            SystemPart(id: "g1", name: "Pinion (12T)",
                       detail: "Small driving gear. Fewer teeth means it spins faster.",
                       home: [-0.08, 0, -0.05], explode: [-0.1, 0, -0.1], hue: 0.02, tiltedOnX: true) {
                gear(teeth: 12, pitchRadius: 0.04, shaftRadius: 0.01, phase: 0)
            },
            SystemPart(id: "g2", name: "Gear (36T)",
                       detail: "Large driven gear. Ratio 36:12 = 3:1, so output speed drops 3x and torque rises about 3x.",
                       home: [0.08, 0, -0.05], explode: [0.1, 0, -0.1], hue: 0.33, tiltedOnX: true) {
                // Half a tooth out of phase, so a gap faces the pinion's tooth where the pitch circles touch.
                gear(teeth: 36, pitchRadius: 0.12, shaftRadius: 0.014, phase: 0.5)
            },
            SystemPart(id: "out", name: "Output Shaft",
                       detail: "Delivers slower, higher-torque rotation to the load.",
                       home: [0.08, 0, 0], explode: [0.1, 0, 0], hue: 0.12, tiltedOnX: true) { shaft(0.028) }
        ]
    )

    static let library = [pistonAssembly, gearTrain]
}
