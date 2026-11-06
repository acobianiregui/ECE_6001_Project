import SwiftUI

struct CircuitLabView: View {
    @Environment(LabModel.self) private var lab
    @Environment(SpaceController.self) private var spaces
    @Environment(LearningStore.self) private var learning
    @State private var mode: LabMode = .guided
    let toggleSpace: (String) -> Void
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 20, alignment: .top)]

    private enum LabMode: String, CaseIterable, Identifiable {
        case guided = "Guided lab", experiment = "Experiment"
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Picker("Lab mode", selection: $mode) {
                    ForEach(LabMode.allCases) { value in Text(value.rawValue).tag(value) }
                }
                .pickerStyle(.segmented)
                if mode == .guided { guidedContent } else { experimentContent }
                references
            }
            .padding(28)
            .frame(maxWidth: 1_100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Circuit Lab")
        .onChange(of: lab.finished, initial: true) { _, finished in
            if finished && lab.consumeCompletion() {
                learning.recordActivity("circuit", score: lab.score)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 32)).foregroundStyle(.orange)
                .padding(15).background(.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 6) {
                Text("Make the invisible visible").font(.title2.bold())
                Text("Build a series circuit, then change one thing and explain what happens.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { toggleSpace("lab") } label: {
                Label(spaces.active == "lab" ? "Leave bench" : "3D bench", systemImage: "visionpro")
            }
            .disabled(spaces.isTransitioning)
            .accessibilityHint("The same guided procedure can also be completed using the controls in this window.")
        }
    }

    private var guidedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                panel {
                    Label("The circuit you are building", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    CircuitDiagram(voltage: 9, resistance: 470, reading: lab.guidedReading)
                    Text("A series circuit has one path. The same current passes through every component.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                panel {
                    if lab.finished {
                        Label("Procedure complete", systemImage: "checkmark.seal.fill")
                            .font(.title3.bold()).foregroundStyle(.green)
                        Text("\(lab.score) / 100").font(.system(size: 42, weight: .bold, design: .rounded))
                        Text("\(lab.mistakes) order \(lab.mistakes == 1 ? "mistake" : "mistakes") · Result saved to your progress.")
                            .foregroundStyle(.secondary)
                        Text("Explain why the resistor is needed before moving to Experiment. This score reflects the sequence you practiced.")
                            .font(.callout)
                        HStack {
                            Button("Experiment") { mode = .experiment }.buttonStyle(.borderedProminent)
                            Button("Practice again") { lab.reset() }
                        }
                    } else if let step = lab.current {
                        HStack {
                            Text("STEP \(lab.stepIndex + 1) OF \(LabModel.steps.count)")
                                .font(.caption.bold()).tracking(1.2).foregroundStyle(.orange)
                            Spacer()
                            Text("\(lab.score) points").font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(lab.stepIndex), total: Double(LabModel.steps.count))
                            .tint(.orange)
                        Text(step.instruction).font(.title3.bold())
                        Text("Choose the component that performs this step.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: lab.lastAttemptCorrect == false ? "arrow.triangle.turn.up.right.diamond" : "lightbulb")
                                .foregroundStyle(lab.lastAttemptCorrect == false ? .orange : .teal)
                            Text(lab.feedback).font(.callout)
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            if !lab.finished {
                panel {
                    Text("Your bench").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 12)], spacing: 12) {
                        ForEach(LabModel.components) { component in
                            Button { lab.attempt(component.id) } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: symbol(for: component.id)).font(.title2)
                                    Text(component.name).font(.callout.weight(.medium)).multilineTextAlignment(.center)
                                    if lab.done.contains(component.id) {
                                        Label(component.id == "switch" ? (lab.switchClosed ? "Closed" : "Open") : "Placed",
                                              systemImage: "checkmark.circle.fill")
                                            .font(.caption).foregroundStyle(.green)
                                    } else {
                                        Text("Choose").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 100)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(component.name)
                        }
                    }
                    Button("Restart procedure") { lab.reset() }.font(.callout)
                }
            }
        }
    }

    private var experimentContent: some View {
        @Bindable var lab = lab
        return VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                panel {
                    Text("Change one variable").font(.headline)
                    CircuitDiagram(voltage: lab.voltage, resistance: lab.resistance, reading: lab.reading)
                    HStack {
                        Label(lab.reading.statusTitle,
                              systemImage: lab.reading.overCurrent || lab.reading.overPower ? "exclamationmark.triangle" : "bolt.circle")
                            .font(.callout.bold())
                            .foregroundStyle(lab.reading.overCurrent || lab.reading.overPower ? .orange : .teal)
                    }
                    Text(lab.reading.explanation).font(.callout).foregroundStyle(.secondary)
                }
                panel {
                    HStack {
                        Text("Circuit controls").font(.headline)
                        Spacer()
                        Button("Reset") { lab.resetExperiment() }.font(.caption)
                    }
                    valueSlider(title: "Supply voltage", value: $lab.voltage, range: 0...12, step: 0.5,
                                formatted: String(format: "%.1f V", lab.voltage))
                    valueSlider(title: "Resistance", value: $lab.resistance, range: 100...2_200, step: 10,
                                formatted: String(format: "%.0f Ω", lab.resistance))
                    HStack {
                        ForEach([220.0, 470.0, 1_000.0], id: \.self) { value in
                            Button(String(format: "%.0f Ω", value)) { lab.resistance = value }
                                .font(.caption)
                        }
                    }
                    Divider()
                    Toggle("Close power switch", isOn: $lab.experimentPowered)
                    Toggle("Reverse the LED", isOn: $lab.ledReversed)
                    Text("Polarity means direction: anode toward +, cathode toward −.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            panel {
                Text("Read the result").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                    measurement("Series current", value: String(format: "%.2f", lab.reading.currentMilliamps), unit: "mA", symbol: "arrow.right")
                    measurement("Resistor voltage", value: String(format: "%.2f", lab.reading.resistorVoltage), unit: "V", symbol: "bolt")
                    measurement("Resistor power", value: String(format: "%.3f", lab.reading.resistorPower), unit: "W", symbol: "flame")
                }
                Divider()
                Text("Ohm’s law applied to the resistor").font(.callout.bold())
                Text("I = (Vₛ − VLED) / R").font(.title3.monospaced())
                Text("I is current in amperes, Vₛ is supply voltage, VLED = 2 V in this model, and R is resistance in ohms. This expression applies when the switch is closed and the LED conducts.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Resistor power").font(.callout.bold())
                Text("P = I²R").font(.title3.monospaced())
                Text("P is power in watts. The example resistor is rated 0.25 W.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            CircuitPredictionView()
            Text("Model assumptions: ideal battery and wires, one resistor, fixed 2 V LED forward drop, no leakage, temperature changes, or reverse breakdown. The 20 mA limit is an example, not a rating for every LED.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var references: some View {
        DisclosureGroup("Read more") {
            VStack(alignment: .leading, spacing: 10) {
                Link("OpenStax · Electrical energy and power", destination: URL(string: "https://openstax.org/books/university-physics-volume-2/pages/9-5-electrical-energy-and-power")!)
                Link("SparkFun · Current-limiting resistors", destination: URL(string: "https://learn.sparkfun.com/tutorials/resistors/example-applications")!)
                Text("Use component datasheets when choosing parts for a real circuit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
        .font(.callout)
    }

    private func symbol(for id: String) -> String {
        switch id {
        case "switch": "switch.2"
        case "resistor": "waveform.path"
        case "led": "lightbulb.led"
        case "battery": "battery.100percent"
        default: "gauge.with.dots.needle.50percent"
        }
    }
    private func valueSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, formatted: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text(formatted).monospacedDigit().foregroundStyle(.teal) }
            Slider(value: value, in: range, step: step) { Text(title) }
        }
        .font(.callout)
    }
    private func measurement(_ title: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title2.bold()).monospacedDigit()
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16, content: content)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct CircuitPredictionView: View {
    @State private var questionIndex = 0
    @State private var selected: Int?
    @State private var checked = false
    private struct Prediction {
        let prompt: String
        let options: [String]
        let answer: Int
        let explanation: String
    }
    private let questions = [
        Prediction(prompt: "At 9 V, the 470 Ω resistor is replaced by 940 Ω. The LED still drops 2 V. What happens to the current?",
                   options: ["It halves", "It doubles", "It stays the same"], answer: 0,
                   explanation: "The resistor still has 7 V across it. Ohm’s law, I = V/R, means doubling R halves current: about 14.9 mA becomes 7.45 mA."),
        Prediction(prompt: "With a forward LED and the switch closed, the supply changes from 5 V to 10 V. Does current exactly double?",
                   options: ["Yes, because supply voltage doubles", "No, it rises by more than double", "No, it rises by less than double"], answer: 1,
                   explanation: "The fixed 2 V LED drop leaves 3 V across the resistor at first and 8 V afterward. Current rises by 8/3, about 2.67 times, in this model."),
        Prediction(prompt: "At the same supply voltage, you halve the resistor. What happens to the resistor’s power while the LED conducts?",
                   options: ["It halves", "It doubles", "It stays the same"], answer: 1,
                   explanation: "Current doubles, so resistor power, P = I²R, becomes four times the current factor times half the resistance: twice the power.")
    ]
    private var question: Prediction { questions[questionIndex] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Predict, then test", systemImage: "brain.head.profile").font(.headline)
            Text(question.prompt).font(.callout)
            ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                Button { if !checked { selected = index } } label: {
                    HStack {
                        Image(systemName: selected == index ? "largecircle.fill.circle" : "circle")
                        Text(option)
                        Spacer()
                        if checked && index == question.answer { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(checked)
                .accessibilityAddTraits(selected == index ? .isSelected : [])
            }
            if checked {
                Text(selected == question.answer ? "Your reasoning matches the model." : "Follow the voltage across the resistor.")
                    .font(.callout.bold()).foregroundStyle(selected == question.answer ? .green : .orange)
                Text(question.explanation).font(.callout).foregroundStyle(.secondary)
                Button("Next prediction") {
                    questionIndex = (questionIndex + 1) % questions.count
                    selected = nil
                    checked = false
                }
            } else {
                Button("Check prediction") { checked = true }
                    .buttonStyle(.borderedProminent).disabled(selected == nil)
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct CircuitDiagram: View {
    let voltage: Double
    let resistance: Double
    let reading: CircuitReading

    var body: some View {
        Canvas { context, size in
            let left = size.width * 0.15, right = size.width * 0.85
            let top: CGFloat = 60, bottom: CGFloat = 218, middle: CGFloat = 136
            let center = size.width / 2
            let wire = reading.isConducting ? Color.teal : Color.secondary
            var path = Path()
            path.move(to: CGPoint(x: left, y: middle - 20))
            path.addLine(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: center - 38, y: top))
            path.move(to: CGPoint(x: center + 38, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: middle - 20))
            path.move(to: CGPoint(x: right, y: middle + 20))
            path.addLine(to: CGPoint(x: right, y: bottom))
            path.addLine(to: CGPoint(x: center + 18, y: bottom))
            path.move(to: CGPoint(x: center - 18, y: bottom))
            path.addLine(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left, y: middle + 20))
            context.stroke(path, with: .color(wire), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            var resistor = Path()
            resistor.move(to: CGPoint(x: center - 38, y: top))
            for index in 0..<8 {
                resistor.addLine(to: CGPoint(x: center - 31 + CGFloat(index) * 9, y: top + (index.isMultiple(of: 2) ? -9 : 9)))
            }
            resistor.addLine(to: CGPoint(x: center + 38, y: top))
            context.stroke(resistor, with: .color(.orange), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            label(String(format: "%.0f Ω", resistance), x: center, y: top - 28, in: context)

            var battery = Path()
            battery.move(to: CGPoint(x: left - 17, y: middle - 10))
            battery.addLine(to: CGPoint(x: left + 17, y: middle - 10))
            battery.move(to: CGPoint(x: left - 10, y: middle + 10))
            battery.addLine(to: CGPoint(x: left + 10, y: middle + 10))
            battery.move(to: CGPoint(x: left, y: middle - 20))
            battery.addLine(to: CGPoint(x: left, y: middle - 10))
            battery.move(to: CGPoint(x: left, y: middle + 10))
            battery.addLine(to: CGPoint(x: left, y: middle + 20))
            context.stroke(battery, with: .color(.primary), lineWidth: 3)
            label("+", x: left - 28, y: middle - 12, in: context)
            label("−", x: left - 28, y: middle + 12, in: context)
            label(String(format: "%.1f V", voltage), x: left, y: middle + 43, in: context)

            let ledColor: Color = reading.isConducting ? (reading.overCurrent ? .orange : .red) : .gray
            if reading.isConducting {
                context.fill(Path(ellipseIn: CGRect(x: right - 29, y: middle - 29, width: 58, height: 58)), with: .color(ledColor.opacity(0.15)))
            }
            context.fill(Path(ellipseIn: CGRect(x: right - 17, y: middle - 17, width: 34, height: 34)), with: .color(ledColor.opacity(0.8)))
            var cathode = Path()
            let cathodeY = reading.ledReversed ? middle - 15 : middle + 15
            cathode.move(to: CGPoint(x: right - 14, y: cathodeY))
            cathode.addLine(to: CGPoint(x: right + 14, y: cathodeY))
            context.stroke(cathode, with: .color(.white), lineWidth: 3)
            label(reading.ledReversed ? "LED ↕" : "LED", x: right, y: middle + 43, in: context)
            label("2 V model", x: right, y: middle - 39, in: context)

            var lever = Path()
            lever.move(to: CGPoint(x: center - 18, y: bottom))
            lever.addLine(to: CGPoint(x: center + 18, y: reading.powered ? bottom : bottom - 20))
            context.stroke(lever, with: .color(wire), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for x in [center - 18, center + 18] {
                context.fill(Path(ellipseIn: CGRect(x: x - 4, y: bottom - 4, width: 8, height: 8)), with: .color(wire))
            }
            label(reading.powered ? "Closed switch" : "Open switch", x: center, y: bottom + 25, in: context)
            context.draw(Text(String(format: "%.2f mA", reading.currentMilliamps)).font(.title3.bold()).foregroundStyle(wire),
                         at: CGPoint(x: center, y: middle))
            label("Series current", x: center, y: middle + 26, in: context)
        }
        .frame(height: 270)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Series circuit: \(String(format: "%.1f", voltage)) volt battery, \(Int(resistance)) ohm resistor, LED, and \(reading.powered ? "closed" : "open") switch. Current \(String(format: "%.2f", reading.currentMilliamps)) milliamperes. \(reading.ledReversed ? "LED is reversed." : "LED has forward polarity.")")
    }
    private func label(_ text: String, x: CGFloat, y: CGFloat, in context: GraphicsContext) {
        context.draw(Text(text).font(.caption).foregroundStyle(.secondary), at: CGPoint(x: x, y: y))
    }
}
