-- The dash pose: the run caught mid-flight (front knee up, back leg stretched behind, hard lean), held for
-- the length of the burst. Three arm placements, one picked at random per dash (DashClient), each authored
-- armed (sword hand keeps its grip, blade along the arm) and unarmed. Full-body KeyframeSequences on the
-- 52-bone Hero_Rig, a pose held 3 s; DashClient plays them at Action2 and stops them with a fade.
-- Source: assets/models/main character/locomotion/author_dash.py (publish_locomotion.py T1_Dash).
--   Pump   one fist punched forward, the other flung back (the run's swing at its extreme)
--   Trail  both arms swept back behind the body
--   Guard  one forearm across the chest, the other back and low
return table.freeze({
	Variants = { "Pump", "Trail", "Guard" },
	Clips = {
		Pump = { Unarmed = "rbxassetid://116770653506036", Armed = "rbxassetid://80705915114245" },
		Trail = { Unarmed = "rbxassetid://137787601806177", Armed = "rbxassetid://76329750554809" },
		Guard = { Unarmed = "rbxassetid://134006930920599", Armed = "rbxassetid://96199476221372" },
	},
})
