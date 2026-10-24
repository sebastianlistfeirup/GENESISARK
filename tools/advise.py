#!/usr/bin/env python3
"""Text-only second opinions from the tool chain (DeepSeek, Kimi). Keys are read from the
environment (DEEPSEEK_API_KEY) or the owner's REALMREND .env (KIMI_API_KEY) and never printed.
Only our own code/text is sent — never purchased assets or captures of them.
  python tools/advise.py deepseek|kimi <prompt-file> <file> [<file>...] > out.md"""
import json, os, pathlib, sys, urllib.request

ENV = pathlib.Path(r"C:\Users\compu\Documents\REALMREND Crowns at War\.env")
APIS = {"deepseek": ("https://api.deepseek.com/chat/completions", "deepseek-chat", "DEEPSEEK_API_KEY"),
        "kimi": ("https://api.moonshot.ai/v1/chat/completions", "kimi-k2-0905-preview", "KIMI_API_KEY")}


def key(name: str) -> str:
    if os.environ.get(name):
        return os.environ[name]
    for line in ENV.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith(name + "="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit(name + " not found")


who, prompt_file, files = sys.argv[1], sys.argv[2], sys.argv[3:]
url, model, kname = APIS[who]
body = open(prompt_file, encoding="utf-8").read() + "\n\n"
for f in files:
    body += f"===== {f} =====\n" + open(f, encoding="utf-8").read() + "\n"
req = urllib.request.Request(url, data=json.dumps({"model": model, "messages": [{"role": "user", "content": body}], "temperature": 0.3}).encode(),
                             headers={"Authorization": "Bearer " + key(kname), "Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=600) as r:
    d = json.loads(r.read())
sys.stdout.reconfigure(encoding="utf-8")
print(d["choices"][0]["message"]["content"])
