--[[
	MobHitFlashClient
	Server confirms a landed hit on a mob (MobCombat.applyDamage, the same
	gate that fires DamageNumberEvent -- actualDamage > 0) and broadcasts
	MobHitFlash to every client, not just the attacker: this is the mob's
	own on-screen state, so everyone looking at it should see the same
	flash at the same moment.

	Effect: a white Highlight overlay snaps on, holds briefly, then fades
	out. Chosen over recoloring every BasePart because it needs no per-part
	bookkeeping (works the same for a ScriptedBody mob's single "Body" part
	and a fully-rigged mob's many MeshParts) and can't drift out of sync
	with anything else touching Color (e.g. MobScriptedBodyAnim's own
	Size tweening).

	Total duration is tunable below; kept comfortably under 0.3s per
	direct request.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MobHitFlash = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("MobHitFlash", 60)
if not MobHitFlash then
	warn("[MobHitFlashClient] MobHitFlash missing after 60s")
	return
end

------------------------------------------------------------
-- Tunables
------------------------------------------------------------

local FLASH_IN_TIME = 0.03 -- near-instant snap to white -- the hit should read immediately
local FLASH_HOLD_TIME = 0.08 -- brief hold at full white
local FLASH_OUT_TIME = 0.12 -- fade back out
-- Total ~0.23s from hit to fully cleared.

local FLASH_FILL_TRANSPARENCY = 0.35 -- how solid the white overlay reads at peak (0 = opaque)
local FLASH_COLOR = Color3.new(1, 1, 1)

------------------------------------------------------------
-- One Highlight per model, reused across rapid re-hits
------------------------------------------------------------

-- Weak-keyed so an entry for a mob model that's since been destroyed (died,
-- or never got a fresh hit again) doesn't linger forever.
local activeFlashes = setmetatable({}, { __mode = "k" })

local function ensureHighlight(model)
	local state = activeFlashes[model]
	if state and state.highlight.Parent then
		return state
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "HitFlash"
	highlight.FillColor = FLASH_COLOR
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1 -- fill only -- reads as the mob itself flashing, not a selection glow
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded -- respect normal occlusion, no x-ray-through-walls
	highlight.Adornee = model
	highlight.Parent = model

	state = { highlight = highlight, token = 0 }
	activeFlashes[model] = state
	return state
end

-- A hit landing again while a flash is already mid-play (fast weapon, an AoE
-- swing catching the same mob twice) bumps the token so the in-flight
-- fade-out below no-ops and this call's own fade-out takes over instead --
-- restarts the hold/fade rather than stacking a second Highlight.
local function flashModel(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent then
		return
	end

	local state = ensureHighlight(model)
	state.token += 1
	local myToken = state.token
	local highlight = state.highlight

	TweenService:Create(highlight, TweenInfo.new(FLASH_IN_TIME, Enum.EasingStyle.Linear), {
		FillTransparency = FLASH_FILL_TRANSPARENCY,
	}):Play()

	task.delay(FLASH_IN_TIME + FLASH_HOLD_TIME, function()
		if state.token ~= myToken or not highlight.Parent then
			return
		end
		local fadeOut = TweenService:Create(highlight, TweenInfo.new(FLASH_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			FillTransparency = 1,
		})
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if state.token == myToken and activeFlashes[model] == state then
				activeFlashes[model] = nil
				highlight:Destroy()
			end
		end)
	end)
end

MobHitFlash.OnClientEvent:Connect(flashModel)
