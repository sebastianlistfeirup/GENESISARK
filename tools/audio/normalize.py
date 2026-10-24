#!/usr/bin/env python3
"""Loudness-normalise the generated audio to the bus targets (docs/PRODUCTION_PLAN.md §4.2):
ambience -28, music -24, SFX -20, UI -22, voice -18 LUFS, true peak -2 dBTP. Originals are kept
in assets/audio/raw/ (local). Needs ffmpeg (pip install imageio-ffmpeg).
  python tools/audio/normalize.py"""
import pathlib, shutil, subprocess
import imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()
ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "assets" / "audio" / "raw"


def target(name: str, vo: bool) -> float:
    if vo: return -18.0
    if name.startswith("amb_"): return -28.0
    if name.startswith(("music_", "stinger_")): return -24.0
    if name.startswith("ui_"): return -22.0
    return -20.0


for d, vo in ((ROOT / "assets/audio/final", False), (ROOT / "assets/audio/vo", True)):
    for f in sorted(d.glob("*.mp3")):
        raw = RAW / d.name / f.name
        raw.parent.mkdir(parents=True, exist_ok=True)
        if not raw.exists():
            shutil.copy2(f, raw)
        t = target(f.stem, vo)
        tmp = f.with_suffix(".tmp.mp3")
        r = subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y", "-i", str(raw),
                            "-af", f"loudnorm=I={t}:TP=-2:LRA=11", "-ar", "44100", "-b:a", "160k", str(tmp)])
        if r.returncode == 0:
            tmp.replace(f)
            print("ok", f.name, t)
