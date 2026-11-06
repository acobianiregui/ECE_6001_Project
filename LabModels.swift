import Foundation
import Observation

struct LabComponent: Identifiable {
    let id: String
    let name: String
    let position: SIMD3<Float>
    let size: SIMD3<Float>
    let hue: CGFloat
}

struct LabStep: Identifiable {
    let id: String
    let targetID: String
    let instruction: String
    let why: String
}

/// A deliberately simple, constant-voltage-drop LED model, not a component-level solver.
struct CircuitReading {
    let voltage: Double
    let resistance: Double
    let powered: Bool
    let ledReversed: Bool

    static let ledForwardVoltage: Double = 2
    static let illustrativeCurrentLimit: Double = 0.020
    static let resistorRating: Double = 0.25

    var isConducting: Bool {
        powered && !ledReversed && voltage > Self.ledForwardVoltage && resistance > 0
    }
    var currentAmps: Double {
        isConducting ? (voltage - Self.ledForwardVoltage) / resistance : 0
    }
    var currentMilliamps: Double { currentAmps * 1_000 }
    var resistorVoltage: Double { currentAmps * max(resistance, 0) }
    var resistorPower: Double { currentAmps * resistorVoltage }
    var overCurrent: Bool { currentAmps > Self.illustrativeCurrentLimit }
    var overPower: Bool { resistorPower > Self.resistorRating }
    var statusTitle: String {
        if !powered { return "Switch open" }
        if ledReversed { return "LED reversed" }
        if resistance <= 0 { return "Choose a positive resistance" }
        if voltage <= Self.ledForwardVoltage { return "Supply at or below 2 V" }
        if overCurrent && overPower { return "Current and power limits exceeded" }
        if overCurrent { return "Above the example LED's 20 mA limit" }
        if overPower { return "Above the resistor's 0.25 W rating" }
        return "Current is flowing"
    }
    var explanation: String {
        if !powered { return "An open switch breaks the loop. Current is zero, even though the battery still has voltage." }
        if ledReversed { return "The ideal model blocks reverse current. Real LEDs can be damaged by reverse voltage; breakdown is not simulated." }
        if resistance <= 0 { return "This model requires a current-limiting resistor with a positive resistance." }
        if voltage <= Self.ledForwardVoltage { return "This model conducts only above a 2 V supply. A real LED turns on gradually rather than at one sharp threshold." }
        if overCurrent && overPower { return "The current exceeds the example LED's 20 mA limit, and the resistor dissipates more than its 0.25 W rating. Try a larger resistance." }
        if overCurrent { return "Try a larger resistor. This example uses a 20 mA limit; actual limits come from the LED's datasheet." }
        if overPower { return "The resistor turns electrical energy into heat. Its power rating matters as well as its resistance." }
        return "The LED takes a modeled 2 V. The remaining voltage is across the resistor, which sets the current." }
}

@Observable
final class LabModel {
    static let components: [LabComponent] = [
        LabComponent(id: "switch", name: "Power switch", position: [-0.5, 0, 0], size: [0.1, 0.05, 0.06], hue: 0.0),
        LabComponent(id: "resistor", name: "470 Ω resistor", position: [-0.25, 0, 0], size: [0.12, 0.03, 0.03], hue: 0.1),
        LabComponent(id: "led", name: "Red LED", position: [0.0, 0, 0], size: [0.04, 0.06, 0.04], hue: 0.98),
        LabComponent(id: "battery", name: "9 V battery", position: [0.25, 0, 0], size: [0.07, 0.1, 0.04], hue: 0.58),
        LabComponent(id: "meter", name: "Multimeter", position: [0.52, 0, 0], size: [0.1, 0.16, 0.04], hue: 0.15)
    ]
    static let steps: [LabStep] = [
        LabStep(id: "isolate", targetID: "switch", instruction: "Confirm the power switch is OFF.",
                why: "An open switch keeps the circuit de-energized while you assemble it."),
        LabStep(id: "limit", targetID: "resistor", instruction: "Add the 470 Ω current-limiting resistor.",
                why: "Ohm's law gives (9 V − 2 V) / 470 Ω ≈ 14.9 mA for our simplified LED model."),
        LabStep(id: "polarize", targetID: "led", instruction: "Add the LED, with its anode toward the positive supply.",
                why: "The anode is the positive-side terminal. The cathode, often marked by a flat edge, faces the negative side."),
        LabStep(id: "connect", targetID: "battery", instruction: "Connect the 9 V battery while the switch stays OFF.",
                why: "The supply is connected after the components are in place."),
        LabStep(id: "energize", targetID: "switch", instruction: "Close the switch to power the circuit.",
                why: "The closed loop now carries the same current through the resistor and LED."),
        LabStep(id: "measure", targetID: "meter", instruction: "Connect the voltmeter across the resistor.",
                why: "A voltmeter connects in parallel. Expect about 7 V across the resistor and 2 V across the LED.")
    ]

    var stepIndex = 0
    var mistakes = 0
    var feedback = "Choose a component below, or tap it on the immersive bench."
    var done: Set<String> = []
    var switchClosed = false
    var lastAttemptCorrect: Bool?
    var voltage: Double = 9 { didSet { saveExperiment() } }
    var resistance: Double = 470 { didSet { saveExperiment() } }
    var experimentPowered = false { didSet { saveExperiment() } }
    var ledReversed = false { didSet { saveExperiment() } }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let settingsKey = "AVPLearn.circuitExperiment.v1"
    @ObservationIgnored private var completionConsumed = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(ExperimentSettings.self, from: data) {
            voltage = min(12, max(0, saved.voltage.isFinite ? saved.voltage : 9))
            resistance = min(2_200, max(100, saved.resistance.isFinite ? saved.resistance : 470))
            ledReversed = saved.ledReversed
            // Open the switch on launch, so the learner chooses when to energize.
        }
    }

    var current: LabStep? { Self.steps.indices.contains(stepIndex) ? Self.steps[stepIndex] : nil }
    var finished: Bool { stepIndex >= Self.steps.count }
    var score: Int { max(0, 100 - mistakes * 10) }
    var reading: CircuitReading {
        CircuitReading(voltage: voltage, resistance: resistance, powered: experimentPowered, ledReversed: ledReversed)
    }
    var guidedReading: CircuitReading {
        CircuitReading(voltage: 9, resistance: 470, powered: switchClosed, ledReversed: false)
    }

    func attempt(_ id: String) {
        guard let step = current, Self.components.contains(where: { $0.id == id }) else { return }
        if id == step.targetID {
            if id == "switch" { switchClosed = step.id == "energize" }
            done.insert(id)
            feedback = step.why
            lastAttemptCorrect = true
            stepIndex += 1
        } else {
            mistakes += 1
            lastAttemptCorrect = false
            let expected = Self.components.first { $0.id == step.targetID }?.name ?? step.targetID
            if id == "battery" && !done.contains("led") {
                feedback = "Keep the supply disconnected while placing components. Next, choose the \(expected.lowercased())."
            } else if id == "meter" {
                feedback = "There is no powered resistor voltage to measure yet. Next, choose the \(expected.lowercased())."
            } else {
                feedback = "That component comes later. Next, choose the \(expected.lowercased()) and read why this step matters."
            }
        }
    }

    func reset() {
        stepIndex = 0
        mistakes = 0
        done = []
        switchClosed = false
        lastAttemptCorrect = nil
        completionConsumed = false
        feedback = "Choose a component below, or tap it on the immersive bench."
    }
    /// A finished run is recorded once, even if its panel is recreated after immersive practice.
    func consumeCompletion() -> Bool {
        guard finished, !completionConsumed else { return false }
        completionConsumed = true
        return true
    }
    func resetExperiment() {
        experimentPowered = false
        voltage = 9
        resistance = 470
        ledReversed = false
    }
    private struct ExperimentSettings: Codable {
        var voltage: Double
        var resistance: Double
        var ledReversed: Bool
    }
    private func saveExperiment() {
        let settings = ExperimentSettings(voltage: voltage, resistance: resistance, ledReversed: ledReversed)
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: settingsKey) }
    }
}
