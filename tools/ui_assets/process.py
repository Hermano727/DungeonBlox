"""
UI art pipeline: cleans ChatGPT (or any) PNGs into Roblox-ready UI pieces.

    python tools/ui_assets/process.py                 # every PNG in assets/ui/incoming/
    python tools/ui_assets/process.py book_cover      # one piece (name without .png)
    python tools/ui_assets/process.py --tile paper    # a seamless tiling texture: no trim
    python tools/ui_assets/process.py --split sheet a b c
        # one image holding several pieces in a row (or a column), separated by clear gaps:
        # cut apart left-to-right (or top-to-bottom) and saved as incoming/a.png, b.png, c.png,
        # then processed like any other piece

For each piece, assets/ui/incoming/<name>.png -> assets/ui/journal/<name>.png:
  1. Checks there is real transparency. Image generators often paint a fake grey
     checkerboard instead of a transparent background; that is rejected with a clear message.
  2. Trims to the visible content (plus a small margin), so 9-slice insets measure the art,
     not empty space.
  3. Bleeds edge colour into fully transparent pixels. Without this, Roblox's filtering pulls
     black from transparent neighbours and every soft edge gets a dark halo.
  4. Caps the longest side at 1024 px (Roblox renders images at 1024 max).
Then prints a report: final size, aspect and a starting 9-slice inset (25% of each side),
which gets tuned by eye.

Uploading is separate (see docs/ui-and-networking.md, "UI art pipeline"): serve
assets/ui/journal/ over a local http server and pass the URLs to the Studio MCP upload_image,
which returns image ids for RS/Assets/Images/JournalUI.
"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
INCOMING = ROOT / "assets" / "ui" / "incoming"
OUT = ROOT / "assets" / "ui" / "journal"
MAX_SIDE = 1024
MARGIN = 4          # px kept around the trimmed content
ALPHA_VISIBLE = 8   # alpha above this counts as content when trimming


def has_real_alpha(arr):
    alpha = arr[:, :, 3]
    return (alpha < 250).mean() > 0.02


def looks_like_fake_checkerboard(arr):
    """Opaque image whose border is a grey/white checker pattern."""
    rgb = arr[:, :, :3].astype(int)
    border = np.concatenate([rgb[:8].reshape(-1, 3), rgb[-8:].reshape(-1, 3),
                             rgb[:, :8].reshape(-1, 3), rgb[:, -8:].reshape(-1, 3)])
    greyish = (np.abs(border[:, 0] - border[:, 1]) < 6) & (np.abs(border[:, 1] - border[:, 2]) < 6)
    light = border.mean(axis=1) > 150
    return (greyish & light).mean() > 0.9


def trim(img):
    arr = np.asarray(img)
    ys, xs = np.nonzero(arr[:, :, 3] > ALPHA_VISIBLE)
    if len(xs) == 0:
        return img
    x0 = max(0, xs.min() - MARGIN)
    y0 = max(0, ys.min() - MARGIN)
    x1 = min(img.width, xs.max() + 1 + MARGIN)
    y1 = min(img.height, ys.max() + 1 + MARGIN)
    return img.crop((x0, y0, x1, y1))


def bleed_edges(img):
    """Fill fully transparent pixels with the colour of the nearest visible pixels."""
    arr = np.asarray(img).astype(np.float32)
    # Sample colour only from solid pixels: faint edge pixels carry too little colour
    # information and would bleed a darkened tone outward.
    solid = (arr[:, :, 3] > 128).astype(np.float32)[:, :, None]
    source = arr[:, :, :3] * solid
    filled = arr[:, :, :3].copy()
    todo = arr[:, :, 3] <= 0.0
    for radius in (1, 2, 4, 8, 16, 32):
        if not todo.any():
            break
        p = Image.fromarray(source.astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
        a = Image.fromarray((solid[:, :, 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
        p = np.asarray(p).astype(np.float32)
        a = np.asarray(a).astype(np.float32)[:, :, None] / 255.0
        ok = todo & (a[:, :, 0] > 0.15)  # only well-supported samples; faint ones round badly
        colour = p / np.maximum(a, 1e-4)
        filled[ok] = colour[ok]
        todo = todo & ~ok
    if todo.any() and solid.any():  # anything left: the art's average colour
        filled[todo] = (arr[:, :, :3] * solid).sum(axis=(0, 1)) / solid.sum()
    out = np.concatenate([np.clip(filled, 0, 255), arr[:, :, 3:4]], axis=2).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def cap_size(img):
    longest = max(img.size)
    if longest <= MAX_SIDE:
        return img
    scale = MAX_SIDE / longest
    return img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)


def process(name, tile=False):
    src = INCOMING / f"{name}.png"
    if not src.exists():
        return {"piece": name, "error": f"missing {src}"}
    img = Image.open(src).convert("RGBA")
    arr = np.asarray(img)
    if not tile:
        if not has_real_alpha(arr):
            reason = "fake checkerboard background (painted, not transparent)" if looks_like_fake_checkerboard(arr) \
                else "no transparency"
            return {"piece": name, "error": reason}
        img = trim(img)
        img = bleed_edges(img)
    img = cap_size(img)
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / f"{name}.png"
    img.save(dst, optimize=True)
    w, h = img.size
    return {
        "piece": name,
        "out": str(dst.relative_to(ROOT)).replace("\\", "/"),
        "size": [w, h],
        "aspect": round(w / h, 4),
        "sliceStart": [round(w * 0.25), round(h * 0.25), round(w * 0.75), round(h * 0.75)],
        "tile": tile,
    }


def split_sheet(sheet, names):
    """Cut a sheet into len(names) pieces along the fully transparent gaps between them."""
    src = INCOMING / f"{sheet}.png"
    if not src.exists():
        return f"missing {src}"
    img = Image.open(src).convert("RGBA")
    alpha = np.asarray(img)[:, :, 3] > ALPHA_VISIBLE

    def runs(occupied):
        spans, start = [], None
        for i, filled in enumerate(occupied):
            if filled and start is None:
                start = i
            elif not filled and start is not None:
                spans.append((start, i))
                start = None
        if start is not None:
            spans.append((start, len(occupied)))
        # merge specks: ignore spans thinner than 2% of the sheet
        return [sp for sp in spans if sp[1] - sp[0] > len(occupied) * 0.02]

    for axis, occupied in (("x", alpha.any(axis=0)), ("y", alpha.any(axis=1))):
        spans = runs(occupied)
        if len(spans) == len(names):
            for (a, b), name in zip(spans, names):
                box = (a, 0, b, img.height) if axis == "x" else (0, a, img.width, b)
                img.crop(box).save(INCOMING / f"{name}.png")
            return None
    return (f"could not find {len(names)} separate pieces in {sheet}.png "
            f"(x gaps -> {len(runs(alpha.any(axis=0)))}, y gaps -> {len(runs(alpha.any(axis=1)))})")


def main(argv):
    if argv and argv[0] == "--split":
        if len(argv) < 3:
            print("usage: process.py --split <sheet> <piece> <piece> ...")
            return 1
        error = split_sheet(argv[1], argv[2:])
        if error:
            print(json.dumps([{"piece": argv[1], "error": error}], indent=2))
            return 1
        argv = argv[2:]
    tile = "--tile" in argv
    names = [a for a in argv if not a.startswith("--")]
    if not names:
        names = sorted(p.stem for p in INCOMING.glob("*.png"))
    if not names:
        print(f"nothing in {INCOMING}")
        return 1
    reports = [process(n, tile=tile) for n in names]
    print(json.dumps(reports, indent=2))
    return 1 if any("error" in r for r in reports) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
