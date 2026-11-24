-- ui/tabs/enemies.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Esp = ctx.Esp
    local window = ctx.window


local espTab = window:CreateTab({ name = "Enemies" })
espTab:CreateToggle({
    name = "highlight enemigos",
    flag = "esp_on",
    value = false,
    callback = function(v) Esp.set_enabled(v) end,
})
espTab:CreateToggle({
    name = "mostrar distancia",
    flag = "esp_dist",
    value = true,
    callback = function(v) Esp.show_distance = v end,
})
espTab:CreateToggle({
    name = "mostrar hp",
    flag = "esp_hp",
    value = true,
    callback = function(v) Esp.show_health = v end,
})
local espLine = espTab:CreateText({ name = "cercanos", text = "sin enemigos" })
    -- handles the HUD refreshes; missing ones are simply skipped
    ctx.elements.espLine = espLine
    return nil
end

return Tab
