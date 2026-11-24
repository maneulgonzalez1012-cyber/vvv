-- ui/tabs/roles.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Roles = ctx.Roles
    local window = ctx.window


window:CreateSection({ name = "sistema" })
local roleTab = window:CreateTab({ name = "Roles" })
roleTab:CreateText({
    name = "solo lobby",
    text = "OutsideRole no se revalida al empezar la ronda; el check de lugar lo hace el modulo.",
})
for _, r in ipairs(Roles.list) do
    roleTab:CreateButton({
        name = "desbloquear: " .. r.label,
        callback = function()
            local ok = Roles.unlock(r.value)
            window:Notify({ title = "roles", content = r.label .. (ok and " ok" or " fallo") })
        end,
    })
end
roleTab:CreateButton({
    name = "tocar todos los role pads",
    callback = function()
        local n = Roles.refresh()
        window:Notify({ title = "roles", content = n .. " pads" })
    end,
})
    return nil
end

return Tab
