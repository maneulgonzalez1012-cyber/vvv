-- ui/tabs/combat.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Combat = ctx.Combat
    local window = ctx.window


window:CreateSection({ name = "juego" })
local combatTab = window:CreateTab({ name = "Combat" })
combatTab:CreateSection({ name = "golpes" })
combatTab:CreateToggle({
    name = "auto hit",
    flag = "combat_auto",
    value = false,
    description = "HitBadguy sobre cada enemigo, throttled",
    callback = function(v)
        Combat.auto_hit = v
        if v then Combat.start() else Combat.stop() end
    end,
})
combatTab:CreateSlider({
    name = "damage",
    flag = "combat_damage",
    range = { 10, 200 },
    increment = 1,
    value = 65,
    callback = function(v) Combat.damage = v end,
})
combatTab:CreateSlider({
    name = "hits por golpe",
    flag = "combat_hits",
    range = { 1, 10 },
    increment = 1,
    value = 4,
    callback = function(v) Combat.hits = v end,
})
combatTab:CreateSlider({
    name = "rango",
    flag = "combat_range",
    range = { 0, 400 },
    increment = 10,
    value = 0,
    suffix = "m",
    description = "0 = sin filtro",
    callback = function(v) Combat.max_range = v end,
})
combatTab:CreateToggle({
    name = "ignorar boss",
    flag = "combat_skip_boss",
    value = false,
    callback = function(v) Combat.skip_boss = v end,
})
combatTab:CreateButton({
    name = "burst x3",
    callback = function()
        local n = Combat.burst(3)
        window:Notify({ title = "combat", content = n .. " golpes" })
    end,
})

combatTab:CreateSection({ name = "boss" })
combatTab:CreateToggle({
    name = "congelar enemigos (cliente)",
    flag = "combat_freeze",
    value = false,
    description = "ancla el root local; el server puede reponer posicion",
    callback = function(v)
        if v then Combat.freeze(true) else Combat.thaw_all() end
    end,
})
    return nil
end

return Tab
