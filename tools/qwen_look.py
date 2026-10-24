#!/usr/bin/env python3
"""Local art critique with Qwen vision (Ollama, 127.0.0.1:11434). Screenshots of
licensed Synty content stay on this machine: this is the only adviser they may be
shown to. Usage: python tools/qwen_look.py <prompt-file-or-text> <image> [<image>...] [--model qwen3.5:27b]
Prints the critique; advisory only - verify every claim against the picture."""
import base64, json, os, sys, urllib.request

args = sys.argv[1:]
model = "qwen3.5:27b"
if "--model" in args:
    i = args.index("--model"); model = args[i + 1]; del args[i:i + 2]
prompt = open(args[0], encoding="utf-8").read() if os.path.isfile(args[0]) else args[0]
images = [base64.b64encode(open(p, "rb").read()).decode() for p in args[1:]]
body = json.dumps({"model": model, "prompt": prompt, "images": images, "stream": False, "keep_alive": 0,
                   "options": {"num_ctx": 8192, "temperature": 0.3}}).encode()
req = urllib.request.Request("http://127.0.0.1:11434/api/generate", data=body, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=600) as r:
    out = json.loads(r.read())
sys.stdout.reconfigure(encoding="utf-8")
print(out.get("response", out))
