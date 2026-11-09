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
                // A transparent outer cylinder must not intercept taps on every inner part.
                if !part.transparent {
                    entity.components.set(InputTargetComponent())
                    entity.generateCollisionShapes(recursive: true)
                }
                root.addChild(entity)
            }
            content.add(root)
        } update: { content in
            guard let root = content.entities.first(where: { $0.name == "sys-root" }) else { return }
            for part in system.parts {
                guard let entity = root.children.first(where: { $0.name == part.id }) as? ModelEntity else { continue }
                let selected = part.id == selectedID
                entity.position = part.home + explode * part.explode
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
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(system.title).font(.headline)
                Spacer()
                Button {
                    explode = 0
                    selectedID = nil
                } label: { Image(systemName: "arrow.counterclockwise") }
                .accessibilityLabel("Reset assembly view")
            }
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
            Text("Simplified static assembly · illustrative geometry")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(width: 430)
        .padding(20)
        .glassBackgroundEffect()
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
