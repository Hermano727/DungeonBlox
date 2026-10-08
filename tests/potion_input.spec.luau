-- Exercise the actual input bootstrap without constructing a HUD or running gameplay.
return function(source)
    local cutoff = assert(source:find("\nlocal player = Players.LocalPlayer", 1, true))
    local bootstrap = source:sub(1, cutoff - 1)
    local checks, drinks, rawInput, bound, destroyed = 0, 0
    local focused, menu = false, {MenuIsOpen = false}
    local function check(value, message) assert(value, message); checks += 1 end
    local enums = {KeyCode = {O = "O"}, UserInputState = {Begin = "Begin", End = "End"},
        ContextActionResult = {Sink = "Sink", Pass = "Pass"}, ContextActionPriority = {High = {Value = 3000}}}
    local cas = {
        BindActionAtPriority = function(_, name, callback, touch, priority, key)
            bound = {name = name, callback = callback, priority = priority, key = key}
        end,
        UnbindAction = function() bound = nil end,
    }
    local modules = {KeybindConfig = {QuickDrink = "O"}, PotionDrinkConfig = {DEBUG_DRINK = true},
        PotionDrinkRequest = {Drink = function() drinks += 1 end}}
    local services = {Players = {}, RunService = {}, TweenService = {}, GuiService = menu,
        ContextActionService = cas,
        UserInputService = {GetFocusedTextBox = function() return focused and {} or nil end,
            InputBegan = {Connect = function(_, fn) rawInput = fn end}},
        ReplicatedStorage = {WaitForChild = function(_, name)
            check(bound ~= nil, "gameplay input bound before dependency waits")
            return name
        end}}
    local env = setmetatable({game = {GetService = function(_, name) return services[name] end},
        Enum = enums, require = function(name) return assert(modules[name]) end,
        script = {Destroying = {Connect = function(_, fn) destroyed = fn end}},
        print = function() end, warn = function() end}, {__index = getfenv()})
    local chunk = assert(loadstring(bootstrap)); setfenv(chunk, env); chunk()
    check(bound.priority == 3000 and bound.key == "O", "O bound above default input, below drink action lock")
    local result = bound.callback("PotionQuickDrink", "Begin")
    rawInput({KeyCode = "O"}, true)
    check(result == "Sink" and drinks == 1, "action fires once even with processed raw input; diagnostic cannot duplicate")
    bound.callback("PotionQuickDrink", "End")
    check(drinks == 1, "key release never drinks")
    focused = true
    check(bound.callback("PotionQuickDrink", "Begin") == "Pass" and drinks == 1, "typing does not consume")
    focused = false; menu.MenuIsOpen = true
    check(bound.callback("PotionQuickDrink", "Begin") == "Pass" and drinks == 1, "Roblox menu does not consume")
    destroyed()
    check(bound == nil, "script cleanup unbinds action")
    return checks
end
