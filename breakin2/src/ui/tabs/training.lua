-- ui/tabs/training.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Train = ctx.Train
    local Game = ctx.Game
    local window = ctx.window


local trainTab = window:CreateTab({ name = "Training" })
trainTab:CreateSection({ name = "auto-train (remoto, visible)" })

trainTab:CreateToggle({
    name = "entrenar en loop",
    flag = "train_loop",
    value = false,
    description = "RainbowWhatStat, espaciado al throttle. el server decide si vale",
    callback = function(v)
        Train.enabled = v
        if v then Train.start() else Train.stop() end
    end,
})

trainTab:CreateDropdown({
    name = "stats",
    flag = "train_stats",
    multiSelect = true,
    options = { "Strength", "Speed" },
    value = { "Strength", "Speed" },
    callback = function(sel)
        -- multiSelect hands back a list, but a single click can hand back a
        -- bare string; normalise both so the toggle never wedges
        if type(sel) == "string" then sel = { sel } end
        if type(sel) ~= "table" then return end
        for _, s in ipairs(Game.STATS) do Train.stats[s] = false end
        for _, s in ipairs(sel) do
            if Train.stats[s] ~= nil then Train.stats[s] = true end
        end
    end,
})

trainTab:CreateSlider({
    name = "intervalo",
    flag = "train_interval",
    range = { 12, 100 },
    increment = 1,
    value = 35,
    suffix = " x10ms",
    callback = function(v) Train.interval = v / 100 end,
})

trainTab:CreateSlider({
    name = "parar en pips",
    flag = "train_target",
    range = { 0, 10 },
    increment = 1,
    value = 5,
    description = "0 = nunca parar",
    callback = function(v) Train.target = v end,
})

trainTab:CreateToggle({
    name = "jitter",
    flag = "train_jitter",
    value = true,
    description = "gap aleatorio, menos metronomo",
    callback = function(v) Train.jitter = v end,
})

trainTab:CreateSection({ name = "manual" })
trainTab:CreateButton({
    name = "burst strength x5",
    callback = function() Train.burst("Strength", 5) end,
})
trainTab:CreateButton({
    name = "burst speed x5",
    callback = function() Train.burst("Speed", 5) end,
})
trainTab:CreateButton({
    name = "burst ambos x5",
    callback = function() Train.burst("Both", 5) end,
})
    return nil
end

return Tab
