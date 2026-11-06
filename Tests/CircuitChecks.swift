import Foundation

@main struct CircuitChecks {
    static func main() {
        let normal = CircuitReading(voltage: 9, resistance: 470, powered: true, ledReversed: false)
        require(abs(normal.currentMilliamps - 14.8936170213) < 0.00001, "default current")
        require(abs(normal.resistorVoltage - 7) < 0.00001, "resistor voltage")
        require(abs(normal.resistorPower - 49.0 / 470.0) < 0.00001, "resistor power")
        require(!normal.overCurrent && !normal.overPower, "default component example limits")
        require(CircuitReading(voltage: 9, resistance: 470, powered: false, ledReversed: false).currentAmps == 0, "open switch")
        require(CircuitReading(voltage: 9, resistance: 470, powered: true, ledReversed: true).currentAmps == 0, "reverse polarity")
        require(CircuitReading(voltage: 2, resistance: 470, powered: true, ledReversed: false).currentAmps == 0, "threshold")
        let twice = CircuitReading(voltage: 9, resistance: 940, powered: true, ledReversed: false)
        require(abs(twice.currentAmps * 2 - normal.currentAmps) < 0.00001, "doubling resistance halves current")
        let overload = CircuitReading(voltage: 12, resistance: 100, powered: true, ledReversed: false)
        require(overload.overCurrent && overload.overPower, "combined limits")
        let suite = "AVPLearn.CircuitChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = LabModel(defaults: defaults)
        require(!model.consumeCompletion(), "incomplete run cannot record")
        model.attempt("battery")
        require(model.stepIndex == 0 && model.mistakes == 1, "incorrect step preserves ordering")
        model.attempt("nonexistent")
        require(model.mistakes == 1, "scene labels do not cost points")
        for id in ["switch", "resistor", "led", "battery", "switch", "meter"] { model.attempt(id) }
        require(model.finished && model.switchClosed && model.score == 90, "guided assembly completes")
        require(model.consumeCompletion(), "first completion is available")
        require(!model.consumeCompletion() && !model.consumeCompletion(), "recreated panels cannot record the same run")
        model.attempt("meter")
        require(model.score == 90, "completed assembly ignores further taps")
        model.voltage = 11
        model.resistance = 680
        model.ledReversed = true
        let restored = LabModel(defaults: defaults)
        require(restored.voltage == 11 && restored.resistance == 680 && restored.ledReversed, "experiment persistence")
        require(!restored.experimentPowered, "launch starts with open switch")
        model.reset()
        require(model.stepIndex == 0 && model.score == 100 && model.done.isEmpty && !model.switchClosed, "reset")
        require(!model.consumeCompletion(), "reset is incomplete")
        for id in ["switch", "resistor", "led", "battery", "switch", "meter"] { model.attempt(id) }
        require(model.consumeCompletion(), "new completed run can record")
        require(!model.consumeCompletion(), "new run records only once")
        print("Circuit checks passed: equations, boundary states, limits, procedure ordering, persistence, reset.")
    }
    static func require(_ condition: Bool, _ label: String) { if !condition { fatalError(label) } }
}
