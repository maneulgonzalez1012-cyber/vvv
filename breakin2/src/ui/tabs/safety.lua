-- ui/tabs/safety.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Net = ctx.Net
    local Train = ctx.Train
    local window = ctx.window


local safeTab = window:CreateTab({ name = "Safety" })
safeTab:CreateText({
    name = "como se comporta esto",
    text = "todo arranca apagado. cada remoto pasa por throttle y por el kill switch. " ..
           "dry-run imprime sin disparar nada.",
})
safeTab:CreateToggle({
    name = "kill switch (desactiva remotos)",
    flag = "safe_enabled",
    value = false,
    description = "apagado = remotos habilitados",
    callback = function(v) Net.enabled = not v end,
})
safeTab:CreateToggle({
    name = "dry-run",
    flag = "safe_dry",
    value = false,
    description = "loguea en vez de disparar",
    callback = function(v) Net.dryRun = v end,
})
safeTab:CreateButton({
    name = "mostrar remotes ausentes",
    callback = function()
        if #Net.missing == 0 then
            window:Notify({ title = "remotes", content = "todos presentes" })
        else
            window:Notify({ title = "remotes ausentes", content = table.concat(Net.missing, ", ") })
        end
    end,
})
safeTab:CreateButton({
    name = "reset contadores",
    callback = function()
        Net.resetStats()
        Train.reset()
    end,
})
    return nil
end

return Tab
