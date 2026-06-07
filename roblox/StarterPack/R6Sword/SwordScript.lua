r = game:service("RunService")

local damage = 0

sword = script.Parent.Handle
Tool = script.Parent

local damages,values,sounds = {30,45,65},{Tool.PlaySlash,Tool.PlayThrust,Tool.PlayOverhead},{Tool.Handle.SlashSound,Tool.Handle.OverheadSound,Tool.Handle.LungeSound}
local enabledToDamage = true

function blow(hit)
	if enabledToDamage == false then return end
	enabledToDamage = false
	if (hit.Parent == nil) then enabledToDamage = true return end -- happens when bullet hits sword
	local humanoid = hit.Parent:findFirstChild("Humanoid")
	local vCharacter = Tool.Parent
	local vPlayer = game.Players:playerFromCharacter(vCharacter)
	local hum = vCharacter:findFirstChild("Humanoid") -- non-nil if tool held by a character
	if humanoid~=nil and humanoid ~= hum and hum ~= nil then
		-- final check, make sure sword is in-hand
		local right_arm = vCharacter:FindFirstChild("Right Arm")
		if (right_arm ~= nil) then
			local joint = right_arm:FindFirstChild("RightGrip")
			if (joint ~= nil and (joint.Part0 == sword or joint.Part1 == sword)) then
				tagHumanoid(humanoid, vPlayer)
				humanoid:TakeDamage(damage)
				wait(1)
				untagHumanoid(humanoid)
			else
				enabledToDamage = true
			end
		else
			enabledToDamage = true
		end
	else
		enabledToDamage = true
	end
end


function tagHumanoid(humanoid, player)
	local creator_tag = Instance.new("ObjectValue")
	creator_tag.Value = player
	creator_tag.Name = "creator"
	creator_tag.Parent = humanoid
end

function untagHumanoid(humanoid)
	if humanoid ~= nil then
		local tag = humanoid:findFirstChild("creator")
		if tag ~= nil then
			tag.Parent = nil
		end
	end
end


function attack()
	damage = slash_damage
	script.Parent.Handle.SlashSound:Play()
	script.Parent.PlaySlash.Value = not script.Parent.PlaySlash.Value
end

function lunge()
	damage = lunge_damage
	script.Parent.Handle.LungeSound:Play()
	script.Parent.PlayOverhead.Value = not script.Parent.PlayOverhead.Value
	force = Instance.new("BodyVelocity")
	force.velocity = Vector3.new(0,10,0) --Tool.Parent.Torso.CFrame.lookVector * 80
	force.Parent = Tool.Parent.Torso
	wait(.5)
	force.Parent = nil
	wait(.5)
	damage = slash_damage
end


Tool.Enabled = true
local last_attack = 0
local status = 0

function onActivated()
	if not Tool.Enabled then
		return
	end
	Tool.Enabled = false
	local character = Tool.Parent;
	local humanoid = character.Humanoid
	if humanoid == nil then
		print("Humanoid not found")
		return
	end
	t = r.Stepped:wait()
	if (t - last_attack < 1.5) then
		if status == 3 then
			status = 0
			damage = 0
		else
			status = status + 1
			values[status].Value = not values[status].Value
			damage = damages[status]
			sounds[status]:Play()
			enabledToDamage = true
			wait(0.5)
			enabledToDamage = false
		end
	else
		status = 0
		damage = 0
	end
	last_attack = t
	Tool.Enabled = true
end

function onEquipped()
	wait(1/3)
	Tool.Handle.UnsheathSound:Play()
end

Tool.Equipped:connect(onEquipped)
script.Parent.Activated:connect(onActivated)
connection = sword.Touched:connect(blow)