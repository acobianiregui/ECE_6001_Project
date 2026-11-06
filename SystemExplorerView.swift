import SwiftUI
import RealityKit

struct SystemExplorerView: View {
    let systemID: String
    @Environment(LearningStore.self) private var learning
    @State private var explode: Float = 0.25
    @State private var selectedID: String?
    @State private var challengeActive = false
    @State private var challengeIndex = 0
    @State private var challengeFeedback = "Look at a part and pinch to select it."
    @State private var running = false
    @State private var speed: Float = 0.5
    @State private var driver = MechanismDriver()

    private var system: EngSystem {
        EngSystem.library.first { $0.id == systemID } ?? .pistonAssembly
    }
    private var selectedPart: SystemPart? { system.parts.first { $0.id == selectedID } }
    private var questions: [(prompt: String, answer: String)] {
        system.id == "gears" ? [
            ("Find the small driving gear.", "g1"),
            ("Find the shaft that receives torque from the motor.", "in"),
            ("Find the large driven gear that trades speed for torque.", "g2")
        ] : [
            ("Find the part that transfers force from the piston to the crankshaft.", "rod"),
            ("Find the part that stores rotational energy to smooth the motion.", "flywheel"),
            ("Find the part that moves inside the cylinder.", "piston")
        ]
    }

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "sys-root"
            // Full explosion still fits the app's 0.6 m volumetric window.
            root.scale = .init(repeating: 0.6)
            for part in system.parts {
                let entity = ModelEntity(mesh: part.mesh(), materials: [Self.material(for: part, selected: false)])
                entity.name = part.id
                entity.position = part.home + explode * part.explode
                if part.tiltedOnX { entity.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) }
                if system.id == "gears", part.id == "g1" || part.id == "g2" {
                    Self.addTeeth(to: entity, part: part, count: part.id == "g1" ? 12 : 36)
                }
                if system.id == "piston", part.id == "crank" || part.id == "flywheel" {
                    Self.addRotationMarker(to: entity, part: part)
                }
                // A transparent outer cylinder must not intercept taps on every inner part.
                if !part.transparent {
                    entity.components.set(InputTargetComponent())
                    entity.generateCollisionShapes(recursive: true)
                }
                root.addChild(entity)
            }
            content.add(root)
            driver.explode = explode
            driver.apply(to: root, system: system)
            let driver = driver
            let system = system
            driver.subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                driver.advance(by: Float(event.deltaTime))
                driver.apply(to: root, system: system)
            }
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "sys-root" }) else { return }
            for part in system.parts {
                guard let entity = root.children.first(where: { $0.name == part.id }) as? ModelEntity else { continue }
                let selected = part.id == selectedID
                entity.scale = .init(repeating: selected ? 1.04 : 1)
                let material = Self.material(for: part, selected: selected)
                entity.model?.materials = [material]
                for child in entity.children {
                    (child as? ModelEntity)?.model?.materials = [material]
                }
            }
        }
        .gesture(TapGesture().targetedToAnyEntity().onEnded { value in
            guard let part = system.parts.first(where: { $0.id == value.entity.name }) else { return }
            selectedID = part.id
            handleChallengeTap(part.id)
        })
        .ornament(attachmentAnchor: .scene(.bottom)) { controlPanel }
        .onChange(of: explode, initial: true) { _, value in driver.explode = value }
        .onChange(of: running, initial: true) { _, value in driver.running = value }
        .onChange(of: speed, initial: true) { _, value in driver.speed = value }
        .onDisappear { driver.subscription?.cancel(); driver.subscription = nil }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(system.title).font(.headline)
                Spacer()
                Button {
                    explode = 0
                    selectedID = nil
                    running = false
                    driver.angle = 0
                } label: { Image(systemName: "arrow.counterclockwise") }
                .accessibilityLabel("Reset assembly view")
            }
            HStack(spacing: 12) {
                Button { running.toggle() } label: {
                    Label(running ? "Pause" : "Run mechanism", systemImage: running ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderedProminent).tint(running ? .gray : .orange)
                Image(systemName: "tortoise").font(.caption).foregroundStyle(.secondary)
                Slider(value: $speed, in: 0.1...2).accessibilityLabel("Animation speed")
                Image(systemName: "hare").font(.caption).foregroundStyle(.secondary)
            }
            Text(motionCaption).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            HStack {
                Text("Assembled").font(.caption)
                Slider(value: $explode, in: 0...1).accessibilityLabel("Assembly explosion")
                Text("Exploded").font(.caption)
            }
            Picker("Inspect a part", selection: $selectedID) {
                Text("Choose a part").tag(Optional<String>.none)
                ForEach(system.parts) { part in Text(part.name).tag(Optional(part.id)) }
            }
            .pickerStyle(.menu)
            if let part = selectedPart {
                Text(part.name).font(.subheadline.bold()).foregroundStyle(.orange)
                Text(part.detail).font(.footnote).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Pinch a part in 3D, or choose its name above. Use the menu to inspect the transparent cylinder block.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Divider()
            if challengeActive {
                if challengeIndex < questions.count {
                    HStack {
                        Label("Identify the part", systemImage: "target").font(.subheadline.bold())
                        Spacer()
                        Text("\(challengeIndex + 1) / \(questions.count)").font(.caption).monospacedDigit()
                    }
                    Text(questions[challengeIndex].prompt).font(.subheadline)
                    Text(challengeFeedback).font(.footnote).foregroundStyle(.secondary)
                    Button("Explore freely") { challengeActive = false }
                        .font(.caption)
                } else {
                    Label("Three parts identified", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold()).foregroundStyle(.green)
                    Text("Activity saved. Describe how these parts transfer motion to each other.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Try the challenge again") { startChallenge() }
                }
            } else {
                Button { startChallenge() } label: {
                    Label("Start identification challenge", systemImage: "target")
                }
                .buttonStyle(.borderedProminent).tint(.orange)
            }
            Text("Simplified assembly · illustrative geometry and motion")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(width: 430)
        .padding(20)
        .glassBackgroundEffect()
    }

    private var motionCaption: String {
        let rpm = Int((speed * 60).rounded())
        return system.id == "gears"
            ? "Input \(rpm) RPM → output \(rpm / 3) RPM, opposite direction. Torque rises 3×."
            : "Crank \(rpm) RPM. Slider-crank: the rod turns the piston's up-and-down push into rotation. The plug fires every second revolution (four-stroke)."
    }

    private func startChallenge() {
        challengeIndex = 0
        challengeFeedback = "Tap the answer in the 3D model. The part menu is for inspection only."
        selectedID = nil
        explode = 1
        challengeActive = true
    }
    private func handleChallengeTap(_ id: String) {
        guard challengeActive, challengeIndex < questions.count else { return }
        if id == questions[challengeIndex].answer {
            challengeIndex += 1
            challengeFeedback = "Correct. Now find the next part."
            if challengeIndex == questions.count { learning.recordActivity("explorer", score: 100) }
        } else {
            challengeFeedback = "Look at what this part does, then try a different part."
        }
    }

    @MainActor
    private static func material(for part: SystemPart, selected: Bool) -> any RealityKit.Material {
        let color = UIColor(hue: part.hue, saturation: selected ? 0.25 : 0.7, brightness: 1, alpha: 1)
        if part.transparent {
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.blending = .transparent(opacity: selected ? 0.4 : 0.16)
            return material
        }
        return SimpleMaterial(color: color, isMetallic: !selected)
    }
    /// Round parts look identical while spinning, so give the crank its throw pin and the flywheel a lug.
    /// Local −Z is world +Y after the 90° tilt, i.e. the top-dead-centre direction.
    @MainActor
    private static func addRotationMarker(to entity: ModelEntity, part: SystemPart) {
        let material = Self.material(for: part, selected: false)
        let marker: ModelEntity
        if part.id == "crank" {
            marker = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [material])
            marker.position = [0, 0, -0.025]
        } else {
            marker = ModelEntity(mesh: .generateBox(width: 0.018, height: 0.04, depth: 0.03, cornerRadius: 0.004), materials: [material])
            marker.position = [0, 0, -0.078]
        }
        marker.name = part.id
        marker.components.set(InputTargetComponent())
        entity.addChild(marker)
    }
    @MainActor
    private static func addTeeth(to entity: ModelEntity, part: SystemPart, count: Int) {
        guard case let .cylinder(height, radius) = part.shape else { return }
        let material = Self.material(for: part, selected: false)
        for index in 0..<count {
            let angle = Float(index) * 2 * .pi / Float(count)
            let tooth = ModelEntity(mesh: .generateBox(width: 0.009, height: height, depth: 0.007), materials: [material])
            tooth.name = part.id
            tooth.position = [radius * cos(angle), 0, radius * sin(angle)]
            tooth.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            tooth.components.set(InputTargetComponent())
            entity.addChild(tooth)
        }
    }
}

/// Drives the per-frame pose of an assembly: slider-crank kinematics for the piston,
/// and a 3:1 counter-rotating pair for the gear train. Positions always include the explosion offset.
@MainActor
final class MechanismDriver {
    var running = false
    var speed: Float = 0.5          // input/crank revolutions per second
    var explode: Float = 0.25
    var angle: Float = 0            // input/crank angle in radians
    var subscription: EventSubscription?
    private var plugLit = false

    // Slider-crank geometry in assembly metres.
    private let crankRadius: Float = 0.025
    private let rodLength: Float = 0.2

    func advance(by dt: Float) {
        guard running else { return }
        angle = (angle + dt * speed * 2 * .pi).truncatingRemainder(dividingBy: 4 * .pi)
    }

    func apply(to root: Entity, system: EngSystem) {
        let tilt = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let spin = { (radians: Float) in simd_quatf(angle: radians, axis: [0, 0, 1]) * tilt }
        let r = crankRadius, l = rodLength, theta = angle
        // Piston travel from top dead centre (≤ 0), and connecting-rod tilt.
        let travel = r * cos(theta) + sqrt(l * l - pow(r * sin(theta), 2)) - l - r
        let rodTilt = asin(r * sin(theta) / l)
        let crankPin = SIMD3<Float>(r * sin(theta), r * cos(theta) - r, 0)

        for part in system.parts {
            guard let entity = root.children.first(where: { $0.name == part.id }) else { continue }
            var position = part.home + explode * part.explode
            var orientation = part.tiltedOnX ? tilt : simd_quatf(angle: 0, axis: [0, 1, 0])
            switch (system.id, part.id) {
            case ("piston", "piston"), ("piston", "pin"):
                position.y += travel
            case ("piston", "rod"):
                position += SIMD3<Float>(crankPin.x / 2, (travel + crankPin.y) / 2, 0)
                orientation = simd_quatf(angle: rodTilt, axis: [0, 0, 1])
            case ("piston", "crank"), ("piston", "flywheel"):
                orientation = spin(-theta)
            case ("piston", "plug"):
                // Fire near top dead centre on every second revolution.
                let lit = running && theta.truncatingRemainder(dividingBy: 4 * .pi) < 0.5
                if lit != plugLit, let model = entity as? ModelEntity {
                    plugLit = lit
                    model.model?.materials = [lit ? UnlitMaterial(color: .systemYellow)
                                                  : SimpleMaterial(color: UIColor(hue: part.hue, saturation: 0.7, brightness: 1, alpha: 1), isMetallic: true)]
                    model.scale = .init(repeating: lit ? 1.25 : 1)
                }
            case ("gears", "in"), ("gears", "g1"):
                orientation = spin(-theta)
            case ("gears", "out"), ("gears", "g2"):
                orientation = spin(theta / 3)
            default:
                break
            }
            entity.position = position
            entity.orientation = orientation
        }
    }
}
