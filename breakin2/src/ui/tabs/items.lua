-- ui/tabs/items.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Menu = ctx.Menu
    local Items = ctx.Items
    local Shield = ctx.Shield
    local U = ctx.U
    local window = ctx.window


-- Every object in the game is reached from here, grouped, and each button
-- reports what actually happened: obtained, or the reason it did not.
local itemsTab = window:CreateTab({ name = "Items" })

local function report(id, ok, why)
    local label = Items.label_of(id)
    if ok then
        U.notify(label, "obtenido (" .. tostring(why) .. ")")
    else
        U.notify(label, "no llego: " .. tostring(why))
    end
end

local function obtain_with_ui(id)
    local ok, why = Items.obtain(id, 1.0)
    report(id, ok, why)
    return ok
end

itemsTab:CreateSection({ name = "comida (GiveTool / vending)" })
itemsTab:CreateDropdown({
    name = "item",
    flag = "item_food",
    options = Items.options("comida"),
    value = Items.label_of("GoldenApple"),
    callback = function(sel)
        Menu.picked_food = Items.id_of(type(sel) == "table" and sel[1] or sel)
    end,
})
itemsTab:CreateButton({
    name = "dar",
    callback = function() obtain_with_ui(Menu.picked_food or "GoldenApple") end,
})
itemsTab:CreateButton({
    name = "x10",
    description = "espaciado al throttle real del remoto",
    callback = function()
        local id = Menu.picked_food or "GoldenApple"
        local fired, gained = Items.stack(id, 10)
        window:Notify({
            title = "x10 " .. Items.label_of(id),
            content = string.format("%d disparos, %d nuevos en mochila", fired, gained),
        })
    end,
})

itemsTab:CreateSection({ name = "bebidas (GiveTool)" })
itemsTab:CreateDropdown({
    name = "bebida",
    flag = "item_drink",
    options = Items.options("bebida"),
    value = Items.label_of("BloxyCola"),
    callback = function(sel)
        Menu.picked_drink = Items.id_of(type(sel) == "table" and sel[1] or sel)
    end,
})
itemsTab:CreateButton({
    name = "dar bebida",
    callback = function() obtain_with_ui(Menu.picked_drink or "BloxyCola") end,
})

itemsTab:CreateSection({ name = "armas (Vending / Weapons)" })
itemsTab:CreateDropdown({
    name = "arma",
    flag = "item_weapon",
    options = Items.options("armas"),
    value = Items.label_of("Crowbar3"),
    callback = function(sel)
        Menu.picked_weapon = Items.id_of(type(sel) == "table" and sel[1] or sel)
    end,
})
itemsTab:CreateButton({
    name = "dar arma",
    callback = function() obtain_with_ui(Menu.picked_weapon or "Crowbar3") end,
})
itemsTab:CreateButton({
    name = "todas las armas",
    description = "una de cada, espaciado",
    callback = function()
        local got, failed = Items.give_set(
            { "Crowbar1", "Crowbar2", "Crowbar3", "Bat", "Wrench", "Pitchfork", "Hammer", "Broom" })
        window:Notify({
            title = "armas",
            content = got .. "/8" .. (#failed > 0 and (" | fallo: " .. table.concat(failed, ", ")) or ""),
        })
    end,
})

itemsTab:CreateSection({ name = "objetos de mision" })
itemsTab:CreateDropdown({
    name = "objeto",
    flag = "item_misc",
    options = Items.options("objetos"),
    value = Items.label_of("Key"),
    callback = function(sel)
        Menu.picked_misc = Items.id_of(type(sel) == "table" and sel[1] or sel)
    end,
})
itemsTab:CreateButton({
    name = "dar objeto",
    callback = function() obtain_with_ui(Menu.picked_misc or "Key") end,
})
itemsTab:CreateButton({
    name = "kit de supervivencia",
    description = "crowbar3 + medkit + golden apple + cola + chips",
    callback = function()
        local got, failed = Items.give_set(Items.survival_set, function(i, n, id, ok)
            if not ok then U.log("kit", id, i, n) end
        end)
        window:Notify({
            title = "kit",
            content = got .. "/" .. #Items.survival_set ..
                (#failed > 0 and (" | fallo: " .. table.concat(failed, ", ")) or ""),
            duration = 6,
        })
    end,
})

itemsTab:CreateSection({ name = "mochila" })
itemsTab:CreateButton({
    name = "que tengo",
    callback = function()
        local list = Items.held()
        window:Notify({
            title = "mochila (" .. #list .. ")",
            content = #list > 0 and table.concat(list, ", ") or "vacia",
            duration = 7,
        })
    end,
})
itemsTab:CreateButton({
    name = "guardar todo",
    callback = function() Items.unequip_all() end,
})

itemsTab:CreateButton({
    name = "que variante de Vending funciono",
    description = "las armas se prueban en 4 formas; aqui dice cual entregó",
    callback = function()
        local variant = Items.weapon_variant
        local lines = {}
        for _, v in ipairs({ "name", "player", "no-count", "bare" }) do
            table.insert(lines, v .. "=" .. tostring(Items.weapon_variant_log[v] or "-"))
        end
        window:Notify({
            title = "vending: " .. (variant and ("variante " .. variant .. " ok") or "sin confirmar"),
            content = table.concat(lines, "  "),
            duration = 7,
        })
    end,
})

itemsTab:CreateSection({ name = "vida (Energy)" })
local hpLine = itemsTab:CreateText({ name = "hp", text = "sin personaje" })

itemsTab:CreateButton({
    name = "+25 de vida (sin comer nada)",
    description = "Energy:FireServer(25) y comprueba que subio",
    callback = function()
        local ok, why, hp = Shield.top_up(25)
        hpLine:Set(string.format("hp %s", tostring(hp)))
        window:Notify({
            title = ok and "+25" or "no subio",
            content = ok and ("via " .. tostring(why)) or tostring(why),
        })
    end,
})

itemsTab:CreateSlider({
    name = "cantidad a sumar",
    flag = "energy_amount",
    range = { 5, 200 },
    increment = 5,
    value = 25,
    callback = function(v) Shield.amount = v end,
})
itemsTab:CreateButton({
    name = "sumar esa cantidad",
    callback = function()
        local ok, why, hp = Shield.add_energy(Shield.amount, 1.2)
        hpLine:Set(string.format("hp %s", tostring(hp)))
        window:Notify({ title = ok and ("+" .. Shield.amount) or "no subio", content = tostring(why) })
    end,
})
itemsTab:CreateButton({
    name = "por que no sube (diagnostico)",
    description = "prueba las formas conocidas y dice cual movio la barra",
    callback = function()
        window:Notify({ title = "probando Energy", content = "5 formas, ~3 s", duration = 3 })
        local report = Shield.diagnose()
        U.log("energy diagnose\n" .. tostring(report))
        window:Notify({ title = "resultado", content = tostring(report), duration = 12 })
        local hp = Shield.health()
        hpLine:Set(hp and string.format("%.0f", hp) or "?")
    end,
})

itemsTab:CreateButton({
    name = "llenar la barra",
    description = "lee el maximo y suma esa diferencia",
    callback = function()
        local hp, max = Shield.health()
        if not hp or not max then return end
        local missing = math.ceil(max - hp)
        if missing <= 0 then
            window:Notify({ title = "vida", content = "ya esta llena" })
            return
        end
        local ok, why, after = Shield.add_energy(missing, 1.5)
        hpLine:Set(string.format("hp %s", tostring(after)))
        window:Notify({ title = ok and "barra llena" or "no subio", content = tostring(why) })
    end,
})

itemsTab:CreateSection({ name = "semi godmode" })
itemsTab:CreateText({
    name = "que hace",
    text = "anula los Energy negativos con los que los bosses hacen dano (hook de __namecall) " ..
           "y ademas mantiene el piso de vida. Los golpes de minion los aplica el server, " ..
           "esos los cubre el top-up.",
})
itemsTab:CreateToggle({
    name = "semi godmode",
    flag = "god_on",
    value = false,
    description = "bloquea dano de boss + energia automatica bajo el piso",
    callback = function(v)
        if v then Shield.god_start() else Shield.god_stop() end
    end,
})
itemsTab:CreateSlider({
    name = "piso de vida",
    flag = "god_floor",
    range = { 10, 180 },
    increment = 5,
    value = 60,
    callback = function(v) Shield.god.floor = v end,
})
local godLine = itemsTab:CreateText({ name = "estado del hook", text = Shield.status() })
itemsTab:CreateButton({
    name = "estado del semi godmode",
    callback = function()
        local text = Shield.status()
        godLine:Set(text)
        window:Notify({ title = "semi godmode", content = text, duration = 6 })
    end,
})
itemsTab:CreateButton({
    name = "quitar el hook",
    description = "vuelve a dejar que el juego reste vida normalmente",
    callback = function()
        Shield.remove()
        godLine:Set(Shield.status())
    end,
})

itemsTab:CreateSection({ name = "curas" })
itemsTab:CreateButton({
    name = "curarme (+25, sin comer nada)",
    description = "suma 25 por el remote Energy; no da, no equipa ni come ningun item",
    callback = function()
        local ok, why, hp = Shield.add_energy(25, 1.2)
        hpLine:Set(string.format("hp %s", tostring(hp)))
        window:Notify({
            title = ok and "+25" or "no subio",
            content = ok and ("via " .. tostring(why) .. ", nada en la mochila") or tostring(why),
            duration = 6,
        })
    end,
})
itemsTab:CreateButton({
    name = "comer (pizza real)",
    description = "la ruta lenta: pide la pizza, la equipa y la come. solo si el remote falla",
    callback = function()
        local ok = Items.eat("Pizza")
        local hp = Shield.health()
        hpLine:Set(string.format("hp %s", tostring(hp)))
        window:Notify({ title = "comer pizza", content = ok and "hecho" or "no pude", duration = 6 })
    end,
})
itemsTab:CreateButton({
    name = "curar a todos",
    description = "golden apple + HealTheNoobs",
    callback = function()
        local ok, why = Items.heal_all()
        window:Notify({ title = "heal all", content = ok and "hecho" or tostring(why) })
    end,
})
    -- handles the HUD refreshes; missing ones are simply skipped
    ctx.elements.hpLine = hpLine
    ctx.elements.godLine = godLine
    return nil
end

return Tab
