"""In-game mix check (D-064): record Movie Maker clips per scene (full mix, Voice bus solo,
Voice bus muted, via DebugCapture --solo/--mute) and measure them with ffmpeg ebur128.
Also collects the "AUDIO ..." lines DebugCapture prints (music/ambience slot, cues fired).
  python tools/audio/mixcheck.py <label> [scene,scene|all] [modes: full,voice,beds]
Clips (AVI with audio, never committed) and mix_<label>.json go to $MIXCHECK_OUT (default:
<temp>/genesis_mixcheck). $GODOT = the Godot console binary (default: godot on PATH)."""
import json, os, pathlib, re, subprocess, sys, statistics, tempfile
import imageio_ffmpeg
FF = imageio_ffmpeg.get_ffmpeg_exe()
GODOT = os.environ.get("GODOT", "godot")
REPO = pathlib.Path(__file__).resolve().parents[2]
SCR = pathlib.Path(os.environ.get("MIXCHECK_OUT", str(pathlib.Path(tempfile.gettempdir()) / "genesis_mixcheck")))

SCENES = {
    "menu": ["--setup=fresh", "--scene=menu", "--wait=420"],
    "ship_fresh": ["--setup=fresh", "--scene=ship", "--wait=1050"],
    "ship_powered": ["--setup=fresh", "--scene=ship", "--wait=240", "--action=powerwave", "--post=720"],
    "flight": ["--setup=approach", "--scene=flight", "--wait=600"],
    "descent": ["--setup=expedition:viridia", "--scene=surface", "--wait=30", "--action=descent:2600", "--post=900"],
    "surface": ["--setup=expedition:viridia", "--scene=surface", "--wait=600"],
    "colony": ["--setup=grown:viridia", "--scene=colony", "--wait=540"],
    "ending": ["--setup=era:viridia:40", "--scene=ending", "--wait=540"],
    # new-cue checks (after only)
    "droppod": ["--setup=expedition:viridia", "--scene=surface", "--wait=120", "--action=droppod", "--post=300"],
    "scan": ["--setup=expedition:viridia", "--scene=surface", "--wait=120", "--action=scan_ground", "--post=240"],
    "ascent": ["--setup=expedition:viridia", "--scene=surface", "--wait=120", "--action=ascent", "--post=420"],
    "leviathan": ["--setup=expedition:pelagos", "--scene=surface", "--wait=60", "--action=leviathan", "--post=900"],
    "landing": ["--setup=expedition:viridia", "--scene=surface", "--wait=30", "--action=descent:700", "--post=1500"],
    "wakeup": ["--setup=fresh", "--scene=ship", "--wait=20", "--action=wakeup", "--post=420"],
    "colony_act2": ["--setup=era:viridia:8", "--scene=colony", "--wait=300"],
    "colony_act3": ["--setup=era:viridia:25", "--scene=colony", "--wait=300"],
    "wildlife": ["--setup=expedition:nivalis", "--scene=surface", "--wait=60", "--action=wildlife", "--post=1500"],
}
AUDIO = {}
MODES = {"full": [], "voice": ["--solo=Voice"], "beds": ["--mute=Voice"]}


def record(label, scene, mode):
    out = SCR / "clips" / label
    out.mkdir(parents=True, exist_ok=True)
    avi = out / f"{scene}_{mode}.avi"
    png = out / f"{scene}_{mode}.png"
    cmd = [GODOT, "--path", str(REPO), "--resolution", "960x540", "--write-movie", str(avi), "--fixed-fps", "30", "--",
           f"--capture={png.as_posix()}"] + SCENES[scene] + MODES[mode]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=1500, encoding="utf-8", errors="replace")
        (out / f"{scene}_{mode}.log").write_text(r.stdout[-6000:] + "\n---\n" + r.stderr[-6000:], encoding="utf-8")
        for line in r.stdout.splitlines():
            if line.startswith("AUDIO "):
                AUDIO.setdefault((scene, mode), []).append(line[6:].strip())
    except subprocess.TimeoutExpired:
        print("TIMEOUT", scene, mode)
    return avi


def measure(avi):
    if not avi.exists():
        return None
    r = subprocess.run([FF, "-hide_banner", "-nostats", "-i", str(avi), "-vn", "-af", "ebur128=peak=true:metadata=1,ametadata=print:key=lavfi.r128.M", "-f", "null", "-"],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    e = r.stderr
    I = re.findall(r"I:\s+(-?[\d.]+) LUFS", e)
    lra = re.findall(r"LRA:\s+(-?[\d.]+) LU", e)
    pk = re.findall(r"Peak:\s+(-?[\d.]+|-inf) dBFS", e)
    m = [float(x) if x != "-inf" else -120.0 for x in re.findall(r"lavfi\.r128\.M=(-?[\d.]+|-inf)", r.stdout + e)]
    return {"I": float(I[-1]) if I else None, "LRA": float(lra[-1]) if lra else None, "peak": pk[-1] if pk else None, "M": m}


def main():
    label = sys.argv[1]
    scenes = sys.argv[2].split(",") if len(sys.argv) > 2 and sys.argv[2] != "all" else ["menu", "ship_fresh", "ship_powered", "flight", "descent", "surface", "colony", "ending"]
    modes = sys.argv[3].split(",") if len(sys.argv) > 3 else ["full", "voice", "beds"]
    SCR.mkdir(parents=True, exist_ok=True)
    res_path = SCR / f"mix_{label}.json"
    res = json.loads(res_path.read_text()) if res_path.exists() else {}
    for sc in scenes:
        row = res.get(sc, {})
        for mo in modes:
            avi = record(label, sc, mo)
            m = measure(avi)
            if m is None:
                print("no clip", sc, mo)
                continue
            row[mo] = {k: v for k, v in m.items() if k != "M"}
            row[mo + "_M"] = m["M"]
            if (sc, mo) in AUDIO:
                row[mo + "_audio"] = AUDIO[(sc, mo)]
        # voice margin: momentary voice vs beds where the voice is active
        if "voice_M" in row and "beds_M" in row:
            v, b = row["voice_M"], row["beds_M"]
            act = [i for i in range(min(len(v), len(b))) if v[i] > -45.0]
            row["voice_active_s"] = round(len(act) * 0.1, 1)
            if act:
                row["voice_med_M"] = round(statistics.median(v[i] for i in act), 1)
                row["beds_med_M_under_voice"] = round(statistics.median(b[i] for i in act), 1)
                row["margin_LU"] = round(row["voice_med_M"] - row["beds_med_M_under_voice"], 1)
            quiet = [i for i in range(min(len(v), len(b))) if v[i] <= -60.0]
            if quiet:
                row["beds_med_M_no_voice"] = round(statistics.median(b[i] for i in quiet), 1)
        res[sc] = row
        res_path.write_text(json.dumps(res))
        print(sc, {k: row[k] for k in row if not k.endswith("_M") or k.startswith(("voice_med", "beds_med"))})


if __name__ == "__main__":
    main()
