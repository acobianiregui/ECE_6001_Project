import Foundation
import RealityKit
import simd

/// Indexed triangle geometry shared by the live viewport and OBJ export.
/// Every prototype has a 0.1 m local bounding box. Cylinders, cones, and tubes run along local Y.
struct CADMeshGeometry {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    mutating func vertex(_ position: SIMD3<Float>, normal: SIMD3<Float>) -> UInt32 {
        positions.append(position)
        normals.append(simd_normalize(normal))
        return UInt32(positions.count - 1)
    }
    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        let cross = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
        guard simd_length_squared(cross) > 1e-16 else { return }
        let expected = normals[Int(a)] + normals[Int(b)] + normals[Int(c)]
        indices += simd_dot(cross, expected) >= 0 ? [a, b, c] : [a, c, b]
    }
    mutating func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) {
        triangle(a, b, c)
        triangle(a, c, d)
    }
}

enum CADMeshLibrary {
    private static let radius: Float = 0.05
    private static let height: Float = 0.1
    private static let segments = 64
    @MainActor private static var meshes: [String: MeshResource] = [:]
    @MainActor private static var tubeCollisions: [UInt32: [ShapeResource]] = [:]

    static func geometry(for kind: ShapeKind, boreRatio: Float = 0.55) -> CADMeshGeometry {
        switch kind {
        case .box: return box()
        case .sphere: return sphere()
        case .cylinder: return roundSolid(innerRadius: 0)
        case .cone: return cone()
        case .tube: return roundSolid(innerRadius: radius * clampedBore(boreRatio))
        }
    }

    @MainActor
    static func mesh(for shape: CADShape) -> MeshResource {
        let key = shape.kind.rawValue + (shape.kind == .tube ? "-\(clampedBore(shape.boreRatio).bitPattern)" : "")
        if let cached = meshes[key] { return cached }
        let geometry = geometry(for: shape.kind, boreRatio: shape.boreRatio)
        var descriptor = MeshDescriptor(name: "CAD-\(shape.kind.rawValue)")
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.primitives = .triangles(geometry.indices)
        // Procedural inputs are bounded and tested; a failed mesh is a programming error.
        let result = try! MeshResource.generate(from: [descriptor])
        if meshes.count > 512 { meshes.removeAll() }
        meshes[key] = result
        return result
    }

    /// Compound wall segments preserve the central opening for selection.
    /// Curved surfaces use a finite polygonal approximation, as does the visible mesh.
    @MainActor
    static func collisionShapes(for shape: CADShape) -> [ShapeResource]? {
        guard shape.kind == .tube else { return nil }
        let bore = clampedBore(shape.boreRatio)
        if let cached = tubeCollisions[bore.bitPattern] { return cached }
        let inner = radius * bore
        let wall = radius - inner
        let centerRadius = (radius + inner) / 2
        let count = 64
        let tangent = 2 * centerRadius * tan(Float.pi / Float(count))
        let result = (0..<count).map { index in
            let angle = (Float(index) + 0.5) * 2 * Float.pi / Float(count)
            return ShapeResource.generateBox(size: [wall, height, tangent])
                .offsetBy(rotation: simd_quatf(angle: -angle, axis: [0, 1, 0]),
                          translation: [centerRadius * cos(angle), 0, centerRadius * sin(angle)])
        }
        if tubeCollisions.count > 512 { tubeCollisions.removeAll() }
        tubeCollisions[bore.bitPattern] = result
        return result
    }

    private static func clampedBore(_ value: Float) -> Float {
        min(0.95, max(0.05, value.isFinite ? value : 0.55))
    }
    private static func box() -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let r = radius
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            ([1,0,0], [[r,-r,-r],[r,r,-r],[r,r,r],[r,-r,r]]),
            ([-1,0,0], [[-r,-r,r],[-r,r,r],[-r,r,-r],[-r,-r,-r]]),
            ([0,1,0], [[-r,r,-r],[-r,r,r],[r,r,r],[r,r,-r]]),
            ([0,-1,0], [[-r,-r,r],[-r,-r,-r],[r,-r,-r],[r,-r,r]]),
            ([0,0,1], [[-r,-r,r],[r,-r,r],[r,r,r],[-r,r,r]]),
            ([0,0,-1], [[r,-r,-r],[-r,-r,-r],[-r,r,-r],[r,r,-r]])
        ]
        for (normal, corners) in faces {
            let ids = corners.map { geometry.vertex($0, normal: normal) }
            geometry.quad(ids[0], ids[1], ids[2], ids[3])
        }
        return geometry
    }
    private static func sphere() -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let latitudeCount = 32
        for latitude in 0...latitudeCount {
            let phi = Float(latitude) * Float.pi / Float(latitudeCount)
            for longitude in 0...segments {
                let theta = Float(longitude) * 2 * Float.pi / Float(segments)
                let direction = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
                _ = geometry.vertex(direction * radius, normal: direction)
            }
        }
        for latitude in 0..<latitudeCount {
            for longitude in 0..<segments {
                let a = UInt32(latitude * (segments + 1) + longitude)
                let b = a + 1
                let c = a + UInt32(segments + 1)
                let d = c + 1
                geometry.triangle(a, c, b)
                geometry.triangle(b, c, d)
            }
        }
        return geometry
    }
    private static func roundSolid(innerRadius: Float) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        func radial(_ angle: Float) -> SIMD3<Float> { [cos(angle), 0, sin(angle)] }
        let half = height / 2
        for index in 0..<segments {
            let a = Float(index) * 2 * Float.pi / Float(segments)
            let b = Float(index + 1) * 2 * Float.pi / Float(segments)
            let ra = radial(a), rb = radial(b)
            let oa = ra * radius, ob = rb * radius
            let lowerA = geometry.vertex(oa + [0,-half,0], normal: ra)
            let upperA = geometry.vertex(oa + [0,half,0], normal: ra)
            let upperB = geometry.vertex(ob + [0,half,0], normal: rb)
            let lowerB = geometry.vertex(ob + [0,-half,0], normal: rb)
            geometry.quad(lowerA, upperA, upperB, lowerB)
            if innerRadius > 0 {
                let ia = ra * innerRadius, ib = rb * innerRadius
                let ila = geometry.vertex(ia + [0,-half,0], normal: -ra)
                let iua = geometry.vertex(ia + [0,half,0], normal: -ra)
                let iub = geometry.vertex(ib + [0,half,0], normal: -rb)
                let ilb = geometry.vertex(ib + [0,-half,0], normal: -rb)
                geometry.quad(ila, iua, iub, ilb)
                for sign in [Float(-1), Float(1)] {
                    let normal = SIMD3<Float>(0, sign, 0)
                    let offset = SIMD3<Float>(0, sign * half, 0)
                    let ids = [oa, ob, ib, ia].map { geometry.vertex($0 + offset, normal: normal) }
                    geometry.quad(ids[0], ids[1], ids[2], ids[3])
                }
            } else {
                for sign in [Float(-1), Float(1)] {
                    let normal = SIMD3<Float>(0, sign, 0)
                    let offset = SIMD3<Float>(0, sign * half, 0)
                    let center = geometry.vertex(offset, normal: normal)
                    let ca = geometry.vertex(oa + offset, normal: normal)
                    let cb = geometry.vertex(ob + offset, normal: normal)
                    geometry.triangle(center, ca, cb)
                }
            }
        }
        return geometry
    }
    private static func cone() -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let half = height / 2
        for index in 0..<segments {
            let a = Float(index) * 2 * Float.pi / Float(segments)
            let b = Float(index + 1) * 2 * Float.pi / Float(segments)
            let mid = (a + b) / 2
            let pa = SIMD3<Float>(radius * cos(a), -half, radius * sin(a))
            let pb = SIMD3<Float>(radius * cos(b), -half, radius * sin(b))
            let ca = geometry.vertex(pa, normal: [cos(a), radius / height, sin(a)])
            let cb = geometry.vertex(pb, normal: [cos(b), radius / height, sin(b)])
            let tip = geometry.vertex([0, half, 0], normal: [cos(mid), radius / height, sin(mid)])
            geometry.triangle(ca, tip, cb)
            let bottom = SIMD3<Float>(0, -1, 0)
            let center = geometry.vertex([0, -half, 0], normal: bottom)
            let ba = geometry.vertex(pa, normal: bottom)
            let bb = geometry.vertex(pb, normal: bottom)
            geometry.triangle(center, ba, bb)
        }
        return geometry
    }
}
