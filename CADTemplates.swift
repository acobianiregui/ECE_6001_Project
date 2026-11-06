import Foundation

/// Composed primitives with meaningful dimensions. These are assemblies, not Boolean solids.
enum CADTemplate: String, CaseIterable, Identifiable {
    case shaftSupport, angleBracket
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shaftSupport: "Shaft support assembly"
        case .angleBracket: "Reinforced angle bracket"
        }
    }
    var subtitle: String {
        switch self {
        case .shaftSupport: "Two hollow collars carry a 36 mm shaft inside 42 mm bores. Inspect the 3 mm radial clearance."
        case .angleBracket: "A 240 mm base, 180 mm upright plate, and two corner blocks. Edit each part independently."
        }
    }
    var shapes: [CADShape] {
        switch self {
        case .shaftSupport:
            return [
                part(1, .box, "Base plate", [0.34, 0.02, 0.30], [0, 0.01, 0], color: 0),
                part(2, .box, "Front pedestal", [0.08, 0.05, 0.045], [0, 0.045, 0.095], color: 5),
                part(3, .box, "Rear pedestal", [0.08, 0.05, 0.045], [0, 0.045, -0.095], color: 5),
                part(4, .tube, "Front hollow collar", [0.07, 0.03, 0.07], [0, 0.105, 0.095], rotation: [90, 0, 0], color: 3, bore: 0.6),
                part(5, .tube, "Rear hollow collar", [0.07, 0.03, 0.07], [0, 0.105, -0.095], rotation: [90, 0, 0], color: 3, bore: 0.6),
                part(6, .cylinder, "Shaft · 36 mm diameter", [0.036, 0.28, 0.036], [0, 0.105, 0], rotation: [90, 0, 0], color: 1)
            ]
        case .angleBracket:
            return [
                part(1, .box, "Horizontal base plate", [0.24, 0.012, 0.16], [0, 0.006, 0], color: 0),
                part(2, .box, "Upright plate", [0.012, 0.18, 0.16], [-0.114, 0.102, 0], color: 0),
                part(3, .box, "Front reinforcing block", [0.06, 0.045, 0.025], [-0.078, 0.0345, 0.0525], color: 4),
                part(4, .box, "Rear reinforcing block", [0.06, 0.045, 0.025], [-0.078, 0.0345, -0.0525], color: 4)
            ]
        }
    }
    private func part(_ number: Int, _ kind: ShapeKind, _ name: String, _ dimensions: SIMD3<Float>,
                      _ position: SIMD3<Float>, rotation: SIMD3<Float> = .zero, color: Int = 0, bore: Float = 0.6) -> CADShape {
        // Stable IDs make the sample assemblies reproducible while each loaded workspace remains independent.
        let family = self == .shaftSupport ? "0001" : "0002"
        let identifier = UUID(uuidString: String(format: "60010000-0000-0000-%@-%012d", family, number))!
        return CADShape(id: identifier, kind: kind, position: position, colorIndex: color,
                        name: name, dimensions: dimensions, rotationDegrees: rotation, boreRatio: bore)
    }
}
