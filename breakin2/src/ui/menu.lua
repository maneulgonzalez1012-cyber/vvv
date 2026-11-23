-- ui/menu.lua
-- Rayfield Gen2 window. Everything off on load, every value saved by flag so a
-- config survives a rejoin.
--
-- Structure: this file owns layout and nothing else. Each control calls into a
-- feature module; no logic lives here beyond translating a widget into a call.
--
-- No tab icons: Gen2 takes an image (asset id), not an icon name, so a string
-- like "house" renders as nothing. The rail headings do the grouping instead.

local Rayfield = require("ui/rayfield")

local U = require("core/util")
local Net = require("core/net")
local Game = require("core/game")

local Train = require("features/train")
local Items = require("features/items")
local Combat = require("features/combat")
local Npc = require("features/npc")
local Move = require("features/move")
local World = require("features/world")
local Esp = require("features/esp")
local Roles = require("features/roles")

local Menu = {}

function Menu.build()
    local window = Rayfield:CreateWindow({
        name = "breaker / break in 2",
        subtitle = "nothing fires until you flip it",
        sidebarLayout = true,
        profile = "external menu",
        theme = "cobalt",
        configuration = {
            autoSave = true,
            autoLoad = true,
            fileName = "breaker_bi2",
            customFolder = "breaker",
        },
    })
    U.window = window
    U.flush()

    -- ── HOME ────────────────────────────────────────────────────────────────
    local home = window:CreateTab({ name = "Home" })

    home:CreateSection({ name = "estado" })
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

    -- ── TRAINING ────────────────────────────────────────────────────────────
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

    -- ── ITEMS ───────────────────────────────────────────────────────────────
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
            local held = {}
            local boxes = {}
            local char = Net.Player.Character
            local bag = Net.Player:FindFirstChild("Backpack")
            if char then table.insert(boxes, char) end
            if bag then table.insert(boxes, bag) end
            for _, box in ipairs(boxes) do
                for _, c in ipairs(box:GetChildren()) do
                    if c:IsA("Tool") then table.insert(held, c.Name) end
                end
            end
            local seen, list = {}, {}
            for _, n in ipairs(held) do
                if not seen[n] then seen[n] = true; table.insert(list, n) end
            end
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

    itemsTab:CreateSection({ name = "curas" })
    itemsTab:CreateButton({
        name = "curarme",
        description = "equipa la pizza y la come",
        callback = function()
            local ok = Items.heal_self()
            window:Notify({ title = "heal", content = ok and "hecho" or "no pude" })
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

    -- ── NPCs ────────────────────────────────────────────────────────────────
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
        description = "lee que comida pide la GUI y la entrega",
        callback = function()
            local ok = Npc.twado()
            window:Notify({ title = "twado", content = ok and "comido" or "no pude" })
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

    -- ── COMBAT ──────────────────────────────────────────────────────────────
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

    -- ── MOVE ────────────────────────────────────────────────────────────────
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

    -- ── WORLD ───────────────────────────────────────────────────────────────
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

    -- ── ENEMIES ─────────────────────────────────────────────────────────────
    local espTab = window:CreateTab({ name = "Enemies" })
    espTab:CreateToggle({
        name = "highlight enemigos",
        flag = "esp_on",
        value = false,
        callback = function(v) Esp.set_enabled(v) end,
    })
    espTab:CreateToggle({
        name = "mostrar distancia",
        flag = "esp_dist",
        value = true,
        callback = function(v) Esp.show_distance = v end,
    })
    espTab:CreateToggle({
        name = "mostrar hp",
        flag = "esp_hp",
        value = true,
        callback = function(v) Esp.show_health = v end,
    })
    local espLine = espTab:CreateText({ name = "cercanos", text = "sin enemigos" })

    -- ── ROLES ───────────────────────────────────────────────────────────────
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

    -- ── SAFETY ──────────────────────────────────────────────────────────────
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

    -- ── HUD loop ────────────────────────────────────────────────────────────
    U.loop("hud", 1, function()
        pcall(function() placeLine:Set(Game.where()) end)
        local list = Esp.read()
        enemyStat:Set(#list)
        remoteStat:Set(U.count(Net.remotes))
        local line = Esp.summary(list)
        pcall(function() enemyLine:Set(line) end)
        pcall(function() espLine:Set(line) end)
        if Esp.enabled then Esp.apply(list) end
    end)

    return window
end

return Menu
