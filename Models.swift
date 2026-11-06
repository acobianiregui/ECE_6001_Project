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

enum PartShape { case cylinder(h: Float, r: Float), sphere(r: Float), box(w: Float, h: Float, d: Float) }

struct SystemPart: Identifiable {
    let id: String
    let name: String
    let detail: String
    let shape: PartShape
    let home: SIMD3<Float>
    let explode: SIMD3<Float>     // displacement at full explosion
    let hue: CGFloat
    var transparent = false
    var tiltedOnX = false          // rotate 90° so a cylinder lies along Z

    func mesh() -> MeshResource {
        switch shape {
        case .cylinder(let h, let r): .generateCylinder(height: h, radius: r)
        case .sphere(let r): .generateSphere(radius: r)
        case .box(let w, let h, let d): .generateBox(width: w, height: h, depth: d)
        }
    }
}

struct EngSystem: Identifiable {
    let id: String
    let title: String
    let summary: String
    let parts: [SystemPart]

    static let pistonAssembly = EngSystem(
        id: "piston",
        title: "Piston & Crank Assembly",
        summary: "How reciprocating motion becomes rotation. Drag the slider to explode the assembly.",
        parts: [
            SystemPart(id: "block", name: "Cylinder Block",
                       detail: "Houses the piston and contains combustion pressure. Shown transparent so you can see inside.",
                       shape: .cylinder(h: 0.28, r: 0.075), home: [0, 0.06, 0], explode: [0, 0, 0], hue: 0.6, transparent: true),
            SystemPart(id: "plug", name: "Spark Plug",
                       detail: "Ignites the air-fuel mixture at the top of the compression stroke.",
                       shape: .cylinder(h: 0.07, r: 0.012), home: [0, 0.22, 0], explode: [0, 0.2, 0], hue: 0.12),
            SystemPart(id: "piston", name: "Piston",
                       detail: "Moves up and down in the cylinder. Gas pressure on its crown produces linear force.",
                       shape: .cylinder(h: 0.06, r: 0.07), home: [0, 0.08, 0], explode: [0, 0.1, 0], hue: 0.02),
            SystemPart(id: "pin", name: "Wrist Pin",
                       detail: "Pivot joint connecting the piston to the connecting rod.",
                       shape: .sphere(r: 0.018), home: [0, 0.03, 0], explode: [0, 0.03, 0], hue: 0.15),
            SystemPart(id: "rod", name: "Connecting Rod",
                       detail: "Transfers force from the piston to the crankshaft; experiences both tension and compression.",
                       shape: .box(w: 0.025, h: 0.18, d: 0.012), home: [0, -0.07, 0], explode: [0, -0.05, 0], hue: 0.5),
            SystemPart(id: "crank", name: "Crankshaft",
                       detail: "Converts the rod's linear push into rotation. The offset throw sets the stroke length.",
                       shape: .cylinder(h: 0.16, r: 0.02), home: [0, -0.17, 0], explode: [0, -0.15, 0], hue: 0.08, tiltedOnX: true),
            SystemPart(id: "flywheel", name: "Flywheel",
                       detail: "Stores rotational energy to smooth out the pulses between power strokes.",
                       shape: .cylinder(h: 0.025, r: 0.1), home: [0, -0.17, 0.1], explode: [0, -0.15, 0.15], hue: 0.78, tiltedOnX: true)
        ]
    )

    static let gearTrain = EngSystem(
        id: "gears",
        title: "3:1 Gear Pair",
        summary: "See how gear ratio trades speed for torque.",
        parts: [
            SystemPart(id: "in", name: "Input Shaft",
                       detail: "Receives torque from the motor.",
                       shape: .cylinder(h: 0.3, r: 0.01), home: [-0.08, 0, 0], explode: [-0.1, 0, 0], hue: 0.58, tiltedOnX: true),
            SystemPart(id: "g1", name: "Pinion (12T)",
                       detail: "Small driving gear. Fewer teeth means it spins faster.",
                       shape: .cylinder(h: 0.03, r: 0.04), home: [-0.08, 0, -0.05], explode: [-0.1, 0, -0.1], hue: 0.02, tiltedOnX: true),
            SystemPart(id: "g2", name: "Gear (36T)",
                       detail: "Large driven gear. Ratio 36:12 = 3:1, so output speed drops 3x and torque rises about 3x.",
                       shape: .cylinder(h: 0.03, r: 0.12), home: [0.08, 0, -0.05], explode: [0.1, 0, -0.1], hue: 0.33, tiltedOnX: true),
            SystemPart(id: "out", name: "Output Shaft",
                       detail: "Delivers slower, higher-torque rotation to the load.",
                       shape: .cylinder(h: 0.3, r: 0.014), home: [0.08, 0, 0], explode: [0.1, 0, 0], hue: 0.12, tiltedOnX: true)
        ]
    )

    static let library = [pistonAssembly, gearTrain]
}
