-- CampMerchant Dialogue Setup
-- LocalScript that initializes dialogue for the Hollow Merchant NPC at the GrimCamp

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local DialogModule = require(game.ReplicatedStorage:WaitForChild("DialogModule"))

-- Wait for the NPC to exist
local function setupMerchant()
    local grimCamp = game.Workspace:FindFirstChild("TutorialPathway")
        and game.Workspace.TutorialPathway.Structures:FindFirstChild("GrimCamp")
    if not grimCamp then return nil end

    local npc = grimCamp:FindFirstChild("CampMerchant")
    if not npc then return nil end

    local prompt = npc:FindFirstChild("HumanoidRootPart")
        and npc.HumanoidRootPart:FindFirstChild("ProximityPrompt")
    if not prompt then return nil end

    -- Create the dialogue instance
    local dialogue = DialogModule.new("Hollow Merchant", npc, prompt, nil)

    -- Add dialogue options with grim-stylized flavor
    dialogue:addDialog(
        "The fire burns low, stranger... but not as low as my spirits. What brings you to this wretched camp?",
        {"What can you tell me about this place?", "Got anything to trade?", "Just passing through."}
    )

    dialogue:addDialog(
        "This camp? A refuge for the forgotten. We scrape by on what the dead leave behind. The mountains hold worse things than us, I promise you that.",
        {"What kind of things?", "Sounds dangerous. I'll be going."}
    )

    dialogue:addDialog(
        "Trade? Ha! I've got rations that taste like ash and blades duller than a beggar's wit. But if you're desperate... take a look.",
        {"Show me what you have.", "Maybe another time."}
    )

    dialogue:addDialog(
        "Shadows with teeth. Echoes that wear the faces of the dead. The mountains have a way of... changing things. Best keep your blade close and your wits closer.",
        {"How do I survive out there?", "I've heard enough."}
    )

    dialogue:addDialog(
        "Stay near the fire when darkness falls. The light keeps the worst of it at bay. And never... NEVER... follow the whispering.",
        {"What whispering?", "I'll keep that in mind."}
    )

    -- Handle player responses
    dialogue.responded:Connect(function(responseNum, dialogNum)
        if dialogNum == 1 then
            if responseNum == 1 then
                dialogue:triggerDialog(player, 2)
            elseif responseNum == 2 then
                dialogue:triggerDialog(player, 3)
            elseif responseNum == 3 then
                dialogue:hideGui("May the ash guide your path...")
            end
        elseif dialogNum == 2 then
            if responseNum == 1 then
                dialogue:triggerDialog(player, 4)
            elseif responseNum == 2 then
                dialogue:hideGui("Cowardice keeps you alive. Can't fault that.")
            end
        elseif dialogNum == 3 then
            if responseNum == 1 then
                dialogue:hideGui("Take what you need. Payment? Your continued breathing is enough.")
            elseif responseNum == 2 then
                dialogue:hideGui("Suit yourself. The offer rots with everything else here.")
            end
        elseif dialogNum == 4 then
            if responseNum == 1 then
                dialogue:triggerDialog(player, 5)
            elseif responseNum == 2 then
                dialogue:hideGui("Ignorance is a kind of armor. Wear it well.")
            end
        elseif dialogNum == 5 then
            if responseNum == 1 then
                dialogue:hideGui("You'll know when you hear it. And when you do... don't listen. Don't follow. Don't look back.")
            elseif responseNum == 2 then
                dialogue:hideGui("Mmm. We'll see.")
            end
        end
    end)

    -- Connect the ProximityPrompt to trigger dialogue
    prompt.Triggered:Connect(function(triggeringPlayer)
        if triggeringPlayer == player then
            dialogue:triggerDialog(player, 1)
        end
    end)

    return dialogue
end

-- Try to set up immediately, or wait for the NPC to appear
local dialogue = setupMerchant()
if not dialogue then
    -- Wait for the NPC to be added
    local descendantConn
    descendantConn = game.Workspace.DescendantAdded:Connect(function(desc)
        if desc.Name == "CampMerchant" then
            task.wait(1) -- Small delay to ensure full structure
            dialogue = setupMerchant()
            if dialogue then
                descendantConn:Disconnect()
            end
        end
    end)
end
