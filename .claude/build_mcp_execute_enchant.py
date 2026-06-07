import json
import pathlib

root = pathlib.Path(__file__).resolve().parent
src = (root / "roblox" / "ReplicatedStorage" / "EnchantScrollApply.lua").read_text(encoding="utf-8")
code = (
    'local rs = game:GetService("ReplicatedStorage")\n'
    "local old = rs:FindFirstChild('EnchantScrollApply')\n"
    "if old then old:Destroy() end\n"
    "local ms = Instance.new('ModuleScript')\n"
    "ms.Name = 'EnchantScrollApply'\n"
    "ms.Parent = rs\n"
    "ms.Source = [=[\n"
    + src
    + "\n]=]\n"
    "return #ms.Source\n"
)
out = {"code": code}
path = root / "mcp_execute_enchant_scroll.json"
path.write_text(json.dumps(out), encoding="utf-8")
print(path, "bytes", path.stat().st_size)
