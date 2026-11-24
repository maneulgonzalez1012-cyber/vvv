-- ui/tabs/move.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Move = ctx.Move
    local window = ctx.window


local moveTab = window:CreateTab({ name = "Move" })
moveTab:CreateSection({ name = "local, sin remotos" })
moveTab:CreateToggle({
    name = "walkspeed",
    flag = "move_speed",
    value = false,
    callback = function(v) Move.speed = v; Move.apply_speed() end,
})
moveTab:CreateSlider({
    name = "speed",
    flag = "move_speed_value",
    range = { 16, 120 },
    increment = 2,
    value = 40,
    callback = function(v) Move.speed_value = v; Move.apply_speed() end,
})
moveTab:CreateToggle({
    name = "jump",
    flag = "move_jump",
    value = false,
    callback = function(v) Move.jump = v; Move.apply_jump() end,
})
moveTab:CreateSlider({
    name = "jump power",
    flag = "move_jump_value",
    range = { 50, 200 },
    increment = 5,
    value = 80,
    callback = function(v) Move.jump_value = v; Move.apply_jump() end,
})
moveTab:CreateToggle({
    name = "noclip",
    flag = "move_noclip",
    value = false,
    callback = function(v) Move.set_noclip(v) end,
})
moveTab:CreateToggle({
    name = "fly (body velocity)",
    flag = "move_fly",
    value = false,
    description = "WASD + space/ctrl",
    callback = function(v) Move.set_fly(v) end,
})
moveTab:CreateSlider({
    name = "fly speed",
    flag = "move_fly_value",
    range = { 20, 200 },
    increment = 5,
    value = 60,
    callback = function(v) Move.fly_value = v end,
})
    return nil
end

return Tab
