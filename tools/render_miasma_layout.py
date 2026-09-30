"""Render a dimensioned top-down drawing of the Miasma arena layout (SVG).

Mirrors the numbers in src/shared/MiasmaArenaLayout.luau (keep them in sync; the Luau file is
the source of truth) and the station footprint in MiasmaValveStationBuilder. Output:
docs/images/miasma-layout-topdown.svg

    python tools/render_miasma_layout.py
"""
import math
from pathlib import Path

FLOOR_Y = 1
APOTHEM = 104
WALL_T = 4
CIRCUM = APOTHEM / math.cos(math.radians(30))
PLATFORM_R = 64
LANDING_R = 49
BASIN_R = 12
SHAFT_HALF = 46
RECESS_W = 24
STATION_DEPTH = 13
ALTAR_DEPTH = 12
STATIONS = [("1 NE", 30), ("2 SE", 150), ("3 SW", 210), ("4 NW", 330)]
ALTARS = [("Altar 1 (W)", 270), ("Altar 2 (E)", 90)]
SAFE = [60, 120, 240, 300]
SAFE_R, SAFE_D = 12, 94
SACKS = [22.5 + 45 * k for k in range(8)]
SACK_D = 98
ENT_W, CORRIDOR_END, VEST_D, VEST_W = 16, 158, 28, 44
SEAL_R, THRESH_R, GATHER_R, SPAWN_R, SPAWN_X = 124, 130, 90, 172, -14
BOSS_W, BOSS_D = 59.8, 64.3

SCALE = 3.2
PAD = 40
SIZE = 2 * 200 * SCALE + 2 * PAD


def polar(angle, r):
    a = math.radians(angle)
    return (math.sin(a) * r, -math.cos(a) * r)


def to_svg(x, z):
    # arena-local x -> right, -Z (north, entrance) -> up
    return (SIZE / 2 + x * SCALE, SIZE / 2 + 30 * SCALE + z * SCALE)


def poly(points, **attrs):
    pts = " ".join(f"{to_svg(x, z)[0]:.1f},{to_svg(x, z)[1]:.1f}" for x, z in points)
    extra = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return f'<polygon points="{pts}" {extra}/>'


def line(a, b, **attrs):
    (x1, y1), (x2, y2) = to_svg(*a), to_svg(*b)
    extra = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" {extra}/>'


def circle(c, r, **attrs):
    x, y = to_svg(*c)
    extra = " ".join(f'{k.replace("_", "-")}="{v}"' for k, v in attrs.items())
    return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r * SCALE:.1f}" {extra}/>'


def text(c, s, size=11, anchor="middle", color="#d8ccb0"):
    x, y = to_svg(*c)
    return f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" text-anchor="{anchor}" fill="{color}" font-family="Segoe UI, sans-serif">{s}</text>'


def station_frame(angle):
    """Returns a function mapping station-local (x, z) to arena-local (x, z)."""
    back_plane = APOTHEM + STATION_DEPTH
    ox, oz = polar(angle, back_plane - 5.3)
    fx, fz = polar(angle, 1)  # LookVector (outward) in x,z
    rx, rz = -fz, fx  # right vector = look x up; for look=(fx,fz): right = (-fz, fx)
    # station origin shifted +1 along local X
    ox, oz = ox + rx * 1, oz + rz * 1

    def to_arena(lx, lz):
        # local -Z = look (outward), local +X = right
        return (ox + rx * lx - fx * lz, oz + rz * lx - fz * lz)
    return to_arena


out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE:.0f}" height="{SIZE:.0f}" viewBox="0 0 {SIZE:.0f} {SIZE:.0f}">',
       f'<rect width="100%" height="100%" fill="#16181a"/>']

# Room floor (hexagon), recesses, entrance
hexagon = [polar(a, CIRCUM) for a in range(0, 360, 60)]
outer = [polar(a, CIRCUM + WALL_T / math.cos(math.radians(30))) for a in range(0, 360, 60)]
out.append(poly(outer, fill="#5c4a3e"))
out.append(poly(hexagon, fill="#2d2e2a"))
for name, angle in STATIONS + ALTARS:
    depth = STATION_DEPTH if "Altar" not in name else ALTAR_DEPTH
    n = polar(angle, 1)
    t = (math.cos(math.radians(angle)), math.sin(math.radians(angle)))
    corners = []
    for s, r in ((-RECESS_W / 2, APOTHEM - .1), (RECESS_W / 2, APOTHEM - .1), (RECESS_W / 2, APOTHEM + depth), (-RECESS_W / 2, APOTHEM + depth)):
        corners.append((n[0] * r + t[0] * s, n[1] * r + t[1] * s))
    out.append(poly(corners, fill="#34342f", stroke="#5c4a3e", stroke_width="2"))
# entrance corridor + vestibule (north)
out.append(poly([(-ENT_W / 2, -CIRCUM + 6), (ENT_W / 2, -CIRCUM + 6), (ENT_W / 2, -CORRIDOR_END), (-ENT_W / 2, -CORRIDOR_END)], fill="#2d2e2a", stroke="#5c4a3e", stroke_width="3"))
out.append(poly([(-VEST_W / 2, -CORRIDOR_END), (VEST_W / 2, -CORRIDOR_END), (VEST_W / 2, -CORRIDOR_END - VEST_D), (-VEST_W / 2, -CORRIDOR_END - VEST_D)], fill="#2d2e2a", stroke="#5c4a3e", stroke_width="3"))

# Combat platform, landing danger, shaft, basin
out.append(circle((0, 0), PLATFORM_R, fill="#4a4843", stroke="#1e1f1c", stroke_width="4"))
out.append(circle((0, 0), LANDING_R, fill="none", stroke="#c04040", stroke_width="1.5", stroke_dasharray="6 5"))
out.append(poly([(-SHAFT_HALF, -SHAFT_HALF), (SHAFT_HALF, -SHAFT_HALF), (SHAFT_HALF, SHAFT_HALF), (-SHAFT_HALF, SHAFT_HALF)], fill="none", stroke="#8a4fb0", stroke_width="1.5", stroke_dasharray="3 4"))
out.append(f'<ellipse cx="{to_svg(0, 0)[0]:.1f}" cy="{to_svg(0, 0)[1]:.1f}" rx="{BOSS_W / 2 * SCALE:.1f}" ry="{BOSS_D / 2 * SCALE:.1f}" fill="#7a3c96" fill-opacity=".18" stroke="#b070d0" stroke-width="1.5"/>')

# Channels (station mouth -> basin)
for name, angle in STATIONS:
    f = station_frame(angle)
    mouth = f(5, 7.7)
    d = math.hypot(*mouth)
    end = (mouth[0] / d * BASIN_R, mouth[1] / d * BASIN_R)
    out.append(line(mouth, end, stroke="#3d8fb8", stroke_width=f"{2.6 * SCALE:.1f}", stroke_opacity=".8"))
    out.append(line(f(5, -3.9), mouth, stroke="#3d8fb8", stroke_width=f"{2.1 * SCALE:.1f}", stroke_opacity=".8"))
out.append(circle((0, 0), BASIN_R, fill="#3d8fb8", fill_opacity=".75", stroke="#2a2a26", stroke_width="2"))

# Stations: footprint, wheel, plate, tablet
for name, angle in STATIONS:
    f = station_frame(angle)
    out.append(poly([f(-10.3, -5.3), f(8.4, -5.3), f(8.4, 7.7), f(-10.3, 7.7)], fill="#6b5a4c", fill_opacity=".55", stroke="#c9a46a", stroke_width="1.5"))
    out.append(poly([f(-8, 0.6), f(-4, 0.6), f(-4, 4.6), f(-8, 4.6)], fill="#6ee0a0", fill_opacity=".8"))
    out.append(poly([f(-9.5, 0.05), f(-8.6, 0.05), f(-8.6, 5.15), f(-9.5, 5.15)], fill="#cfd8cf"))
    out.append(circle(f(0, -1.45), 1.45, fill="#b06a3a"))
    out.append(circle(f(0, 0), .9, fill="#ffffff"))
    label = f(-1, 18)
    out.append(text(label, f"Gate {name}", 12, color="#f0c890"))

# Altars
for name, angle in ALTARS:
    c = polar(angle, APOTHEM + 6)
    out.append(circle(c, 5.5, fill="#78ebdc", fill_opacity=".35", stroke="#78ebdc"))
    out.append(circle(c, 1.5, fill="#78ebdc"))
    out.append(text(polar(angle, APOTHEM - 10), name, 12, color="#78ebdc"))

# Safe pads, sacks
for i, a in enumerate(SAFE, 1):
    c = polar(a, SAFE_D)
    out.append(circle(c, SAFE_R, fill="#52e1e1", fill_opacity=".15", stroke="#52e1e1", stroke_width="2"))
    out.append(text(c, f"Safe {i}", 11, color="#52e1e1"))
for a in SACKS:
    out.append(circle(polar(a, SACK_D), 2, fill="#a050c0"))

# Entrance markers
out.append(line((-ENT_W / 2, -SEAL_R), (ENT_W / 2, -SEAL_R), stroke="#e05a4a", stroke_width="4"))
out.append(text((ENT_W / 2 + 3, -SEAL_R + 1), "seal", 10, anchor="start", color="#e05a4a"))
out.append(line((-ENT_W / 2, -THRESH_R), (ENT_W / 2, -THRESH_R), stroke="#b07a3a", stroke_width="2", stroke_dasharray="4 3"))
out.append(text((ENT_W / 2 + 3, -THRESH_R + 1), "threshold", 10, anchor="start", color="#b07a3a"))
for k in range(8):
    out.append(circle((SPAWN_X + 4 * k, -SPAWN_R), 1.2, fill="#f0f0f0"))
out.append(text((0, -SPAWN_R - 6), "arrival (8 slots, realm SpawnPoint)", 10))
out.append(circle((0, -GATHER_R), 2.5, fill="#f0c890"))
out.append(text((4, -GATHER_R + 1), "party gather", 10, anchor="start", color="#f0c890"))

# Dimensions
def dim(a, b, label, offset=(0, 0), color="#9a9a90"):
    out.append(line(a, b, stroke=color, stroke_width="1"))
    mid = ((a[0] + b[0]) / 2 + offset[0], (a[1] + b[1]) / 2 + offset[1])
    out.append(text(mid, label, 10, color=color))

dim((0, 0), polar(90, PLATFORM_R), "platform r64", (0, -2))
dim(polar(90, PLATFORM_R), polar(90, APOTHEM), "ring 40", (0, -2))
dim((0, 0), polar(180, LANDING_R), "landing danger r49", (14, 0), "#c04040")
dim(polar(150, APOTHEM), polar(150, APOTHEM + STATION_DEPTH), "recess 13", (10, 4))
out.append(text((0, 5), "boss 60 x 64 (scale 0.67)", 11, color="#c890e0"))
out.append(text((0, 18), "latch shaft 92 x 92", 10, color="#8a4fb0"))

# Legend and scale bar
x0, y0 = PAD, SIZE - PAD
out.append(f'<line x1="{x0}" y1="{y0}" x2="{x0 + 50 * SCALE}" y2="{y0}" stroke="#d8ccb0" stroke-width="3"/>')
out.append(f'<text x="{x0}" y="{y0 - 8}" font-size="12" fill="#d8ccb0" font-family="Segoe UI, sans-serif">50 studs</text>')
legend = [
    ("Miasma T1 arena, player-scale layout pass (2026-09-25). North (entrance) is up.", "#d8ccb0"),
    ("Hexagon: wall inner face 104 from centre (corner 120). Ceiling underside 61 above floor.", "#9a9a90"),
    ("Stations: white = operator spot, orange = wheel, green = pressure plate, pale bar = rune tablet.", "#9a9a90"),
]
for i, (s, color) in enumerate(legend):
    out.append(f'<text x="{PAD}" y="{PAD + 14 + i * 18}" font-size="13" fill="{color}" font-family="Segoe UI, sans-serif">{s}</text>')
out.append("</svg>")

repo = Path(__file__).resolve().parents[1]
target = repo / "docs" / "images" / "miasma-layout-topdown.svg"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text("\n".join(out), encoding="utf-8")
print(f"wrote {target}")
