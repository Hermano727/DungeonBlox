-- Select visuals from actual resolved combat outcomes. Never roll on the client.
local Feedback = {}

function Feedback.Select(hitInfo, armorHit, extras)
	local hit = hitInfo or {}
	local armor = armorHit or {}
	local effects = {
		Execute = hit.isExe == true and (hit.executeBonus or 0) > 0,
		Piercing = hit.isPiercing == true,
		Shatter = armor.isShatter == true,
		Crushing = armor.isCrushing == true,
		Elemental = (hit.elementalDamage or 0) > 0,
	}
	for key, value in pairs(extras or {}) do effects[key] = value == true end
	return effects
end

-- Called before damage, while the model still exists. Clamp the validated hit
-- point back to its bounds so latency forgiveness doesn't float the effect away.
function Feedback.Snapshot(model, attackerRoot, hitPosition)
	if not model or not attackerRoot then return nil end
	local box, size = model:GetBoundingBox()
	local half = size * 0.5
	local point = typeof(hitPosition) == "Vector3" and box:PointToObjectSpace(hitPosition) or Vector3.zero
	point = Vector3.new(math.clamp(point.X, -half.X, half.X), math.clamp(point.Y, -half.Y, half.Y), math.clamp(point.Z, -half.Z, half.Z))
	local position = box:PointToWorldSpace(point)
	local delta = position - attackerRoot.Position
	local direction = delta.Magnitude > 0.01 and delta.Unit or attackerRoot.CFrame.LookVector
	do
		-- Overlap/area attacks can report a point inside the body. Move outward
		-- along the incoming direction to the surface (a ray hit stays in place).
		local toward = box:VectorToObjectSpace(-direction)
		local distance = math.huge
		for _, pair in ipairs({ {toward.X, half.X, point.X}, {toward.Y, half.Y, point.Y}, {toward.Z, half.Z, point.Z} }) do
			if math.abs(pair[1]) > 0.001 then
				local edge = pair[1] > 0 and pair[2] or -pair[2]
				distance = math.min(distance, (edge - pair[3]) / pair[1])
			end
		end
		position -= direction * distance
	end
	return { position = position - direction * 0.12, direction = direction,
		scale = math.clamp(math.min(size.X, size.Y) / 3, 0.65, 1.6) }
end

return Feedback
