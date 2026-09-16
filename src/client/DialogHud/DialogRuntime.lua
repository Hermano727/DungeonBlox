--!strict
-- DialogRuntime: client-side "brain" for the tree-based dialog system.
-- Owns session state, walks the current NPC's dialog tree, evaluates
-- response conditions against the cached profile snapshot, and either
-- performs client-only actions directly or forwards server-validated
-- actions through the existing NPCRequest RemoteFunction -- the same one
-- every other NPC transaction (repairs, purchases, trades) already uses.
-- No new remotes.
--
-- Entry point: DialogRuntime.startConversation(npcModel, npcId, npcType),
-- called by whatever resolves the NPC's ProximityPrompt (currently
-- MerchantShopClient's router, for Blacksmith).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DialogConfig = require(ReplicatedStorage.DialogSystem.DialogConfig)
local DialogTrees = require(ReplicatedStorage.DialogSystem.DialogTreeLoader)
local DialogConditions = require(ReplicatedStorage.DialogSystem.DialogConditions)
local DialogActionTypes = require(ReplicatedStorage.DialogSystem.DialogActions)
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local Dialog = require(script.Parent:WaitForChild("Dialog"))

-- Sibling client modules (BlacksmithClient, DungeonMenuNet, ...) live one
-- level up in StarterPlayerScripts, same reach pattern MerchantShopClient
-- already uses for its own XxxClient requires.
local StarterPlayerScripts = script.Parent.Parent
local DungeonMenuNet = require(StarterPlayerScripts:WaitForChild("DungeonMenuNet"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local NPCRequest = GameEvents:WaitForChild("NPCRequest")

-- Friendlier copy for the handful of server error codes a dialog action can
-- come back with. Falls back to the raw code (still better than nothing).
local FRIENDLY_ERRORS = {
	objective_incomplete = "You don't have enough yet.",
	insufficient_funds = "Not enough Coins.",
	already_active_or_complete = "Already taken care of.",
	too_far = "Move closer.",
	throttled = "Slow down a moment.",
}

-- Client-only action handlers: side effects with no server round-trip.
-- key -> function(ctx) where ctx = { npcModel, npcId, npcType, args }
local ClientActionHandlers = {
	OpenMenu = function(ctx)
		local moduleName = ctx.args and ctx.args.client
		if type(moduleName) ~= "string" then
			warn("[DialogRuntime] OpenMenu action missing `client` module name")
			return
		end
		local ok, mod = pcall(function()
			return require(StarterPlayerScripts:WaitForChild(moduleName))
		end)
		if ok and type(mod) == "table" and type(mod.open) == "function" then
			mod.open(ctx.npcId)
		else
			warn("[DialogRuntime] OpenMenu: could not open '" .. moduleName .. "': " .. tostring(mod))
		end
	end,
}

local DialogRuntime = {}

---------------------------------------------------------------------------
-- GUI root (built once, mounted immediately -- same pattern as InventoryHud)
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DialogHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 140
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = playerGui

local root = ReactRoblox.createRoot(gui)

---------------------------------------------------------------------------
-- Session state
---------------------------------------------------------------------------

type Session = {
	npcModel: Instance,
	npcId: string,
	npcType: string,
	tree: any,
	nodeId: string,
	statusText: string?,
}

local session: Session? = nil
local frozenWalk: number?, frozenJump: number?, frozenJumpHeight: number? = nil, nil, nil

local function setFrozen(frozen: boolean)
	if not DialogConfig.FreezePlayer then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if frozen then
		frozenWalk, frozenJump, frozenJumpHeight = hum.WalkSpeed, hum.JumpPower, hum.JumpHeight
		hum.WalkSpeed, hum.JumpPower, hum.JumpHeight = 0, 0, 0
	else
		hum.WalkSpeed = frozenWalk or 16
		hum.JumpPower = frozenJump or 50
		hum.JumpHeight = frozenJumpHeight or 7.2
		frozenWalk, frozenJump, frozenJumpHeight = nil, nil, nil
	end
end

local function evalCondition(condition): boolean
	if not condition then
		return true
	end
	local fn = DialogConditions[condition.type]
	if not fn then
		warn("[DialogRuntime] unknown condition type: " .. tostring(condition.type))
		return true
	end
	local snap = DungeonMenuNet.getLastSnapshot()
	local profile = snap and snap.profile
	return fn(player, condition, { profile = profile })
end

local function render()
	if not session then
		root:render(nil)
		return
	end
	local node = session.tree.nodes[session.nodeId]
	if not node then
		warn("[DialogRuntime] missing node '" .. tostring(session.nodeId) .. "' in tree for " .. session.npcType)
		root:render(nil)
		return
	end

	local visibleResponses = {}
	for _, resp in ipairs(node.responses or {}) do
		if evalCondition(resp.condition) then
			table.insert(visibleResponses, resp)
		end
	end

	root:render(React.createElement(Dialog, {
		npcName = session.npcType,
		text = node.text,
		image = node.image,
		responses = visibleResponses,
		statusText = session.statusText,
		onChoose = function(resp)
			DialogRuntime._choose(resp)
		end,
	}))
end

local function closeSession()
	if not session then
		return
	end
	session = nil
	gui.Enabled = false
	setFrozen(false)
	CursorUtils.release()
	render()
end

---------------------------------------------------------------------------
-- Response handling
---------------------------------------------------------------------------

function DialogRuntime._choose(resp)
	if not session then
		return
	end

	local proceed = true

	if resp.action then
		local actionDef = DialogActionTypes[resp.action.type]
		if not actionDef then
			warn("[DialogRuntime] unknown action type: " .. tostring(resp.action.type))
		elseif actionDef.kind == "client" then
			local handler = ClientActionHandlers[resp.action.type]
			if handler then
				handler({
					npcModel = session.npcModel,
					npcId = session.npcId,
					npcType = session.npcType,
					args = resp.action,
				})
			end
		elseif actionDef.kind == "server" then
			local ok, res = pcall(function()
				return NPCRequest:InvokeServer({
					npcId = session.npcId,
					action = actionDef.serverAction,
					questId = resp.action.quest,
				})
			end)
			DungeonMenuNet.requestSync()
			if not (ok and res and res.ok) then
				proceed = false
				local errCode = ok and res and res.err
				session.statusText = FRIENDLY_ERRORS[errCode] or "Something went wrong."
			end
		end
	end

	if not session then
		-- A client action (unlikely, but be defensive) could have closed the
		-- session indirectly.
		return
	end

	if proceed and resp.exit then
		closeSession()
		return
	end

	if proceed and resp.next then
		session.nodeId = resp.next
		session.statusText = nil
	end

	render()
end

---------------------------------------------------------------------------
-- Start / lifecycle
---------------------------------------------------------------------------

function DialogRuntime.startConversation(npcModel: Instance, npcId: string, npcType: string)
	local tree = DialogTrees[npcType]
	if not tree then
		warn("[DialogRuntime] no dialog tree registered for NpcType '" .. tostring(npcType) .. "'")
		return
	end
	if session then
		closeSession()
	end

	session = {
		npcModel = npcModel,
		npcId = npcId,
		npcType = npcType,
		tree = tree,
		nodeId = tree.start,
		statusText = nil,
	}
	gui.Enabled = true
	setFrozen(true)
	CursorUtils.acquire()
	render()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if session and Keys.Matches(Keys.CloseMenu, input.KeyCode) then
		closeSession()
	end
end)

player.CharacterAdded:Connect(function()
	closeSession()
end)

print("[DialogRuntime] ready")

return DialogRuntime
