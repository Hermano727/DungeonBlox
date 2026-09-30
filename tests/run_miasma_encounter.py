"""Run Miasma encounter + valve maze pure-logic regressions with the Luau CLI.

Uses the same bundle as tests/build_miasma_studio_bundle.py --mode spec, prefixed with
minimal shims for the Roblox types the modules touch (Vector2, Random). Without a Luau
CLI, generate the bundle and run it in Studio's command bar in Edit mode instead.
"""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--luau", default="luau", help="Path to the Luau CLI executable")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]

SHIMS = r'''
local V = {}
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y); return Vector2.new(t.X / m, t.Y / m) end
end
V.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
V.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
V.__mul = function(a, b)
	if type(a) == "number" then return Vector2.new(a * b.X, a * b.Y) end
	if type(b) == "number" then return Vector2.new(a.X * b, a.Y * b) end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
V.__div = function(a, b) return Vector2.new(a.X / b, a.Y / b) end
V.__unm = function(a) return Vector2.new(-a.X, -a.Y) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V) end }
Random = { new = function()
	return {
		NextInteger = function(_, a, b) return math.random(a, b) end,
		NextNumber = function() return math.random() end,
	}
end }
'''

bundle = subprocess.run(
    [sys.executable, str(repo / "tests" / "build_miasma_studio_bundle.py"), "--mode", "spec"],
    check=True, capture_output=True, text=True,
).stdout
# The bundle ends with `return "PASS..."`; print it instead so the CLI shows the result.
source = SHIMS + "\nlocal function run()\n" + bundle + "\nend\nlocal result = run()\nprint(result)\nif not string.find(result, '^PASS') then error(result) end\n"
with tempfile.TemporaryDirectory(prefix="miasma-encounter-") as directory:
    path = Path(directory) / "tests.luau"
    path.write_text(source, encoding="utf-8")
    result = subprocess.run([args.luau, str(path)], check=False)
raise SystemExit(result.returncode)
