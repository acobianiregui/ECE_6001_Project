"""Independent Wavefront OBJ geometry audit; no application source is modified.
Usage: python3 work/cad_obj_review.py PATH.obj
"""
from __future__ import annotations
from collections import Counter
import math
from itertools import product
import sys
from pathlib import Path


def subtract(a, b): return tuple(x-y for x, y in zip(a, b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def dot(a, b): return sum(x*y for x, y in zip(a, b))


def audit(path: Path):
    vertices = []
    normals = []
    objects = {}
    name = 'unnamed'
    for line in path.read_text().splitlines():
        fields = line.split()
        if not fields or fields[0].startswith('#'): continue
        token, args = fields[0], fields[1:]
        if token in ('v', 'vn'):
            value = tuple(map(float, args[:3]))
            assert len(value) == 3 and all(math.isfinite(x) for x in value), line
            (vertices if token == 'v' else normals).append(value)
        elif token in ('o', 'g'):
            name = ' '.join(args)
            objects.setdefault(name, [])
        elif token == 'f':
            assert len(args) >= 3, line
            parsed = []
            for item in args:
                parts = item.split('/')
                index = int(parts[0])
                assert index > 0, 'Expected positive global OBJ indices'
                normal = int(parts[2]) if len(parts) > 2 and parts[2] else None
                parsed.append((index - 1, normal - 1 if normal is not None else None))
            for i in range(1, len(parsed)-1):
                objects.setdefault(name, []).append((parsed[0], parsed[i], parsed[i+1]))
    assert vertices and any(objects.values()), 'Expected a nonempty mesh'
    for normal in normals:
        assert abs(dot(normal, normal) - 1) < 0.002, f'Non-unit normal {normal}'
    result = {}
    for object_name, faces in objects.items():
        if not faces: continue
        edges = Counter()
        directed = Counter()
        volume = 0.0
        welded_vertices = set()
        buckets = {}
        welded_positions = []
        tolerance = 1e-7
        def weld(point):
            cell = tuple(math.floor(value / tolerance) for value in point)
            for shift in product((-1, 0, 1), repeat=3):
                neighbor = tuple(c+s for c,s in zip(cell,shift))
                for index in buckets.get(neighbor, []):
                    candidate = welded_positions[index]
                    if sum((a-b)**2 for a,b in zip(point,candidate)) <= tolerance*tolerance:
                        return index
            index = len(welded_positions)
            welded_positions.append(point)
            buckets.setdefault(cell, []).append(index)
            return index
        surface = 0.0
        for face in faces:
            for vi, ni in face:
                assert 0 <= vi < len(vertices), f'Invalid vertex index in {object_name}'
                assert ni is None or 0 <= ni < len(normals), f'Invalid normal index in {object_name}'
            a, b, c = [vertices[vi] for vi, _ in face]
            face_normal = cross(subtract(b,a), subtract(c,a))
            area2 = math.sqrt(dot(face_normal, face_normal))
            assert area2 > 1e-12, f'Degenerate face in {object_name}'
            surface += area2/2
            volume += dot(a, cross(b,c))/6
            for _, ni in face:
                if ni is not None:
                    assert dot(face_normal, normals[ni]) > -1e-9, f'Winding opposes a vertex normal in {object_name}'
            welded = [weld(point) for point in (a,b,c)]
            welded_vertices.update(welded)
            for u,v in zip(welded, welded[1:]+welded[:1]):
                edges[tuple(sorted((u,v)))] += 1
                directed[(u,v)] += 1
        bad_edges = [edge for edge, count in edges.items() if count != 2]
        bad_direction = [edge for edge in edges if directed[edge] != 1 or directed[(edge[1],edge[0])] != 1]
        assert not bad_edges, f'Non-manifold/boundary edges in {object_name}: {len(bad_edges)}'
        assert not bad_direction, f'Inconsistent shared-edge winding in {object_name}: {len(bad_direction)}'
        assert volume > 0, f'Nonpositive signed solid volume in {object_name}: {volume}'
        result[object_name] = {'triangles':len(faces), 'volume':volume, 'surface_area':surface, 'euler_characteristic': len(welded_vertices) - len(edges) + len(faces)}
    print(f'PASS {path.name}: {len(vertices)} vertices, {len(normals)} normals, {len(result)} closed consistently wound solids')
    return result

if __name__ == '__main__':
    for arg in sys.argv[1:]: print(audit(Path(arg)))
