#!/usr/bin/env python3
"""Unpacks a purchased Synty pack into the quarantine folder (never committed).

Accepts a Unity package (.unitypackage), a zip (the "Source Files"/FBX download)
or an already extracted folder. Only models and textures are kept; Unity-only
files (.prefab, .mat, .meta, .asset, .controller, scripts) are skipped.

  python3 tools/synty/unpack.py <package|zip|folder> [--pack NAME] [--root assets/quarantine]

Result: assets/quarantine/<pack>/... with the pack's own folder layout, plus
assets/quarantine/<pack>/manifest.json (path, size, sha256 per file). The
quarantine folder has a .gdignore so Godot does not import thousands of files,
and .gitignore keeps it out of git (bible p.23: raw packs are never committed).
"""
import argparse, hashlib, io, json, os, re, shutil, sys, tarfile, zipfile

KEEP = {".fbx", ".glb", ".gltf", ".bin", ".obj", ".png", ".tga", ".jpg", ".jpeg", ".psd", ".tif", ".tiff", ".exr", ".wav", ".ogg"}
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def slug(name: str) -> str:
    s = re.sub(r"\.(unitypackage|zip)$", "", os.path.basename(name.rstrip("/\\")), flags=re.I)
    s = re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_")
    return s or "pack"


def safe_rel(path: str) -> str:
    """Normalise a pack-internal path and refuse anything escaping the target."""
    p = path.replace("\\", "/").lstrip("/")
    if p.startswith("Assets/"):
        p = p[len("Assets/"):]
    parts = [x for x in p.split("/") if x not in ("", ".")]
    if any(x == ".." for x in parts):
        raise ValueError("unsafe path in package: " + path)
    return "/".join(parts)


def from_unitypackage(src: str):
    """A .unitypackage is a gzip tar of <guid>/{asset, pathname, asset.meta}."""
    with tarfile.open(src, "r:gz") as tar:
        members = {m.name: m for m in tar.getmembers() if m.isfile()}
        for name, m in members.items():
            if not name.endswith("/pathname"):
                continue
            guid = name[: -len("/pathname")]
            asset = members.get(guid + "/asset")
            if asset is None:
                continue  # folders have no asset
            rel = tar.extractfile(m).read().decode("utf-8", "replace").splitlines()[0].strip()
            yield rel, lambda a=asset: tar.extractfile(a).read()


def from_zip(src: str):
    with zipfile.ZipFile(src) as z:
        for info in z.infolist():
            if not info.is_dir():
                yield info.filename, lambda i=info: z.read(i)


def from_folder(src: str):
    for base, _dirs, files in os.walk(src):
        for f in files:
            full = os.path.join(base, f)
            yield os.path.relpath(full, src), lambda p=full: open(p, "rb").read()


def unpack(src: str, pack: str, root: str) -> dict:
    if os.path.isdir(src):
        items = from_folder(src)
    elif src.lower().endswith(".zip"):
        items = from_zip(src)
    elif src.lower().endswith(".unitypackage"):
        items = from_unitypackage(src)
    else:
        raise SystemExit("unknown package type: " + src)
    qroot = os.path.join(root, "assets", "quarantine")
    os.makedirs(qroot, exist_ok=True)
    open(os.path.join(qroot, ".gdignore"), "a").close()
    out = os.path.join(qroot, pack)
    files, skipped = [], 0
    for rel, read in items:
        ext = os.path.splitext(rel)[1].lower()
        if ext not in KEEP:
            skipped += 1
            continue
        rel = safe_rel(rel)
        data = read()
        dst = os.path.join(out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as fh:
            fh.write(data)
        files.append({"path": rel, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    files.sort(key=lambda f: f["path"])
    manifest = {"pack": pack, "source": os.path.basename(src), "files": files,
                "models": sum(1 for f in files if os.path.splitext(f["path"])[1].lower() in (".fbx", ".glb", ".gltf", ".obj")),
                "textures": sum(1 for f in files if os.path.splitext(f["path"])[1].lower() in (".png", ".tga", ".jpg", ".jpeg", ".psd", ".tif", ".tiff", ".exr")),
                "skipped_unity_files": skipped}
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1)
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("source")
    ap.add_argument("--pack", help="folder name in quarantine (default: from the file name)")
    ap.add_argument("--root", default=ROOT, help="project root (default: this repo)")
    a = ap.parse_args()
    m = unpack(a.source, a.pack or slug(a.source), a.root)
    print("unpacked %s: %d models, %d textures (%d Unity-only files skipped) -> assets/quarantine/%s/"
          % (m["source"], m["models"], m["textures"], m["skipped_unity_files"], m["pack"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
