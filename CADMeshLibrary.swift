import Foundation
import RealityKit
import simd

/// Indexed triangle geometry shared by the live viewport, the 2D previews and OBJ export.
/// Parts are built at their true size in meters, centered on the origin. Round parts run along local Y.
struct CADMeshGeometry: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var indices: [UInt32] = []

    mutating func vertex(_ position: SIMD3<Float>, normal: SIMD3<Float>) -> UInt32 {
        positions.append(position)
        normals.append(simd_normalize(normal))
        return UInt32(positions.count - 1)
    }
    /// Winding follows the vertex normals, so callers never track handedness. Collapsed triangles are dropped.
    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        let ab = positions[Int(b)] - positions[Int(a)], ac = positions[Int(c)] - positions[Int(a)]
        let cross = simd_cross(ab, ac)
        guard !Self.isCollapsed(ab, ac, cross) else { return }
        let expected = normals[Int(a)] + normals[Int(b)] + normals[Int(c)]
        indices += simd_dot(cross, expected) >= 0 ? [a, b, c] : [a, c, b]
    }
    /// True when two corners coincide. The test is relative, so millimeter-scale features survive
    /// while the collapsed triangles a lathe makes on its axis do not.
    private static func isCollapsed(_ ab: SIMD3<Float>, _ ac: SIMD3<Float>, _ cross: SIMD3<Float>) -> Bool {
        simd_length_squared(cross) <= 1e-10 * simd_length_squared(ab) * simd_length_squared(ac)
            || simd_length_squared(ac - ab) <= 1e-10 * simd_length_squared(ab)
    }
    mutating func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) {
        triangle(a, b, c)
        triangle(a, c, d)
    }
    /// A flat-shaded triangle whose normal is the face normal on the `facing` side.
    mutating func flatTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, facing: SIMD3<Float>) {
        var normal = simd_cross(b - a, c - a)
        guard !Self.isCollapsed(b - a, c - a, normal) else { return }
        if simd_dot(normal, facing) < 0 { normal = -normal }
        triangle(vertex(a, normal: normal), vertex(b, normal: normal), vertex(c, normal: normal))
    }
    /// Adds another mesh, rotated then moved. Used to compose display models from several solids.
    mutating func append(_ other: CADMeshGeometry, rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]),
                         translation: SIMD3<Float> = .zero) {
        let offset = UInt32(positions.count)
        positions += other.positions.map { rotation.act($0) + translation }
        normals += other.normals.map { rotation.act($0) }
        indices += other.indices.map { $0 + offset }
    }
    /// Enclosed volume in cubic meters, for closed meshes.
    var volume: Float {
        var total: Float = 0
        for face in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[face])], b = positions[Int(indices[face + 1])], c = positions[Int(indices[face + 2])]
            total += simd_dot(a, simd_cross(b, c)) / 6
        }
        return abs(total)
    }
}

/// The axis a 2D profile is swept along. `.y` profiles live in the X–Z plane, `.z` profiles in X–Y.
private enum SweepAxis {
    case y, z
    func point(_ p: SIMD2<Float>, _ h: Float) -> SIMD3<Float> { self == .y ? [p.x, h, p.y] : [p.x, p.y, h] }
    var direction: SIMD3<Float> { self == .y ? [0, 1, 0] : [0, 0, 1] }
}

private extension CADMeshGeometry {
    /// Flat cap over a loop that is visible from `center` (any convex loop, or a star-shaped one).
    mutating func cap(_ loop: [SIMD2<Float>], center: SIMD2<Float>, at h: Float, axis: SweepAxis, up: Float) {
        let normal = axis.direction * up
        let hub = vertex(axis.point(center, h), normal: normal)
        let rim = loop.map { vertex(axis.point($0, h), normal: normal) }
        for index in rim.indices { triangle(hub, rim[index], rim[(index + 1) % rim.count]) }
    }

    /// Fills the band between two loops that both wind counter-clockwise around `center`. The outer loop must be convex.
    /// The loops may sit at different heights, which gives a chamfer instead of a flat face.
    mutating func ring(outer: [SIMD2<Float>], at outerH: Float, inner: [SIMD2<Float>], at innerH: Float,
                       center: SIMD2<Float>, axis: SweepAxis, up: Float) {
        func angle(_ p: SIMD2<Float>) -> Float { atan2(p.y - center.y, p.x - center.x) }
        func wrap(_ value: Float) -> Float {
            var result = value
            while result > .pi { result -= 2 * .pi }
            while result <= -.pi { result += 2 * .pi }
            return result
        }
        func unwrapped(_ loop: [SIMD2<Float>], from start: Float) -> [Float] {
            var result = [start]
            for index in 1...loop.count {
                result.append(result[index - 1] + wrap(angle(loop[index % loop.count]) - angle(loop[index - 1])))
            }
            return result
        }
        let outerAngles = unwrapped(outer, from: angle(outer[0]))
        // Start the inner loop at the point nearest in angle, so the two walks stay side by side.
        let first = inner.indices.min { abs(wrap(angle(inner[$0]) - outerAngles[0])) < abs(wrap(angle(inner[$1]) - outerAngles[0])) } ?? 0
        let turned = Array(inner[first...] + inner[..<first])
        let innerAngles = unwrapped(turned, from: outerAngles[0] + wrap(angle(turned[0]) - outerAngles[0]))
        let facing = axis.direction * up
        var i = 0, j = 0
        func turn(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        while i < outer.count || j < turned.count {
            let o = outer[i % outer.count], oNext = outer[(i + 1) % outer.count]
            let n = turned[j % turned.count], nNext = turned[(j + 1) % turned.count]
            var stepOuter = j == turned.count
            if i < outer.count, j < turned.count {
                // Advance whichever loop is behind in angle, unless that triangle would fold over:
                // a tooth flank or a keyway wall can face away from the point across the band.
                stepOuter = outerAngles[i + 1] <= innerAngles[j + 1]
                let outerFits = turn(o, oNext, n) > 0, innerFits = turn(o, nNext, n) > 0
                if stepOuter, !outerFits, innerFits { stepOuter = false }
                else if !stepOuter, !innerFits, outerFits { stepOuter = true }
            }
            let a = axis.point(o, outerH), b = axis.point(n, innerH)
            if stepOuter {
                flatTriangle(a, axis.point(oNext, outerH), b, facing: facing)
                i += 1
            } else {
                flatTriangle(a, axis.point(nNext, innerH), b, facing: facing)
                j += 1
            }
        }
    }

    /// Side wall of a swept loop. Gentle bends shade smoothly; corners sharper than about 35° stay crisp.
    mutating func wall(_ source: [SIMD2<Float>], from h0: Float, to h1: Float, axis: SweepAxis, outward: Bool) {
        var loop: [SIMD2<Float>] = []
        for point in source where loop.last.map({ simd_length_squared($0 - point) > 1e-18 }) ?? true { loop.append(point) }
        if loop.count > 1, simd_length_squared(loop[0] - loop[loop.count - 1]) <= 1e-18 { loop.removeLast() }
        guard loop.count >= 3 else { return }
        let count = loop.count
        var doubledArea: Float = 0
        for index in 0..<count {
            let p = loop[index], q = loop[(index + 1) % count]
            doubledArea += p.x * q.y - q.x * p.y
        }
        let side: Float = (doubledArea >= 0 ? 1 : -1) * (outward ? 1 : -1)
        let edgeNormals: [SIMD2<Float>] = (0..<count).map { index in
            let d = loop[(index + 1) % count] - loop[index]
            return simd_normalize(SIMD2<Float>(d.y, -d.x)) * side
        }
        func blend(_ own: SIMD2<Float>, _ neighbor: SIMD2<Float>) -> SIMD3<Float> {
            axis.point(simd_dot(own, neighbor) > 0.82 ? simd_normalize(own + neighbor) : own, 0)
        }
        for index in 0..<count {
            let next = (index + 1) % count
            let own = edgeNormals[index]
            let startNormal = blend(own, edgeNormals[(index + count - 1) % count])
            let endNormal = blend(own, edgeNormals[next])
            let a0 = vertex(axis.point(loop[index], h0), normal: startNormal)
            let a1 = vertex(axis.point(loop[index], h1), normal: startNormal)
            let b1 = vertex(axis.point(loop[next], h1), normal: endNormal)
            let b0 = vertex(axis.point(loop[next], h0), normal: endNormal)
            quad(a0, a1, b1, b0)
        }
    }

    /// Lathes a profile around local Y. Profile x is a fraction of `radii`; y is height in meters.
    /// The profile must run counter-clockwise in the (radius, height) half-plane: up the outside, down the bore.
    mutating func revolve(_ profile: [SIMD2<Float>], radii: SIMD2<Float>, closed: Bool, smooth: Bool = false) {
        let circle = CADMeshLibrary.unitCircle
        let segmentCount = closed ? profile.count : profile.count - 1
        func segmentNormal(_ segment: Int, _ direction: SIMD2<Float>) -> SIMD3<Float>? {
            let p = profile[segment], q = profile[(segment + 1) % profile.count]
            let delta = q - p
            guard simd_length_squared(delta) > 1e-18 else { return nil }
            return [delta.y * direction.x / radii.x, -delta.x, delta.y * direction.y / radii.y]
        }
        func normal(_ segment: Int, atEnd: Bool, _ direction: SIMD2<Float>) -> SIMD3<Float>? {
            guard let own = segmentNormal(segment, direction) else { return nil }
            guard smooth else { return own }
            var neighbor = atEnd ? segment + 1 : segment - 1
            if closed { neighbor = (neighbor + segmentCount) % segmentCount }
            guard neighbor >= 0, neighbor < segmentCount, let other = segmentNormal(neighbor, direction) else { return own }
            return simd_normalize(own) + simd_normalize(other)
        }
        func position(_ p: SIMD2<Float>, _ direction: SIMD2<Float>) -> SIMD3<Float> {
            [p.x * radii.x * direction.x, p.y, p.x * radii.y * direction.y]
        }
        for segment in 0..<segmentCount {
            let p = profile[segment], q = profile[(segment + 1) % profile.count]
            for step in 0..<circle.count {
                let d0 = circle[step], d1 = circle[(step + 1) % circle.count]
                guard let p0 = normal(segment, atEnd: false, d0), let q0 = normal(segment, atEnd: true, d0),
                      let q1 = normal(segment, atEnd: true, d1), let p1 = normal(segment, atEnd: false, d1) else { continue }
                quad(vertex(position(p, d0), normal: p0), vertex(position(q, d0), normal: q0),
                     vertex(position(q, d1), normal: q1), vertex(position(p, d1), normal: p1))
            }
        }
    }
}

enum CADMeshLibrary {
    static let segments = 64
    /// One shared table, so a lathed surface and a swept loop that meet share exact vertices.
    static let unitCircle: [SIMD2<Float>] = (0..<segments).map {
        let angle = Float($0) * 2 * .pi / Float(segments)
        return [cos(angle), sin(angle)]
    }
    @MainActor private static var meshes: [String: MeshResource] = [:]

    private static func circle(_ radius: Float, center: SIMD2<Float> = .zero) -> [SIMD2<Float>] {
        unitCircle.map { center + $0 * radius }
    }
    private static func clampedRatio(_ value: Float) -> Float {
        min(0.95, max(0.05, value.isFinite ? value : 0.6))
    }
    /// Identifies a mesh: two parts with the same key share one.
    static func key(_ shape: CADShape) -> String {
        "\(shape.kind.rawValue)-\(shape.dimensions.x.bitPattern)-\(shape.dimensions.y.bitPattern)-\(shape.dimensions.z.bitPattern)-\(shape.boreRatio.bitPattern)-\(shape.teeth)"
    }

    static func geometry(for shape: CADShape) -> CADMeshGeometry {
        var part = shape
        part.dimensions = simd_max(shape.dimensions, SIMD3<Float>(repeating: 0.0001))
        part.boreRatio = clampedRatio(shape.boreRatio)
        part.teeth = min(max(shape.teeth, 8), 60)
        let d = part.dimensions
        switch part.kind {
        case .box: return box(d)
        case .sphere: return sphere(d)
        case .cylinder: return cylinder(d)
        case .cone: return cone(d)
        case .tube: return tube(d, bore: part.boreRatio)
        case .wedge: return wedge(d)
        case .plate: return plate(part)
        case .gear:
            return spurGear(teeth: part.teeth, radii: [d.x / 2, d.z / 2], thickness: d.y,
                            boreFraction: part.boreRatio * 0.75 * part.gearRootFraction)
        case .hexBolt: return hexBolt(part)
        case .hexNut: return hexNut(part)
        case .bearingBlock: return bearingBlock(part)
        }
    }

    @MainActor
    static func resource(_ geometry: CADMeshGeometry, name: String) -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(geometry.positions)
        descriptor.normals = MeshBuffers.Normals(geometry.normals)
        descriptor.primitives = .triangles(geometry.indices)
        // Procedural inputs are bounded and tested; a failed mesh is a programming error.
        return try! MeshResource.generate(from: [descriptor])
    }

    @MainActor
    static func mesh(for shape: CADShape) -> MeshResource {
        let key = key(shape)
        if let cached = meshes[key] { return cached }
        let result = resource(geometry(for: shape), name: "CAD-\(shape.kind.rawValue)")
        // A two-hand resize makes a new size every frame; keep the cache from growing without bound.
        if meshes.count > 256 { meshes.removeAll() }
        meshes[key] = result
        return result
    }

    /// Parts with a bore along local Y get a ring of wall segments, so a shaft inside stays selectable.
    /// Other parts return nil and use the bounds of their mesh.
    @MainActor
    static func collisionShapes(for shape: CADShape) -> [ShapeResource]? {
        guard [.tube, .gear, .hexNut].contains(shape.kind), let bore = shape.featureDiameter else { return nil }
        let outer = SIMD2<Float>(shape.dimensions.x, shape.dimensions.z) / 2
        let scale = shape.kind == .hexNut ? SIMD2<Float>(repeating: bore / 2) : outer * (bore / shape.dimensions.x)
        let count = 32
        return (0..<count).map { index in
            let angle = (Float(index) + 0.5) * 2 * .pi / Float(count)
            let direction = SIMD2<Float>(cos(angle), sin(angle))
            let far = outer * direction, near = scale * direction
            let middle = (far + near) / 2, across = far - near
            let tangent = 2 * simd_length(middle) * tan(.pi / Float(count))
            return ShapeResource.generateBox(size: [max(simd_length(across), 0.0002), shape.dimensions.y, max(tangent, 0.0002)])
                .offsetBy(rotation: simd_quatf(angle: -atan2(across.y, across.x), axis: [0, 1, 0]),
                          translation: [middle.x, 0, middle.y])
        }
    }

    // MARK: Solids

    /// A box with its edges broken by a small bevel, as a machined block would be.
    private static func box(_ d: SIMD3<Float>) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let half = d / 2
        let inner = half - SIMD3<Float>(repeating: min(0.002, 0.06 * d.min()))
        func point(_ values: [(Int, Float)]) -> SIMD3<Float> {
            var result = SIMD3<Float>.zero
            for (axis, value) in values { result[axis] = value }
            return result
        }
        let signs: [Float] = [-1, 1]
        for axis in 0..<3 {
            let u = (axis + 1) % 3, v = (axis + 2) % 3
            for sign in signs {
                let normal = point([(axis, sign)])
                let ids = [(-1, -1), (1, -1), (1, 1), (-1, 1)].map { corner in
                    geometry.vertex(point([(axis, sign * half[axis]), (u, Float(corner.0) * inner[u]), (v, Float(corner.1) * inner[v])]), normal: normal)
                }
                geometry.quad(ids[0], ids[1], ids[2], ids[3])
            }
        }
        for along in 0..<3 {
            let a = (along + 1) % 3, b = (along + 2) % 3
            for sa in signs {
                for sb in signs {
                    let normal = point([(a, sa), (b, sb)])
                    func corner(onA: Bool, _ end: Float) -> UInt32 {
                        geometry.vertex(point([(a, sa * (onA ? half[a] : inner[a])), (b, sb * (onA ? inner[b] : half[b])), (along, end * inner[along])]), normal: normal)
                    }
                    geometry.quad(corner(onA: true, -1), corner(onA: true, 1), corner(onA: false, 1), corner(onA: false, -1))
                }
            }
        }
        for sx in signs {
            for sy in signs {
                for sz in signs {
                    let normal = SIMD3<Float>(sx, sy, sz)
                    geometry.triangle(geometry.vertex([sx * half.x, sy * inner.y, sz * inner.z], normal: normal),
                                      geometry.vertex([sx * inner.x, sy * half.y, sz * inner.z], normal: normal),
                                      geometry.vertex([sx * inner.x, sy * inner.y, sz * half.z], normal: normal))
                }
            }
        }
        return geometry
    }

    private static func sphere(_ d: SIMD3<Float>) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let half = d / 2
        let latitudeCount = 32
        for latitude in 0...latitudeCount {
            let phi = Float(latitude) * Float.pi / Float(latitudeCount)
            for longitude in 0...segments {
                let around = unitCircle[longitude % segments]
                // Both poles are exact points; sin(π) alone leaves a ring a few nanometers wide.
                let ring = latitude == 0 || latitude == latitudeCount ? 0 : sin(phi)
                let direction = SIMD3<Float>(ring * around.x, cos(phi), ring * around.y)
                _ = geometry.vertex(direction * half, normal: direction / half)
            }
        }
        for latitude in 0..<latitudeCount {
            for longitude in 0..<segments {
                let a = UInt32(latitude * (segments + 1) + longitude)
                let b = a + 1
                let c = a + UInt32(segments + 1)
                let e = c + 1
                geometry.triangle(a, c, b)
                geometry.triangle(b, c, e)
            }
        }
        return geometry
    }

    /// A round bar with chamfered ends.
    private static func cylinder(_ d: SIMD3<Float>) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let radii = SIMD2<Float>(d.x, d.z) / 2, half = d.y / 2
        let chamfer = min(0.0015, 0.08 * min(radii.min(), d.y))
        let inset = 1 - chamfer / radii.min()
        geometry.revolve([[0, -half], [inset, -half], [1, -half + chamfer], [1, half - chamfer], [inset, half], [0, half]],
                         radii: radii, closed: false)
        return geometry
    }

    private static func cone(_ d: SIMD3<Float>) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        geometry.revolve([[0, -d.y / 2], [1, -d.y / 2], [0, d.y / 2]], radii: SIMD2<Float>(d.x, d.z) / 2, closed: false)
        return geometry
    }

    /// A hollow round bar: bushing, collar or washer. Outer edges are chamfered.
    private static func tube(_ d: SIMD3<Float>, bore: Float) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let radii = SIMD2<Float>(d.x, d.z) / 2, half = d.y / 2
        let chamfer = min(0.001, 0.2 * (1 - bore) * radii.min(), 0.12 * d.y)
        let inset = chamfer / radii.min()
        geometry.revolve([[bore + inset, -half], [1 - inset, -half], [1, -half + chamfer], [1, half - chamfer],
                          [1 - inset, half], [bore + inset, half], [bore, half - chamfer], [bore, -half + chamfer]],
                         radii: radii, closed: true)
        return geometry
    }

    /// A right-triangle prism. The right angle sits at the −X, −Y corner; thickness runs along Z.
    private static func wedge(_ d: SIMD3<Float>) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let half = d / 2
        let loop: [SIMD2<Float>] = [[-half.x, -half.y], [half.x, -half.y], [-half.x, half.y]]
        let center = (loop[0] + loop[1] + loop[2]) / 3
        geometry.cap(loop, center: center, at: half.z, axis: .z, up: 1)
        geometry.cap(loop, center: center, at: -half.z, axis: .z, up: -1)
        geometry.wall(loop, from: -half.z, to: half.z, axis: .z, outward: true)
        return geometry
    }

    // MARK: Machine parts

    /// A flat plate with rounded corners and a bolt hole in each corner. Thickness runs along Y.
    private static func plate(_ shape: CADShape) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let a = shape.dimensions.x / 2, b = shape.dimensions.z / 2, t = shape.dimensions.y / 2
        let inset = shape.plateHoleInset
        let holeRadius = (shape.featureDiameter ?? 0) / 2
        let cornerRadius = inset / 2
        // Each hole sits in the middle of a square corner cell; plain rectangles fill the rest.
        let xIn = a - 2 * inset, zIn = b - 2 * inset
        var corner: [SIMD2<Float>] = [[a, zIn]]
        for step in 0...8 {
            let angle = Float(step) * .pi / 16
            corner.append([a - cornerRadius + cornerRadius * cos(angle), b - cornerRadius + cornerRadius * sin(angle)])
        }
        corner.append([xIn, b])
        var perimeter: [SIMD2<Float>] = []
        for (sx, sz) in [(Float(1), Float(1)), (-1, 1), (-1, -1), (1, -1)] {
            let mirrored = corner.map { SIMD2<Float>(sx * $0.x, sz * $0.y) }
            // Mirroring one axis reverses the winding; put it back so every loop stays counter-clockwise.
            let edge = sx * sz < 0 ? Array(mirrored.reversed()) : mirrored
            perimeter += edge
            let center = SIMD2<Float>(sx * (a - inset), sz * (b - inset))
            let cell = [SIMD2<Float>(sx * xIn, sz * zIn)] + edge
            let hole = circle(holeRadius, center: center)
            geometry.ring(outer: cell, at: t, inner: hole, at: t, center: center, axis: .y, up: 1)
            geometry.ring(outer: cell, at: -t, inner: hole, at: -t, center: center, axis: .y, up: -1)
            geometry.wall(hole, from: -t, to: t, axis: .y, outward: false)
        }
        let xs = [-a, -xIn, xIn, a], zs = [-b, -zIn, zIn, b]
        for column in 0..<3 {
            for row in 0..<3 where column == 1 || row == 1 {
                let loop: [SIMD2<Float>] = [[xs[column], zs[row]], [xs[column + 1], zs[row]], [xs[column + 1], zs[row + 1]], [xs[column], zs[row + 1]]]
                let center = (loop[0] + loop[2]) / 2
                geometry.cap(loop, center: center, at: t, axis: .y, up: 1)
                geometry.cap(loop, center: center, at: -t, axis: .y, up: -1)
            }
        }
        geometry.wall(perimeter, from: -t, to: t, axis: .y, outward: true)
        return geometry
    }

    /// A spur gear with a keyed bore. Tooth flanks approximate an involute with four points a side.
    /// `phase` turns the teeth by a fraction of one tooth pitch, so a mating gear can be set in mesh.
    static func spurGear(teeth: Int, radii: SIMD2<Float>, thickness: Float, boreFraction: Float, phase: Float = 0) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let count = Float(teeth), half = thickness / 2
        let pitch = 2 * Float.pi / count
        let pitchRadius = count / (count + 2), rootRadius = (count - 2.5) / (count + 2)
        // (radius as a fraction of the outside radius, angle from the tooth center as a fraction of the pitch)
        let flank: [(Float, Float)] = [(rootRadius, 0.31), (pitchRadius, 0.25), ((pitchRadius + 1) / 2, 0.185), (1, 0.115)]
        // The web circle sits just inside the tooth roots, with one point under every outline point.
        // Tooth flanks face away from parts of the bore, so the band to the bore is filled from this circle instead.
        var outline: [SIMD2<Float>] = [], web: [SIMD2<Float>] = []
        func add(_ radius: Float, _ angle: Float) {
            let direction = SIMD2<Float>(radii.x * cos(angle), radii.y * sin(angle))
            outline.append(direction * radius)
            web.append(direction * (0.94 * rootRadius))
        }
        for tooth in 0..<teeth {
            let center = (Float(tooth) + phase) * pitch
            for (radius, offset) in flank { add(radius, center - offset * pitch) }
            add(1, center)
            for (radius, offset) in flank.reversed() { add(radius, center + offset * pitch) }
            add(rootRadius, center + 0.5 * pitch)
        }
        // Bore with a keyway: a quarter of the bore wide, cut toward +Z.
        let keyHalfWidth = 0.25 * boreFraction, keyTop = 1.22 * boreFraction
        let start = Float.pi / 2 + asin(0.25)
        var bore: [SIMD2<Float>] = []
        for step in 0...40 {
            let angle = start + Float(step) * (2 * .pi - 2 * asin(0.25)) / 40
            bore.append([boreFraction * cos(angle), boreFraction * sin(angle)])
        }
        bore += [[keyHalfWidth, keyTop], [-keyHalfWidth, keyTop]]
        bore = bore.map { $0 * radii }
        for side: Float in [-1, 1] {
            let facing = SIMD3<Float>(0, side, 0)
            func lifted(_ point: SIMD2<Float>) -> SIMD3<Float> { [point.x, side * half, point.y] }
            for index in outline.indices {
                let next = (index + 1) % outline.count
                geometry.flatTriangle(lifted(outline[index]), lifted(outline[next]), lifted(web[index]), facing: facing)
                geometry.flatTriangle(lifted(outline[next]), lifted(web[next]), lifted(web[index]), facing: facing)
            }
            geometry.ring(outer: web, at: side * half, inner: bore, at: side * half, center: .zero, axis: .y, up: side)
        }
        geometry.wall(outline, from: -half, to: half, axis: .y, outward: true)
        geometry.wall(bore, from: -half, to: half, axis: .y, outward: false)
        return geometry
    }

    /// A hexagon with across-corners along X and across-flats along Z, each side split so chamfers shade evenly.
    private static func hexagon(_ shape: CADShape) -> [SIMD2<Float>] {
        let corners: [SIMD2<Float>] = (0..<6).map {
            let angle = Float($0) * .pi / 3
            return [shape.dimensions.x / 2 * cos(angle), shape.dimensions.z / 2 / 0.8660254 * sin(angle)]
        }
        return (0..<6).flatMap { index in
            (0..<6).map { step in simd_mix(corners[index], corners[(index + 1) % 6], SIMD2<Float>(repeating: Float(step) / 6)) }
        }
    }

    /// A hex-head bolt, head up. The lower shank carries thread grooves.
    private static func hexBolt(_ shape: CADShape) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let flat = shape.hexFlatRadius, shank = (shape.featureDiameter ?? flat) / 2
        let top = shape.dimensions.y / 2, tip = -top
        let underHead = top - shape.boltHeadHeight
        let chamfer = 0.18 * shape.boltHeadHeight
        let hex = hexagon(shape), crown = circle(0.92 * flat)
        geometry.cap(crown, center: .zero, at: top, axis: .y, up: 1)
        geometry.ring(outer: hex, at: top - chamfer, inner: crown, at: top, center: .zero, axis: .y, up: 1)
        geometry.wall(hex, from: underHead, to: top - chamfer, axis: .y, outward: true)
        geometry.ring(outer: hex, at: underHead, inner: circle(shank), at: underHead, center: .zero, axis: .y, up: -1)
        // Shank, lathed from the pointed tip up to the underside of the head.
        let threadStart = tip + 0.12 * shank
        let threadLength = 0.62 * (underHead - threadStart)
        let turns = max(4, min(22, Int(threadLength / (0.32 * shank))))
        let pitch = threadLength / (Float(turns) + 0.5)
        var profile: [SIMD2<Float>] = [[0, tip], [0.74, tip], [0.86, threadStart]]
        for turn in 0..<turns {
            profile.append([1, threadStart + (Float(turn) + 0.5) * pitch])
            profile.append([0.86, threadStart + Float(turn + 1) * pitch])
        }
        profile += [[1, threadStart + threadLength], [1, underHead]]
        geometry.revolve(profile, radii: [shank, shank], closed: false)
        return geometry
    }

    /// A hex nut, chamfered on both faces, with a plain bore standing in for the thread.
    private static func hexNut(_ shape: CADShape) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let flat = shape.hexFlatRadius, half = shape.dimensions.y / 2
        let chamfer = 0.15 * shape.dimensions.y
        let hex = hexagon(shape), crown = circle(0.92 * flat), hole = circle((shape.featureDiameter ?? flat) / 2)
        for side: Float in [-1, 1] {
            geometry.ring(outer: crown, at: side * half, inner: hole, at: side * half, center: .zero, axis: .y, up: side)
            geometry.ring(outer: hex, at: side * (half - chamfer), inner: crown, at: side * half, center: .zero, axis: .y, up: side)
        }
        geometry.wall(hex, from: -(half - chamfer), to: half - chamfer, axis: .y, outward: true)
        geometry.wall(hole, from: -half, to: half, axis: .y, outward: false)
        return geometry
    }

    /// A pillow block: two mounting feet and an arched housing around a bore that runs along Z.
    private static func bearingBlock(_ shape: CADShape) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let halfWidth = shape.dimensions.x / 2, halfDepth = shape.dimensions.z / 2
        let bottom = -shape.dimensions.y / 2, footTop = bottom + shape.blockFootThickness
        let arch = shape.blockArchRadius
        let center = SIMD2<Float>(0, shape.blockBoreCenterY)
        var column: [SIMD2<Float>] = [[arch, bottom], [arch, footTop]]
        for step in 0...24 {
            let angle = Float(step) * .pi / 24
            column.append(center + SIMD2<Float>(cos(angle), sin(angle)) * arch)
        }
        column += [[-arch, footTop], [-arch, bottom]]
        let bore = circle((shape.featureDiameter ?? arch) / 2, center: center)
        let rightFoot: [SIMD2<Float>] = [[arch, bottom], [halfWidth, bottom], [halfWidth, footTop], [arch, footTop]]
        let leftFoot: [SIMD2<Float>] = [[-halfWidth, bottom], [-arch, bottom], [-arch, footTop], [-halfWidth, footTop]]
        for side: Float in [-1, 1] {
            geometry.ring(outer: column, at: side * halfDepth, inner: bore, at: side * halfDepth, center: center, axis: .z, up: side)
            for foot in [rightFoot, leftFoot] {
                geometry.cap(foot, center: (foot[0] + foot[2]) / 2, at: side * halfDepth, axis: .z, up: side)
            }
        }
        let outline = [leftFoot[0], leftFoot[1], rightFoot[0], rightFoot[1], rightFoot[2]] + column.dropFirst().dropLast() + [leftFoot[3]]
        geometry.wall(outline, from: -halfDepth, to: halfDepth, axis: .z, outward: true)
        geometry.wall(bore, from: -halfDepth, to: halfDepth, axis: .z, outward: false)
        return geometry
    }

    // MARK: Display models

    /// Lathes a profile given in meters as (radius, height), running up the outside. Used by the 3D explorer.
    static func lathe(_ profile: [SIMD2<Float>], closed: Bool = false, smooth: Bool = false) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        geometry.revolve(profile, radii: [1, 1], closed: closed, smooth: smooth)
        return geometry
    }

    /// A connecting rod in the X–Y plane: big end at the bottom, small end `length` above it, thickness along Z.
    static func connectingRod(length: Float, bigRadius: Float, bigBore: Float, smallRadius: Float, smallBore: Float,
                              thickness: Float) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let half = thickness / 2
        let big = SIMD2<Float>(0, -length / 2), small = SIMD2<Float>(0, length / 2)
        let bigNeck = 0.62 * bigRadius, smallNeck = 0.7 * smallRadius
        let bigJoin = atan2((bigRadius * bigRadius - bigNeck * bigNeck).squareRoot(), bigNeck)
        let smallJoin = atan2((smallRadius * smallRadius - smallNeck * smallNeck).squareRoot(), smallNeck)
        func arc(_ center: SIMD2<Float>, _ radius: Float, from: Float, to: Float) -> [SIMD2<Float>] {
            (0...28).map { step in
                let angle = from + (to - from) * Float(step) / 28
                return center + SIMD2<Float>(cos(angle), sin(angle)) * radius
            }
        }
        // Each eye is the outside arc of its circle, closed by the chord where the beam joins.
        let bigEye = arc(big, bigRadius, from: .pi - bigJoin, to: 2 * .pi + bigJoin)
        let smallEye = arc(small, smallRadius, from: -smallJoin, to: .pi + smallJoin)
        let beam = [bigEye[0], bigEye[bigEye.count - 1], smallEye[0], smallEye[smallEye.count - 1]]
        let bigHole = circle(bigBore, center: big), smallHole = circle(smallBore, center: small)
        for side: Float in [-1, 1] {
            geometry.ring(outer: bigEye, at: side * half, inner: bigHole, at: side * half, center: big, axis: .z, up: side)
            geometry.ring(outer: smallEye, at: side * half, inner: smallHole, at: side * half, center: small, axis: .z, up: side)
            geometry.cap(beam, center: .zero, at: side * half, axis: .z, up: side)
        }
        geometry.wall(bigEye + smallEye, from: -half, to: half, axis: .z, outward: true)
        geometry.wall(bigHole, from: -half, to: half, axis: .z, outward: false)
        geometry.wall(smallHole, from: -half, to: half, axis: .z, outward: false)
        return geometry
    }

    /// A flat plate swept along local Y from a loop in the X–Z plane that is visible from `center`.
    static func slab(_ loop: [SIMD2<Float>], center: SIMD2<Float>, thickness: Float) -> CADMeshGeometry {
        var geometry = CADMeshGeometry()
        let half = thickness / 2
        geometry.cap(loop, center: center, at: half, axis: .y, up: 1)
        geometry.cap(loop, center: center, at: -half, axis: .y, up: -1)
        geometry.wall(loop, from: -half, to: half, axis: .y, outward: true)
        return geometry
    }
}
