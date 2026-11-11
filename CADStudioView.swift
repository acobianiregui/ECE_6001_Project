import SwiftUI
import UniformTypeIdentifiers
import simd

/// The CAD workspace: a large 3D viewport with its tools above it, and one side panel that switches
/// between editing the selected part, browsing the assembly, guided challenges, and saved files.
struct CADStudioView: View {
    private enum Panel: String, CaseIterable {
        case edit = "Edit", parts = "Parts", learn = "Learn", files = "Files"
    }
    @Environment(CADModel.self) private var cad
    @Environment(SpaceController.self) private var spaces
    @Environment(LearningStore.self) private var learning
    let toggleSpace: (String) -> Void

    @State private var yaw = CADViewAngle.isometric.yaw
    @State private var pitch = CADViewAngle.isometric.pitch
    @State private var zoom: Float = 1
    @State private var fitRequest = 0
    @State private var dimensionsVisible = true
    @State private var panel = Panel.edit
    @State private var addingPart = false
    @State private var choosingStarter = false

    // Text being typed in the inspector. Nothing changes in the model until it is applied.
    @State private var draftName = ""
    @State private var draftSize = ["", "", ""]
    @State private var draftPlace = ["", "", ""]
    @State private var draftTurn = ["", "", ""]
    @State private var draftFeature = ""
    @State private var inputMessage: String?
    @State private var referenceID: UUID?

    @State private var challenge: CADChallenge = .support
    @State private var designName = ""
    @State private var saveMessage: String?
    @State private var confirmClear = false
    @State private var pendingTemplate: CADTemplate?
    @State private var pendingDesign: CADSavedDesign?
    @State private var exporting = false
    @State private var exportMessage: String?
    /// Mesh volume in cubic meters, by mesh key. Filled in the background for the mass readouts.
    @State private var volumes: [String: Float] = [:]

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 12) {
                        toolbar
                        viewport.frame(maxHeight: .infinity)
                        challengeStrip
                    }
                    sidePanel.frame(width: 330)
                }
                .padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        toolbar
                        viewport.frame(height: 400)
                        challengeStrip
                        sidePanel.frame(height: 640)
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("CAD studio").toolbarTitleDisplayMode(.inline)
        .onChange(of: cad.selected, initial: true) { _, _ in refreshDrafts() }
        .onChange(of: cad.selectedID) { _, selected in
            if referenceID == selected { referenceID = nil }
            // Picking a part in the 3D view brings up its editor, unless a challenge is being read.
            if selected != nil, panel != .learn { panel = .edit }
        }
        .onChange(of: cad.units) { _, _ in refreshDrafts() }
        .onChange(of: cad.shapes) { _, shapes in
            if !shapes.contains(where: { $0.id == referenceID && $0.id != cad.selectedID && !$0.isHidden }) { referenceID = nil }
        }
        .onChange(of: challengeComplete) { _, complete in
            if complete { learning.recordActivity("cad", score: 100) }
        }
        .task(id: cad.shapes.map(CADMeshLibrary.key)) { await measureVolumes() }
        .sheet(isPresented: $choosingStarter) { starterSheet }
        .confirmationDialog("Clear the unlocked parts?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear unlocked parts", role: .destructive) { cad.clear() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Locked parts stay in the workspace. Undo restores the cleared parts.") }
        .confirmationDialog("Replace this workspace with a starter?", isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }), titleVisibility: .visible) {
            Button("Open starter assembly") {
                if let pendingTemplate { open(pendingTemplate) }
                pendingTemplate = nil
            }
            Button("Cancel", role: .cancel) { pendingTemplate = nil }
        } message: { Text("Your current parts are replaced. Save a snapshot in Files to keep them, or use Undo straight after opening the starter.") }
        .confirmationDialog("Load this saved design?", isPresented: Binding(get: { pendingDesign != nil }, set: { if !$0 { pendingDesign = nil } }), titleVisibility: .visible) {
            Button("Load design") {
                if let pendingDesign { cad.loadDesign(pendingDesign); resetView() }
                pendingDesign = nil
            }
            Button("Cancel", role: .cancel) { pendingDesign = nil }
        } message: { Text("This replaces the workspace, including locked parts. Undo restores the previous workspace.") }
        .fileExporter(isPresented: $exporting, document: CADOBJDocument(shapes: exporting ? cad.shapes : []), contentType: CADOBJDocument.readableContentTypes[0], defaultFilename: "AVPLearn-assembly") { result in
            switch result {
            case .success: exportMessage = "Exported the visible parts as an OBJ mesh. One coordinate unit equals one meter."
            case .failure(let error): exportMessage = "Couldn’t export the model: \(error.localizedDescription)"
            }
        }
        .alert("Model export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }

    // MARK: Toolbar and viewport

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button { addingPart = true } label: { Label("Add part", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .disabled(!cad.canAdd)
                .popover(isPresented: $addingPart, arrowEdge: .top) { partPalette }
            Button { choosingStarter = true } label: { Label("Starters", systemImage: "shippingbox") }
            Spacer(minLength: 4)
            Button { cad.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!cad.canUndo).accessibilityLabel("Undo").keyboardShortcut("z", modifiers: .command)
            Button { cad.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!cad.canRedo).accessibilityLabel("Redo").keyboardShortcut("z", modifiers: [.command, .shift])
            Toggle(isOn: $dimensionsVisible) { Image(systemName: "ruler") }
                .toggleStyle(.button).accessibilityLabel("Show dimensions of the selected part")
            Button { toggleSpace("cad") } label: {
                Label(spaces.active == "cad" ? "Leave space" : "Life size", systemImage: "visionpro")
            }
            .disabled(spaces.isTransitioning)
        }
        .controlSize(.small)
    }

    private var viewport: some View {
        CADSceneView(immersive: false, yaw: yaw, pitch: pitch, zoom: zoom, showDimensions: dimensionsVisible, fitRequest: fitRequest)
            .frame(maxWidth: .infinity, minHeight: 260)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 22))
            .overlay(alignment: .topLeading) { viewButtons.padding(12) }
            .overlay(alignment: .bottomTrailing) { viewControls.padding(12) }
            .overlay { if cad.shapes.isEmpty { emptyWorkplane } }
    }

    private var viewButtons: some View {
        HStack(spacing: 4) {
            ForEach(CADViewAngle.allCases) { preset in
                let active = abs(yaw - preset.yaw) < 0.01 && abs(pitch - preset.pitch) < 0.01
                Button(preset.title) { yaw = preset.yaw; pitch = preset.pitch }
                    .buttonStyle(.plain)
                    .font(.caption.weight(active ? .bold : .regular))
                    .foregroundStyle(active ? LearningStyle.teal : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(active ? LearningStyle.teal.opacity(0.16) : .clear, in: Capsule())
                    .contentShape(Capsule()).hoverEffect()
                    .accessibilityLabel("\(preset == .isometric ? "Three-quarter" : preset.title) view")
                    .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(4).background(.ultraThinMaterial, in: Capsule())
    }

    private var viewControls: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(spacing: 6) {
                Button { zoom = min(3, zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("Zoom in")
                Button { zoom = max(0.4, zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("Zoom out")
                Button { resetView() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.accessibilityLabel("Fit the design in view")
            }
            .buttonBorderShape(.circle).controlSize(.small)
            CADOrbitPad(yaw: $yaw, pitch: $pitch)
        }
    }

    private var emptyWorkplane: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.transparent").font(.system(size: 40, weight: .light)).foregroundStyle(LearningStyle.teal)
            Text("The workplane is empty").font(.title3.bold())
            Text("Open a real assembly to take apart and measure, or start from a single part.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button { choosingStarter = true } label: { Label("Open a starter", systemImage: "shippingbox") }
                    .buttonStyle(.borderedProminent)
                Button { addingPart = true } label: { Label("Add a part", systemImage: "plus") }
            }
        }
        .padding(26).frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: Adding parts and opening starters

    private static let prototypes: [CADShape] = ShapeKind.allCases.enumerated().map { index, kind in
        CADShape(id: UUID(uuidString: String(format: "60020000-0000-0000-0000-%012d", index))!, kind: kind, position: .zero,
                 colorIndex: kind.isMachinePart ? CADPalette.steel : 0, dimensions: kind.defaultDimensions)
    }

    private var partPalette: some View {
        VStack(alignment: .leading, spacing: 14) {
            paletteGroup("Solids", detail: "Plain building blocks", kinds: ShapeKind.allCases.filter { !$0.isMachinePart })
            paletteGroup("Machine parts", detail: "Real components with holes, teeth and threads", kinds: ShapeKind.allCases.filter(\.isMachinePart))
        }
        .padding(20).frame(width: 520)
    }

    private func paletteGroup(_ title: String, detail: String, kinds: [ShapeKind]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(kinds) { kind in
                    Button {
                        cad.add(kind)
                        addingPart = false
                        panel = .edit
                    } label: {
                        HStack(spacing: 8) {
                            CADPreviewImage(shapes: [Self.prototypes[ShapeKind.allCases.firstIndex(of: kind) ?? 0]], pixels: 120)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.label).font(.subheadline.weight(.semibold))
                                Text(kind.role).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14)).hoverEffect()
                    }
                    .buttonStyle(.plain).accessibilityLabel("Add \(kind.label). \(kind.role)")
                }
            }
        }
    }

    private var starterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Each starter is a real mechanism built from catalog parts at true size. Open one, take it apart, measure it, and change it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(CADTemplate.allCases) { template in starterCard(template) }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Starter assemblies")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { choosingStarter = false } } }
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 600, idealHeight: 720)
    }

    private func starterCard(_ template: CADTemplate) -> some View {
        let shapes = template.shapes
        return StudyCard(tint: .teal) {
            VStack(alignment: .leading, spacing: 10) {
                CADPreviewImage(shapes: shapes, pixels: 520)
                    .frame(height: 170)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
                Text(template.title).font(.headline)
                Text(template.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Label(template.concept, systemImage: "lightbulb").font(.caption2.weight(.semibold)).foregroundStyle(LearningStyle.teal)
                    Spacer()
                    Text("\(shapes.count) parts").font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    choosingStarter = false
                    if cad.shapes.isEmpty { open(template) } else { pendingTemplate = template }
                } label: { Label("Open", systemImage: "arrow.right.circle") }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func open(_ template: CADTemplate) {
        cad.loadTemplate(template)
        cad.select(nil)
        resetView()
        panel = .parts
    }

    // MARK: Challenge strip

    private var challengeChecks: [(String, Bool)] { challenge.checks(in: cad.shapes) }
    private var challengeComplete: Bool { challengeChecks.allSatisfy { $0.1 } }

    private var challengeStrip: some View {
        let checks = challengeChecks
        let done = checks.filter(\.1).count
        return Button { panel = .learn } label: {
            HStack(spacing: 12) {
                Image(systemName: done == checks.count ? "checkmark.seal.fill" : "target")
                    .font(.title3).foregroundStyle(done == checks.count ? .green : LearningStyle.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Challenge \(challenge.title)").font(.subheadline.weight(.semibold))
                    HStack(spacing: 10) {
                        ForEach(checks.indices, id: \.self) { index in
                            Image(systemName: checks[index].1 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checks[index].1 ? Color.green : .secondary)
                        }
                        Text(done == checks.count ? "Complete. Choose the next one in Learn." : "\(done) of \(checks.count) checks pass")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18)).hoverEffect()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Challenge \(challenge.title). \(done) of \(checks.count) checks pass. Opens the Learn panel.")
    }

    // MARK: Side panel

    private var sidePanel: some View {
        VStack(spacing: 12) {
            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch panel {
                    case .edit: editPanel
                    case .parts: partsPanel
                    case .learn: learnPanel
                    case .files: filesPanel
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func sectionTitle(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.bold())
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }

    // MARK: Edit panel

    @ViewBuilder private var editPanel: some View {
        Label(cad.coachTip, systemImage: "lightbulb").font(.caption).foregroundStyle(.secondary)
        if let shape = cad.selected {
            partHeader(shape)
            Group {
                sizeSection(shape)
                placeSection(shape)
                turnSection(shape)
                if let inputMessage { Label(inputMessage, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                Button { applyEdits() } label: { Label("Apply changes", systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(!hasEdits(shape))
            }
            .disabled(shape.isLocked)
            if shape.isLocked {
                Label("Unlock this part to change it.", systemImage: "lock").font(.caption).foregroundStyle(.orange)
            }
            Divider()
            finishSection(shape)
            Divider()
            assemblySection(shape)
            Divider()
            HStack {
                Button("Duplicate", systemImage: "plus.square.on.square") { cad.duplicateSelected() }.disabled(!cad.canAdd)
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) { cad.deleteSelected() }.disabled(shape.isLocked)
            }
            .controlSize(.small)
        } else {
            ContentUnavailableView("No part selected", systemImage: "cursorarrow.rays",
                                   description: Text(cad.shapes.isEmpty ? "Add a part or open a starter to begin." : "Tap a part in the 3D view, or pick one in Parts."))
        }
        Divider()
        workspaceSettings
    }

    private func partHeader(_ shape: CADShape) -> some View {
        var picture = shape
        picture.id = Self.prototypes[0].id
        picture.position = .zero
        picture.isHidden = false
        return HStack(spacing: 10) {
            CADPreviewImage(shapes: [picture], pixels: 160).frame(width: 54, height: 54)
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                TextField("Part name", text: $draftName).textFieldStyle(.roundedBorder)
                    .onSubmit(renamePart).accessibilityLabel("Part name")
                Text("\(shape.kind.label) · \(shape.kind.role)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            VStack(spacing: 6) {
                Button { cad.toggleVisibility(shape.id) } label: { Image(systemName: shape.isHidden ? "eye.slash" : "eye") }
                    .accessibilityLabel(shape.isHidden ? "Show part" : "Hide part")
                Button { cad.toggleLock(shape.id) } label: { Image(systemName: shape.isLocked ? "lock.fill" : "lock.open") }
                    .accessibilityLabel(shape.isLocked ? "Unlock part" : "Lock part")
            }
            .buttonBorderShape(.circle).controlSize(.mini)
        }
    }

    private func sizeSection(_ shape: CADShape) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Size", detail: cad.units.suffix)
            CADAxisFields(captions: ["Width X", "Height Y", "Depth Z"], values: $draftSize, onSubmit: applyEdits)
            if let label = shape.kind.featureLabel {
                HStack {
                    Text(label).font(.caption)
                    Spacer()
                    TextField(label, text: $draftFeature).textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .frame(width: 96).onSubmit(applyEdits)
                        .accessibilityLabel("\(label) in \(cad.units.suffix)")
                    Text(cad.units.suffix).font(.caption).foregroundStyle(.secondary)
                }
            }
            if shape.kind == .gear {
                Stepper(value: Binding(get: { shape.teeth }, set: { cad.beginEdit(); cad.setTeeth(shape.id, $0) }), in: 8...60) {
                    Text("Teeth: \(shape.teeth)").font(.caption)
                }
            }
            ForEach(featureNotes(shape), id: \.self) { note in
                Label(note, systemImage: "info.circle").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Derived dimensions a learner needs to place mating parts: where the holes are, how tall a bolt head is.
    private func featureNotes(_ shape: CADShape) -> [String] {
        func length(_ meters: Float) -> String { "\(number(meters * cad.units.unitsPerMeter)) \(cad.units.suffix)" }
        switch shape.kind {
        case .gear:
            guard let module = shape.gearModule, let pitch = shape.pitchDiameter else { return [] }
            return ["Module \(length(module)) = outside ⌀ ÷ (teeth + 2). Meshing gears share a module.",
                    "Pitch ⌀ \(length(pitch)). Mesh distance = half the sum of two pitch diameters."]
        case .plate:
            return ["Four holes, centered \(length(shape.plateHoleInset)) in from each edge."]
        case .hexBolt:
            return ["Head is \(length(shape.boltHeadHeight)) tall; the shank below it is \(length(shape.dimensions.y - shape.boltHeadHeight)) long."]
        case .hexNut:
            return ["Across flats \(length(2 * shape.hexFlatRadius)): the wrench size."]
        case .bearingBlock:
            return ["Bore axis runs along Z, \(length(shape.dimensions.y / 2 + shape.blockBoreCenterY)) above the base.",
                    "Feet are \(length(shape.blockFootThickness)) thick."]
        case .tube:
            guard let bore = shape.featureDiameter else { return [] }
            return ["Wall \(length((shape.dimensions.x - bore) / 2)) thick."]
        case .box, .sphere, .cylinder, .cone, .wedge:
            return []
        }
    }

    private func placeSection(_ shape: CADShape) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Position of center", detail: cad.units.suffix)
            CADAxisFields(captions: ["X", "Y (up)", "Z"], values: $draftPlace, onSubmit: applyEdits)
            Button("Rest on workplane", systemImage: "arrow.down.to.line") { cad.placeOnPlane() }
                .controlSize(.small)
        }
    }

    private func turnSection(_ shape: CADShape) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Rotation", detail: "degrees")
            CADAxisFields(captions: ["about X", "about Y", "about Z"], values: $draftTurn, onSubmit: applyEdits)
            HStack(spacing: 6) {
                Text("Quarter turn").font(.caption).foregroundStyle(.secondary)
                Spacer()
                ForEach(0..<3) { axis in
                    Button(["X", "Y", "Z"][axis]) {
                        var degrees = shape.rotationDegrees
                        degrees[axis] += 90
                        cad.beginEdit(); cad.setRotation(shape.id, degrees)
                    }
                    .accessibilityLabel("Turn 90 degrees about \(["X", "Y", "Z"][axis])")
                }
            }
            .controlSize(.small)
        }
    }

    private func finishSection(_ shape: CADShape) -> some View {
        let finish = CADPalette.finish(shape.colorIndex)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Finish", detail: finish.material)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 8) {
                ForEach(CADPalette.finishes.indices, id: \.self) { index in
                    Button { cad.setColor(index) } label: {
                        Circle().fill(Color(CADPalette.color(index, selected: false))).frame(width: 30, height: 30)
                            .overlay { if CADPalette.finishes[index].isMetal { Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear, .black.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)) } }
                            .overlay { Circle().strokeBorder(.white.opacity(shape.colorIndex == index ? 0.95 : 0.15), lineWidth: shape.colorIndex == index ? 3 : 1) }
                            .frame(maxWidth: .infinity).contentShape(Circle()).hoverEffect()
                    }
                    .buttonStyle(.plain).accessibilityLabel(CADPalette.finishes[index].name)
                    .accessibilityAddTraits(shape.colorIndex == index ? .isSelected : [])
                }
            }
            .disabled(shape.isLocked)
            if let volume = volumes[CADMeshLibrary.key(shape)] {
                let cubicCentimeters = volume * 1_000_000
                Label("Volume \(number(cubicCentimeters)) cm³ · about \(mass(cubicCentimeters * finish.density)) in \(finish.material.lowercased())",
                      systemImage: "scalemass")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func assemblySection(_ shape: CADShape) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Assemble")
            Picker("Reference part", selection: $referenceID) {
                Text("Choose a reference part").tag(Optional<UUID>.none)
                ForEach(cad.shapes.filter { $0.id != shape.id && !$0.isHidden }) { reference in
                    Text(reference.name).tag(Optional(reference.id))
                }
            }
            .font(.caption)
            HStack(spacing: 6) {
                Text("Align centers").font(.caption)
                Spacer()
                ForEach(0..<3) { axis in
                    Button(["X", "Y", "Z"][axis]) {
                        if let referenceID { cad.alignSelected(to: referenceID, axis: axis) }
                    }
                    .disabled(!canAlign(shape, axis: axis))
                    .accessibilityLabel("Align \(["X", "Y", "Z"][axis]) center to the reference")
                }
            }
            .controlSize(.small)
            Button("Stack on reference", systemImage: "square.3.layers.3d") {
                if let referenceID { cad.stackSelected(on: referenceID) }
            }
            .controlSize(.small).disabled(!canStack(shape))
            Text(referenceID == nil ? "Pick another part to line this one up with it or sit it on top." : "Stacking centers this part over the reference and rests it on top. The parts are not joined: move one and the other stays.")
                .font(.caption2).foregroundStyle(.secondary)
            if let reference = referencePart {
                if reference.position.y < shape.halfHeight - 0.000001 {
                    Text("Aligning Y would push this part below the workplane. Align X or Z instead.")
                        .font(.caption2).foregroundStyle(.orange)
                }
                if reference.position.y + reference.halfHeight + shape.halfHeight > 1.5 {
                    Text("Stacking would pass the 1.5 m height limit.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
    }

    private var workspaceSettings: some View {
        @Bindable var cad = cad
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Units and grid")
            HStack {
                Picker("Display units", selection: $cad.units) {
                    ForEach(CADUnit.allCases) { Text($0.suffix).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Snap", isOn: $cad.snapEnabled).toggleStyle(.button).controlSize(.small)
            }
            Picker("Snap positions to", selection: $cad.gridSpacing) {
                Text("1 mm grid").tag(Float(0.001))
                Text("5 mm grid").tag(Float(0.005))
                Text("1 cm grid").tag(Float(0.01))
                Text("5 cm grid").tag(Float(0.05))
            }
            .font(.caption).disabled(!cad.snapEnabled)
            Text("Snap rounds positions to the grid. Sizes are never rounded.").font(.caption2).foregroundStyle(.secondary)
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

    // MARK: Parts panel

    @ViewBuilder private var partsPanel: some View {
        sectionTitle("Assembly", detail: "\(cad.shapes.count) of 80 parts")
        if cad.shapes.isEmpty {
            Text("Nothing here yet. Add a part or open a starter assembly.").font(.caption).foregroundStyle(.secondary)
        } else {
            assemblySummary
        }
        ForEach(cad.shapes) { shape in
            HStack(spacing: 8) {
                Button {
                    cad.select(shape.id)
                    panel = .edit
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: shape.kind.icon)
                            .foregroundStyle(Color(CADPalette.color(shape.colorIndex, selected: false))).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shape.name).font(.caption.weight(.semibold)).lineLimit(1)
                            Text(dimensionSummary(shape)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(shape.isHidden ? 0.45 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(shape.name)")
                .accessibilityAddTraits(cad.selectedID == shape.id ? .isSelected : [])
                Button { cad.toggleVisibility(shape.id) } label: { Image(systemName: shape.isHidden ? "eye.slash" : "eye") }
                    .accessibilityLabel("\(shape.isHidden ? "Show" : "Hide") \(shape.name)")
                Button { cad.toggleLock(shape.id) } label: { Image(systemName: shape.isLocked ? "lock.fill" : "lock.open") }
                    .accessibilityLabel("\(shape.isLocked ? "Unlock" : "Lock") \(shape.name)")
            }
            .buttonBorderShape(.circle).controlSize(.mini)
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(cad.selectedID == shape.id ? LearningStyle.teal.opacity(0.16) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
        if !cad.shapes.isEmpty {
            Text("Tap a part to edit it. Hide the parts in front to see inside an assembly.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var assemblySummary: some View {
        let visible = cad.shapes.filter { !$0.isHidden }
        let bounds = CADSceneView.bounds(of: visible)
        let extent = (bounds.max - bounds.min) * cad.units.unitsPerMeter
        let grams = visible.reduce(Float(0)) { total, shape in
            total + (volumes[CADMeshLibrary.key(shape)] ?? 0) * 1_000_000 * CADPalette.finish(shape.colorIndex).density
        }
        return VStack(alignment: .leading, spacing: 4) {
            if !visible.isEmpty {
                Label("\(number(extent.x)) × \(number(extent.y)) × \(number(extent.z)) \(cad.units.suffix) overall", systemImage: "ruler")
                if grams > 0 { Label("About \(mass(grams)) in the chosen materials", systemImage: "scalemass") }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Learn panel

    @ViewBuilder private var learnPanel: some View {
        sectionTitle("Build it yourself", detail: "\(CADChallenge.allCases.filter { $0.checks(in: cad.shapes).allSatisfy(\.1) }.count) of \(CADChallenge.allCases.count) done")
        Text("Checks update as you build. Nothing to submit.").font(.caption2).foregroundStyle(.secondary)
        ForEach(CADChallenge.allCases) { item in
            let checks = item.checks(in: cad.shapes)
            let complete = checks.allSatisfy(\.1)
            VStack(alignment: .leading, spacing: 8) {
                Button { challenge = item } label: {
                    HStack {
                        Image(systemName: complete ? "checkmark.circle.fill" : (challenge == item ? "target" : "circle"))
                            .foregroundStyle(complete ? Color.green : (challenge == item ? LearningStyle.teal : .secondary))
                        Text(item.title).font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(challenge == item ? .isSelected : [])
                if challenge == item {
                    Text(item.objective).font(.caption).fixedSize(horizontal: false, vertical: true)
                    ForEach(checks.indices, id: \.self) { index in
                        Label(checks[index].0, systemImage: checks[index].1 ? "checkmark.circle.fill" : "circle")
                            .font(.caption2).foregroundStyle(checks[index].1 ? Color.green : .secondary)
                    }
                    DisclosureGroup("Show a hint") {
                        Text(item.hint).font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    .font(.caption)
                }
            }
            .padding(10)
            .background(challenge == item ? LearningStyle.teal.opacity(0.1) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
        Divider()
        sectionTitle("Investigate a starter")
        Text("Open a starter, predict the answer, then change the model to test it.").font(.caption2).foregroundStyle(.secondary)
        ForEach(CADTemplate.allCases) { template in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(template.investigation)
                    DisclosureGroup("See the reasoning") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.reasoningTitle).bold()
                            Text(template.reasoning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    Button("Open this starter", systemImage: "shippingbox") {
                        if cad.shapes.isEmpty { open(template) } else { pendingTemplate = template }
                    }
                    .controlSize(.small)
                }
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            } label: {
                Label(template.title, systemImage: template.icon).font(.caption.weight(.semibold))
            }
        }
    }

    // MARK: Files panel

    @ViewBuilder private var filesPanel: some View {
        sectionTitle("Snapshots", detail: "\(cad.savedDesigns.count) of 6")
        Text("Your workspace saves itself. A snapshot is a named copy you can come back to.").font(.caption2).foregroundStyle(.secondary)
        HStack {
            TextField("Snapshot name", text: $designName).textFieldStyle(.roundedBorder)
            Button("Save") {
                cad.saveDesign(named: designName)
                saveMessage = "Saved \(cad.savedDesigns.first?.name ?? "design")."
                designName = ""
            }
            .disabled(cad.shapes.isEmpty)
        }
        if let saveMessage { Label(saveMessage, systemImage: "checkmark.circle").font(.caption2).foregroundStyle(LearningStyle.teal) }
        ForEach(cad.savedDesigns) { design in
            HStack(spacing: 10) {
                CADPreviewImage(shapes: design.shapes, pixels: 140).frame(width: 46, height: 46)
                    .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(design.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Text("\(design.shapes.count) parts · \(design.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Load") { pendingDesign = design }
                Button(role: .destructive) { cad.deleteDesign(design.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete saved design \(design.name)")
            }
            .controlSize(.mini)
        }
        Divider()
        sectionTitle("Share and reset")
        Button("Export visible parts as OBJ", systemImage: "square.and.arrow.up") { exporting = true }
            .controlSize(.small).disabled(cad.shapes.allSatisfy(\.isHidden))
        Text("OBJ is a triangle mesh in meters that other 3D tools can open.").font(.caption2).foregroundStyle(.secondary)
        Button("Clear unlocked parts", systemImage: "trash", role: .destructive) { confirmClear = true }
            .controlSize(.small).disabled(cad.shapes.allSatisfy(\.isLocked))
    }

    // MARK: Editing

    private struct Drafts: Equatable {
        var size: [String], place: [String], turn: [String], feature: String
    }
    private func current(_ shape: CADShape) -> Drafts {
        func strings(_ value: SIMD3<Float>) -> [String] { [number(value.x), number(value.y), number(value.z)] }
        return Drafts(size: strings(shape.dimensions * cad.units.unitsPerMeter),
                      place: strings(shape.position * cad.units.unitsPerMeter),
                      turn: strings(shape.rotationDegrees),
                      feature: shape.featureDiameter.map { number($0 * cad.units.unitsPerMeter) } ?? "")
    }
    private func hasEdits(_ shape: CADShape) -> Bool {
        current(shape) != Drafts(size: draftSize, place: draftPlace, turn: draftTurn, feature: draftFeature)
    }
    private func refreshDrafts() {
        inputMessage = nil
        guard let selected = cad.selected else {
            draftName = ""; draftSize = ["", "", ""]; draftPlace = ["", "", ""]; draftTurn = ["", "", ""]; draftFeature = ""
            return
        }
        let values = current(selected)
        draftName = selected.name
        draftSize = values.size; draftPlace = values.place; draftTurn = values.turn; draftFeature = values.feature
    }

    /// Applies only the groups whose text changed, as one undo step. Untouched groups are left exactly as they are,
    /// so resizing a part never nudges its position onto the snap grid.
    private func applyEdits() {
        guard let shape = cad.selected, !shape.isLocked else { return }
        let before = current(shape)
        func vector(_ texts: [String]) -> SIMD3<Float>? {
            guard let x = parsed(texts[0]), let y = parsed(texts[1]), let z = parsed(texts[2]) else { return nil }
            return [x, y, z]
        }
        var size: SIMD3<Float>?, place: SIMD3<Float>?, turn: SIMD3<Float>?, ratio: Float?
        if draftSize != before.size {
            guard let value = vector(draftSize) else { inputMessage = "Enter a number for each size."; return }
            let meters = value / cad.units.unitsPerMeter
            guard meters.min() >= 0.001, meters.max() <= 1 else { inputMessage = "Each size must be between 1 mm and 1 m."; return }
            size = meters
        }
        if draftPlace != before.place {
            guard let value = vector(draftPlace) else { inputMessage = "Enter a number for each position."; return }
            let meters = value / cad.units.unitsPerMeter
            guard abs(meters.x) <= 0.9, abs(meters.z) <= 0.9, (0...1.5).contains(meters.y) else {
                inputMessage = "Keep X and Z within ±90 cm, and Y between 0 and 150 cm."; return
            }
            place = meters
        }
        if draftTurn != before.turn {
            guard let value = vector(draftTurn) else { inputMessage = "Enter a number for each rotation."; return }
            turn = value
        }
        if draftFeature != before.feature, let label = shape.kind.featureLabel {
            var resized = shape
            if let size { resized.dimensions = size }
            guard let value = parsed(draftFeature), let full = resized.featureFullDiameter else { inputMessage = "Enter a number for \(label)."; return }
            let wanted = value / cad.units.unitsPerMeter / full
            guard wanted >= 0.0999, wanted <= 0.9001 else {
                inputMessage = "\(label) must be between \(number(0.1 * full * cad.units.unitsPerMeter)) and \(number(0.9 * full * cad.units.unitsPerMeter)) \(cad.units.suffix) for a part this size."
                return
            }
            ratio = wanted
        }
        guard size != nil || place != nil || turn != nil || ratio != nil else { return }
        cad.beginEdit()
        if let size { cad.setDimensions(shape.id, size) }
        if let ratio { cad.setBoreRatio(shape.id, ratio) }
        if let turn { cad.setRotation(shape.id, turn) }
        if let place { cad.setPosition(shape.id, place) }
        refreshDrafts()
        // Say so when the model could not take the position as typed, instead of silently changing it.
        if let place, let result = cad.selected?.position, simd_reduce_max(simd_abs(result - place)) > 0.00001 {
            if result.y > place.y + 0.00001, abs(result.x - place.x) < 0.00001, abs(result.z - place.z) < 0.00001 {
                inputMessage = "The workplane is solid: the part was lifted so its lowest point sits at Y = 0."
            } else {
                inputMessage = "Snap rounded the position to the \(number(cad.gridSpacing * 1000)) mm grid. Turn Snap off or choose a finer grid for exact values."
            }
        }
    }
    private func renamePart() {
        guard let selected = cad.selected else { return }
        cad.beginEdit(); cad.rename(selected.id, draftName)
        refreshDrafts()
    }
    private func resetView() {
        yaw = CADViewAngle.isometric.yaw; pitch = CADViewAngle.isometric.pitch
        zoom = 1; fitRequest += 1
    }
    private func measureVolumes() async {
        let shapes = cad.shapes, known = volumes
        volumes = await Task.detached(priority: .utility) {
            var result: [String: Float] = [:]
            for shape in shapes {
                let key = CADMeshLibrary.key(shape)
                result[key] = known[key] ?? CADMeshLibrary.geometry(for: shape).volume
            }
            return result
        }.value
    }

    // MARK: Formatting

    private func dimensionSummary(_ shape: CADShape) -> String {
        let d = shape.dimensions * cad.units.unitsPerMeter
        return "\(number(d.x)) × \(number(d.y)) × \(number(d.z)) \(cad.units.suffix)"
    }
    private func number(_ value: Float) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func mass(_ grams: Float) -> String {
        grams >= 1000 ? "\(number(grams / 1000)) kg" : "\(number(grams)) g"
    }
    private func parsed(_ text: String) -> Float? {
        let locale = Locale.current
        var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = locale.groupingSeparator, !separator.isEmpty { normalized = normalized.replacingOccurrences(of: separator, with: "") }
        if let separator = locale.decimalSeparator, separator != "." { normalized = normalized.replacingOccurrences(of: separator, with: ".") }
        guard let value = Float(normalized), value.isFinite else { return nil }
        return value
    }
}

/// Three number fields in a row, tinted to match the red, green and blue axes drawn in the viewport.
private struct CADAxisFields: View {
    let captions: [String]
    @Binding var values: [String]
    let onSubmit: () -> Void
    private static let tints: [Color] = [.red, .green, .blue]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                VStack(alignment: .leading, spacing: 3) {
                    Text(captions[index]).font(.caption2.weight(.semibold)).foregroundStyle(Self.tints[index])
                    TextField(captions[index], text: $values[index])
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing)
                        .onSubmit(onSubmit)
                        .accessibilityLabel(captions[index])
                }
            }
        }
    }
}

/// A small view compass. Dragging it orbits the model; the three arms show where X, Y and Z point right now.
struct CADOrbitPad: View {
    @Binding var yaw: Float
    @Binding var pitch: Float
    @State private var start: (yaw: Float, pitch: Float)?

    var body: some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let reach = min(size.width, size.height) * 0.34
                let rotation = CADViewAngle.rotation(yaw: yaw, pitch: pitch)
                let axes: [(SIMD3<Float>, Color, String)] = [([1, 0, 0], .red, "X"), ([0, 1, 0], .green, "Y"), ([0, 0, 1], .blue, "Z")]
                // Draw the arm pointing away first, so the nearest one sits on top.
                for (axis, color, name) in axes.map({ (rotation.act($0.0), $0.1, $0.2) }).sorted(by: { $0.0.z < $1.0.z }) {
                    let tip = CGPoint(x: center.x + CGFloat(axis.x) * reach, y: center.y - CGFloat(axis.y) * reach)
                    var arm = Path()
                    arm.move(to: center)
                    arm.addLine(to: tip)
                    context.stroke(arm, with: .color(color.opacity(axis.z < -0.2 ? 0.55 : 1)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    context.draw(Text(name).font(.caption2.bold()).foregroundStyle(color),
                                 at: CGPoint(x: tip.x + CGFloat(axis.x) * 9, y: tip.y - CGFloat(axis.y) * 9))
                }
                context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(.white))
            }
            .frame(width: 92, height: 92)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.22)))
            .contentShape(Circle())
            .hoverEffect()
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let origin = start ?? (yaw, pitch)
                        start = origin
                        yaw = origin.yaw + Float(value.translation.width) * 0.012
                        pitch = min(.pi / 2, max(-.pi / 6, origin.pitch + Float(value.translation.height) * 0.012))
                    }
                    .onEnded { _ in start = nil }
            )
            Text("Drag to orbit").font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Orbit the view")
        .accessibilityValue("Turned \(Int(yaw * 180 / .pi)) degrees, tilted \(Int(pitch * 180 / .pi)) degrees")
        .accessibilityAdjustableAction { direction in
            yaw += (direction == .increment ? 1 : -1) * .pi / 12
        }
    }
}
