local RS=game:GetService("ReplicatedStorage")
local SSS=game:GetService("ServerScriptService")
local EnergyData=require(SSS:WaitForChild("EnergyData"))
local EnergyConfig=require(RS:WaitForChild("EnergyConfig"))
local MountService=require(SSS:WaitForChild("MountService"))
local TrySwing=RS:WaitForChild("GameEvents"):WaitForChild("TrySwing")
local SwingResult=RS:WaitForChild("GameEvents"):WaitForChild("SwingResult")

local _dp
local function getDP() if not _dp then _dp=require(SSS:WaitForChild("ProfileService")) end return _dp end

local function getWeaponSwingMult(player)
	local char=player.Character
	local tool=char and char:FindFirstChildOfClass("Tool")
	if not tool then return 1.0 end
	local uuid=tool:GetAttribute("DungeonItemUuid")
	if type(uuid)~="string" or uuid=="" then return 1.0 end
	local profile=getDP().Get(player)
	if not profile or type(profile.inventory)~="table" then return 1.0 end
	local item=profile.inventory[uuid]
	if type(item)~="table" or type(item.tags)~="table" then return 1.0 end
	local mults=EnergyConfig.WEAPON_SWING_MULT or {}
	for _,tag in ipairs(item.tags) do if mults[tag] then return mults[tag] end end
	return 1.0
end

TrySwing.OnServerEvent:Connect(function(p,weaponId)
	MountService.dismount(p)
	local mult=getWeaponSwingMult(p)
	local allowed=EnergyData.trySwing(p,mult)
	SwingResult:FireClient(p,allowed)
end)
print("[CombatService] ready")
