#!/usr/bin/env python3
"""Generate the game's sound cues with ElevenLabs Sound Effects from docs/AUDIO_LEDGER.csv.

Each ledger row whose tool mentions ElevenLabs SFX gets one generation from its prompt,
saved as assets/audio/final/<cue_id>.mp3 (AudioService picks finals up by name). Beds
(amb_*, *_loop, sfx_thruster) are requested as seamless loops. The key is read from the
owner's .env and never printed; every call is logged to tools/audio/eleven_log.jsonl
(no key). Skips cues that already have a final file unless --force.
  python tools/audio/eleven_sfx.py [--only amb_space,ui_click] [--force] [--dry]
"""
import csv, json, pathlib, sys, time, urllib.request, urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENV = pathlib.Path(r"C:\Users\compu\Documents\REALMREND Crowns at War\.env")
OUT = ROOT / "assets" / "audio" / "final"
LOG = pathlib.Path(__file__).with_name("eleven_log.jsonl")
MAX_S = 30.0


def key() -> str:
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("ELEVENLABS_API_KEY") and "=" in line:
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("ELEVENLABS_API_KEY not found")


def loops(cue: str) -> bool:
    if cue.startswith("music_ending_"):
        return False
    return cue.startswith("amb_") or cue.endswith("_loop") or cue == "sfx_thruster"


def generate(k: str, cue: str, prompt: str, seconds: float) -> bytes:
    body = {"text": prompt, "duration_seconds": max(0.5, min(MAX_S, seconds)), "prompt_influence": 0.45,
            "model_id": "eleven_text_to_sound_v2"}
    if loops(cue):
        body["loop"] = True
    req = urllib.request.Request("https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128",
                                 data=json.dumps(body).encode(), method="POST",
                                 headers={"xi-api-key": k, "Content-Type": "application/json", "Accept": "audio/mpeg"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def main() -> None:
    args = sys.argv[1:]
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else set()
    force, dry = "--force" in args, "--dry" in args
    rows = list(csv.DictReader(open(ROOT / "docs" / "AUDIO_LEDGER.csv", encoding="utf-8")))
    OUT.mkdir(parents=True, exist_ok=True)
    k = None if dry else key()
    done = 0
    for r in rows:
        cue, tool, prompt = r["cue_id"], r["tool"], r["prompt"].strip()
        if only and cue not in only:
            continue
        if "ElevenLabs" not in tool or "Music" in tool or not prompt or prompt.startswith("("):
            continue
        dst = OUT / (cue + ".mp3")
        if dst.exists() and not force:
            continue
        secs = float(r["length_s"] or 2)
        if dry:
            print("would generate", cue, secs, "s", "loop" if loops(cue) else "")
            continue
        try:
            data = generate(k, cue, prompt, secs)
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode(errors="replace")
            print("FAIL", cue, e.code, msg)
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps({"cue": cue, "status": e.code, "error": msg, "t": time.time()}) + "\n")
            if e.code in (401, 402, 429):
                break
            continue
        dst.write_bytes(data)
        done += 1
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"cue": cue, "bytes": len(data), "seconds": min(MAX_S, secs), "loop": loops(cue), "t": time.time()}) + "\n")
        print("ok", cue, len(data))
    print("generated", done)


if __name__ == "__main__":
    main()
