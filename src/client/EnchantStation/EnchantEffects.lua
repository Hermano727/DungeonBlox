--!strict
--[[
	EnchantEffects
	Local-only particle bursts for an enchant result, played around the local
	player's character: green sparkles that shoot out and arc down like tiny
	fireworks on success; black ash plus falling red/orange embers on failure.

	Built from throwaway ParticleEmitters (Rate 0, one-shot :Emit bursts) parented
	to short-lived Attachments on the HumanoidRootPart, then Debris'd -- nothing
	persists, nothing replicates (other players don't see it; it's feedback for the
	person enchanting).

	PARTICLE_TEXTURE is empty on purpose: ParticleEmitter's built-in sparkle sprite
	is used until a pixel-art sprite (the Minecraft-style 4-point star) is uploaded.
	Put its rbxassetid here and every emitter below picks it up.
]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local PARTICLE_TEXTURE = ""

local EnchantEffects = {}

local function getRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function newEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.LockedToPart = false
	emitter.SpreadAngle = Vector2.new(360, 360)
	if PARTICLE_TEXTURE ~= "" then
		emitter.Texture = PARTICLE_TEXTURE
	end
	for k, v in pairs(props) do
		(emitter :: any)[k] = v
	end
	emitter.Parent = parent
	return emitter
end

-- Attachments spread on a ring around (and at chest height on) the character, so the
-- burst reads as coming from "around the player" rather than from one point.
local function ringAttachments(root: BasePart, count: number, radius: number, height: number): { Attachment }
	local out = {}
	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
		att.Parent = root
		Debris:AddItem(att, 4)
		table.insert(out, att)
	end
	return out
end

function EnchantEffects.PlaySuccess()
	local root = getRoot()
	if not root then
		return
	end
	local green = ColorSequence.new(Color3.fromRGB(120, 255, 150), Color3.fromRGB(0, 170, 60))
	for _, att in ipairs(ringAttachments(root, 4, 2.5, 1)) do
		local emitter = newEmitter(att, {
			Color = green,
			LightEmission = 1,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.7, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(0.8, 1.4),
			Speed = NumberRange.new(14, 26),
			Acceleration = Vector3.new(0, -22, 0),
			Drag = 1.2,
			RotSpeed = NumberRange.new(-120, 120),
		})
		-- Two staggered bursts per ring point: the second reads as the firework's trailing pop.
		emitter:Emit(22)
		task.delay(0.18, function()
			if emitter.Parent then
				emitter:Emit(14)
			end
		end)
	end
end

function EnchantEffects.PlayFail()
	local root = getRoot()
	if not root then
		return
	end
	for _, att in ipairs(ringAttachments(root, 4, 2, 1)) do
		-- Ash: dark, slow, drifts down and fades.
		local ash = newEmitter(att, {
			Color = ColorSequence.new(Color3.fromRGB(38, 34, 34), Color3.fromRGB(12, 10, 10)),
			LightEmission = 0,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.7),
				NumberSequenceKeypoint.new(1, 1.2),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.05),
				NumberSequenceKeypoint.new(0.6, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(1.2, 2.2),
			Speed = NumberRange.new(4, 11),
			Acceleration = Vector3.new(0, -5, 0),
			Drag = 2,
			RotSpeed = NumberRange.new(-90, 90),
		})
		ash:Emit(14)

		-- Embers: small glowing red/orange balls that pop out then fall hard.
		local embers = newEmitter(att, {
			Color = ColorSequence.new(Color3.fromRGB(255, 190, 60), Color3.fromRGB(200, 30, 0)),
			LightEmission = 1,
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 0.1),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.8, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(0.9, 1.6),
			Speed = NumberRange.new(6, 16),
			Acceleration = Vector3.new(0, -42, 0),
			Drag = 0.6,
		})
		embers:Emit(10)
	end
end

return EnchantEffects
