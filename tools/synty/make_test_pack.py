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
    ("SM_Env_Rock_02", (1.4, 1.0, 1.6), (0.0, 0.5, 0.0)),
    ("SM_Env_Rock_03", (2.6, 1.8, 2.2), (0.0, 0.9, 0.0)),
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


# ---------------------------------------------------------------- skinned humanoids
# Character rig with Synty-style bone names; animations with Mixamo-style names,
# so the test proves retargeting across naming schemes (the real-life case).
SYNTY_RIG = [  # name, parent, local offset
    ("Hips", None, (0, 1.0, 0)), ("Spine_01", "Hips", (0, 0.12, 0)), ("Spine_02", "Spine_01", (0, 0.12, 0)),
    ("Spine_03", "Spine_02", (0, 0.12, 0)), ("Neck", "Spine_03", (0, 0.15, 0)), ("Head", "Neck", (0, 0.12, 0)),
    ("Clavicle_L", "Spine_03", (0.08, 0.1, 0)), ("Shoulder_L", "Clavicle_L", (0.12, 0, 0)), ("Elbow_L", "Shoulder_L", (0.28, 0, 0)), ("Hand_L", "Elbow_L", (0.26, 0, 0)),
    ("Clavicle_R", "Spine_03", (-0.08, 0.1, 0)), ("Shoulder_R", "Clavicle_R", (-0.12, 0, 0)), ("Elbow_R", "Shoulder_R", (-0.28, 0, 0)), ("Hand_R", "Elbow_R", (-0.26, 0, 0)),
    ("UpperLeg_L", "Hips", (0.1, -0.05, 0)), ("LowerLeg_L", "UpperLeg_L", (0, -0.45, 0)), ("Ankle_L", "LowerLeg_L", (0, -0.45, 0)), ("Ball_L", "Ankle_L", (0, -0.05, 0.12)),
    ("UpperLeg_R", "Hips", (-0.1, -0.05, 0)), ("LowerLeg_R", "UpperLeg_R", (0, -0.45, 0)), ("Ankle_R", "LowerLeg_R", (0, -0.45, 0)), ("Ball_R", "Ankle_R", (0, -0.05, 0.12)),
]
MIXAMO = {"Hips": "mixamorig:Hips", "Spine_01": "mixamorig:Spine", "Spine_02": "mixamorig:Spine1", "Spine_03": "mixamorig:Spine2",
          "Neck": "mixamorig:Neck", "Head": "mixamorig:Head", "Clavicle_L": "mixamorig:LeftShoulder", "Shoulder_L": "mixamorig:LeftArm",
          "Elbow_L": "mixamorig:LeftForeArm", "Hand_L": "mixamorig:LeftHand", "Clavicle_R": "mixamorig:RightShoulder",
          "Shoulder_R": "mixamorig:RightArm", "Elbow_R": "mixamorig:RightForeArm", "Hand_R": "mixamorig:RightHand",
          "UpperLeg_L": "mixamorig:LeftUpLeg", "LowerLeg_L": "mixamorig:LeftLeg", "Ankle_L": "mixamorig:LeftFoot", "Ball_L": "mixamorig:LeftToeBase",
          "UpperLeg_R": "mixamorig:RightUpLeg", "LowerLeg_R": "mixamorig:RightLeg", "Ankle_R": "mixamorig:RightFoot", "Ball_R": "mixamorig:RightToeBase"}


def quat_x(deg):
    import math
    h = math.radians(deg) / 2
    return (math.sin(h), 0.0, 0.0, math.cos(h))


def skinned_gltf(names, anim=None, mesh=True):
    """names: rig bone -> file bone name. anim: None | (name, {rig_bone: [(t, quat)]}, hips_travel_m)."""
    idx = {b[0]: i for i, b in enumerate(SYNTY_RIG)}
    glob = {}
    for b, parent, off in SYNTY_RIG:
        base = glob[parent] if parent else (0, 0, 0)
        glob[b] = tuple(base[k] + off[k] for k in range(3))
    nodes = []
    for b, parent, off in SYNTY_RIG:
        n = {"name": names[b], "translation": list(off)}
        kids = [idx[c] for c, p, _o in SYNTY_RIG if p == b]
        if kids:
            n["children"] = kids
        nodes.append(n)
    buf = b""
    views, accs = [], []

    def add(data, ctype, count, typ, extra=None):
        nonlocal buf
        while len(buf) % 4:
            buf += b"\0"
        views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data)})
        buf += data
        a = {"bufferView": len(views) - 1, "componentType": ctype, "count": count, "type": typ}
        if extra:
            a.update(extra)
        accs.append(a)
        return len(accs) - 1

    jcount = len(SYNTY_RIG)
    ibm = b""
    for b, _p, _o in SYNTY_RIG:
        x, y, z = glob[b]
        ibm += struct.pack("<16f", 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -x, -y, -z, 1)
    skin = {"joints": list(range(jcount)), "inverseBindMatrices": add(ibm, 5126, jcount, "MAT4"), "skeleton": 0}
    root_children = [0]
    meshes = []
    if mesh:
        pos, jnt, wgt, ind = [], [], [], []
        for j, (b, _p, _o) in enumerate(SYNTY_RIG):
            cx, cy, cz = glob[b]
            base = len(pos)
            for dx in (-0.05, 0.05):
                for dy in (-0.05, 0.05):
                    for dz in (-0.05, 0.05):
                        pos.append((cx + dx, cy + dy, cz + dz))
                        jnt.append((j, 0, 0, 0))
                        wgt.append((1.0, 0.0, 0.0, 0.0))
            for a_, b_, c_ in [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]:
                ind += [base + a_, base + b_, base + c_]
        lo = [min(p[k] for p in pos) for k in range(3)]
        hi = [max(p[k] for p in pos) for k in range(3)]
        pa = add(b"".join(struct.pack("<3f", *p) for p in pos), 5126, len(pos), "VEC3", {"min": lo, "max": hi})
        ja = add(b"".join(struct.pack("<4H", *j) for j in jnt), 5123, len(jnt), "VEC4")
        wa = add(b"".join(struct.pack("<4f", *w) for w in wgt), 5126, len(wgt), "VEC4")
        ia = add(b"".join(struct.pack("<H", i) for i in ind), 5123, len(ind), "SCALAR")
        meshes = [{"name": "Body", "primitives": [{"attributes": {"POSITION": pa, "JOINTS_0": ja, "WEIGHTS_0": wa}, "indices": ia, "material": 0}]}]
        nodes.append({"name": "SK_Body", "mesh": 0, "skin": 0})
        root_children.append(len(nodes) - 1)
    nodes.append({"name": "Armature", "children": root_children})
    g = {"asset": {"version": "2.0", "generator": "genesis-ark make_test_pack"}, "scene": 0, "scenes": [{"nodes": [len(nodes) - 1]}],
         "nodes": nodes, "skins": [skin], "materials": [{"name": "PolygonSciFi_Mat_01_A"}]}
    if meshes:
        g["meshes"] = meshes
    else:
        # Animation-only files still need a skinned mesh for some importers; keep a tiny one.
        g["meshes"] = []
    if anim:
        name, tracks, travel = anim
        samplers, channels = [], []
        for bone, keys in tracks.items():
            t = add(b"".join(struct.pack("<f", k[0]) for k in keys), 5126, len(keys), "SCALAR", {"min": [keys[0][0]], "max": [keys[-1][0]]})
            v = add(b"".join(struct.pack("<4f", *k[1]) for k in keys), 5126, len(keys), "VEC4")
            samplers.append({"input": t, "output": v, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": idx[bone], "path": "rotation"}})
        if travel:
            ts = [0.0, 0.5, 1.0]
            t = add(b"".join(struct.pack("<f", x) for x in ts), 5126, 3, "SCALAR", {"min": [0.0], "max": [1.0]})
            v = add(b"".join(struct.pack("<3f", 0, 1.0, travel * x) for x in ts), 5126, 3, "VEC3")
            samplers.append({"input": t, "output": v, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": idx["Hips"], "path": "translation"}})
        g["animations"] = [{"name": name, "samplers": samplers, "channels": channels}]
    g["buffers"] = [{"byteLength": len(buf), "uri": "data:application/octet-stream;base64," + base64.b64encode(buf).decode()}]
    g["bufferViews"] = views
    g["accessors"] = accs
    return json.dumps(g).encode()


def character_entries(prefix):
    synty = {b[0]: b[0] for b in SYNTY_RIG}
    swing = lambda a: [(0.0, quat_x(a)), (0.5, quat_x(-a)), (1.0, quat_x(a))]
    walk = ("Walk", {"UpperLeg_L": swing(30), "UpperLeg_R": swing(-30)}, 1.5)    # root motion: 1.5 m per cycle
    run = ("Run", {"UpperLeg_L": swing(50), "UpperLeg_R": swing(-50)}, 4.5)
    idle = ("Idle", {"Spine_01": [(0.0, quat_x(0)), (1.0, quat_x(3)), (2.0, quat_x(0))]}, 0)
    out = [(prefix + "Characters/SK_Chr_Captain_01.gltf", skinned_gltf(synty))]
    for a in (walk, run, idle):
        out.append((prefix + "Animations/A_%s_01.gltf" % a[0], skinned_gltf(MIXAMO, a, mesh=True)))
    return out


def main() -> int:
    out = sys.argv[1] if len(sys.argv) > 1 else "TestSyntyPack.unitypackage"
    entries = []
    for name, size, center in MODELS:
        entries.append(("Assets/PolygonSciFiSpace/Models/%s.gltf" % name, box_gltf(name, size, center)))
        entries.append(("Assets/PolygonSciFiSpace/Prefabs/%s.prefab" % name, b"%YAML 1.1 fake prefab"))
    entries.append(("Assets/PolygonSciFiSpace/Textures/" + TEXTURE, png(64, 64)))
    entries += character_entries("Assets/PolygonSciFiSpace/")
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
