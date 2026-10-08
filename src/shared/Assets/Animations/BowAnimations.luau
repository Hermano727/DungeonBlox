-- Custom 52-bone Hero_Rig. Upper-body masked clips, played by the shooter's client and
-- replicated to everyone through the Animator.
-- Source: assets/models/armor weapons equipment/T1_Bow/animation/author_bow.py
-- Published under the experience owner. An empty id skips that clip; the bow still shoots.
return {
	T1_BOW_HOLD = "rbxassetid://76306614088210", -- loop, Idle: bow carried low across the body, string up (hand-posed in T1_Bow_Anims.blend, both arms)
	T1_BOW_DRAW = "rbxassetid://134578852964081", -- 1.0 s, Action: raise, nock (0.22 s), draw to the chin
	T1_BOW_AIM = "rbxassetid://89252030824538", -- loop, Action: full draw, slight tremble
	T1_BOW_RELEASE = "rbxassetid://109318222050856", -- 0.45 s, Action: loose, then lower to the hold
}
