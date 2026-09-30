"""Bundle the Miasma pure-logic spec for a Studio EDIT-MODE run (no Play mode needed).

Writes a single Luau chunk that:
  1. compiles (loadstring, not runs) every Miasma valve / encounter script, and
  2. runs tests/miasma_encounter.spec.luau against the real shared modules and
     MiasmaMazeService, with os.clock() and require() shimmed.

Usage:
    python tests/build_miasma_studio_bundle.py --mode compile > bundle_compile.luau
    python tests/build_miasma_studio_bundle.py --mode spec > bundle_spec.luau
Paste the output into Studio's command bar (or an MCP execute_luau call) in Edit mode.
It needs no running game and changes nothing in the place.
"""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--mode", choices=["compile", "spec"], required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]

RUNTIME = {
    "MiasmaEncounterConfig": "src/shared/MiasmaEncounterConfig.luau",
    "MiasmaEncounterMath": "src/shared/MiasmaEncounterMath.luau",
    "MiasmaMazeLayouts": "src/shared/MiasmaMazeLayouts.luau",
    "MiasmaMazeGeometry": "src/shared/MiasmaMazeGeometry.luau",
    "MiasmaRunes": "src/shared/MiasmaRunes.luau",
    "MiasmaArenaLayout": "src/shared/MiasmaArenaLayout.luau",
    "MiasmaMazeService": "src/server/MiasmaMazeService.luau",
    "Spec": "tests/miasma_encounter.spec.luau",
}
COMPILE_ONLY = [
    "src/shared/MiasmaRuneArt.luau",
    "src/shared/MiasmaEncounterProtocol.luau",
    "src/shared/KeybindConfig.luau",
    "src/server/MiasmaValveStationPlacement.luau",
    "src/server/MiasmaValveStationBuilder.luau",
    "src/server/MiasmaValveStation.luau",
    "src/server/MiasmaValveGate.luau",
    "src/server/MiasmaValveDevHarness.server.luau",
    "src/server/MiasmaArenaResolver.luau",
    "src/server/MiasmaEncounterController.luau",
    "src/server/MiasmaEncounterService.luau",
    "src/client/MiasmaValveMazeUI.luau",
    "src/client/MiasmaEncounterClient.client.luau",
]


def long_string(source: str) -> str:
    level = 1
    while ("]" + "=" * level + "]") in source:
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{source}\n]{eq}]"


out = ["local sources = {}"]
if args.mode == "compile":
    for path in COMPILE_ONLY + list(RUNTIME.values()):
        src = (repo / path).read_text(encoding="utf-8-sig")
        out.append(f'sources["{path}"] = {long_string(src)}')
    out.append('''local failures = {}
local n = 0
for name, src in pairs(sources) do
	n += 1
	local fn, err = loadstring(src, "=" .. name)
	if not fn then table.insert(failures, name .. ": " .. tostring(err)) end
end
if #failures > 0 then return "COMPILE FAIL\\n" .. table.concat(failures, "\\n") end
return ("COMPILE OK: %d files"):format(n)''')
else:
    for name, path in RUNTIME.items():
        src = (repo / path).read_text(encoding="utf-8-sig")
        out.append(f'sources["{name}"] = {long_string(src)}')
    out.append('''local now = 0
local modules = {}
local fakeReplicatedStorage = { WaitForChild = function(_, name) return name end }
local env = setmetatable({
	game = { GetService = function() return fakeReplicatedStorage end },
	require = function(name) return assert(modules[name], "no module " .. tostring(name)) end,
	os = setmetatable({ clock = function() return now end }, { __index = os }),
	warn = function(...) error(table.concat({ ... }, " ")) end,
}, { __index = getfenv(0) })
local function load(name)
	local fn = assert(loadstring(sources[name], "=" .. name))
	setfenv(fn, env)
	return fn()
end
for _, name in ipairs({ "MiasmaEncounterConfig", "MiasmaEncounterMath", "MiasmaMazeLayouts", "MiasmaMazeGeometry", "MiasmaRunes", "MiasmaArenaLayout", "MiasmaMazeService" }) do
	modules[name] = load(name)
end
local spec = load("Spec")
local ok, result = pcall(spec, {
	Math = modules.MiasmaEncounterMath,
	Config = modules.MiasmaEncounterConfig,
	Layouts = modules.MiasmaMazeLayouts,
	Geometry = modules.MiasmaMazeGeometry,
	Runes = modules.MiasmaRunes,
	Layout = modules.MiasmaArenaLayout,
	newMazeService = function() return modules.MiasmaMazeService.new() end,
	setClock = function(t) now = t end,
})
if not ok then return "SPEC FAIL: " .. tostring(result) end
return ("PASS: %d Miasma checks"):format(result)''')
print("\n".join(out))
