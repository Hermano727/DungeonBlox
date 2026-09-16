--[[
	NPCBootstrapKit
	Shared building blocks for every *Bootstrap / *NpcBootstrap server script
	(MerchantBootstrap, BlacksmithBootstrap, InnkeeperBootstrap, AnimalTrainerBootstrap,
	DungeoneerBootstrap, CusoNpcBootstrap, MinerNpcBootstrap, FishermanNpcBootstrap).

	Each of those scripts wires a hand-placed Workspace Model into the NPC system:
	attributes + CollectionService "NPC" tag + ProximityPrompt + a floating
	name/dialog BillboardGui (the DialogModule contract). Before this module existed,
	all eight scripts hand-rolled their own copy of that ~90-line boilerplate with only
	small per-NPC differences (nameplate colors, prompt text, id-numbering scheme,
	retry timing) — this factors out the identical parts so each bootstrap script only
	has to state what's actually different about that NPC.

	Deliberately NOT abstracted here (kept in each bootstrap file, on purpose):
	  - The exact wording/shape of warn() calls on missing Head/root — these differ
	    subtly per file (some include model:GetFullName(), some don't; some warn on a
	    missing Head, some silently skip) and preserving that exactly during this
	    refactor mattered more than making every log line identical.
	  - Workspace.ChildAdded / DescendantAdded watcher wiring — each NPC type reacts a
	    little differently (single-instance vs multi-instance, per-instance rewire vs
	    "rewire everything"), and that routing logic is the one genuinely NPC-specific
	    part of each script.

	Nothing here is server-only (no ServerScriptService requires), so it lives in
	shared/ alongside NPCRegistry rather than server/, in case a client script ever
	wants the same "find all NPC models" helpers.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local NPCBootstrapKit = {}

-- Fallback nameplate colors for callers that don't pass their own scheme.
NPCBootstrapKit.DefaultColors = {
	text   = Color3.fromRGB(255, 220, 150),
	stroke = Color3.fromRGB(80, 60, 20),
}

---------------------------------------------------------------------------
-- Head billboard (name / talk-arrow / dialog line)
---------------------------------------------------------------------------

--- Creates the standard floating name/dialog BillboardGui on `head` if one isn't
--- already there (idempotent — safe to call every bootstrap pass). Matches the
--- DialogModule contract every NPC dialog UI expects: a "gui" BillboardGui with
--- "name", "arrow", and "dialog" TextLabels.
--- colors: { text = Color3, stroke = Color3 } — optional, defaults to DefaultColors.
--- npcType: string identifying the NPC archetype ("Merchant", "Blacksmith", etc.) -- passed
--- straight to UIFonts.GetNPCFont so a future per-archetype override (UIFonts.NPCOverrides)
--- takes effect without this function changing. nil falls back to UIFonts.NPCDefault.
function NPCBootstrapKit.EnsureHeadGui(head, displayName, colors, npcType)
	if head:FindFirstChild("gui") then
		return
	end
	colors = colors or NPCBootstrapKit.DefaultColors

	local bb = Instance.new("BillboardGui")
	bb.Name        = "gui"
	bb.Size        = UDim2.new(8, 0, 1.5, 0)
	bb.StudsOffset = Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop = false
	bb.Parent      = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name                   = "name"
	nameLabel.Size                   = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.FontFace               = UIFonts.GetNPCFont(npcType, "Name")
	nameLabel.TextSize               = 16
	nameLabel.TextColor3             = colors.text
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text                   = displayName
	nameLabel.Parent                 = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color  = colors.stroke
		s.Parent = nameLabel
	end)

	local arrow = Instance.new("TextLabel")
	arrow.Name                   = "arrow"
	arrow.Size                   = UDim2.new(1, 0, 0.3, 0)
	arrow.Position               = UDim2.new(0, 0, 0.45, 0)
	arrow.BackgroundTransparency = 1
	arrow.FontFace               = UIFonts.GetNPCFont(npcType, "Name")
	arrow.TextSize               = 13
	arrow.TextColor3             = colors.text
	arrow.Text                   = "\226\150\188" -- ▼
	arrow.Parent                 = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color  = colors.stroke
		s.Parent = arrow
	end)

	local dialog = Instance.new("TextLabel")
	dialog.Name                   = "dialog"
	dialog.Size                   = UDim2.new(1, 0, 1, 0)
	dialog.BackgroundTransparency = 1
	dialog.FontFace               = UIFonts.GetNPCFont(npcType, "Dialog")
	dialog.TextSize               = 13
	dialog.TextColor3             = Color3.new(1, 1, 1)
	dialog.TextWrapped            = true
	dialog.Visible                = false
	dialog.Text                   = ""
	dialog.Parent                 = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color  = Color3.fromRGB(0, 0, 0)
		s.Parent = dialog
	end)
end

---------------------------------------------------------------------------
-- ProximityPrompt
---------------------------------------------------------------------------

--- Creates (if missing) or refreshes the standard ProximityPrompt on `root`.
--- Always refreshes interaction settings so a stale/edited-in-Studio prompt
--- can't end up disabled or blocking triggers.
--- opts: { actionText, objectText, maxActivationDistance = 12, tag = "NPCprompt" }
function NPCBootstrapKit.SetupProximityPrompt(root, opts)
	opts = opts or {}
	local pp = root:FindFirstChildOfClass("ProximityPrompt")
	if not pp then
		pp = Instance.new("ProximityPrompt")
		pp.Name   = "NpcTalkPrompt"
		pp.Parent = root
	end
	pp.ActionText            = opts.actionText or "Talk"
	pp.ObjectText            = opts.objectText or ""
	pp.KeyboardKeyCode       = Enum.KeyCode.E
	pp.GamepadKeyCode        = Enum.KeyCode.ButtonX
	pp.MaxActivationDistance = math.max(pp.MaxActivationDistance, opts.maxActivationDistance or 12)
	pp.HoldDuration          = 0
	pp.RequiresLineOfSight   = false
	pp.Enabled               = true
	pp.ClickablePrompt       = true

	local tag = opts.tag or "NPCprompt"
	if not CollectionService:HasTag(pp, tag) then
		CollectionService:AddTag(pp, tag)
	end
	return pp
end

---------------------------------------------------------------------------
-- Model attributes / tagging
---------------------------------------------------------------------------

--- Sets the standard NpcId/NpcType/NpcName/MaxActivationDistance attributes,
--- PrimaryPart, "NPC" CollectionService tag, and disables the floating Humanoid
--- nameplate. Returns the resolved root BasePart, or nil if the model has
--- neither a HumanoidRootPart nor a Torso (caller is responsible for warning —
--- the exact wording differs per bootstrap script, see file header).
function NPCBootstrapKit.TagAsNPC(model, npcId, npcType, npcName, maxActivationDistance)
	model:SetAttribute("NpcId",   npcId)
	model:SetAttribute("NpcType", npcType)
	model:SetAttribute("NpcName", npcName)
	model:SetAttribute("MaxActivationDistance",
		math.max(tonumber(model:GetAttribute("MaxActivationDistance")) or 0, maxActivationDistance or 12))

	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	model.PrimaryPart = root

	if not CollectionService:HasTag(model, "NPC") then
		CollectionService:AddTag(model, "NPC")
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	return root
end

---------------------------------------------------------------------------
-- Model discovery
---------------------------------------------------------------------------

--- Finds every Model anywhere under `root` (default Workspace) whose Name equals
--- `name`. Sorted by GetFullName so sequential id numbering (foo_01, foo_02, ...)
--- stays stable across server restarts.
function NPCBootstrapKit.FindAllModelsByName(name, root)
	root = root or workspace
	local found = {}
	for _, inst in ipairs(root:GetDescendants()) do
		if inst.Name == name and inst:IsA("Model") then
			table.insert(found, inst)
		end
	end
	table.sort(found, function(a, b) return a:GetFullName() < b:GetFullName() end)
	return found
end

--- Finds every Model anywhere under `root` (default Workspace) whose NpcType
--- attribute equals `npcType` OR whose Name equals `name` — the pattern used by
--- NPC types that tolerate being renamed in Studio (Merchant, Dungeoneer).
--- Not sorted (mirrors the historical per-file behaviour); dedups by instance.
function NPCBootstrapKit.FindAllModelsByTypeOrName(npcType, name, root)
	root = root or workspace
	local found, seen = {}, {}
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("Model") and not seen[inst] then
			if inst:GetAttribute("NpcType") == npcType or inst.Name == name then
				seen[inst] = true
				table.insert(found, inst)
			end
		end
	end
	return found
end

---------------------------------------------------------------------------
-- Retry scheduling
---------------------------------------------------------------------------

--- Runs `fn`, then again after each delay (seconds) in `delays`. A delay of 0
--- runs on task.defer rather than task.delay (matches the historical per-file
--- behaviour, and avoids a same-frame double-run).
--- Every *Bootstrap script re-runs its wiring a few times on a timer to beat
--- Workspace streaming / replication ordering in Play Solo — this is that retry
--- pattern factored out. Pass delays = {} to run once only.
--- opts.sync = false skips the immediate synchronous call, so `fn` only ever
--- runs from task.defer/task.delay (used by the Cuso/Miner/Fisherman family,
--- which historically never called its wiring function synchronously).
function NPCBootstrapKit.ScheduleRetries(fn, delays, opts)
	opts = opts or {}
	if opts.sync ~= false then
		fn()
	end
	for _, d in ipairs(delays or {}) do
		if d <= 0 then
			task.defer(fn)
		else
			task.delay(d, fn)
		end
	end
end

return NPCBootstrapKit
