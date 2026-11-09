import SwiftUI
import UniformTypeIdentifiers

struct CADStudioView: View {
    private enum InspectorPage: String, CaseIterable {
        case size = "Size", position = "Position", rotation = "Rotation"
    }
    @Environment(CADModel.self) private var cad
    @Environment(SpaceController.self) private var spaces
    @Environment(LearningStore.self) private var learning
    let toggleSpace: (String) -> Void
    @State private var angle: CADViewAngle = .isometric
    @State private var zoom: Float = 1
    @State private var fitRequest = 0
    @State private var dimensionsVisible = true
    @State private var inspectorPage = InspectorPage.size
    @State private var draftX = ""
    @State private var draftY = ""
    @State private var draftZ = ""
    @State private var draftName = ""
    @State private var draftBore = ""
    @State private var referenceID: UUID?
    @State private var inputMessage: String?
    @State private var designName = ""
    @State private var saveMessage: String?
    @State private var challenge: CADChallenge = .support
    @State private var checkedChallenge: CADChallenge?
    @State private var confirmClear = false
    @State private var pendingTemplate: CADTemplate?
    @State private var pendingDesign: CADSavedDesign?
    @State private var exporting = false
    @State private var exportMessage: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    introduction
                    starterModels
                    if geometry.size.width > 820 {
                        HStack(alignment: .top, spacing: 18) {
                            workplane.frame(maxWidth: .infinity)
                            inspector.frame(width: 310)
                        }
                    } else {
                        workplane
                        inspector
                    }
                    partList
                    designChallenge
                    savedDesigns
                }.padding(24)
            }
        }
        .navigationTitle("CAD studio").toolbarTitleDisplayMode(.inline)
        .onChange(of: cad.selected, initial: true) { _, _ in refreshDrafts() }
        .onChange(of: cad.selectedID) { _, selected in
            if referenceID == selected { referenceID = nil }
        }
        .onChange(of: cad.units) { _, _ in refreshDrafts() }
        .onChange(of: inspectorPage) { _, _ in refreshDrafts() }
        .onChange(of: cad.shapes) { _, shapes in
            checkedChallenge = nil
            if !shapes.contains(where: { $0.id == referenceID && $0.id != cad.selectedID && !$0.isHidden }) { referenceID = nil }
        }
        .confirmationDialog("Clear the unlocked parts?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear unlocked parts", role: .destructive) { cad.clear() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Locked parts stay in the workspace. Undo restores the cleared parts.") }
        .confirmationDialog("Replace this workspace with a starter?", isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }), titleVisibility: .visible) {
            Button("Load starter assembly") {
                if let pendingTemplate { cad.loadTemplate(pendingTemplate); resetView() }
                pendingTemplate = nil
            }
            Button("Cancel", role: .cancel) { pendingTemplate = nil }
        } message: { Text("Your current work is autosaved until you replace it. Save a named snapshot to keep it, or use Undo immediately after loading the starter.") }
        .confirmationDialog("Load this saved design?", isPresented: Binding(get: { pendingDesign != nil }, set: { if !$0 { pendingDesign = nil } }), titleVisibility: .visible) {
            Button("Load design") {
                if let pendingDesign { cad.loadDesign(pendingDesign); resetView() }
                pendingDesign = nil
            }
            Button("Cancel", role: .cancel) { pendingDesign = nil }
        } message: { Text("This replaces the workspace, including locked parts. Undo restores the previous workspace.") }
        .fileExporter(isPresented: $exporting, document: CADOBJDocument(shapes: cad.shapes), contentType: CADOBJDocument.readableContentTypes[0], defaultFilename: "AVPLearn-assembly") { result in
            switch result {
            case .success: exportMessage = "Exported the visible parts as an OBJ mesh. One coordinate unit equals one meter."
            case .failure(let error): exportMessage = "Couldn’t export the model: \(error.localizedDescription)"
            }
        }
        .alert("Model export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudyHeading(eyebrow: "Design with intention", title: "From shapes to assemblies.", subtitle: "Inspect a mechanical starter, change exact dimensions, and learn how parts fit together.")
            HStack {
                Label(cad.coachTip, systemImage: "lightbulb").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Button { toggleSpace("cad") } label: {
                    Label(spaces.active == "cad" ? "Leave space" : "View at life size", systemImage: "visionpro")
                }.disabled(spaces.isTransitioning)
            }
        }
    }

    private var starterModels: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], alignment: .leading, spacing: 16) {
            ForEach(CADTemplate.allCases) { template in
                StudyCard(tint: .teal) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(template.title, systemImage: template == .shaftSupport ? "gearshape.2" : "ruler").font(.headline)
                        Text(template.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        Button("Load starter", systemImage: "cube.transparent") {
                            if cad.shapes.isEmpty { cad.loadTemplate(template); resetView() }
                            else { pendingTemplate = template }
                        }.buttonStyle(.bordered)
                        DisclosureGroup("Try a design investigation") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(template == .shaftSupport
                                     ? "Make the shaft 40 mm in diameter: set Width X and Depth Z to 40 mm, keeping Height Y at 280 mm. Predict the new radial clearance before checking."
                                     : "Keep the base 12 mm thick and make the upright 200 mm tall. What center height will keep the upright resting on the base?")
                                DisclosureGroup("See the reasoning") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(template == .shaftSupport ? "Radial clearance for concentric circular parts" : "Center height above a supporting surface").bold()
                                        Text(template == .shaftSupport
                                             ? "Radial clearance = (bore diameter − shaft diameter) ÷ 2 = (42 − 40) ÷ 2 = 1 mm. The collars stay unchanged."
                                             : "Center height = base thickness + half the upright height = 12 + 200 ÷ 2 = 112 mm. Apply 112 mm to the upright’s Y position.")
                                    }.padding(.top, 8)
                                }
                            }.padding(.top, 8)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var workplane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("3D workplane", systemImage: "square.3.layers.3d").font(.headline)
                Spacer()
                Button("Fit", systemImage: "arrow.up.left.and.arrow.down.right") { resetView() }.font(.caption)
            }
            Picker("Viewing angle", selection: $angle) {
                ForEach(CADViewAngle.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            CADSceneView(immersive: false, angle: angle, zoom: zoom, showDimensions: dimensionsVisible, fitRequest: fitRequest)
                .frame(height: 390)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topLeading) {
                    Text("X: red · Y: green · Z: blue").font(.caption2).foregroundStyle(.secondary)
                        .padding(12).allowsHitTesting(false)
                }
            HStack {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $zoom, in: 0.5...2).accessibilityLabel("View zoom")
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                Toggle("Dimensions", isOn: $dimensionsVisible).toggleStyle(.button).font(.caption)
            }
            HStack(spacing: 8) {
                ForEach(ShapeKind.allCases) { kind in
                    Button { cad.add(kind) } label: {
                        VStack(spacing: 5) {
                            Image(systemName: kind.icon).font(.title3)
                            Text(kind.label).font(.caption2)
                        }.frame(maxWidth: .infinity, minHeight: 45)
                    }.disabled(!cad.canAdd).accessibilityLabel("Add \(kind.label)")
                }
            }
            HStack(spacing: 12) {
                Button { cad.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!cad.canUndo).accessibilityLabel("Undo").keyboardShortcut("z", modifiers: .command)
                Button { cad.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!cad.canRedo).accessibilityLabel("Redo").keyboardShortcut("z", modifiers: [.command, .shift])
                Spacer()
                Button("Export OBJ", systemImage: "square.and.arrow.up") { exporting = true }
                    .disabled(cad.shapes.allSatisfy(\.isHidden)).font(.caption)
                Button("Clear", role: .destructive) { confirmClear = true }
                    .disabled(cad.shapes.allSatisfy(\.isLocked)).font(.caption)
            }
            Text("Select a part to inspect it. Drag unlocked parts to move; use two hands to resize proportionally. Exact entries below let you change one dimension at a time.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var inspector: some View {
        @Bindable var cad = cad
        return VStack(alignment: .leading, spacing: 16) {
            Label("Part inspector", systemImage: "slider.horizontal.3").font(.headline)
            HStack {
                Picker("Display units", selection: $cad.units) {
                    ForEach(CADUnit.allCases) { Text($0.suffix).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("Snap", isOn: $cad.snapEnabled).toggleStyle(.button).font(.caption)
            }
            Picker("Position grid", selection: $cad.gridSpacing) {
                Text("1 mm grid").tag(Float(0.001))
                Text("5 mm grid").tag(Float(0.005))
                Text("1 cm grid").tag(Float(0.01))
                Text("5 cm grid").tag(Float(0.05))
            }.font(.caption)
            if let shape = cad.selected {
                HStack {
                    TextField("Part name", text: $draftName).textFieldStyle(.roundedBorder)
                        .onSubmit(renamePart).accessibilityLabel("Part name")
                    Button(action: renamePart) { Image(systemName: "checkmark") }.accessibilityLabel("Apply part name")
                }
                HStack {
                    Label(shape.kind.label, systemImage: shape.kind.icon).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { cad.toggleVisibility(shape.id) } label: { Image(systemName: shape.isHidden ? "eye.slash" : "eye") }
                        .accessibilityLabel(shape.isHidden ? "Show part" : "Hide part")
                    Button { cad.toggleLock(shape.id) } label: { Image(systemName: shape.isLocked ? "lock.fill" : "lock.open") }
                        .accessibilityLabel(shape.isLocked ? "Unlock part" : "Lock part")
                }
                Picker("Edit part", selection: $inspectorPage) {
                    ForEach(InspectorPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                transformFields(shape)
                    .disabled(shape.isLocked)
                if shape.isLocked {
                    Label("Unlock this part to change its geometry.", systemImage: "lock").font(.caption).foregroundStyle(.orange)
                }
                if let inputMessage { Text(inputMessage).font(.caption).foregroundStyle(.orange) }
                Divider()
                assemblyControls(shape)
                Divider()
                HStack(spacing: 9) {
                    ForEach(CADPalette.names.indices, id: \.self) { index in
                        Button { cad.setColor(index) } label: {
                            Circle().fill(Color(CADPalette.color(index, selected: false))).frame(width: 26, height: 26)
                                .overlay { if shape.colorIndex == index { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.black) } }
                        }.buttonStyle(.plain).accessibilityLabel(CADPalette.names[index])
                    }
                }.disabled(shape.isLocked)
                HStack {
                    Button("Duplicate", systemImage: "plus.square.on.square") { cad.duplicateSelected() }.disabled(!cad.canAdd)
                    Spacer()
                    Button(role: .destructive) { cad.deleteSelected() } label: { Image(systemName: "trash") }
                        .disabled(shape.isLocked).accessibilityLabel("Delete selected part")
                }.font(.caption)
            } else {
                ContentUnavailableView("Choose a part", systemImage: "cursorarrow.rays", description: Text("Add a shape or load a starter assembly, then select a part in 3D or in the parts list."))
            }
        }.padding(20).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private func transformFields(_ shape: CADShape) -> some View {
        let labels = inspectorPage == .size ? ["Width · X", "Height · Y", "Depth · Z"] : ["X", "Y", "Z"]
        let suffix = inspectorPage == .rotation ? "°" : cad.units.suffix
        VStack(alignment: .leading, spacing: 12) {
            if inspectorPage == .size {
                Text("Local dimensions. Position snapping does not round these entries.").font(.caption).foregroundStyle(.secondary)
            } else if inspectorPage == .position {
                Text("World position of the part’s center. The floor keeps the part’s rotated bounding box above the workplane.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Rotations apply around X, then Y, then Z. Angles wrap after one full turn.").font(.caption).foregroundStyle(.secondary)
            }
            CADNumericEntry(label: labels[0], value: $draftX, suffix: suffix)
            CADNumericEntry(label: labels[1], value: $draftY, suffix: suffix)
            CADNumericEntry(label: labels[2], value: $draftZ, suffix: suffix)
            if inspectorPage == .size && shape.kind == .tube {
                CADNumericEntry(label: "Bore ratio", value: $draftBore, suffix: "%")
                Text("The bore is the opening. Its width and depth are this percentage of the outside size.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button("Apply \(inspectorPage.rawValue.lowercased())", systemImage: "checkmark") { applyTransform() }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
    }

    private func assemblyControls(_ shape: CADShape) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assembly tools").font(.subheadline.bold())
            Button("Rest bounds on workplane", systemImage: "arrow.down.to.line") { cad.placeOnPlane() }
                .font(.caption).disabled(shape.isLocked)
            Picker("Reference part", selection: $referenceID) {
                Text("Choose reference part").tag(Optional<UUID>.none)
                ForEach(cad.shapes.filter { $0.id != shape.id && !$0.isHidden }) { reference in
                    Text(reference.name).tag(Optional(reference.id))
                }
            }.font(.caption)
            HStack {
                Text("Align centers").font(.caption)
                Spacer()
                ForEach(0..<3) { axis in
                    Button(["X", "Y", "Z"][axis]) {
                        if let referenceID { cad.alignSelected(to: referenceID, axis: axis) }
                    }.font(.caption).disabled(!canAlign(shape, axis: axis))
                }
            }
            Button("Stack on reference", systemImage: "square.3.layers.3d") {
                if let referenceID { cad.stackSelected(on: referenceID) }
            }.font(.caption).disabled(!canStack(shape))
            Text(referenceID == nil ? "A bounding box encloses a part. Choose a reference to align centers or stack these boxes." : "Stacking centers X/Z and places the rotated bounds on top of the reference. It does not join the solids.")
                .font(.caption2).foregroundStyle(.secondary)
            if let reference = referencePart {
                if reference.position.y < shape.halfHeight - 0.000001 {
                    Text("Y alignment would put this part below the workplane. Move the reference higher, or align X/Z instead.")
                        .font(.caption2).foregroundStyle(.orange)
                }
                if reference.position.y + reference.halfHeight + shape.halfHeight > 1.5 {
                    Text("Stacking would exceed the 1.5 m center-height limit. Lower the reference or reduce the part’s size.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private var referencePart: CADShape? {
        cad.shapes.first { $0.id == referenceID && $0.id != cad.selectedID && !$0.isHidden }
    }
    private func canAlign(_ shape: CADShape, axis: Int) -> Bool {
        guard !shape.isLocked, let reference = referencePart else { return false }
        return axis != 1 || reference.position.y >= shape.halfHeight - 0.000001
    }
    private func canStack(_ shape: CADShape) -> Bool {
        guard !shape.isLocked, let reference = referencePart else { return false }
        return reference.position.y + reference.halfHeight + shape.halfHeight <= 1.5
    }

    private var partList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("Assembly parts", systemImage: "list.bullet.rectangle").font(.headline); Spacer(); Text("\(cad.shapes.count)/80").font(.caption).foregroundStyle(.secondary) }
            if cad.shapes.isEmpty {
                Text("Start from a mechanical assembly above, or add your first shape.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(cad.shapes) { shape in
                HStack(spacing: 14) {
                    Button { cad.select(shape.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: shape.kind.icon).foregroundStyle(Color(CADPalette.color(shape.colorIndex, selected: false))).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(shape.name).font(.subheadline.weight(.semibold))
                                Text(dimensionSummary(shape)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if cad.selectedID == shape.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { cad.toggleVisibility(shape.id) } label: { Image(systemName: shape.isHidden ? "eye.slash" : "eye") }
                        .accessibilityLabel("\(shape.isHidden ? "Show" : "Hide") \(shape.name)")
                    Button { cad.toggleLock(shape.id) } label: { Image(systemName: shape.isLocked ? "lock.fill" : "lock.open") }
                        .accessibilityLabel("\(shape.isLocked ? "Unlock" : "Lock") \(shape.name)")
                }
                .padding(12).background(cad.selectedID == shape.id ? Color.teal.opacity(0.12) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
        }.padding(22).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private var designChallenge: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Build it yourself", systemImage: "target").font(.title3.bold())
            Picker("Design challenge", selection: $challenge) {
                ForEach(CADChallenge.allCases) { Text($0.title).tag($0) }
            }.onChange(of: challenge) { _, _ in checkedChallenge = nil }
            Text(challenge.objective).font(.subheadline)
            if checkedChallenge == challenge {
                let checks = challenge.checks(in: cad.shapes)
                ForEach(checks.indices, id: \.self) { index in
                    Label(checks[index].0, systemImage: checks[index].1 ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline).foregroundStyle(checks[index].1 ? Color.green : .secondary)
                }
            }
            Button("Check my design") {
                checkedChallenge = challenge
                if challenge.checks(in: cad.shapes).allSatisfy({ $0.1 }) { learning.recordActivity("cad", score: 100) }
            }.buttonStyle(.bordered).disabled(cad.shapes.isEmpty)
            Text("A starter helps you inspect an assembly; these challenges ask you to make and check your own parts.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
    }

    private var savedDesigns: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Design library", systemImage: "folder").font(.title3.bold())
            Text("The workspace saves automatically. Keep up to six named snapshots, or export visible parts as a mesh to open in other 3D tools.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                TextField("Design name", text: $designName).textFieldStyle(.roundedBorder)
                Button("Save snapshot") {
                    cad.saveDesign(named: designName)
                    saveMessage = "Saved \(cad.savedDesigns.first?.name ?? "design")."
                    designName = ""
                }.disabled(cad.shapes.isEmpty)
            }
            if let saveMessage { Label(saveMessage, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.teal) }
            ForEach(cad.savedDesigns) { design in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(design.name).font(.subheadline.bold())
                        Text("\(design.shapes.count) parts · \(design.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Load") { pendingDesign = design }.font(.caption)
                    Button(role: .destructive) { cad.deleteDesign(design.id) } label: { Image(systemName: "trash") }.accessibilityLabel("Delete saved design \(design.name)")
                }.padding(.vertical, 5)
            }
        }.padding(22).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func refreshDrafts() {
        inputMessage = nil
        guard let selected = cad.selected else { draftName = ""; draftX = ""; draftY = ""; draftZ = ""; return }
        draftName = selected.name
        let value: SIMD3<Float>
        switch inspectorPage {
        case .size: value = selected.dimensions * cad.units.unitsPerMeter
        case .position: value = selected.position * cad.units.unitsPerMeter
        case .rotation: value = selected.rotationDegrees
        }
        draftX = number(value.x); draftY = number(value.y); draftZ = number(value.z)
        draftBore = number(selected.boreRatio * 100)
    }
    private func applyTransform() {
        guard let selected = cad.selected, !selected.isLocked,
              let x = parsed(draftX), let y = parsed(draftY), let z = parsed(draftZ) else {
            inputMessage = "Enter three valid numbers before applying."; return
        }
        let value = SIMD3<Float>(x, y, z)
        switch inspectorPage {
        case .size:
            let meters = value / cad.units.unitsPerMeter
            guard meters.x >= 0.001, meters.y >= 0.001, meters.z >= 0.001,
                  meters.x <= 1, meters.y <= 1, meters.z <= 1 else {
                inputMessage = "Each dimension must be between 1 mm and 1 m."; return
            }
            if selected.kind == .tube {
                guard let ratio = parsed(draftBore), (10...90).contains(ratio) else { inputMessage = "Use a bore ratio from 10% to 90% so the tube has a positive wall."; return }
                cad.beginEdit(); cad.setDimensions(selected.id, meters); cad.setBoreRatio(selected.id, ratio / 100)
            } else { cad.beginEdit(); cad.setDimensions(selected.id, meters) }
        case .position:
            let meters = value / cad.units.unitsPerMeter
            guard abs(meters.x) <= 0.9, abs(meters.z) <= 0.9, (0...1.5).contains(meters.y) else {
                inputMessage = "Keep X/Z within ±90 cm and the center height between 0 and 150 cm."; return
            }
            cad.beginEdit(); cad.setPosition(selected.id, meters)
        case .rotation:
            cad.beginEdit(); cad.setRotation(selected.id, value)
        }
        refreshDrafts()
    }
    private func renamePart() {
        guard let selected = cad.selected else { return }
        cad.beginEdit(); cad.rename(selected.id, draftName)
        refreshDrafts()
    }
    private func resetView() { angle = .isometric; zoom = 1; fitRequest += 1 }
    private func dimensionSummary(_ shape: CADShape) -> String {
        let d = shape.dimensions * cad.units.unitsPerMeter
        return "\(number(d.x)) × \(number(d.y)) × \(number(d.z)) \(cad.units.suffix)"
    }
    private func number(_ value: Float) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func parsed(_ text: String) -> Float? {
        let locale = Locale.current
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = locale.groupingSeparator, !separator.isEmpty { normalized = normalized.replacingOccurrences(of: separator, with: "") }
        if let separator = locale.decimalSeparator, separator != "." { normalized = normalized.replacingOccurrences(of: separator, with: ".") }
        guard let value = Float(normalized), value.isFinite else { return nil }
        return value
    }
}

private struct CADNumericEntry: View {
    let label: String
    @Binding var value: String
    let suffix: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer(minLength: 8)
            TextField(label, text: $value).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                .frame(width: 105).accessibilityLabel("\(label) in \(suffix)")
            Text(suffix).font(.caption).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
        }
    }
}
