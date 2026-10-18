#!/usr/bin/env python3
"""Builds a small, licence-free FAKE Synty pack for testing the import pipeline
without the purchased files: a .unitypackage with the same layout Synty uses
(<guid>/asset + <guid>/pathname), glTF box models named like Synty meshes, an
atlas texture, and Unity-only junk (.prefab/.mat/.meta/.cs) that must be skipped.

One model is authored in centimetres (100x too big) and one has an off-centre
pivot, so the wrapper builder's unit fix and re-centring are exercised.

  python3 tools/synty/make_test_pack.py <out.unitypackage>
"""
import base64, io, json, os, struct, sys, tarfile, uuid, zlib

# name, size (x, y, z) in the file's units, pivot offset (where the box sits relative to origin)
MODELS = [
    ("SM_Env_Floor_01", (4.0, 0.2, 4.0), (0.0, -0.1, 0.0)),
    ("SM_Env_Wall_01", (4.0, 3.6, 0.3), (0.0, 1.8, 0.0)),
    ("SM_Prop_Console_01", (1.2, 1.4, 0.8), (0.0, 0.7, 0.0)),
    ("SM_Prop_Crate_01", (120.0, 120.0, 120.0), (0.0, 60.0, 0.0)),      # centimetres
    ("SM_Bld_Habitat_Module_01", (9.0, 3.4, 7.0), (4.5, 1.7, 3.5)),     # pivot in a corner
    ("SM_Prop_Solar_Panel_01", (4.0, 2.2, 3.0), (0.0, 1.1, 0.0)),
    ("SM_Veh_Lander_01", (6.0, 4.5, 6.0), (0.0, 2.25, 0.0)),
    ("SM_Env_Rock_01", (2.0, 1.4, 1.8), (0.0, 0.7, 0.0)),
    ("SM_Env_Tree_Alien_01", (3.0, 7.0, 3.0), (0.0, 3.5, 0.0)),
]
TEXTURE = "PolygonSciFiSpace_Texture_01_A.png"


def box_gltf(name, size, center):
    sx, sy, sz = (s / 2 for s in size)
    cx, cy, cz = center
    faces = [((1, 0, 0), [(1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1)]),
             ((-1, 0, 0), [(-1, -1, 1), (-1, 1, 1), (-1, 1, -1), (-1, -1, -1)]),
             ((0, 1, 0), [(-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1)]),
             ((0, -1, 0), [(-1, -1, 1), (-1, -1, -1), (1, -1, -1), (1, -1, 1)]),
             ((0, 0, 1), [(1, -1, 1), (1, 1, 1), (-1, 1, 1), (-1, -1, 1)]),
             ((0, 0, -1), [(-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)])]
    pos, nrm, uv, idx = [], [], [], []
    for n, quad in faces:
        base = len(pos)
        for i, (x, y, z) in enumerate(quad):
            pos.append((cx + x * sx, cy + y * sy, cz + z * sz))
            nrm.append(n)
            uv.append(((0.1, 0.1), (0.1, 0.2), (0.2, 0.2), (0.2, 0.1))[i])  # a swatch in the atlas
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    buf = b"".join(struct.pack("<3f", *p) for p in pos) + b"".join(struct.pack("<3f", *n) for n in nrm)
    buf += b"".join(struct.pack("<2f", *t) for t in uv) + b"".join(struct.pack("<H", i) for i in idx)
    n = len(pos)
    lo = [min(p[k] for p in pos) for k in range(3)]
    hi = [max(p[k] for p in pos) for k in range(3)]
    g = {
        "asset": {"version": "2.0", "generator": "genesis-ark make_test_pack"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        # Like many Synty FBX imports: a material without the atlas attached.
        "materials": [{"name": "PolygonSciFi_Mat_01_A", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 0.9}}],
        "buffers": [{"byteLength": len(buf), "uri": "data:application/octet-stream;base64," + base64.b64encode(buf).decode()}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": n * 12}, {"buffer": 0, "byteOffset": n * 12, "byteLength": n * 12},
                        {"buffer": 0, "byteOffset": n * 24, "byteLength": n * 8}, {"buffer": 0, "byteOffset": n * 32, "byteLength": len(idx) * 2}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3", "min": lo, "max": hi},
                      {"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"},
                      {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC2"},
                      {"bufferView": 3, "componentType": 5123, "count": len(idx), "type": "SCALAR"}],
    }
    return json.dumps(g).encode()


def png(w, h):
    """Tiny RGB atlas: four colour swatches."""
    rows = []
    for y in range(h):
        row = b"\x00"
        for x in range(w):
            c = [(95, 174, 110), (210, 91, 76), (232, 163, 61), (127, 214, 208)][(x * 2 // w) + 2 * (y * 2 // h)]
            row += bytes(c)
        rows.append(row)
    raw = zlib.compress(b"".join(rows))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", raw) + chunk(b"IEND", b"")


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "TestSyntyPack.unitypackage"
    entries = []
    for name, size, center in MODELS:
        entries.append(("Assets/PolygonSciFiSpace/Models/%s.gltf" % name, box_gltf(name, size, center)))
        entries.append(("Assets/PolygonSciFiSpace/Prefabs/%s.prefab" % name, b"%YAML 1.1 fake prefab"))
    entries.append(("Assets/PolygonSciFiSpace/Textures/" + TEXTURE, png(64, 64)))
    entries.append(("Assets/PolygonSciFiSpace/Materials/PolygonSciFi_Mat_01_A.mat", b"%YAML 1.1 fake material"))
    entries.append(("Assets/PolygonSciFiSpace/Scripts/Rotate.cs", b"// unity script"))
    with tarfile.open(out, "w:gz") as tar:
        def add(path, data):
            ti = tarfile.TarInfo(path)
            ti.size = len(data)
            tar.addfile(ti, io.BytesIO(data))
        for path, data in entries:
            g = uuid.uuid5(uuid.NAMESPACE_URL, path).hex
            add(g + "/asset", data)
            add(g + "/pathname", (path + "\n00\n").encode())
            add(g + "/asset.meta", b"fileFormatVersion: 2\n")
        add(uuid.uuid4().hex + "/pathname", b"Assets/PolygonSciFiSpace\n")  # a folder entry: no asset
    print("wrote", out, len(MODELS), "models")
    return 0


if __name__ == "__main__":
    sys.exit(main())
