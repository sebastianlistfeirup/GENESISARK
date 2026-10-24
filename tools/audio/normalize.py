#!/usr/bin/env python3
"""Loudness-normalise the generated audio to the bus targets (docs/PRODUCTION_PLAN.md §4.2):
ambience -28, music -24, SFX -20, UI -22, voice -18 LUFS, true peak -2 dBTP. Wildlife calls and
the leviathan (sparse positional one-shots on the Ambience bus) sit at -24. Originals are kept
in assets/audio/raw/ (local) and every run starts from them, so it is repeatable.

Loops (AudioService.loops: amb_*, music_* except endings, *_loop, sfx_thruster) are made
seam-free (D-064): music first loses its leading/trailing silence, then every loop gets its
tail crossfaded over its head (equal power; 1.5 s for beds, 0.4 s for short loops, 4 s for
music), so the last sample runs straight into the first and the level matches across the
loop point. Loops are written as Ogg Vorbis (<cue>.ogg, which AudioService prefers over
.mp3): MP3 encoder delay/padding put a gap/click back at the loop point (measured), Vorbis
keeps the length sample-exact. Needs ffmpeg (pip install imageio-ffmpeg).
  python tools/audio/normalize.py [--only cue1,cue2]"""
import pathlib, shutil, subprocess, sys, tempfile, wave
import imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()
ROOT = pathlib.Path(__file__).resolve().parents[2]
RAW = ROOT / "assets" / "audio" / "raw"


def target(name: str, vo: bool) -> float:
    if vo: return -18.0
    if name.startswith(("sfx_wild_", "sfx_leviathan")): return -24.0
    if name.startswith("amb_"): return -28.0
    if name.startswith(("music_", "stinger_")): return -24.0
    if name.startswith("ui_"): return -22.0
    return -20.0


def loops(name: str) -> bool:
    if name.startswith("music_ending_"):
        return False
    return name.startswith(("amb_", "music_")) or name.endswith("_loop") or name == "sfx_thruster"


def xfade_s(name: str, dur: float) -> float:
    if name.startswith("music_"):
        return min(4.0, dur * 0.1)
    return min(1.5 if dur >= 15.0 else 0.4, dur * 0.1)


def run(args: list) -> bool:
    return subprocess.run([FF, "-hide_banner", "-loglevel", "error", "-y"] + args).returncode == 0


def wav_seconds(p: pathlib.Path) -> float:
    with wave.open(str(p)) as w:
        return w.getnframes() / float(w.getframerate())


def process(raw: pathlib.Path, dst: pathlib.Path, t: float, name: str) -> bool:
    tmp = dst.with_suffix(".tmp.mp3")
    if name.startswith(("scene_", "nav_")) or dst.parent.name == "vo":
        ok = run(["-i", str(raw), "-af", f"loudnorm=I={t}:TP=-2:LRA=11", "-ar", "44100", "-b:a", "160k", str(tmp)])
    elif not loops(name):
        # One-shots end on a short fade (10 % of the length, at most 0.3 s): some
        # generations stop mid-sound and would click (D-064).
        with tempfile.TemporaryDirectory() as td:
            mid = pathlib.Path(td) / "mid.wav"
            if not run(["-i", str(raw), "-af", f"loudnorm=I={t}:TP=-2:LRA=11", "-ar", "44100", "-c:a", "pcm_s16le", str(mid)]):
                return False
            fade = min(0.3, wav_seconds(mid) * 0.1)
            ok = run(["-i", str(mid), "-af", f"areverse,afade=t=in:d={fade:.3f},areverse", "-ar", "44100", "-b:a", "160k", str(tmp)])
    else:
        with tempfile.TemporaryDirectory() as td:
            mid = pathlib.Path(td) / "mid.wav"
            chain = f"loudnorm=I={t}:TP=-2:LRA=11"
            if name.startswith("music_"):
                trim = "silenceremove=start_periods=1:start_threshold=-60dB"
                chain = f"{trim},areverse,{trim},areverse,{chain}"
            if not run(["-i", str(raw), "-af", chain, "-ar", "44100", "-c:a", "pcm_s16le", str(mid)]):
                return False
            dur = wav_seconds(mid)
            x = xfade_s(name, dur)
            body = dur - x
            graph = (f"[0]atrim=0:{body:.4f},asetpts=N/SR/TB,afade=t=in:d={x:.4f}:curve=qsin[a];"
                     f"[0]atrim={body:.4f},asetpts=N/SR/TB,afade=t=out:d={x:.4f}:curve=qsin,apad=whole_dur={body:.4f}[b];"
                     f"[a][b]amix=inputs=2:normalize=0:duration=first[o]")
            ogg = dst.with_suffix(".ogg")
            ok = run(["-i", str(mid), "-filter_complex", graph, "-map", "[o]", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "6", str(ogg)])
            if ok:
                for old in (dst, dst.with_name(dst.name + ".import")):
                    old.unlink(missing_ok=True)  # the .ogg replaces the seamed .mp3
            return ok
    if ok:
        tmp.replace(dst)
    return ok


def main() -> None:
    args = sys.argv[1:]
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else set()
    for d, vo in ((ROOT / "assets/audio/final", False), (ROOT / "assets/audio/vo", True)):
        names = {f.name for f in d.glob("*.mp3") if not f.name.endswith(".tmp.mp3")}
        names |= {f.name for f in (RAW / d.name).glob("*.mp3")}  # loops live on as .ogg only
        for nm in sorted(names):
            f = d / nm
            if only and f.stem not in only:
                continue
            raw = RAW / d.name / f.name
            raw.parent.mkdir(parents=True, exist_ok=True)
            if not raw.exists():
                shutil.copy2(f, raw)
            t = target(f.stem, vo)
            if process(raw, f, t, f.stem):
                print("ok", f.stem + (".ogg" if loops(f.stem) and not vo else ".mp3"), t)
            else:
                print("FAIL", f.name)


if __name__ == "__main__":
    main()
