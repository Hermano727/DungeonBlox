--[[
	AppearanceApply -- puts a saved appearance (RS/Assets/Appearance/AppearanceOptions) onto a
	character model. One function for both sides, so what the wardrobe previews is exactly
	what everyone else sees:
		server  AppearanceService, on every spawn and after a save (replicates to all)
		client  the wardrobe's preview clone, live while you browse

	Skin: the player mesh (Hero_Character) wears the skin-mask texture as a SurfaceAppearance
	in Overlay mode, so the MeshPart's Color IS the skin tone (clothes are opaque, unaffected).

	Face (eyes / nose / mouth): written as attributes on the model ("Appearance_Eyes" = option
	Id). The face itself is a cosmetic plate every client draws and moves with the head bone
	(src/client/FacePlates), the same way weapons follow the hand; the attributes are how it
	knows what to draw (server-set attributes replicate to everyone).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AppearanceOptions = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Appearance"):WaitForChild("AppearanceOptions"))

local AppearanceApply = {}

local BODY_MESH = "Hero_Character"
AppearanceApply.ATTRIBUTE_PREFIX = "Appearance_"

function AppearanceApply.Apply(character, appearance)
	if typeof(character) ~= "Instance" then return end
	appearance = AppearanceOptions.Sanitize(appearance)
	local body = character:FindFirstChild(BODY_MESH)
	if body and body:IsA("MeshPart") then
		body.Color = AppearanceOptions.SkinColor(appearance.Skin)
	end
	for _, id in ipairs(AppearanceOptions.FaceLayers) do
		character:SetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. id, appearance[id])
	end
	character:SetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. "EyeColor", appearance.EyeColor)
	character:SetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. "Hair", appearance.Hair)
	character:SetAttribute(AppearanceApply.ATTRIBUTE_PREFIX .. "HairColor", appearance.HairColor)
end

return AppearanceApply
