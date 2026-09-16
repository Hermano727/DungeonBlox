-- SettingsStore
-- Fetches the player's saved Settings-menu values from the server exactly
-- once (RemoteFunction "GetPlayerSettings"), so VolumeSettings.luau and
-- VideoSettings.luau -- two separate ModuleScripts -- don't each make their
-- own round trip. Whichever of them is required first blocks on this;
-- Roblox caches ModuleScript results, so every later requirer (of either
-- module) gets the resolved values instantly, no matter the load order of
-- FirstPersonViewModel/Crouching/Animate2/ZoneClient/SettingsClient.
--
-- Returns a sparse table: only fields the player has actually changed and
-- saved come back non-nil (a brand new player gets {}). VolumeSettings /
-- VideoSettings are responsible for filling gaps with their own defaults --
-- same fill-missing-from-default pattern already used by DataSchema.lua /
-- ProfileTypes.lua for the player profile.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsStore = {}

local cached = nil

function SettingsStore.Get()
	if cached then
		return cached
	end

	if not RunService:IsClient() then
		-- Nothing server-side reads these today; stay quiet and inert rather
		-- than erroring if that ever changes.
		cached = {}
		return cached
	end

	local rf = ReplicatedStorage:WaitForChild("GetPlayerSettings", 10)
	local ok, result = false, nil
	if rf then
		ok, result = pcall(function()
			return rf:InvokeServer()
		end)
	end

	if ok and type(result) == "table" then
		cached = result
	else
		if not ok then
			warn("[SettingsStore] GetPlayerSettings failed, using defaults: " .. tostring(result))
		end
		cached = {}
	end
	return cached
end

return SettingsStore
