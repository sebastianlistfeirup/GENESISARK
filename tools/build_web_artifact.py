#!/usr/bin/env python3
"""Packages builds/web (Godot Web export, no threads) into a phone-friendly
page whose files all fit the artifact host limits: the .wasm is split into
<15 MB parts and reassembled in the browser by a fetch shim; the engine JS is
inlined. Usage: python3 tools/build_web_artifact.py <out_dir>"""
import json, os, re, sys, shutil
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "builds", "web")
OUT = sys.argv[1]
PART = 12 * 1024 * 1024
os.makedirs(OUT, exist_ok=True)
html = open(os.path.join(SRC, "index.html"), encoding="utf-8").read()
cfg = json.loads(re.search(r"const GODOT_CONFIG = (\{.*?\});", html).group(1))
wasm = open(os.path.join(SRC, "index.wasm"), "rb").read()
parts = []
for i in range(0, len(wasm), PART):
    name = f"index.wasm.part{len(parts)}"
    open(os.path.join(OUT, name), "wb").write(wasm[i:i + PART])
    parts.append(name)
for f in ["index.pck", "index.audio.worklet.js", "index.audio.position.worklet.js"]:
    shutil.copy(os.path.join(SRC, f), os.path.join(OUT, f))
engine_js = open(os.path.join(SRC, "index.js"), encoding="utf-8").read().replace("</script>", "<\\/script>")
page = """<title>Genesis Ark Spiltest</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
[hidden] { display: none !important; }
:root { --bg: #0b1219; --fg: #e6f2f2; --muted: #8fa3ad; --petrol: #1f8a8a; --amber: #e8a33d; color-scheme: dark; }
html, body { height: 100%; background: var(--bg); color: var(--fg); margin: 0; overflow: hidden; touch-action: none; }
#canvas { display: block; width: 100vw; height: 100vh; height: 100dvh; outline: none; }
#overlay { position: fixed; inset: 0; display: grid; place-items: center; background: var(--bg);
  padding: env(safe-area-inset-top, 0px) max(16px, env(safe-area-inset-right, 0px)) env(safe-area-inset-bottom, 0px) max(16px, env(safe-area-inset-left, 0px)); }
.box { max-width: 520px; display: grid; gap: 14px; text-align: center; font: 16px/1.5 system-ui, sans-serif; }
h1 { font: 700 34px/1.1 system-ui, sans-serif; letter-spacing: .06em; margin: 0; }
p { margin: 0; color: var(--muted); }
#bar { height: 6px; background: #142832; border-radius: 3px; overflow: hidden; }
#fill { height: 100%; width: 0; background: var(--petrol); transition: width .2s; }
button { font: 600 18px system-ui, sans-serif; color: var(--fg); background: var(--petrol); border: 0; border-radius: 6px; padding: 14px 22px; }
button:focus-visible { outline: 2px solid var(--amber); outline-offset: 2px; }
#err { color: var(--amber); white-space: pre-wrap; text-align: left; font-size: 13px; }
</style>
<canvas id="canvas" tabindex="0">Din browser understøtter ikke canvas.</canvas>
<div id="overlay"><div class="box">
  <h1>GENESIS ARK</h1>
  <p>Greybox-testversion. Hold telefonen vandret. Venstre side: joystick. Træk i højre side: kig rundt. Knapperne er E (brug), Løb, Byg, II (pause) og Log (journal).</p>
  <div id="bar"><div id="fill"></div></div>
  <p id="status">Indlæser spillet (ca. 40 MB)…</p>
  <button id="start" hidden>Start spillet</button>
  <div id="err"></div>
</div></div>
<script>
const WASM_PARTS = __PARTS__;
const realFetch = window.fetch.bind(window);
window.fetch = async function (input, init) {
  const url = (typeof input === "string") ? input : input.url;
  if (url && /index\\.wasm(\\?|$)/.test(url)) {
    const chunks = [];
    for (const p of WASM_PARTS) {
      const r = await realFetch(p, init);
      if (!r.ok) throw new Error("Kunne ikke hente " + p + " (" + r.status + ")");
      chunks.push(await r.arrayBuffer());
    }
    return new Response(new Blob(chunks, { type: "application/wasm" }), { status: 200, headers: { "Content-Type": "application/wasm" } });
  }
  return realFetch(input, init);
};
</script>
<script>__ENGINE__</script>
<script>
const GODOT_CONFIG = __CONFIG__;
const engine = new Engine(GODOT_CONFIG);
const statusEl = document.getElementById("status");
const fill = document.getElementById("fill");
const startBtn = document.getElementById("start");
const errEl = document.getElementById("err");
function fail(e) { statusEl.textContent = "Spillet kunne ikke starte i denne browser."; errEl.textContent = String(e && e.message || e); }
if (!Engine.isWebGLAvailable(2)) { fail("WebGL 2 er ikke tilgængeligt."); }
else {
  engine.init("index").then(() => {
    statusEl.textContent = "Klar.";
    fill.style.width = "100%";
    startBtn.hidden = false;
  }).catch(fail);
}
startBtn.addEventListener("click", () => {
  startBtn.hidden = true;
  statusEl.textContent = "Starter…";
  engine.startGame({
    onProgress: (cur, total) => { if (total > 0) fill.style.width = Math.round(100 * cur / total) + "%"; },
  }).then(() => { document.getElementById("overlay").hidden = true; document.getElementById("canvas").focus(); }).catch(fail);
});
</script>
"""
page = page.replace("__PARTS__", json.dumps(parts)).replace("__CONFIG__", json.dumps(cfg)).replace("__ENGINE__", engine_js)
open(os.path.join(OUT, "index.html"), "w", encoding="utf-8").write(page)
print("parts", parts, "html KB", len(page) // 1024)
