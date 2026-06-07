from pathlib import Path

for i in (1, 2, 3):
    b = Path(f"b64_{i}.txt").read_text().strip()
    if "]]" in b:
        raise SystemExit("base64 chunk contains ]]")
    if i == 1:
        code = f'''local HS = game:GetService("HttpService")
local rs = game.ReplicatedStorage
local old = rs:FindFirstChild("EnchantScrollApply")
if old then old:Destroy() end
local ms = Instance.new("ModuleScript")
ms.Name = "EnchantScrollApply"
ms.Parent = rs
ms.Source = HS:Base64Decode([[{b}]])
return #ms.Source
'''
    else:
        code = f'''local HS = game:GetService("HttpService")
local rs = game.ReplicatedStorage
local ms = rs:WaitForChild("EnchantScrollApply")
ms.Source = ms.Source .. HS:Base64Decode([[{b}]])
return #ms.Source
'''
    Path(f"luau_exec_{i}.lua").write_text(code, encoding="utf-8")
print("wrote", [Path(f"luau_exec_{i}.lua").stat().st_size for i in (1, 2, 3)])
