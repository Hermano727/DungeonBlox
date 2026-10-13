-- The hand that holds the sword (client/SwordGripPose): Roblox bone Transforms for Hand_R and the right
-- fingers, measured from the grip posed in assets/models/main character/locomotion/FP_Swing_Edit.blend
-- (2026-10-13; raw values in grip_final.json there), converted with export_fp_swing.py's bone correction.
-- The sword's placement in this hand is CharacterAnimProfiles.SWORD_GRIP_OFFSET, measured from the same pose.
--   HandTilt  multiplied onto whatever the playing clip gives Hand_R: a fixed tilt toward the little
--             finger, so the blade runs near the line of the forearm. It never changes during a swing.
--   Fingers   replace the clips' own finger keys outright: the fist closed round the diagonal handle,
--             thumb over the fingers.
-- CFrame components: x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22.
return {
	HandTilt = { 0, 0, 0, 0.95523, -0.29469, -0.02637, 0.29469, 0.93969, 0.1736, -0.02637, -0.1736, 0.98446 },
	Fingers = {
		Thumb_01_R = { 0, 0, 0, 1, 0, 0, 0, 0.57358, -0.81915, 0, 0.81915, 0.57358 },
		Thumb_02_R = { -0.01332, 0.02311, -0.00242, 0.79322, -0.6076, 0.04028, 0.56907, 0.76322, 0.30603, -0.21668, -0.21983, 0.95117 },
		Thumb_03_R = { 0.01284, 0.04005, 0.02573, 0.82441, -0.31292, -0.47163, 0.53294, 0.14858, 0.83301, -0.19059, -0.93808, 0.28926 },
		Index_01_R = { 0, 0, 0, 1, 0, 0, 0, 0.74314, -0.66913, 0, 0.66913, 0.74314 },
		Index_02_R = { 0, 0, 0, 1, 0, 0, 0, 0.55919, -0.82904, 0, 0.82904, 0.55919 },
		Index_03_R = { 0, 0, 0, 1, 0, 0, 0, 0.81915, -0.57358, 0, 0.57358, 0.81915 },
		Middle_01_R = { 0, 0, 0, 1, 0, 0, 0, 0.74314, -0.66913, 0, 0.66913, 0.74314 },
		Middle_02_R = { 0, 0, 0, 1, 0, 0, 0, 0.55919, -0.82904, 0, 0.82904, 0.55919 },
		Middle_03_R = { 0, 0, 0, 1, 0, 0, 0, 0.81915, -0.57358, 0, 0.57358, 0.81915 },
		Ring_01_R = { 0, 0, 0, 1, 0, 0, 0, 0.74314, -0.66913, 0, 0.66913, 0.74314 },
		Ring_02_R = { 0, 0, 0, 1, 0, 0, 0, 0.55919, -0.82904, 0, 0.82904, 0.55919 },
		Ring_03_R = { 0, 0, 0, 1, 0, 0, 0, 0.81915, -0.57358, 0, 0.57358, 0.81915 },
		Little_01_R = { 0, 0, 0, 1, 0, 0, 0, 0.74314, -0.66913, 0, 0.66913, 0.74314 },
		Little_02_R = { 0, 0, 0, 1, 0, 0, 0, 0.55919, -0.82904, 0, 0.82904, 0.55919 },
		Little_03_R = { 0, 0, 0, 1, 0, 0, 0, 0.81915, -0.57358, 0, 0.57358, 0.81915 },
	},
}
