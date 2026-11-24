-- ui/tabs/npcs.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Npc = ctx.Npc
    local Pet = ctx.Pet
    local window = ctx.window


local npcTab = window:CreateTab({ name = "NPCs" })
npcTab:CreateSection({ name = "objetivos" })
npcTab:CreateButton({
    name = "liberar a Uncle Pete",
    callback = function()
        local ok = Npc.uncle_pete()
        window:Notify({ title = "pete", content = ok and "llave usada" or "fallo" })
    end,
})
npcTab:CreateButton({
    name = "detective (Louise)",
    callback = function()
        local ok = Npc.detective()
        window:Notify({ title = "detective", content = ok and "louise entregada" or "fallo" })
    end,
})
npcTab:CreateButton({
    name = "alimentar a Twado",
    description = "lee que comida pide (telefono o nota) y la entrega",
    callback = function()
        local _, why = Pet.try_feed()
        window:Notify({ title = "twado", content = tostring(why) })
    end,
})
npcTab:CreateSection({ name = "ruta" })
npcTab:CreateButton({
    name = "despejar el camino (20x por arbol)",
    callback = function()
        local n = Npc.clear_road_blocks(20)
        window:Notify({ title = "road", content = n .. " golpes" })
    end,
})
npcTab:CreateSection({ name = "teleport (te ven)" })
for key, label in pairs({ pete = "Uncle Pete", louise = "Louise", gym = "gym",
                          kitchen = "cocina", apple = "golden apple" }) do
    npcTab:CreateButton({
        name = "tp: " .. label,
        callback = function()
            if Npc.teleport(key) then
                window:Toast({ title = "tp", subtitle = label })
            end
        end,
    })
end
    return nil
end

return Tab
