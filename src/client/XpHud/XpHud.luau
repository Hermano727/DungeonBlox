--!strict
--  XpHud -- React-lua port of the Combat / Mining / Fishing XP bars.
--
--  Replaces three near-identical imperative scripts (CombatXPClient,
--  FishingXPClient, and a copy-pasted block inside WoodenPickaxe/MiningScript)
--  that each ran their own `while task.wait(0.1)` loop walking GetDescendants()
--  on all three frames to juggle ZIndex. That polling is gone: render order is
--  derived from state, and the auto-hide is a single scheduled task.
--
--  This component READS state only. XP accumulation and level-ups still live in
--  the existing scripts, which write into SkillXPShared and stamp
--  player:SetAttribute("Last<Skill>XPGain", tick()). Deliberate -- it keeps the
--  migration reversible and means the StarterPack tool script is untouched.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React              = require(ReplicatedStorage.Packages.React)
local SkillXPShared      = require(ReplicatedStorage:WaitForChild("SkillXPShared"))
local DecorationIcons    = require(ReplicatedStorage.Assets.Icons.Decorations.DecorationIcons)
local UIDevTuning        = require(ReplicatedStorage:WaitForChild("UIDevTuning"))

local e      = React.createElement
local player = Players.LocalPlayer

local HIDE_DELAY = 5        -- seconds of no XP before a bar fades out
local BAR_W = 300

-- Branch/leaf wrap art (rbxassetid://124036052677892). Rendered fully
-- UNCROPPED -- no ImageRectOffset/Size -- so the whole asset shows instead
-- of a guessed sub-rect (past attempts at cropping kept guessing wrong
-- coordinates against a resolution Roblox silently re-encodes on upload).
-- Native served size confirmed via AssetService:CreateEditableImageAsync:
-- 1023x558. The art is one long wavy branch with a leaf cluster bunched at
-- ONE end only, so two copies -- one plain, one rotated 180 -- let that
-- single leaf cluster land in two different corners.
local BRANCH_IMAGE = DecorationIcons.XP_BAR_BRANCH
local BRANCH_NATIVE_W, BRANCH_NATIVE_H = 1023, 558

-- Geometry (scale/offset/rotation, per Top and Bottom copy) comes from
-- UIDevTuning instead of being hardcoded here, so it can be nudged live via
-- the UIDevTool keybind (KeybindConfig.UIDevTool) without redeploying. The
-- values below are the dialed-in look approved 2026-08-16 -- Top anchored
-- on the pill's right edge straddling the top border (leaf end lands
-- top-right), Bottom anchored on the left edge straddling the bottom
-- border, rotated 180 so the same leaf end lands bottom-left. Press
-- UIDevTool, tune further, and hand-copy its printed snapshot back here if
-- the look changes again.
local BranchTuning = UIDevTuning.Register("XpHudBranch", {
    Top    = { Scale = 1.11, OffsetX = 47, OffsetY = 9, Rotation = 0 },
    Bottom = { Scale = 1.11, OffsetX = -46, OffsetY = -10, Rotation = 180 },
})
local function branchGeometry(tuning: { Scale: number, OffsetX: number, OffsetY: number, Rotation: number }, edge: "Top" | "Bottom")
    local w = math.floor(BAR_W * tuning.Scale)
    local h = math.floor(w * (BRANCH_NATIVE_H / BRANCH_NATIVE_W))
    local anchorX = edge == "Top" and 1 or 0
    local xScale = edge == "Top" and 1 or 0
    local yScale = edge == "Top" and 0 or 1
    return {
        size = UDim2.fromOffset(w, h),
        anchorPoint = Vector2.new(anchorX, 0.5),
        position = UDim2.new(xScale, tuning.OffsetX, yScale, tuning.OffsetY),
        rotation = tuning.Rotation,
    }
end

-- TEMP (2026-08-15): keep the Combat bar pinned above the hotbar and always
-- visible for review, bypassing the normal gain-triggered auto-hide. Revert
-- by setting this false once the look is approved.
local COMBAT_ALWAYS_VISIBLE = true
local COMBAT_POSITION = UDim2.new(0.5, 0, 1, -170)  -- bottom-center, well clear of the hotbar; nudge to taste
local COMBAT_ANCHOR   = Vector2.new(0.5, 1)
local DEFAULT_POSITION = UDim2.new(0, 10, 1, -10)
local DEFAULT_ANCHOR   = Vector2.new(0, 1)

-- Palette lives in one table so the zone-theming work can swap it wholesale
-- rather than hunting Color3 literals. Semantic names, never geometry.
local THEME = {
    TrackBg     = Color3.fromRGB(20, 16, 13),   -- #14100D, pill interior
    PillBorder  = Color3.fromRGB(107, 66, 38),  -- #6B4226
    XpGreen     = Color3.fromRGB(78, 124, 54),  -- #4E7C36
    XpDot       = Color3.fromRGB(0, 0, 0),
    TextPrimary = Color3.fromRGB(240, 230, 210), -- #F0E6D2
}

local SKILLS = {
    { key = "Combat",  label = "Combat",  fill = Color3.fromRGB(150, 52, 40) },
    { key = "Mining",  label = "Mining",  fill = Color3.fromRGB(120, 104, 78) },
    { key = "Fishing", label = "Fishing", fill = Color3.fromRGB(64, 104, 118) },
}

local function lastGain(key: string): number
    return (player:GetAttribute("Last" .. key .. "XPGain") :: number?) or 0
end

--------------------------------------------------------------------------------

type BarProps = {
    label: string,
    fill: Color3,
    level: number,
    xp: number,
    xpNeeded: number,
    zIndex: number,
    position: UDim2,
    anchorPoint: Vector2,
}

local function merge(a: { [string]: any }, b: { [string]: any }): { [string]: any }
    local out = table.clone(a)
    for k, v in pairs(b) do
        out[k] = v
    end
    return out
end

-- actual height dimension of xp bar shape
local PILL_H = 20 -- skinnier -- width was fine, height was too chunky
local DOT_COUNT = 12

-- Small evenly-spaced stars across the pill so the fill reads as segmented
-- "XP" progress rather than a plain solid gauge, matching the v5 mockup ask.
-- Text glyph, not an asset -- "*" renders fine in Gotham with no new art.
local function buildDots(zIndex: number)
    local dots: { [string]: any } = {}
    for i = 1, DOT_COUNT do
        local frac = i / (DOT_COUNT + 1)
        dots["Dot" .. i] = e("TextLabel", {
            Size = UDim2.fromOffset(10, 10),
            Position = UDim2.new(frac, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            Text = "\226\152\133", -- "★" (U+2605)
            TextColor3 = THEME.XpDot,
            TextTransparency = 0.45,
            TextScaled = true,
            Font = Enum.Font.GothamBold,
            ZIndex = zIndex,
        })
    end
    return dots
end

local function XpBar(props: BarProps)
    local pct = math.clamp(props.xp / math.max(props.xpNeeded, 1), 0, 1)

    -- Live-tunable via UIDevTool (F6 by default) -- re-renders this bar
    -- whenever the tuning numbers change, no code redeploy needed.
    local branchTuning, setBranchTuning = React.useState(BranchTuning:Get())
    React.useEffect(function()
        return BranchTuning:Subscribe(function()
            setBranchTuning(BranchTuning:Get())
        end)
    end, {})
    local topGeo = branchGeometry(branchTuning.Top, "Top")
    local bottomGeo = branchGeometry(branchTuning.Bottom, "Bottom")

    -- No panel/card container anymore -- just the stacked label / pill /
    -- amount, per the v5 mockup. AutomaticSize on Y so the stack's total
    -- height follows the UIListLayout instead of a hand-summed constant.
    return e("Frame", {
        Size = UDim2.new(0, BAR_W, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = props.position,
        AnchorPoint = props.anchorPoint,
        BackgroundTransparency = 1,
        ZIndex = props.zIndex,
    }, {
        Layout = e("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }),

        Label = e("TextLabel", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            Text = string.format("%s  LV %d", string.upper(props.label), props.level),
            TextColor3 = THEME.TextPrimary,
            TextTransparency = 0.25,
            TextStrokeColor3 = Color3.new(0, 0, 0),
            TextStrokeTransparency = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextSize = 26,
            Font = Enum.Font.GothamBold,
            ZIndex = props.zIndex,
        }),

        Pill = e("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, PILL_H),
            BackgroundColor3 = THEME.TrackBg,
            BorderSizePixel = 0,
            ZIndex = props.zIndex,
        }, merge({
            Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
            Stroke = e("UIStroke", {
                Color = THEME.PillBorder,
                Thickness = 2, -- subtle on purpose -- the BRANCH art is what should read as the wrap, not this line
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            }),
            Fill = e("Frame", {
                Size = UDim2.fromScale(pct, 1),
                BackgroundColor3 = THEME.XpGreen,
                BorderSizePixel = 0,
                ZIndex = props.zIndex + 1,
            }, {
                Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
            }),

            -- Decorative branch wrap. Same image twice, second copy rotated
            -- 180 so the leaf cluster reads as growing from opposite
            -- corners. Geometry comes from branchTuning -- see
            -- XpHudBranchTuning / XpHudBranchDevTool.
            BranchTopRight = e("ImageLabel", {
                Image = BRANCH_IMAGE,
                Size = topGeo.size,
                AnchorPoint = topGeo.anchorPoint,
                Position = topGeo.position,
                Rotation = topGeo.rotation,
                BackgroundTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                ZIndex = props.zIndex + 3,
            }),
            BranchBottomLeft = e("ImageLabel", {
                Image = BRANCH_IMAGE,
                Size = bottomGeo.size,
                AnchorPoint = bottomGeo.anchorPoint,
                Position = bottomGeo.position,
                Rotation = bottomGeo.rotation,
                BackgroundTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                ZIndex = props.zIndex + 3,
            }),
        }, buildDots(props.zIndex + 2))),

        Amount = e("TextLabel", {
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            Text = string.format("%d / %d XP", props.xp, props.xpNeeded),
            TextColor3 = THEME.TextPrimary,
            TextStrokeColor3 = Color3.new(0, 0, 0),
            TextStrokeTransparency = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextSize = 24,
            Font = Enum.Font.GothamBold,
            ZIndex = props.zIndex,
        }),
    })
end

--------------------------------------------------------------------------------

local function XpHud()
    -- bumped whenever XP changes or a bar is due to hide; drives re-render
    local version, setVersion = React.useState(0)

    React.useEffect(function()
        return SkillXPShared.Subscribe(function()
            setVersion(function(v) return v + 1 end)
        end)
    end, {})

    -- Schedule ONE re-render for the moment the soonest visible bar expires.
    -- Event-driven, so nothing polls while the HUD is idle.
    React.useEffect(function()
        local soonest: number? = nil
        for _, s in ipairs(SKILLS) do
            local hideAt = lastGain(s.key) + HIDE_DELAY
            if hideAt > tick() and (soonest == nil or hideAt < soonest) then
                soonest = hideAt
            end
        end
        if soonest == nil then
            return
        end
        -- Do NOT use task.cancel here. Once the delay has fired the thread is
        -- dead, and task.cancel on a dead thread raises -- which kills the
        -- effect cleanup and stops every future re-render. Flag instead.
        local cancelled = false
        task.delay(soonest - tick() + 0.05, function()
            if cancelled then
                return
            end
            setVersion(function(v) return v + 1 end)
        end)
        return function()
            cancelled = true
        end
    end, { version })

    -- visible bars, most recently gained last (drawn on top)
    local now = tick()
    local shown = {}
    for _, s in ipairs(SKILLS) do
        local last = lastGain(s.key)
        local forceShow = COMBAT_ALWAYS_VISIBLE and s.key == "Combat"
        if forceShow or now - last < HIDE_DELAY then
            table.insert(shown, { skill = s, last = forceShow and now or last })
        end
    end
    table.sort(shown, function(a, b) return a.last < b.last end)

    local children: { [string]: any } = {}
    for i, entry in ipairs(shown) do
        local s = entry.skill
        local state = SkillXPShared[s.key]
        local isCombat = s.key == "Combat"
        children[s.key] = e(XpBar, {
            label = s.label,
            fill = s.fill,
            level = state.Level,
            xp = state.XP,
            xpNeeded = SkillXPShared.GetXPForLevel(state.Level),
            zIndex = 5 + i * 2,
            position = (isCombat and COMBAT_ALWAYS_VISIBLE) and COMBAT_POSITION or DEFAULT_POSITION,
            anchorPoint = (isCombat and COMBAT_ALWAYS_VISIBLE) and COMBAT_ANCHOR or DEFAULT_ANCHOR,
        })
    end

    return e("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, children)
end

return XpHud
