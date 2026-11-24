-- ui/tabs/world.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local World = ctx.World
    local window = ctx.window


local worldTab = window:CreateTab({ name = "World" })
worldTab:CreateSection({ name = "calidad de vida" })
worldTab:CreateToggle({
    name = "luz / sin niebla",
    flag = "world_bright",
    value = false,
    description = "solo tu pantalla",
    callback = function(v)
        World.set_bright(v)
        World.hold_bright(v)
    end,
})
worldTab:CreateToggle({
    name = "anti lodo",
    flag = "world_mud",
    value = false,
    callback = function(v) World.set_anti_mud(v) end,
})
worldTab:CreateToggle({
    name = "anti viento",
    flag = "world_wind",
    value = false,
    callback = function(v) World.set_anti_wind(v) end,
})
worldTab:CreateSection({ name = "cash" })
worldTab:CreateButton({
    name = "recoger cash (una vez)",
    callback = function()
        local n = World.collect_cash(60)
        window:Notify({ title = "cash", content = n .. " pickups" })
    end,
})
worldTab:CreateToggle({
    name = "cash loop",
    flag = "world_cash",
    value = false,
    callback = function(v)
        World.cash_loop = v
        if v then World.start_cash() else World.stop_cash() end
    end,
})
    return nil
end

return Tab
