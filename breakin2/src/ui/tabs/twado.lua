-- ui/tabs/twado.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Menu = ctx.Menu
    local Pet = ctx.Pet
    local Items = ctx.Items
    local window = ctx.window


local petTab = window:CreateTab({ name = "Twado" })
petTab:CreateText({
    name = "que quiere",
    text = "se lee de dos sitios: el telefono (TwadoWants) y la nota (Circle<item>). " ..
           "Nunca adivina: la comida equivocada cuesta 10 de energia.",
})
local petLine = petTab:CreateText({ name = "estado", text = Pet.summary() })
local petCounter = petTab:CreateStat({ name = "veces alimentado", value = 0 })

petTab:CreateButton({
    name = "leer que quiere",
    callback = function()
        local wants = Pet.wants()
        local text = #wants > 0 and table.concat(wants, ", ") or "nada todavia"
        petLine:Set(text)
        window:Notify({ title = "twado quiere", content = text, duration = 6 })
    end,
})
petTab:CreateButton({
    name = "alimentar ahora",
    callback = function()
        local _, why = Pet.try_feed()
        petLine:Set(tostring(why))
        petCounter:Set(Pet.fed_total)
        window:Notify({ title = "twado", content = tostring(why) })
    end,
})
petTab:CreateToggle({
    name = "detector automatico",
    flag = "pet_auto",
    value = false,
    description = "vigila cada 2 s y le da la comida cuando pide",
    callback = function(v)
        if v then Pet.start() else Pet.stop() end
    end,
})
petTab:CreateSlider({
    name = "cada cuanto revisar",
    flag = "pet_interval",
    range = { 1, 10 },
    increment = 1,
    value = 2,
    suffix = "s",
    callback = function(v) Pet.watch_interval = v end,
})
petTab:CreateDropdown({
    name = "forzar comida",
    flag = "pet_food",
    options = Items.options("comida"),
    value = Items.label_of("Pizza"),
    callback = function(sel) Menu.picked_pet = Items.id_of(type(sel) == "table" and sel[1] or sel) end,
})
petTab:CreateButton({
    name = "dar esa comida de todas formas",
    description = "para cuando la GUI no dice nada y tu sabes que toca",
    callback = function()
        local _, why = Pet.feed(Menu.picked_pet or "Pizza")
        petLine:Set(tostring(why))
        petCounter:Set(Pet.fed_total)
        window:Notify({ title = "twado", content = tostring(why) })
    end,
})
    -- handles the HUD refreshes; missing ones are simply skipped
    ctx.elements.petLine = petLine
    ctx.elements.petCounter = petCounter
    return nil
end

return Tab
