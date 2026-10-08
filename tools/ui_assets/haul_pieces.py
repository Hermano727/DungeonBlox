# Rebuilds two haul-bar pieces from the processed art:
#   haul_zone_grid.png  -- square rope-net catch zone (border + a 3x4 net), drawn Stretch, not 9-slice
#   haul_reel_body.png / haul_reel_crank.png -- the reel split so the crank can turn about its nut
import numpy as np
from PIL import Image, ImageDraw
J = "assets/UI/journal/"
zone = Image.open(J + "haul_zone.png").convert("RGBA")
a = np.array(zone)[:, :, 3]

def centres(profile, lo, hi):
    out, run = [], None
    for i in range(lo, hi):
        if profile[i] > 100:
            run = run or [i, i]; run[1] = i
        elif run:
            out.append((run[0] + run[1]) / 2); run = None
    return out

vx = centres(a[160], 70, 950)          # net verticals (between the side ropes)
hy = centres(a[:, 512], 64, 255)       # net horizontals (between top and bottom rope)
print("verticals", vx, "horizontals", hy)
# One cell-centred tile: a whole knot in the middle, rope ends on all four edges.
x0, x1 = (vx[2] + vx[3]) / 2, (vx[3] + vx[4]) / 2
y0 = hy[0] - (hy[1] - hy[0]) / 2
y1 = hy[0] + (hy[1] - hy[0]) / 2
tile = zone.crop((round(x0 - (vx[3] - x0) + (vx[3]-x0)), round(y0), round(x1), round(y1)))
print("tile", tile.size)

N, C = 512, 96          # canvas, corner size (unscaled from the source)
INNER = 62              # the rope border's inner edge from the canvas edge
COLS, ROWS = 3, 4
out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
# The net runs under the border rope (UNDER px past its inner edge), so no gap where they meet.
UNDER = 16
span = N - 2 * (INNER - UNDER)
tw, th = span / COLS, span / ROWS
t = tile.resize((round(tw), round(th)), Image.BICUBIC)
for c in range(COLS):
    for r in range(ROWS):
        out.alpha_composite(t, (round(INNER - UNDER + c * tw), round(INNER - UNDER + r * th)))

# Border on top: corners as drawn, edges cut from the long top/bottom rope (sides are it turned).
W0, H0 = zone.size
border = Image.new("RGBA", (N, N), (0, 0, 0, 0))
def strip(y_from, y_to):
    # Rope only between the net's attachment points, so no stubs ride along.
    want = N - 2 * C
    out_s = Image.new("RGBA", (want, y_to - y_from), (0, 0, 0, 0))
    x, i = 0, 0
    while x < want:
        a0, a1 = vx[i] + 14, vx[i + 1] - 14
        seg = zone.crop((round(a0), y_from, round(a1), y_to))
        out_s.alpha_composite(seg, (x, 0))
        x += seg.size[0]; i += 1
    return out_s
top = strip(0, 66)
bottom = strip(H0 - 66, H0)
# keep only the rope itself (drop the net stubs hanging off it)
def rope_only(img, keep_top):
    arr = np.array(img).copy()
    h = arr.shape[0]
    rows = range(61, h) if keep_top else range(0, h - 61)
    for y in rows: arr[y, :, 3] = 0
    return Image.fromarray(arr)
top = rope_only(top, True); bottom = rope_only(bottom, False)
border.alpha_composite(top, (C, 0))
border.alpha_composite(bottom, (C, N - 66))
side = top.resize((N - 2 * C, 66))
border.alpha_composite(side.rotate(90, expand=True), (0, C))
border.alpha_composite(side.rotate(-90, expand=True), (N - 66, C))
for (sx, sy, dx, dy) in [(0, 0, 0, 0), (W0 - C, 0, N - C, 0), (0, H0 - C, 0, N - C), (W0 - C, H0 - C, N - C, N - C)]:
    corner = np.array(zone.crop((sx, sy, sx + C, sy + C))).copy()
    border.alpha_composite(Image.fromarray(corner), (dx, dy))
out.alpha_composite(border)
out.save(J + "haul_zone_grid.png")

# Reel: crank = the lever plate, arm and handle; it turns about the nut.
reel = Image.open(J + "haul_reel.png").convert("RGBA")
mask = Image.new("L", reel.size, 0)
ImageDraw.Draw(mask).polygon([(712, 30), (800, 12), (960, 0), (1024, 0), (1024, 205), (806, 192), (796, 322),
    (802, 334), (802, 458), (697, 458), (697, 332), (706, 302), (712, 172)], fill=255)
m = np.array(mask) > 0
ra = np.array(reel)
crank = ra.copy(); crank[~m, 3] = 0
body = ra.copy(); body[m, 3] = 0
PIVOT = (727, 376)
R = 480
canvas = Image.new("RGBA", (2 * R, 2 * R), (0, 0, 0, 0))
canvas.alpha_composite(Image.fromarray(crank), (R - PIVOT[0], R - PIVOT[1]))
canvas.save(J + "haul_reel_crank.png")
Image.fromarray(body).save(J + "haul_reel_body.png")
print("reel", reel.size, "crank canvas", canvas.size, "pivot", PIVOT)
