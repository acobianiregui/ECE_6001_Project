import SwiftUI
import UniformTypeIdentifiers
import simd

/// A triangle-mesh export: visible geometry only, in meters, with transforms baked into vertices.
/// OBJ does not contain this app's edit history, dimension constraints, or solid CAD features.
struct CADOBJDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "obj") ?? .plainText] }
    var text: String

    init(shapes: [CADShape]) {
        var lines = ["# AVP Learn geometry export", "# Units: one OBJ unit = one meter", "# Y is up. Hidden shapes are excluded. Geometry is triangulated.", "# Independent meshes may overlap; no boolean union or solid-CAD history is implied.", ""]
        var offset = 1
        let locale = Locale(identifier: "en_US_POSIX")
        func number(_ value: Float) -> String { String(format: "%.9g", locale: locale, Double(value)) }
        for (index, shape) in shapes.filter({ !$0.isHidden }).enumerated() {
            let mesh = CADMeshLibrary.geometry(for: shape)
            let rotation = shape.rotationQuaternion
            let name = shape.name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? String($0) : "_" }.joined()
            lines.append("o \(index + 1)_\(name.isEmpty ? shape.kind.rawValue : name)")
            lines.append("g part_\(shape.id.uuidString.replacingOccurrences(of: "-", with: "_"))")
            for vertex in mesh.positions {
                let point = rotation.act(vertex) + shape.position
                lines.append("v \(number(point.x)) \(number(point.y)) \(number(point.z))")
            }
            for normal in mesh.normals {
                let transformed = simd_normalize(rotation.act(normal))
                lines.append("vn \(number(transformed.x)) \(number(transformed.y)) \(number(transformed.z))")
            }
            for face in stride(from: 0, to: mesh.indices.count, by: 3) {
                let a = Int(mesh.indices[face]) + offset
                let b = Int(mesh.indices[face + 1]) + offset
                let c = Int(mesh.indices[face + 2]) + offset
                lines.append("f \(a)//\(a) \(b)//\(b) \(c)//\(c)")
            }
            offset += mesh.positions.count
            lines.append("")
        }
        text = lines.joined(separator: "\n") + "\n"
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let decoded = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = decoded
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Draws parts as a shaded picture, for thumbnails that can sit in scrolling lists where a live 3D view cannot.
/// A small depth-buffered rasterizer: the same meshes as the viewport, lit from the upper left, with part outlines.
enum CADPreviewRenderer {
    struct Item: Sendable {
        var geometry: CADMeshGeometry
        var rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        var position = SIMD3<Float>.zero
        var color: SIMD3<Float>
        var isMetal = false
    }

    static func items(for shapes: [CADShape]) -> [Item] {
        shapes.filter { !$0.isHidden }.map { shape in
            let finish = CADPalette.finish(shape.colorIndex)
            return Item(geometry: CADMeshLibrary.geometry(for: shape), rotation: shape.rotationQuaternion,
                        position: shape.position, color: [finish.red, finish.green, finish.blue], isMetal: finish.isMetal)
        }
    }

    /// Renders on a transparent background, fitted to the frame. `width` and `height` are output pixels.
    static func image(_ items: [Item], width: Int, height: Int, yaw: Float = -.pi / 5, pitch: Float = .pi / 6) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let sampling = 2
        let w = width * sampling, h = height * sampling
        let view = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
        let light = simd_normalize(SIMD3<Float>(-0.45, 0.75, 0.55))
        let halfway = simd_normalize(light + SIMD3<Float>(0, 0, 1))

        // View space: X right, Y up, Z toward the viewer.
        var lower = SIMD3<Float>(repeating: .infinity), upper = SIMD3<Float>(repeating: -.infinity)
        let placed: [[SIMD3<Float>]] = items.map { item in
            item.geometry.positions.map { vertex in
                let point = view.act(item.rotation.act(vertex) + item.position)
                lower = simd_min(lower, point)
                upper = simd_max(upper, point)
                return point
            }
        }
        guard lower.x.isFinite else { return nil }
        let extent = simd_max(upper - lower, SIMD3<Float>(repeating: 1e-6))
        let margin = Float(min(w, h)) * 0.06
        let scale = min((Float(w) - 2 * margin) / extent.x, (Float(h) - 2 * margin) / extent.y)
        let middle = (lower + upper) / 2

        var depth = [Float](repeating: -.infinity, count: w * h)
        var owner = [Int32](repeating: -1, count: w * h)
        var shade = [SIMD3<Float>](repeating: .zero, count: w * h)
        for (itemIndex, item) in items.enumerated() {
            let points = placed[itemIndex]
            let screen: [SIMD3<Float>] = points.map {
                [Float(w) / 2 + ($0.x - middle.x) * scale, Float(h) / 2 - ($0.y - middle.y) * scale, $0.z]
            }
            let orientation = view * item.rotation
            let lit: [SIMD3<Float>] = item.geometry.normals.map { normal in
                let n = orientation.act(normal)
                let diffuse = max(0, simd_dot(n, light))
                let glint = item.isMetal ? 0.45 * pow(max(0, simd_dot(n, halfway)), 28) : 0.12 * pow(max(0, simd_dot(n, halfway)), 12)
                let base = item.color * (item.isMetal ? 0.30 + 0.62 * diffuse : 0.38 + 0.62 * diffuse)
                return simd_min(base + SIMD3<Float>(repeating: glint), SIMD3<Float>(repeating: 1))
            }
            let indices = item.geometry.indices
            for face in stride(from: 0, to: indices.count, by: 3) {
                let ia = Int(indices[face]), ib = Int(indices[face + 1]), ic = Int(indices[face + 2])
                let a = screen[ia], b = screen[ib], c = screen[ic]
                // Screen Y points down, so a front face has negative area here.
                let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
                guard area < -1e-9 else { continue }
                let minX = max(0, Int(min(a.x, b.x, c.x).rounded(.down))), maxX = min(w - 1, Int(max(a.x, b.x, c.x).rounded(.up)))
                let minY = max(0, Int(min(a.y, b.y, c.y).rounded(.down))), maxY = min(h - 1, Int(max(a.y, b.y, c.y).rounded(.up)))
                guard minX <= maxX, minY <= maxY else { continue }
                for y in minY...maxY {
                    let py = Float(y) + 0.5
                    for x in minX...maxX {
                        let px = Float(x) + 0.5
                        let wa = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
                        let wb = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
                        let wc = 1 - wa - wb
                        guard wa >= 0, wb >= 0, wc >= 0 else { continue }
                        let z = wa * a.z + wb * b.z + wc * c.z
                        let pixel = y * w + x
                        guard z > depth[pixel] else { continue }
                        depth[pixel] = z
                        owner[pixel] = Int32(itemIndex)
                        shade[pixel] = wa * lit[ia] + wb * lit[ib] + wc * lit[ic]
                    }
                }
            }
        }

        // Darken pixels where the part changes or the surface steps back, which draws each part's outline.
        let step = extent.z * 0.02 + extent.x * 0.004
        var edge = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let pixel = y * w + x
                guard owner[pixel] >= 0 else { continue }
                for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let other = ny * w + nx
                    if owner[other] != owner[pixel] || depth[pixel] - depth[other] > step { edge[pixel] = true; break }
                }
            }
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let samples = Float(sampling * sampling)
        for y in 0..<height {
            for x in 0..<width {
                var color = SIMD3<Float>.zero
                var coverage: Float = 0
                for sy in 0..<sampling {
                    for sx in 0..<sampling {
                        let pixel = (y * sampling + sy) * w + x * sampling + sx
                        guard owner[pixel] >= 0 else { continue }
                        color += shade[pixel] * (edge[pixel] ? 0.28 : 1)
                        coverage += 1
                    }
                }
                // Premultiplied alpha: partly covered pixels fade out at the silhouette.
                let out = (y * width + x) * 4
                bytes[out] = UInt8(max(0, min(255, color.x / samples * 255)))
                bytes[out + 1] = UInt8(max(0, min(255, color.y / samples * 255)))
                bytes[out + 2] = UInt8(max(0, min(255, color.z / samples * 255)))
                bytes[out + 3] = UInt8(coverage / samples * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A shaded picture of some parts. Rendering happens off the main thread and repeats only when `id` changes.
struct CADPreviewImage<ID: Equatable>: View {
    let id: ID
    var pixels = 360
    let items: @Sendable () -> [CADPreviewRenderer.Item]
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: id) {
            let pixels = pixels, items = items
            image = await Task.detached(priority: .userInitiated) {
                CADPreviewRenderer.image(items(), width: pixels, height: pixels)
            }.value
        }
        .accessibilityHidden(true)
    }
}

extension CADPreviewImage where ID == [CADShape] {
    init(shapes: [CADShape], pixels: Int = 360) {
        self.init(id: shapes, pixels: pixels) { CADPreviewRenderer.items(for: shapes) }
    }
}
