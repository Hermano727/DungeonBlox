--[[
	MountRiderGuiCleanup
	Single source of truth for stripping the horse-ride HUD leftovers
	(the cloned "LocalControlScript" ride-control LocalScript and "HorseGui")
	out of a PlayerGui. This exact scan used to be pasted twice:
	  - MountService (server), pre-emptively before destroying the mount model
	  - MountRiderCleanupClient (client), after the MountRiderCleanup remote
	    fires -- needed because jump-state restoration is client-authoritative
	    and can't be driven purely from the server (see that script's header).
	Both call sides still run their own extra Humanoid state fixes after this;
	only the GUI-scan part was truly identical and worth sharing.
]]

local MountRiderGuiCleanup = {}

function MountRiderGuiCleanup.Clean(playerGui)
	if not playerGui then
		return
	end
	for _, c in ipairs(playerGui:GetChildren()) do
		if c:IsA("LocalScript") and c.Name == "LocalControlScript" then
			local hv = c:FindFirstChild("Horse")
			if hv and hv:IsA("ObjectValue") then
				c:Destroy()
			end
		end
	end
	local hg = playerGui:FindFirstChild("HorseGui")
	if hg then
		hg:Destroy()
	end
end

return MountRiderGuiCleanup
