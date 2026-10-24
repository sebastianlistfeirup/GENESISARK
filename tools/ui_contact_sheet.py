#!/usr/bin/env python3
"""Contact sheet of a local sprite folder (dev tool, D-055).

Lays every PNG of a folder out on a dark grid with its file name, so the right
Synty INTERFACE frames, icons and FX sprites can be picked by eye. The packs are
purchased and local only: write the sheets OUTSIDE the repo (e.g. a temp dir).

Usage: python3 tools/ui_contact_sheet.py <sprite_dir> <out.jpg> [--cell=128] [--cols=10] [--filter=text]
"""
import os
import sys

from PIL import Image, ImageDraw


def main() -> int:
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
	if len(args) < 2:
		print(__doc__)
		return 1
	src, out = args[0], args[1]
	cell = int(opts.get("cell", 128))
	cols = int(opts.get("cols", 10))
	filt = opts.get("filter", "").lower()
	files = sorted(f for f in os.listdir(src) if f.lower().endswith(".png") and filt in f.lower())
	if not files:
		print("no png files")
		return 1
	rows = (len(files) + cols - 1) // cols
	lab = 26
	sheet = Image.new("RGB", (cols * cell, rows * (cell + lab)), (18, 24, 30))
	draw = ImageDraw.Draw(sheet)
	for i, f in enumerate(files):
		x, y = (i % cols) * cell, (i // cols) * (cell + lab)
		# checker so white-on-transparent masks stay visible
		for cy in range(0, cell, 16):
			for cx in range(0, cell, 16):
				if (cx // 16 + cy // 16) % 2 == 0:
					draw.rectangle([x + cx, y + cy, x + cx + 15, y + cy + 15], fill=(28, 36, 44))
		try:
			im = Image.open(os.path.join(src, f)).convert("RGBA")
			w, h = im.size
			s = (cell - 8) / max(w, h)
			im = im.resize((max(1, int(w * s)), max(1, int(h * s))), Image.LANCZOS)
			sheet.paste(im, (x + (cell - im.width) // 2, y + (cell - im.height) // 2), im)
			size = "%dx%d" % (w, h)
		except Exception as e:  # noqa: BLE001 - a dev sheet: show the failure in place
			size = "ERR " + str(e)[:10]
		name = os.path.splitext(f)[0]
		for pre in ("SPR_SciFiMenus_", "ICON_SciFiMenus_", "SPR_HUD_SciFi_", "ICON_SciFi_", "SPR_"):
			name = name.replace(pre, "")
		draw.text((x + 2, y + cell), name[:22], fill=(200, 230, 230))
		draw.text((x + 2, y + cell + 12), name[22:40] + " " + size, fill=(120, 150, 160))
	sheet.save(out, quality=85)
	print("%d sprites -> %s" % (len(files), out))
	return 0


if __name__ == "__main__":
	sys.exit(main())
