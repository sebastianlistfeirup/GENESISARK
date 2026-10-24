#!/usr/bin/env python3
"""Generate the score with ElevenLabs Music from docs/AUDIO_LEDGER.csv (music_*, stinger_*).
One shared musical identity: every prompt carries the same theme description so the cues
sound like one soundtrack. Saves assets/audio/final/<cue>.mp3; key never printed; log in
tools/audio/eleven_log.jsonl. Skips existing finals unless --force.
  python tools/audio/eleven_music.py [--only music_hope] [--force] [--dry]"""
import csv, json, pathlib, sys, time, urllib.request, urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENV = pathlib.Path(r"C:\Users\compu\Documents\REALMREND Crowns at War\.env")
OUT = ROOT / "assets" / "audio" / "final"
LOG = pathlib.Path(__file__).with_name("eleven_log.jsonl")
THEME = ("Genesis Ark original score: cinematic ambient sci-fi, the last human waking a derelict colony ark carrying "
         "50,000 embryos; a recurring four-note hopeful motif in D minor resolving to F major; warm analog synth pads, "
         "felt piano, cello, distant choir; instrumental, no vocals with words, no drums unless stated.")


def key() -> str:
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("ELEVENLABS_API_KEY") and "=" in line:
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("ELEVENLABS_API_KEY not found")


def main() -> None:
    a = sys.argv[1:]
    only = set(a[a.index("--only") + 1].split(",")) if "--only" in a else set()
    force, dry = "--force" in a, "--dry" in a
    k = None if dry else key()
    OUT.mkdir(parents=True, exist_ok=True)
    for r in csv.DictReader(open(ROOT / "docs" / "AUDIO_LEDGER.csv", encoding="utf-8")):
        cue = r["cue_id"]
        if not cue.startswith(("music_", "stinger_")) or (only and cue not in only):
            continue
        dst = OUT / (cue + ".mp3")
        if (dst.exists() or dst.with_suffix(".ogg").exists()) and not force:  # looping music lives on as .ogg (normalize.py)
            continue
        secs = max(10.0, min(180.0, float(r["length_s"] or 60)))
        prompt = THEME + " This cue: " + r["prompt"].strip() + ("" if cue.startswith("stinger_") else " Loopable: the ending flows back into the beginning.")
        if dry:
            print("would generate", cue, secs, "s")
            continue
        body = {"prompt": prompt, "music_length_ms": int(secs * 1000)}
        req = urllib.request.Request("https://api.elevenlabs.io/v1/music?output_format=mp3_44100_128", data=json.dumps(body).encode(),
                                     method="POST", headers={"xi-api-key": k, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=600) as resp:
                data = resp.read()
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode(errors="replace")
            print("FAIL", cue, e.code, msg)
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps({"cue": cue, "status": e.code, "error": msg, "t": time.time()}) + "\n")
            if e.code in (401, 402, 403, 429):
                break
            continue
        dst.write_bytes(data)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"cue": cue, "bytes": len(data), "seconds": secs, "music": True, "t": time.time()}) + "\n")
        print("ok", cue, len(data))


if __name__ == "__main__":
    main()
