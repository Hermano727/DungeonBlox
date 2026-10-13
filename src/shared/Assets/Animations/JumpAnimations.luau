-- Custom 52-bone Hero_Rig jump clips, played by the jumper's client (src/characterscripts/JumpMotion)
-- and replicated to everyone through the Animator. Each state is two native KeyframeSequences so the
-- arms can be left to the weapon hold: Body (pelvis, spine, neck, head, legs: always) and Arms
-- (clavicles to fingers: only when nothing is held).
-- Source: assets/models/main character/jump/author_jump.py (publish_jump.py -> jump_ids.json).
-- Takeoff / Land play their motion (0.40 / 0.52 s) and then HOLD the last pose, so a state that outlasts the clip
-- never drops the character back to the run pose (JumpMotion ends them on JumpConfig's timings). Rise / LongAir /
-- Fall: the Body clip moves into its pose and holds it for 6 s;
-- the Arms clip LOOPS a small balance wobble (LoopedArms) for as long as the jump lasts.
local Clips = {
	Takeoff = { Body = "rbxassetid://97211627941488", Arms = "rbxassetid://98260091668407" }, -- 0.40 s, then holds
	Rise    = { Body = "rbxassetid://116520771300069", Arms = "rbxassetid://105534865667971" }, -- standing / short jump air pose
	LongAir = { Body = "rbxassetid://81948190176750", Arms = "rbxassetid://139069681951194" }, -- faster than any sprint
	Fall    = { Body = "rbxassetid://109350208749411", Arms = "rbxassetid://87222255858429" },
	Land    = { Body = "rbxassetid://114156540189891", Arms = "rbxassetid://121737493187241" }, -- 0.52 s, then holds
}

local bodyIds = {}
for _, clip in pairs(Clips) do bodyIds[clip.Body] = true end

return {
	Clips = Clips,
	LoopedArms = { Rise = true, LongAir = true, Fall = true },
	-- True for a jump BODY clip: other systems that clear the Action layer (the potion drink) leave
	-- these alone, because they carry the legs and spine, not the arms the drink needs.
	IsBodyClip = function(animationId)
		return bodyIds[animationId] == true
	end,
}
