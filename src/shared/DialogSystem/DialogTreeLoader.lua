--!strict
-- Loads every ModuleScript under DialogSystem.Trees into one lookup table,
-- keyed by module Name -- which must equal the NpcType the tree is for
-- (e.g. Trees/Blacksmith.lua -> DialogTrees["Blacksmith"]). Trees are keyed
-- by NpcType rather than NpcId so duplicate NPCs of the same type share a
-- tree, same convention as quest flags and NPCRegistry.
--
-- Tree shape:
--   {
--     start = "greeting",
--     nodes = {
--       greeting = {
--         text = "...",
--         image = "rbxassetid://...", -- optional portrait; box only shows
--                                      -- when a node sets this (see
--                                      -- DialogConfig.UI.ImageSize/Overflow*)
--         responses = {
--           -- Plain navigation: shows unconditionally, moves to another node.
--           { text = "Tell me more.", next = "moreInfo" },
--
--           -- Conditional: only shown when the condition evaluates true.
--           { text = "Any work for me?", next = "questOffer",
--             condition = { type = "QuestState", quest = "BlacksmithScrapRun", is = "available" } },
--
--           -- Action: performs a side effect (see DialogActions). May be
--           -- combined with `next` (e.g. accept a quest, then show a
--           -- "quest accepted" node) or with `exit` (e.g. open a shop menu
--           -- and close the dialog panel). If a server action fails,
--           -- `next`/`exit` are skipped and a status message shows instead
--           -- -- see DialogRuntime.
--           { text = "Open the forge", exit = true,
--             action = { type = "OpenMenu", client = "BlacksmithClient" } },
--
--           -- Terminal: closes the conversation, no action.
--           { text = "Just passing through.", exit = true },
--         },
--       },
--     },
--   }
--
-- A response with no `condition` always shows.

local treesFolder = script.Parent:WaitForChild("Trees")

local DialogTrees = {}

for _, child in ipairs(treesFolder:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, tree = pcall(require, child)
		if ok and type(tree) == "table" and type(tree.start) == "string" and type(tree.nodes) == "table" then
			DialogTrees[child.Name] = tree
		else
			warn("[DialogTreeLoader] " .. child:GetFullName() .. " did not return a valid tree; skipping. (" .. tostring(tree) .. ")")
		end
	end
end

return DialogTrees
