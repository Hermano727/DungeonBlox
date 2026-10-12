"""
VFX texture pipeline: turns generated art into Roblox-ready particle / beam / decal textures.

    python tools/vfx_assets/process.py <out_dir> <image> [mode] [<image> [mode] ...]

Modes (default: lum):
  lum      white/grey art on a pure black background (what the VFX prompts ask for).
           Alpha comes from brightness: black -> clear, the shapes -> solid, while the grey cel
           shading inside a shape stays as darker colour instead of turning see-through.
  tile     same as lum, then crops to the content band and crossfades the left/right edges so the
           texture repeats seamlessly (Beam textures).
  grid4    same as lum, resized to exactly 1024x1024 so a 4x4 ParticleEmitter flipbook lands on
           256 px cells.
  alpha    the image already has real transparency (icons): trim to the content only.
  bleed    real transparency that must keep its exact framing (UV-mapped mesh textures, e.g. the
           baked flipbook frames): no trim, no resize.

Every mode then bleeds edge colour into fully clear pixels (no dark halos when Roblox filters the
texture) and caps the longest side at 1024 px. Output keeps the source file name, written into
<out_dir> (use a scratch directory: the processed copy is only an upload intermediate, the source
art stays where it was handed over, under its own name).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

MAX_SIDE = 1024
LUM_CLEAR = 0.04   # below this brightness: fully clear
LUM_SOLID = 0.30   # above this brightness: fully solid
MARGIN = 6


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def lum_to_alpha(img):
    rgb = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    lum = rgb.mean(axis=2)
    alpha = smoothstep(LUM_CLEAR, LUM_SOLID, lum)
    # Keep the shading: re-normalise colour so the brightest shape is white and grey stays grey.
    shade = np.clip(lum / max(np.percentile(lum[alpha > 0.5], 99) if (alpha > 0.5).any() else 1.0, 1e-3), 0, 1)
    out = np.dstack([shade, shade, shade, alpha])
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def trim(img):
    a = np.asarray(img)[:, :, 3]
    ys, xs = np.nonzero(a > 8)
    if len(xs) == 0:
        return img
    x0, x1 = max(xs.min() - MARGIN, 0), min(xs.max() + MARGIN + 1, img.width)
    y0, y1 = max(ys.min() - MARGIN, 0), min(ys.max() + MARGIN + 1, img.height)
    return img.crop((x0, y0, x1, y1))


def make_tileable(img):
    """Crop to the content's rows, then crossfade the right end over the left so x=0 follows x=W-1."""
    a = np.asarray(img)[:, :, 3]
    ys = np.nonzero((a > 8).any(axis=1))[0]
    img = img.crop((0, max(ys.min() - MARGIN, 0), img.width, min(ys.max() + MARGIN + 1, img.height)))
    arr = np.asarray(img).astype(np.float32)
    w = arr.shape[1]
    overlap = w // 6
    keep = arr[:, : w - overlap].copy()
    tail = arr[:, w - overlap:]
    weight = (np.arange(overlap) / overlap)[None, :, None]
    keep[:, :overlap] = tail * (1 - weight) + keep[:, :overlap] * weight
    return Image.fromarray(keep.clip(0, 255).astype(np.uint8), "RGBA")


def bleed(img):
    """Spread the colour of visible pixels into clear ones (alpha untouched)."""
    arr = np.asarray(img).astype(np.float32)
    alpha = arr[:, :, 3:4] / 255.0
    rgb = arr[:, :, :3]
    weighted = Image.fromarray((rgb * alpha).clip(0, 255).astype(np.uint8))
    mask = Image.fromarray((alpha[:, :, 0] * 255).astype(np.uint8))
    for _ in range(4):
        weighted = weighted.filter(ImageFilter.GaussianBlur(6))
        mask = mask.filter(ImageFilter.GaussianBlur(6))
    w = np.asarray(weighted).astype(np.float32)
    m = np.asarray(mask).astype(np.float32)[:, :, None] / 255.0
    spread = np.where(m > 1e-3, w / np.maximum(m, 1e-3), 0)
    out_rgb = np.where(alpha > 0.02, rgb, spread)
    return Image.fromarray(np.dstack([out_rgb, arr[:, :, 3]]).clip(0, 255).astype(np.uint8), "RGBA")


def cap(img, exact=None):
    if exact:
        return img.resize((exact, exact), Image.LANCZOS)
    scale = MAX_SIDE / max(img.size)
    if scale < 1:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    return img


def process(path, mode, out_dir):
    img = Image.open(path)
    if mode == "bleed":
        img = img.convert("RGBA")
    elif mode == "alpha":
        img = trim(img.convert("RGBA"))
    else:
        img = lum_to_alpha(img)
        if mode == "tile":
            img = make_tileable(img)
    img = bleed(img)
    img = cap(img, exact=MAX_SIDE if mode == "grid4" else None)
    out = out_dir / path.name
    img.save(out)
    print(f"{path.name}: {mode} -> {img.width}x{img.height}")


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    args = sys.argv[2:]
    i = 0
    while i < len(args):
        path = Path(args[i])
        mode = "lum"
        if i + 1 < len(args) and args[i + 1] in ("lum", "tile", "grid4", "alpha", "bleed"):
            mode = args[i + 1]
            i += 1
        process(path, mode, out_dir)
        i += 1


if __name__ == "__main__":
    main()
