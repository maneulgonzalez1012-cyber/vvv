-- features/shield.lua
-- Survival: adding energy out of thin air, and stopping the game from taking it.
--
-- What the game actually does, from the scripts that work against it:
--
--   Events.Energy:FireServer(25, "Pizza")     -- +25, no pizza required
--   Events.Energy:FireServer(999999)          -- one argument alone is accepted
--   Events.Energy:FireServer(-amount, false, false)  -- negative SUBTRACTS
--
-- So the heal is not the food: the food name is a label the server echoes back.
-- Giving a Pizza first was theatre. Here the amount is sent on its own and the
-- result is *checked*: the local Humanoid mirrors server health, so if the
-- number actually went up, the call landed. Whichever argument shape worked is
-- cached, the same way the weapon route is.
--
-- Semi-godmode is a different mechanism. In Break In 2 the boss attacks apply
-- their damage *through this same remote* with a negative amount, so hooking
-- the namecall and clamping a negative to zero stops them. That is the trick
-- every public semi-godmode uses. It only works if the executor exposes
-- hookmetamethod / getrawmetatable, so it is guarded, reported, and backed by a
-- periodic top-up for the damage that is applied server-side (ordinary enemies),
-- which a client hook cannot touch.

local Net = require("core/net")
local U = require("core/util")

local Shield = {}

Shield.amount = 25
Shield.energy_variant = nil     -- 1 = (amount, food), 2 = (amount), set on first success
Shield.hooked = false
Shield.blocked = 0

-- ── energy ──────────────────────────────────────────────────────────────────

function Shield.health()
    local hum = Net.humanoid()
    if not hum then return nil, nil end
    return hum.Health, hum.MaxHealth
end

local ENTRY_POINTS = {
    { label = "amount+food", args = function(amount) return amount, "Pizza" end },
    { label = "amount", args = function(amount) return amount end },
    { label = "amount+false", args = function(amount) return amount, false, false end },
}

local function try_fire(index, amount)
    local entry = ENTRY_POINTS[index]
    return Net.fire_wait("Energy", entry.args(amount))
end

-- Send, then look at the humanoid. `+25` is easy to confirm: either Health went
-- up by it or the call was ignored.
function Shield.add_energy(amount, timeout)
    amount = amount or Shield.amount
    local before = Shield.health()
    local now = os.clock or tick
    local deadline = now() + (timeout or 1.0)

    local order = {}
    if Shield.energy_variant then
        table.insert(order, Shield.energy_variant)
    end
    for i = 1, #ENTRY_POINTS do
        if i ~= Shield.energy_variant then table.insert(order, i) end
    end

    for _, index in ipairs(order) do
        if not try_fire(index, amount) then
            -- throttled or missing; one retry through fire_wait is enough
            try_fire(index, amount)
        end
        repeat
            task.wait(0.08)
            local after = Shield.health()
            if before and after and after > before + 0.5 then
                Shield.energy_variant = index
                return true, ENTRY_POINTS[index].label, after
            end
        until now() >= deadline
        deadline = now() + 0.8
    end

    local after = Shield.health()
    if after and before and after > before + 0.5 then
        return true, "subio solo", after
    end
    return false, "el server no sumo nada"
end

-- Instance heal, the button the user actually wants: +25 without touching food.
function Shield.top_up(amount)
    return Shield.add_energy(amount or Shield.amount, 1.2)
end

-- ── hook ────────────────────────────────────────────────────────────────────

-- The pure decision, split out so it can be tested without a hook.
function Shield.filter_energy(arg)
    if type(arg) ~= "number" then return arg end
    if arg < 0 then return 0 end
    return arg
end

function Shield.hook_supported()
    return type(getrawmetatable) == "function"
        and type(setreadonly) == "function"
        and type(getnamecallmethod) == "function"
        and type(hookmetamethod) == "function"
end

local original_namecall = nil

function Shield.install()
    if Shield.hooked then return true end
    if not Shield.hook_supported() then
        U.notify("semi godmode", "tu executor no expone hookmetamethod; uso el top-up")
        return false
    end

    local ok = pcall(function()
        local mt = getrawmetatable(game)
        original_namecall = mt.__namecall

        local function wrapped(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" and self.Name == "Energy" then
                local args = { ... }
                if type(args[1]) == "number" and args[1] < 0 then
                    args[1] = 0
                    Shield.blocked = Shield.blocked + 1
                end
                return original_namecall(self, table.unpack(args))
            end
            return original_namecall(self, ...)
        end

        -- newcclosure keeps the hook out of the game's own introspection where
        -- the executor provides it; the plain function is a fine fallback.
        if type(newcclosure) == "function" then wrapped = newcclosure(wrapped) end

        setreadonly(mt, false)
        mt.__namecall = wrapped
        setreadonly(mt, true)
    end)

    if not ok then
        U.log("semi godmode: hook fallo")
        return false
    end
    Shield.hooked = true
    return true
end

function Shield.remove()
    if not Shield.hooked then return end
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        mt.__namecall = original_namecall
        setreadonly(mt, true)
    end)
    Shield.hooked = false
end

-- ── semi godmode ────────────────────────────────────────────────────────────

Shield.god = {
    enabled = false,
    floor = 60,
    interval = 0.6,
    heals = 0,
}

local last_heal = nil

function Shield.god_tick()
    if not Shield.god.enabled then return false end
    local hp = Shield.health()
    if not hp then return false end
    local now = os.clock or tick
    if hp > Shield.god.floor then return false end
    if last_heal and (now() - last_heal) < Shield.god.interval then return false end
    local ok = Shield.add_energy(Shield.amount, 0.5)
    if ok then
        last_heal = now()
        Shield.god.heals = Shield.god.heals + 1
    end
    return ok
end

function Shield.god_start()
    Shield.god.enabled = true
    Shield.install()
    U.loop("god", Shield.god.interval, function()
        if not Shield.god.enabled then U.stop("god"); return end
        Shield.god_tick()
    end)
end

function Shield.god_stop()
    Shield.god.enabled = false
    Shield.remove()
    U.stop("god")
end

function Shield.status()
    if Shield.hooked then
        return "hook activo | negativos bloqueados: " .. Shield.blocked
    end
    local hp = Shield.health()
    if hp then return string.format("sin hook | hp %.0f", hp) end
    return "sin personaje"
end

return Shield
