import SwiftUI

struct MechanicsExplorerView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var inputTeeth = 12
    @State private var outputTeeth = 36
    @State private var inputRPM: Double = 90
    @State private var inputTorque: Double = 1
    @State private var turns: Double = 0
    @State private var motorRunning = false
    @State private var motorStart: Date?
    @State private var motorTurns: Double = 0      // input turns accumulated by the motor
    @State private var playbackSpeed: Double = 0.25
    @State private var prediction = "Slower"
    @State private var predictionChecked = false
    private var result: GearRatioResult {
        .init(inputTeeth: inputTeeth, outputTeeth: outputTeeth, inputRPM: inputRPM, inputTorque: inputTorque)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                StudyHeading(eyebrow: "MECHANICS LAB", title: "See how parts work together",
                    subtitle: "Inspect an assembly in 3D, then change a gear pair to test the trade between speed and torque.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                    ForEach(EngSystem.library) { system in
                        StudyCard(tint: .orange) {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: system.id == "piston" ? "engine.combustion" : "gearshape.2")
                                    .font(.system(size: 36)).foregroundStyle(.orange)
                                Text(system.title).font(.title3.bold())
                                Text(system.summary).font(.subheadline).foregroundStyle(.secondary)
                                Text("Explode the assembly, inspect each part, and complete a three-part identification challenge.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button { openWindow(id: "system", value: system.id) } label: {
                                    Label("Open in 3D", systemImage: "cube.transparent")
                                }
                                .buttonStyle(.borderedProminent).tint(.orange)
                            }
                        }
                    }
                }
                gearLab
                StudyCard(tint: .orange) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Think like an engineer", systemImage: "lightbulb").font(.headline)
                        Text("A motor turns quickly but cannot deliver enough turning force to lift a load. Which gear should have more teeth? Change the pair, then explain what happens to speed, torque, and direction.")
                            .font(.subheadline)
                        Text("Torque means turning force. RPM means revolutions per minute. This model assumes rigid gears with equal tooth size, no slip, and no frictional losses.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Gear relationships · Carnegie Mellon University", destination: URL(string: "https://www.cs.cmu.edu/~rapidproto/mechanisms/chpt7.html")!)
                            .font(.caption)
                        Link("Rotational power · OpenStax", destination: URL(string: "https://openstax.org/books/university-physics-volume-1/pages/10-8-work-and-power-for-rotational-motion")!)
                            .font(.caption)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("3D Explorer")
        .onChange(of: inputTeeth) { _, _ in predictionChecked = false; resetMotion() }
        .onChange(of: outputTeeth) { _, _ in predictionChecked = false; resetMotion() }
        .onChange(of: inputRPM) { _, _ in if motorRunning { foldMotorTurns(); motorStart = .now } }
        .onChange(of: playbackSpeed) { _, _ in if motorRunning { foldMotorTurns(); motorStart = .now } }
    }

    private var gearLab: some View {
        StudyCard(tint: .orange) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Gear ratio playground", systemImage: "gearshape.2.fill").font(.title2.bold())
                    Spacer()
                    Text("One external gear pair").font(.caption).foregroundStyle(.secondary)
                }
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !motorRunning)) { timeline in
                    let input = totalInputTurns(at: timeline.date)
                    VStack(alignment: .leading, spacing: 10) {
                        gearDiagram(inputTurns: input)
                        revolutionCounter(inputTurns: input)
                    }
                }
                HStack(spacing: 14) {
                    Button {
                        if motorRunning { foldMotorTurns(); motorStart = nil } else { motorStart = .now }
                        motorRunning.toggle()
                    } label: {
                        Label(motorRunning ? "Stop motor" : "Run motor", systemImage: motorRunning ? "stop.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderedProminent).tint(motorRunning ? .red : .orange)
                    Picker("Playback", selection: $playbackSpeed) {
                        Text("¼× speed").tag(0.25)
                        Text("½×").tag(0.5)
                        Text("Real time").tag(1.0)
                    }
                    .pickerStyle(.segmented).frame(maxWidth: 320)
                    Spacer(minLength: 0)
                    Button("Reset", systemImage: "arrow.counterclockwise") { resetMotion() }.font(.caption)
                }
                Text("Run the motor or drag the turn control. Watch the counters: the output completes one turn for every \(String(format: "%.2f", result.ratio)) input turns. Tooth outlines are simplified.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Input turns").font(.subheadline)
                    Slider(value: $turns, in: 0...2)
                        .accessibilityLabel("Input gear turns")
                    Text(turns.formatted(.number.precision(.fractionLength(2)))).monospacedDigit().frame(width: 55)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], alignment: .leading, spacing: 14) {
                    Stepper("Input: \(inputTeeth) teeth", value: $inputTeeth, in: 12...60, step: 6)
                    Stepper("Output: \(outputTeeth) teeth", value: $outputTeeth, in: 12...60, step: 6)
                    Stepper(value: $inputRPM, in: 30...180, step: 30) {
                        Text("Input speed: \(Int(inputRPM)) RPM")
                    }
                    Stepper(value: $inputTorque, in: 0.5...5, step: 0.5) {
                        Text(String(format: "Input torque: %.1f N·m", inputTorque))
                    }
                }
                Divider()
                Text("Predict the output speed before checking").font(.headline)
                Picker("Output speed", selection: $prediction) {
                    ForEach(["Slower", "Same speed", "Faster"], id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: prediction) { _, _ in predictionChecked = false }
                Button("Test my prediction") { predictionChecked = true }
                    .buttonStyle(.borderedProminent).tint(.orange)
                if predictionChecked {
                    Label(prediction == result.speedPrediction ? "Your prediction matches the ratio." : "Compare the tooth counts: the output is \(result.speedPrediction.lowercased()).",
                          systemImage: prediction == result.speedPrediction ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .font(.subheadline).foregroundStyle(prediction == result.speedPrediction ? Color.green : Color.orange)
                    results
                }
                Text("Gear ratio").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("ratio = output teeth ÷ input teeth").font(.system(.body, design: .monospaced))
                Text("Ideal gear speed relation").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("output RPM = input RPM ÷ ratio").font(.system(.body, design: .monospaced))
                Text("Ideal gear torque relation").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("output torque = input torque × ratio").font(.system(.body, design: .monospaced))
                Text("The touching gears turn in opposite directions. Increasing torque reduces speed; an ideal gear pair conserves power.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func totalInputTurns(at date: Date) -> Double {
        let live = motorStart.map { date.timeIntervalSince($0) * inputRPM / 60 * playbackSpeed } ?? 0
        return turns + motorTurns + live
    }
    private func foldMotorTurns() {
        if let start = motorStart { motorTurns += Date.now.timeIntervalSince(start) * inputRPM / 60 * playbackSpeed }
    }
    private func resetMotion() {
        turns = 0
        motorTurns = 0
        motorStart = motorRunning ? .now : nil
    }

    private func revolutionCounter(inputTurns: Double) -> some View {
        HStack(spacing: 18) {
            Label(String(format: "Input %.2f rev", inputTurns), systemImage: "arrow.clockwise")
                .foregroundStyle(.orange)
            Label(String(format: "Output %.2f rev", inputTurns / result.ratio), systemImage: "arrow.counterclockwise")
                .foregroundStyle(.mint)
            Spacer(minLength: 0)
            Text(String(format: "Power in %.1f W = out %.1f W", result.inputTorque * result.inputRPM * 2 * .pi / 60,
                        result.outputTorque * result.outputRPM * 2 * .pi / 60))
                .foregroundStyle(.secondary)
        }
        .font(.callout.monospacedDigit())
        .accessibilityElement(children: .combine)
    }

    private func gearDiagram(inputTurns: Double) -> some View {
        GeometryReader { geometry in
            let total = Double(inputTeeth + outputTeeth)
            let scale = min(Double(geometry.size.width - 32) / total, 170 / Double(max(inputTeeth, outputTeeth)))
            let inputDiameter = CGFloat(Double(inputTeeth) * scale)
            let outputDiameter = CGFloat(Double(outputTeeth) * scale)
            // Phase the outlines so an input tooth sits in an output gap at the contact point,
            // and overlap the rims by about one tooth depth so the pair visibly meshes.
            let inputPhase = -135.0 / Double(inputTeeth)
            let outputPhase = 180.0 - 315.0 / Double(outputTeeth)
            HStack(spacing: -0.06 * (inputDiameter + outputDiameter) / 2) {
                gear(teeth: inputTeeth, color: .orange, diameter: inputDiameter, degrees: inputPhase + inputTurns * 360)
                gear(teeth: outputTeeth, color: .mint, diameter: outputDiameter, degrees: outputPhase - inputTurns * 360 / result.ratio)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 185)
        .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topLeading) { Text("INPUT ↻").font(.caption.bold()).foregroundStyle(.orange).padding(12) }
        .overlay(alignment: .topTrailing) { Text("OUTPUT ↺").font(.caption.bold()).foregroundStyle(.mint).padding(12) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(inputTeeth)-tooth input gear turns clockwise. \(outputTeeth)-tooth output gear turns counterclockwise at \(result.outputRPM.formatted()) revolutions per minute.")
    }

    private func gear(teeth: Int, color: Color, diameter: CGFloat, degrees: Double) -> some View {
        GearOutline(teeth: teeth)
            .fill(color.opacity(0.22))
            .overlay(GearOutline(teeth: teeth).stroke(color, lineWidth: 2))
            .overlay {
                Circle().stroke(color, lineWidth: 3).frame(width: diameter * 0.16, height: diameter * 0.16)
            }
            .overlay(alignment: .top) {
                Circle().fill(color).frame(width: 7, height: 7).offset(y: diameter * 0.20)
            }
            .rotationEffect(.degrees(degrees))
            .frame(width: diameter, height: diameter)
    }

    private var results: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
            MetricTile(value: String(format: "%.2f:1", result.ratio), label: "Output/input teeth", symbol: "divide", tint: .orange)
            MetricTile(value: String(format: "%.1f RPM", result.outputRPM), label: "Output speed · opposite direction", symbol: "arrow.counterclockwise", tint: .mint)
            MetricTile(value: String(format: "%.2f N·m", result.outputTorque), label: "Ideal output torque", symbol: "arrow.clockwise", tint: .orange)
        }
    }
}

/// A readable schematic tooth outline, not an involute manufacturing profile.
private struct GearOutline: Shape {
    let teeth: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 2
        let root = outer * 0.88
        var path = Path()
        for index in 0..<(teeth * 4) {
            let angle = Double(index) * 2 * .pi / Double(teeth * 4)
            let radius = index % 4 == 1 || index % 4 == 2 ? outer : root
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
