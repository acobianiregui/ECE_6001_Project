import SwiftUI
import RealityKit
import Observation

// MARK: - Shared app state

@Observable
final class SpaceController {
    var active: String?   // "cad", "lab", or nil
}

// MARK: - CAD

enum ShapeKind: String, CaseIterable, Identifiable, Codable {
    case box, sphere, cylinder, cone
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .box: "cube"
        case .sphere: "circle"
        case .cylinder: "cylinder"
        case .cone: "triangle"
        }
    }
    /// Base size is 10 cm; scale multiplies it.
    func mesh() -> MeshResource {
        switch self {
        case .box: .generateBox(size: 0.1)
        case .sphere: .generateSphere(radius: 0.05)
        case .cylinder: .generateCylinder(height: 0.1, radius: 0.05)
        case .cone: .generateCone(height: 0.1, radius: 0.05)
        }
    }
}

struct CADShape: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ShapeKind
    var position: SIMD3<Float>
    var scale: Float = 1
    var colorIndex: Int = 0
    var sizeCM: Float { 10 * scale }
}

enum CADPalette {
    static let hues: [CGFloat] = [0.58, 0.02, 0.33, 0.12, 0.78, 0.5]
    static func color(_ index: Int, selected: Bool) -> UIColor {
        UIColor(hue: hues[index % hues.count],
                saturation: selected ? 0.35 : 0.85,
                brightness: 1, alpha: 1)
    }
}

@Observable
final class CADModel {
    var shapes: [CADShape] = []
    var selectedID: UUID?
    var snapEnabled = true
    let gridStep: Float = 0.05   // 5 cm
    private var history: [[CADShape]] = []

    var selected: CADShape? { shapes.first { $0.id == selectedID } }
    var canUndo: Bool { !history.isEmpty }

    /// Plain-language coaching for beginners, based on what they've done so far.
    var coachTip: String {
        if shapes.isEmpty { return "Start by adding a shape. Every 3D part is built from simple solids like these." }
        if selected == nil { return "Look at a shape and pinch it to select it." }
        if shapes.count == 1 { return "Pinch and drag to move it. Try adding a Cylinder and stacking it on top." }
        if shapes.count < 4 { return "Pinch with both hands to resize. Combining simple solids is how real parts are modeled." }
        return "Nice. Snap-to-grid keeps parts aligned like real CAD constraints. Try turning it off to feel the difference."
    }

    func snap(_ v: SIMD3<Float>) -> SIMD3<Float> {
        guard snapEnabled else { return v }
        return (v / gridStep).rounded() * gridStep
    }

    func beginEdit() { history.append(shapes); if history.count > 50 { history.removeFirst() } }

    func add(_ kind: ShapeKind) {
        beginEdit()
        let offset = Float(shapes.count % 5) * gridStep
        let s = CADShape(kind: kind, position: SIMD3(offset, 0.05, 0), colorIndex: shapes.count)
        shapes.append(s)
        selectedID = s.id
    }

    func select(_ id: UUID?) { selectedID = id }

    func setPosition(_ id: UUID, _ p: SIMD3<Float>) {
        guard let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        var q = snap(p)
        q.y = max(q.y, 0.0)   // keep above workplane
        shapes[i].position = q
    }

    func setScale(_ id: UUID, _ s: Float) {
        guard let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(snapEnabled ? (s * 4).rounded() / 4 : s, 0.25), 6)
        shapes[i].scale = clamped
    }

    func setColor(_ index: Int) {
        guard let id = selectedID, let i = shapes.firstIndex(where: { $0.id == id }) else { return }
        beginEdit(); shapes[i].colorIndex = index
    }

    func duplicateSelected() {
        guard var s = selected else { return }
        beginEdit()
        s.id = UUID(); s.position.x += gridStep
        shapes.append(s); selectedID = s.id
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        beginEdit(); shapes.removeAll { $0.id == id }; selectedID = nil
    }

    func undo() {
        guard let last = history.popLast() else { return }
        shapes = last
        if !shapes.contains(where: { $0.id == selectedID }) { selectedID = nil }
    }

    func clear() { beginEdit(); shapes = []; selectedID = nil }
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
        title: "Two-Stage Gear Train",
        summary: "See how gear ratio trades speed for torque.",
        parts: [
            SystemPart(id: "in", name: "Input Shaft",
                       detail: "Receives torque from the motor.",
                       shape: .cylinder(h: 0.3, r: 0.01), home: [-0.1, 0, 0], explode: [-0.1, 0, 0], hue: 0.58, tiltedOnX: true),
            SystemPart(id: "g1", name: "Pinion (12T)",
                       detail: "Small driving gear. Fewer teeth means it spins faster.",
                       shape: .cylinder(h: 0.03, r: 0.04), home: [-0.1, 0, -0.05], explode: [-0.1, 0, -0.1], hue: 0.02, tiltedOnX: true),
            SystemPart(id: "g2", name: "Gear (36T)",
                       detail: "Large driven gear. Ratio 36:12 = 3:1, so output speed drops 3x and torque rises about 3x.",
                       shape: .cylinder(h: 0.03, r: 0.12), home: [0.1, 0, -0.05], explode: [0.1, 0, -0.1], hue: 0.33, tiltedOnX: true),
            SystemPart(id: "out", name: "Output Shaft",
                       detail: "Delivers slower, higher-torque rotation to the load.",
                       shape: .cylinder(h: 0.3, r: 0.014), home: [0.1, 0, 0], explode: [0.1, 0, 0], hue: 0.12, tiltedOnX: true)
        ]
    )

    static let library = [pistonAssembly, gearTrain]
}

// MARK: - Virtual lab

struct LabComponent: Identifiable {
    let id: String
    let name: String
    let position: SIMD3<Float>
    let size: SIMD3<Float>
    let hue: CGFloat
}

struct LabStep: Identifiable {
    let id = UUID()
    let targetID: String
    let instruction: String
    let why: String
}

@Observable
final class LabModel {
    static let components: [LabComponent] = [
        LabComponent(id: "switch", name: "Power Switch", position: [-0.5, 0, 0], size: [0.1, 0.05, 0.06], hue: 0.0),
        LabComponent(id: "resistor", name: "330 Ω Resistor", position: [-0.25, 0, 0], size: [0.12, 0.03, 0.03], hue: 0.1),
        LabComponent(id: "led", name: "Red LED", position: [0.0, 0, 0], size: [0.04, 0.06, 0.04], hue: 0.98),
        LabComponent(id: "battery", name: "9 V Battery", position: [0.25, 0, 0], size: [0.07, 0.1, 0.04], hue: 0.58),
        LabComponent(id: "meter", name: "Multimeter", position: [0.52, 0, 0], size: [0.1, 0.16, 0.04], hue: 0.15)
    ]

    static let steps: [LabStep] = [
        LabStep(targetID: "switch", instruction: "Confirm the power switch is OFF.",
                why: "Always de-energize before changing a circuit."),
        LabStep(targetID: "resistor", instruction: "Place the 330 Ω resistor in the circuit.",
                why: "Ohm's law: (9 V − 2 V) / 330 Ω ≈ 21 mA, close to the LED's safe limit."),
        LabStep(targetID: "led", instruction: "Place the LED in series after the resistor.",
                why: "LEDs are polarized; the long leg goes toward the positive side."),
        LabStep(targetID: "battery", instruction: "Connect the 9 V battery.",
                why: "The source goes last so no part of the circuit is live while you wire it."),
        LabStep(targetID: "switch", instruction: "Close the switch to power the circuit.",
                why: "The LED should light. If it doesn't, check polarity."),
        LabStep(targetID: "meter", instruction: "Measure the voltage across the resistor with the multimeter.",
                why: "Expect about 7 V; the LED drops the other ~2 V (Kirchhoff's voltage law).")
    ]

    var stepIndex = 0
    var mistakes = 0
    var feedback = "Tap the component each step asks for."
    var done: Set<String> = []        // component ids already placed
    var switchClosed = false

    var current: LabStep? { stepIndex < Self.steps.count ? Self.steps[stepIndex] : nil }
    var finished: Bool { stepIndex >= Self.steps.count }
    var score: Int { max(0, 100 - mistakes * 10) }

    func attempt(_ id: String) {
        guard let step = current else { return }
        if id == step.targetID {
            if id == "switch" { switchClosed = stepIndex == 4 }
            done.insert(id)
            feedback = "Correct. " + step.why
            stepIndex += 1
        } else {
            mistakes += 1
            let name = Self.components.first { $0.id == id }?.name ?? id
            feedback = "Not yet: \(name) isn't the next step. Safety first, order matters in real labs. (−10 points)"
        }
    }

    func reset() {
        stepIndex = 0; mistakes = 0; done = []; switchClosed = false
        feedback = "Tap the component each step asks for."
    }
}
