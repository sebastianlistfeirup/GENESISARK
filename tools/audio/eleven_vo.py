#!/usr/bin/env python3
"""Voice-over for the story lines with ElevenLabs TTS, from docs/VO_SCRIPT.csv.

Writes assets/audio/vo/<line_id>.mp3 (StoryPlayer plays them on the Voice bus with the
subtitle). One voice per role, chosen deliberately and kept for the whole game:
  ark_ai  -> calm, precise, warm (no robot filter in the recording; the bus adds it)
  captain -> gender-neutral voice (the role is gender-neutral)
  noor / elias / sana -> three distinct first-generation colonists
The narrator stays subtitles-only (bible p.13) unless --narrator. Key from the owner's
.env, never printed; log in tools/audio/eleven_log.jsonl.
  python tools/audio/eleven_vo.py [--only scene_intro_wakeup] [--force] [--dry] [--narrator]"""
import csv, json, pathlib, sys, time, urllib.request, urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENV = pathlib.Path(r"C:\Users\compu\Documents\REALMREND Crowns at War\.env")
OUT = ROOT / "assets" / "audio" / "vo"
LOG = pathlib.Path(__file__).with_name("eleven_log.jsonl")
# Preferred premade voice names per role (first one found on the account wins).
CAST = {
    "ark_ai": ["Alice", "Charlotte", "Matilda", "Sarah"],
    "captain": ["River", "Chris", "Brian"],
    "noor": ["Lily", "Laura", "Jessica"],
    "elias": ["Daniel", "George", "Callum"],
    "sana": ["Matilda", "Aria", "Sarah"],
    "narrator": ["George", "Brian", "Daniel"],
}
SETTINGS = {
    "ark_ai": {"stability": 0.62, "similarity_boost": 0.8, "style": 0.15},
    "captain": {"stability": 0.45, "similarity_boost": 0.75, "style": 0.25},
}


def key() -> str:
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("ELEVENLABS_API_KEY") and "=" in line:
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("ELEVENLABS_API_KEY not found")


def api(k: str, path: str, body=None, accept="application/json"):
    req = urllib.request.Request("https://api.elevenlabs.io" + path, data=json.dumps(body).encode() if body is not None else None,
                                 method="POST" if body is not None else "GET",
                                 headers={"xi-api-key": k, "Content-Type": "application/json", "Accept": accept})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


def main() -> None:
    a = sys.argv[1:]
    only = a[a.index("--only") + 1] if "--only" in a else ""
    force, dry, narrator = "--force" in a, "--dry" in a, "--narrator" in a
    rows = list(csv.DictReader(open(ROOT / "docs" / "VO_SCRIPT.csv", encoding="utf-8")))
    todo = [r for r in rows if (narrator or r["voice_id"] != "narrator") and (not only or r["scene"].startswith(only))
            and (force or not (OUT / (r["line_id"] + ".mp3")).exists())]
    print(len(todo), "lines,", sum(len(r["text"]) for r in todo), "chars")
    if dry:
        return
    k = key()
    voices = json.loads(api(k, "/v1/voices"))["voices"]
    by_name = {v["name"].split(" ")[0]: v["voice_id"] for v in voices}
    cast = {}
    for role, names in CAST.items():
        cast[role] = next((by_name[n] for n in names if n in by_name), voices[0]["voice_id"])
    print("cast:", {r: next((n for n in CAST[r] if n in by_name), "?") for r in CAST})
    OUT.mkdir(parents=True, exist_ok=True)
    for r in todo:
        role = r["voice_id"] if r["voice_id"] in cast else "narrator"
        body = {"text": r["text"], "model_id": "eleven_multilingual_v2",
                "voice_settings": SETTINGS.get(role, {"stability": 0.5, "similarity_boost": 0.75, "style": 0.2})}
        try:
            data = api(k, "/v1/text-to-speech/%s?output_format=mp3_44100_128" % cast[role], body, "audio/mpeg")
        except urllib.error.HTTPError as e:
            msg = e.read()[:300].decode(errors="replace")
            print("FAIL", r["line_id"], e.code, msg)
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps({"vo": r["line_id"], "status": e.code, "error": msg, "t": time.time()}) + "\n")
            if e.code in (401, 402, 403, 429):
                break
            continue
        (OUT / (r["line_id"] + ".mp3")).write_bytes(data)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"vo": r["line_id"], "role": role, "chars": len(r["text"]), "bytes": len(data), "t": time.time()}) + "\n")
        print("ok", r["line_id"], role)


if __name__ == "__main__":
    main()
