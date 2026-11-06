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
            let mesh = CADMeshLibrary.geometry(for: shape.kind, boreRatio: shape.boreRatio)
            let scale = shape.dimensions / SIMD3<Float>(repeating: 0.1)
            let rotation = shape.rotationQuaternion
            let name = shape.name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" ? String($0) : "_" }.joined()
            lines.append("o \(index + 1)_\(name.isEmpty ? shape.kind.rawValue : name)")
            lines.append("g part_\(shape.id.uuidString.replacingOccurrences(of: "-", with: "_"))")
            for vertex in mesh.positions {
                let point = rotation.act(vertex * scale) + shape.position
                lines.append("v \(number(point.x)) \(number(point.y)) \(number(point.z))")
            }
            for normal in mesh.normals {
                let transformed = simd_normalize(rotation.act(normal / scale))
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
