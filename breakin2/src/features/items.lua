-- features/items.lua
-- One catalogue for every obtainable object, and one function that actually
-- checks whether the object arrived.
--
-- Background, because the two halves of the game do not behave the same:
--   * most tools (food, drinks, Key, Louise, Phone, Book, Ladder) come back from
--     Events.GiveTool:FireServer("GoldenApple") - one string, no spaces;
--   * vending-only stock (Golden Apple, Gold/Rainbow Pizza, RainbowPizzaBox,
--     every weapon, armour) goes through Events.Vending with a category:
--         Vending:FireServer(3, "Crowbar1", "Weapons", playerName, 1)
--         Vending:FireServer(3, "RainbowPizzaBox", "Food", playerName, 1)
--         Vending:FireServer(3, "Armor2", "Armor", playerName, 1)
--     and the golden armour is bought rather than granted:
--         Vending:FireServer(1, "Armor", playerName, 150)
--
-- Sources disagree on two items (GoldenApple and GoldPizza appear on both
-- routes), so those are "auto": the give route is tried, the backpack is checked,
-- and the vending route is used if nothing showed up. That check is also what
-- makes the UI honest - a button that says "listo" only after the tool exists.

local Net = require("core/net")

local Items = {}

-- group: which dropdown it shows up in.
-- route: "give" | "food" | "weapon" | "armor" | "gold_armor" | "auto"
Items.catalog = {
    -- food and drink: GiveTool
    { id = "Apple",             label = "Apple",             group = "comida",  route = "give" },
    { id = "Cookie",            label = "Cookie",            group = "comida",  route = "give" },
    { id = "Chips",             label = "Bag of Chips",      group = "comida",  route = "give" },
    { id = "Pizza",             label = "Pizza",             group = "comida",  route = "give" },
    { id = "Lollipop",          label = "Lollipop",          group = "comida",  route = "give" },
    { id = "BloxyCola",         label = "Bloxy Cola",        group = "bebida",  route = "give" },
    { id = "ExpiredBloxyCola",  label = "Expired Bloxy Cola",group = "bebida",  route = "give" },
    { id = "Bottle",            label = "Bottle",            group = "bebida",  route = "give" },

    -- food the vending machines sell
    { id = "GoldenApple",       label = "Golden Apple",      group = "comida",  route = "auto" },
    { id = "GoldPizza",         label = "Golden Pizza",      group = "comida",  route = "auto" },
    { id = "RainbowPizza",      label = "Rainbow Pizza",     group = "comida",  route = "food" },
    { id = "RainbowPizzaBox",   label = "Rainbow Pizza Box", group = "comida",  route = "food" },

    -- weapons: vending only, category "Weapons"
    { id = "Crowbar1",          label = "Crowbar 1",         group = "armas",   route = "weapon" },
    { id = "Crowbar2",          label = "Crowbar 2",         group = "armas",   route = "weapon" },
    { id = "Crowbar3",          label = "Crowbar 3 (golden)",group = "armas",   route = "weapon" },
    { id = "Bat",               label = "Bat",               group = "armas",   route = "weapon" },
    { id = "Wrench",            label = "Wrench",            group = "armas",   route = "weapon" },
    { id = "Pitchfork",         label = "Pitchfork",         group = "armas",   route = "weapon" },
    { id = "Hammer",            label = "Hammer",            group = "armas",   route = "weapon" },
    { id = "Broom",             label = "Broom",             group = "armas",   route = "weapon" },

    -- armour: the gold one is a purchase, the plain one a vending grant
    { id = "Armor2",            label = "Golden Armor",      group = "armas",   route = "gold_armor" },

    -- quest and utility objects: GiveTool
    { id = "MedKit",            label = "Med Kit",           group = "objetos", route = "give" },
    { id = "Key",               label = "Key (Uncle Pete)",  group = "objetos", route = "give" },
    { id = "GoldKey",           label = "Gold Key",          group = "objetos", route = "give" },
    { id = "Louise",            label = "Louise (the rat)",  group = "objetos", route = "give" },
    { id = "Phone",             label = "Phone (hacker)",    group = "objetos", route = "give" },
    { id = "Book",              label = "Book (nerd)",       group = "objetos", route = "give" },
    { id = "Ladder",            label = "Ladder",            group = "objetos", route = "give" },
    { id = "Battery",           label = "Battery",           group = "objetos", route = "give" },
}

Items.GROUPS = { "comida", "bebida", "armas", "objetos" }

local byId = {}
for _, entry in ipairs(Items.catalog) do byId[entry.id] = entry end
Items.byId = byId

local function strip(s)
    return (tostring(s):gsub("%s+", ""))
end
Items.strip = strip

-- Gen2 dropdowns take plain strings, so the widgets list the human labels and
-- id_of() maps the choice back to the tool name the remote expects.
function Items.options(group)
    local out = {}
    for _, entry in ipairs(Items.catalog) do
        if not group or entry.group == group then
            table.insert(out, entry.label)
        end
    end
    return out
end

local byLabel = {}
for _, entry in ipairs(Items.catalog) do byLabel[entry.label] = entry.id end
Items.byLabel = byLabel

-- Accepts either a label or an id, so a saved config with an old value cannot
-- wedge the button.
function Items.id_of(choice)
    if type(choice) ~= "string" then return "GoldenApple" end
    return byLabel[choice] or (byId[strip(choice)] and strip(choice)) or "GoldenApple"
end

function Items.label_of(id)
    local entry = byId[id]
    return entry and entry.label or tostring(id)
end

-- ── backpack checks ─────────────────────────────────────────────────────────
-- Whether a tool is in the backpack or already in hand. This is the difference
-- between "I fired a remote" and "I have the object": several of these remotes
-- accept the call and then silently refuse it (level gate, wrong place, out of
-- money), so the only trustworthy answer comes from the character.
local function containers()
    local p = Net.Player
    local out = {}
    local char = p and p.Character
    if char then table.insert(out, char) end
    local bag = p and p:FindFirstChild("Backpack")
    if bag then table.insert(out, bag) end
    return out
end

function Items.has(id)
    local want = strip(id)
    for _, box in ipairs(containers()) do
        for _, child in ipairs(box:GetChildren()) do
            if child:IsA("Tool") and strip(child.Name) == want then return true, child end
        end
    end
    return false, nil
end

function Items.count_of(id)
    local want = strip(id)
    local n = 0
    for _, box in ipairs(containers()) do
        for _, child in ipairs(box:GetChildren()) do
            if child:IsA("Tool") and strip(child.Name) == want then
                n = n + 1
            elseif child:IsA("Tool") and child:FindFirstChild("Handle") then
                -- stacked copies sometimes land inside a folder tool
                for _, inner in ipairs(child:GetChildren()) do
                    if inner:IsA("Tool") and strip(inner.Name) == want then n = n + 1 end
                end
            end
        end
    end
    return n
end

-- Polls for the tool for a short window. 0.9 s is enough for a healthy server
-- response and short enough that the menu never feels stuck.
function Items.await(id, timeout)
    -- os.clock is not available in every sandbox the gate runs in; tick() is,
    -- and in Roblox both are seconds.
    local now = os.clock or tick
    local deadline = now() + (timeout or 0.9)
    repeat
        if Items.has(id) then return true end
        task.wait(0.1)
    until now() >= deadline
    return Items.has(id)
end

-- ── routes ──────────────────────────────────────────────────────────────────
local function player_name()
    local p = Net.Player
    return p and p.Name or "?"
end

-- fire_wait, not fire: these are hand-triggered, so waiting the 120 ms throttle
-- out is invisible to the player, while dropping the call is a dead button.
local function fire_give(id)
    return Net.fire_wait("GiveTool", strip(id))
end

local function fire_food(id)
    return Net.fire_wait("Vending", 3, strip(id), "Food", player_name(), 1)
end

local function fire_weapon(id)
    return Net.fire_wait("Vending", 3, strip(id), "Weapons", player_name(), 1)
end

local function fire_armor()
    -- the paid half first (it is what actually grants the gold armour), then the
    -- vending grant the older scripts use as the reliable one
    Net.fire_wait("Vending", 3, "Armor2", "Armor", player_name(), 1)
    task.wait(Net.gap_of("Vending") + 0.05)
    return Net.fire_wait("Vending", 3, "Armor2", "Armor", tostring(Net.Player), 1)
end

Items.routes = {
    give = fire_give,
    food = fire_food,
    weapon = fire_weapon,
    gold_armor = fire_armor,
}

-- Ordered attempts for a route. "auto" is give-then-food, because those two
-- items exist on both halves and only the backpack says which one took.
local ATTEMPTS = {
    give = { "give" },
    food = { "food" },
    weapon = { "weapon" },
    gold_armor = { "gold_armor" },
    auto = { "give", "food" },
}

-- Obtain one object and report the truth: did it land, and by which route.
-- Returns ok, reason.
function Items.obtain(id, timeout)
    local entry = byId[id]
    if not entry then return false, "unknown item" end
    if Items.has(id) and entry.group ~= "armas" then
        -- already holding it; giving again is how duplicates are made, so skip
        return true, "already held"
    end

    local reasons = {}
    for _, route in ipairs(ATTEMPTS[entry.route] or { "give" }) do
        local fired, why = Items.routes[route](id)
        if fired then
            if Items.await(id, timeout) then
                return true, route
            end
            table.insert(reasons, route .. " fired, nothing arrived")
        else
            table.insert(reasons, route .. ": " .. tostring(why))
        end
        task.wait(Net.gap_of("GiveTool") + 0.03)
    end
    return false, table.concat(reasons, "; ")
end

-- Give and equip in one step, waiting for the tool to exist before reparenting.
function Items.equip(id)
    local ok, tool = Items.has(id)
    if not ok then
        Items.await(id, 1.2)
        ok, tool = Items.has(id)   -- await only says whether it appeared
    end
    if not ok or not tool then return false end
    local char = Net.Player.Character
    if not char then return false end
    local fine = pcall(function() tool.Parent = char end)
    return fine
end

function Items.equip_if_present(id)
    local ok, tool = Items.has(id)
    if not ok then return false end
    local char = Net.Player.Character
    if not char then return false end
    return pcall(function() tool.Parent = char end)
end

function Items.unequip_all()
    local char = Net.Player.Character
    local bag = Net.Player:FindFirstChild("Backpack")
    if not char or not bag then return false end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then pcall(function() t.Parent = bag end) end
    end
    return true
end

-- ── bulk ────────────────────────────────────────────────────────────────────
-- Spaced by the actual throttle of the remote in use, so a stack is never
-- silently swallowed by Net's rate limit (that was the x10 bug: 0.15 s spacing
-- against a 0.15 s gate rejected roughly every other call).
function Items.stack(id, count)
    count = count or 5
    local entry = byId[id]
    local gap = Net.gap_of(entry and entry.route == "weapon" and "Vending" or "GiveTool")
    local step = gap + 0.08
    local got_before = Items.count_of(id)
    local fired = 0
    for i = 1, count do
        local ok = false
        if entry and entry.route == "weapon" then
            ok = fire_weapon(id)
        elseif entry and entry.route == "food" then
            ok = fire_food(id)
        elseif entry and entry.route == "gold_armor" then
            ok = fire_armor()
        else
            ok = fire_give(id)
        end
        if ok then fired = fired + 1 end
        if i < count then task.wait(step) end
    end
    task.wait(0.4)
    return fired, Items.count_of(id) - got_before
end

-- A short, deliberately small kit: enough to survive a wave, not a flood.
Items.survival_set = { "Crowbar3", "MedKit", "GoldenApple", "BloxyCola", "Chips" }

function Items.give_set(ids, on_progress)
    local ok_count, failed = 0, {}
    for i, id in ipairs(ids) do
        local ok, why = Items.obtain(id, 0.8)
        if ok then ok_count = ok_count + 1 else table.insert(failed, id .. " (" .. tostring(why) .. ")") end
        if on_progress then on_progress(i, #ids, id, ok) end
        task.wait(0.15)
    end
    return ok_count, failed
end

-- ── heals ───────────────────────────────────────────────────────────────────
-- Eating is the tool's own behaviour: equip the food and let the client activate
-- it. That is how a player heals, so nothing here invents a remote argument.
function Items.eat(id)
    if not Items.obtain(id, 1.0) then return false end
    Items.unequip_all()
    task.wait(0.1)
    if not Items.equip(id) then return false end
    task.wait(0.25)
    local _, tool = Items.has(id)
    if not tool then return false end
    local ok = pcall(function() tool:Activate() end)
    task.wait(0.4)
    return ok
end

function Items.heal_self()
    if Items.eat("Pizza") then return true end
    -- fallback: the energy remote the older scripts use for a top-up
    if Net.fire("Energy", 25, "Pizza") then return true end
    return false
end

-- Heal everyone: the server only trusts players who are actually holding a
-- Golden Apple, so it is given, equipped, then swapped in.
function Items.heal_all()
    Items.unequip_all()
    task.wait(0.15)
    if not Items.obtain("GoldenApple", 1.0) then
        return false, "no pude obtener la golden apple"
    end
    task.wait(0.2)
    if not Items.equip("GoldenApple") then
        return false, "no pude equiparla"
    end
    task.wait(0.3)
    local ok = Net.fire("HealTheNoobs")
    task.wait(0.3)
    Items.unequip_all()
    return ok
end

-- ── Twado ───────────────────────────────────────────────────────────────────
-- Two places report what the dog wants; both are read, because which one is
-- populated depends on whether the phone UI has been opened yet.
function Items.dog_wants()
    local out, seen = {}, {}
    local pg = Net.Player:FindFirstChild("PlayerGui")
    if not pg then return out end

    local assets = pg:FindFirstChild("Assets")
    local holder = assets and assets:FindFirstChild("Note", true)
    if holder then
        for _, v in ipairs(holder:GetDescendants()) do
            if v.Name:match("^Circle") and v.Visible and not seen[v.Name] then
                local id = strip((v.Name:gsub("Circle", "")))
                seen[id] = true
                table.insert(out, id)
            end
        end
    end

    local twado = pg:FindFirstChild("TwadoWants", true)
    if twado and twado:IsA("TextLabel") and twado.Text ~= "" and not seen[strip(twado.Text)] then
        table.insert(out, strip(twado.Text))
    end
    return out
end

function Items.feed_dog(id)
    if not Items.obtain(id, 1.0) then return false end
    Items.equip_if_present(id)
    task.wait(0.2)
    return Net.fire("CatFed", strip(id))
end

-- Self-check used by the build gate: every catalogue entry must name a route
-- the module can actually fire, and every route must be reachable. A typo here
-- used to mean a dead button instead of a failed build.
function Items.check_catalog()
    local problems = {}
    for _, entry in ipairs(Items.catalog) do
        if not Items.routes[entry.route] and not ATTEMPTS[entry.route] then
            table.insert(problems, entry.id .. " -> unknown route " .. tostring(entry.route))
        end
        if Items.id_of(entry.label) ~= entry.id then
            table.insert(problems, entry.id .. " -> label does not map back")
        end
    end
    for group in pairs({ comida = true, bebida = true, armas = true, objetos = true }) do
        if #Items.options(group) == 0 then
            table.insert(problems, "group without options: " .. group)
        end
    end
    return problems
end

return Items
