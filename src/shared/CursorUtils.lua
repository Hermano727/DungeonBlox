-- CursorUtils
-- Reference-counted free cursor for UI while in first person / shift-lock.
-- Replaces the broken MenuMouse module (capability issues).
-- Binds at RenderPriority.Last so we run after scripts that force LockCenter.

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local BIND_NAME = "CursorUtils_FreeCursor"

local refCount        = 0
local savedBehavior   = Enum.MouseBehavior.Default
local savedIconEnabled = true

local function applyFree()
    UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
    UserInputService.MouseIconEnabled = true
end

local CursorUtils = {}

function CursorUtils.acquire()
    if refCount == 0 then
        savedBehavior    = UserInputService.MouseBehavior
        savedIconEnabled = UserInputService.MouseIconEnabled
        pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
        RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, applyFree)
        applyFree()
    end
    refCount += 1
end

function CursorUtils.release()
    if refCount <= 0 then return end
    refCount -= 1
    if refCount > 0  then return end
    pcall(function() RunService:UnbindFromRenderStep(BIND_NAME) end)
    local restoreBehavior = savedBehavior
    local restoreIcon = savedIconEnabled
    UserInputService.MouseBehavior    = restoreBehavior
    UserInputService.MouseIconEnabled = restoreIcon
    -- First-person camera only rotates while LockCenter is active; re-assert next
    -- frame so a stale Default from the free-cursor bind cannot stick after close.
    if restoreBehavior == Enum.MouseBehavior.LockCenter then
        task.defer(function()
            if refCount == 0 then
                UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
            end
        end)
    end
end

return CursorUtils