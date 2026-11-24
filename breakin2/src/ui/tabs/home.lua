-- ui/tabs/home.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Train = ctx.Train
    local Combat = ctx.Combat
    local World = ctx.World
    local Move = ctx.Move
    local Esp = ctx.Esp
    local Net = ctx.Net
    local Game = ctx.Game
    local U = ctx.U
    local window = ctx.window


local home = window:CreateTab({ name = "Home" })

home:CreateSection({ name = "estado" })
home:CreateText({
    name = "version",
    text = "build " .. tostring(U.VERSION),
})
local placeLine = home:CreateText({ name = "lugar", text = Game.where() })
local enemyStat = home:CreateStat({ name = "enemigos", value = 0 })
local remoteStat = home:CreateStat({ name = "remotes", value = 0 })

local enemyLine = home:CreateText({ name = "cercanos", text = "sin enemigos" })

home:CreateButton({
    name = "rescan remotes",
    callback = function()
        local r = Net.resolve()
        remoteStat:Set(U.count(r))
        window:Notify({ title = "remotes", content = U.count(r) .. " resueltos, " ..
            #Net.missing .. " ausentes" })
    end,
})

home:CreateButton({
    name = "panic: apagar todo",
    description = "restaura movimiento, luz, highlights y loops",
    callback = function()
        Train.stop()
        Combat.stop()
        Combat.thaw_all()
        World.reset()
        Move.reset()
        Esp.set_enabled(false)
        Esp.clear()
        Net.enabled = true
        window:Notify({ title = "panic", content = "todo apagado" })
    end,
})
    -- handles the HUD refreshes; missing ones are simply skipped
    ctx.elements.placeLine = placeLine
    ctx.elements.enemyStat = enemyStat
    ctx.elements.remoteStat = remoteStat
    ctx.elements.enemyLine = enemyLine
    return nil
end

return Tab
