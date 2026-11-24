-- breaker / break in 2 - readable bundle
-- built from 28 modules; this file is for reading, dist/breakin2_v3.obf.lua
-- is what ships (same modules, split into parts, obfuscated).

local MODULES = {}
local CACHE = {}

local function require(name)
    local hit = CACHE[name]
    if hit ~= nil then return hit end
    local factory = MODULES[name]
    if not factory then error("missing module: " .. tostring(name), 2) end
    local value = factory(require)
    if value == nil then value = true end
    CACHE[name] = value
    return value
end
MODULES["core/game"] = function(require)
-- core/game.lua
-- Read-only view of the workspace. Everything here is discovery: the game does
-- not publish its folder layout, so each accessor tries the known path, then a
-- descendant search, then gives up and says so. Nothing in this file fires a
-- remote or moves a part.


local Game = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

Game.Player = Players.LocalPlayer

-- Known folders, confirmed against the live game. Witnesses/Enemies are listed
-- with their historic names too, because Cracky4 has renamed them before.
local FOLDERS = {
    badGuys      = { "BadGuys" },
    badGuysBoss  = { "BadGuysBoss" },
    badGuysFront = { "BadGuysFront", "BadGuysFront2" },
    badGuyBrute  = { "BadGuyBrute" },
    badGuyPizza  = { "BadGuyPizza" },
    fallenTrees  = { "FallenTrees" },
    outside      = { "OutsideParts" },
    final        = { "Final" },
}

function Game.folder(key, deep)
    local names = FOLDERS[key]
    if not names then return nil end
    for _, n in ipairs(names) do
        local direct = Workspace:FindFirstChild(n)
        if direct then return direct end
    end
    if deep then
        for _, n in ipairs(names) do
            local hit = Workspace:FindFirstChild(n, true)
            if hit then return hit end
        end
    end
    return nil
end

-- Returns { {name=, inst=}, ... } for a folder. Health is read when a Humanoid
-- is there so the enemy list can drop the corpses without another call site.
function Game.enemies()
    local out = {}
    local seen = {}
    for _, key in ipairs({ "badGuys", "badGuysBoss", "badGuysFront", "badGuyBrute", "badGuyPizza" }) do
        local f = Game.folder(key)
        if f then
            for _, m in ipairs(f:GetChildren()) do
                if not seen[m] then
                    seen[m] = true
                    local hum = m:FindFirstChildOfClass("Humanoid")
                    table.insert(out, {
                        name = m.Name,
                        inst = m,
                        hp = hum and hum.Health or nil,
                        root = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChildWhichIsA("BasePart", true),
                    })
                end
            end
        end
    end
    return out
end

function Game.enemy_count()
    return #Game.enemies()
end

-- Stat names as the remote expects them. The gym equipment and the rainbow
-- pizza both end up on RainbowWhatStat, so one reader covers both.
Game.STATS = { "Strength", "Speed" }

-- Local stat numbers are not networked in a readable field; the game shows them
-- as segmented pips in the gym UI. We read the pips when present so the HUD can
-- display something truthful, and report "unknown" rather than guessing.
function Game.local_stats()
    local out = { Strength = nil, Speed = nil }
    local pg = Game.Player:FindFirstChild("PlayerGui")
    if not pg then return out end
    local ui = pg:FindFirstChild("Assets")
    if not ui then return out end
    for _, statName in ipairs(Game.STATS) do
        local holder = ui:FindFirstChild(statName, true)
        if holder then
            local on = 0
            for _, child in ipairs(holder:GetDescendants()) do
                if child:IsA("Frame") and child.Visible and child.BackgroundTransparency < 0.5 then
                    on = on + 1
                end
            end
            if on > 0 then out[statName] = on end
        end
    end
    return out
end

function Game.is_lobby()
    -- the base has BadGuys; the lobby does not
    return Game.folder("badGuys") == nil and Game.folder("outside") == nil
end

function Game.place_id()
    return game.PlaceId
end

-- Named places, so a feature can refuse to run somewhere it would be useless
-- instead of failing halfway through.
Game.PLACES = {
    lobby      = 13864661000,
    private    = 14775231477,
    base       = 13864667823,
}

function Game.where()
    local id = game.PlaceId
    if id == Game.PLACES.base then return "base" end
    if id == Game.PLACES.lobby then return "lobby" end
    if id == Game.PLACES.private then return "private" end
    return "other:" .. tostring(id)
end

-- Cheap world -> screen, used by the ESP list and nothing else.
function Game.screen_of(worldPart)
    if not worldPart then return nil end
    local cam = Workspace.CurrentCamera
    if not cam then return nil end
    local vp = cam.ViewportSize
    local p = cam:WorldToViewportPoint(worldPart.Position)
    if p.Z <= 0 then return nil end
    return Vector2.new(p.X, p.Y), vp, p.Z
end

return Game

end
MODULES["core/net"] = function(require)
-- core/net.lua
-- Everything that talks to the server goes through here. Three rules:
--   1. A remote that is not there is reported once and never fired.
--   2. Every fire passes the same gate: kill switch, dry-run, rate limit.
--   3. Arguments are whatever the caller passes; no packing magic, so a broken
--      remote signature shows up as a missing feature instead of a kick.

local U = require("core/util")

local Net = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Net.Player = Players.LocalPlayer
Net.RS = ReplicatedStorage

-- master switches, driven from the Safety tab
Net.enabled = true
Net.dryRun = false

Net.remotes = {}
Net.missing = {}
local lastFired = {}
local fireCount = {}

-- Known remotes. Names come from the live game; if one disappears the module
-- that needs it logs a miss instead of erroring every frame.
local KNOWN = {
    Events = {
        "GiveTool", "Vending", "Energy", "HealTheNoobs", "RainbowWhatStat",
        "HitBadguy", "RoadMissionEvent", "KeyEvent", "LouiseGive", "CatFed",
        "OnDoorHit", "LarryEndingEvent", "OutsideFood",
    },
    RemoteEvents = { "OutsideRole" },
}

local function waitChild(parent, name, timeout)
    if not parent then return nil end
    local found = parent:FindFirstChild(name)
    if found then return found end
    local ok, res = pcall(function()
        return parent:WaitForChild(name, timeout or 5)
    end)
    if ok then return res end
    return nil
end
Net.waitChild = waitChild

function Net.container(name)
    return waitChild(ReplicatedStorage, name, 10)
end

-- Resolves every known remote once, at load. Result lands in Net.remotes keyed
-- by name so features stay readable.
function Net.resolve()
    Net.remotes = {}
    Net.missing = {}
    -- Lua 5.1 target: no `continue`, so the missing container is handled with a
    -- plain else. Same behaviour, and Prometheus can compile it.
    for containerName, names in pairs(KNOWN) do
        local box = Net.container(containerName)
        if not box then
            for _, n in ipairs(names) do table.insert(Net.missing, containerName .. "." .. n) end
        else
            for _, n in ipairs(names) do
                local r = waitChild(box, n, 2)
                if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction") or r:IsA("UnreliableRemoteEvent")) then
                    Net.remotes[n] = r
                else
                    table.insert(Net.missing, containerName .. "." .. n)
                end
            end
        end
    end
    return Net.remotes
end

-- Anything not in Net.remotes is picked up lazily, so a remote that loads late
-- still works without a restart.
function Net.get(name)
    local r = Net.remotes[name]
    if r and r.Parent then return r end
    for containerName, names in pairs(KNOWN) do
        for _, n in ipairs(names) do
            if n == name then
                local box = ReplicatedStorage:FindFirstChild(containerName)
                if box then
                    local c = box:FindFirstChild(name)
                    if c then
                        Net.remotes[name] = c
                        return c
                    end
                end
            end
        end
    end
    return nil
end

-- Per-remote throttle. minGap is seconds between fires, burst is how many can
-- go out back to back. Defaults are deliberately conservative: the training and
-- combat remotes are the two that get a player kicked for spamming.
local GAP = {
    RainbowWhatStat = 0.10,
    HitBadguy = 0.05,
    Energy = 0.20,
    GiveTool = 0.12,
    Vending = 0.12,
    HealTheNoobs = 0.50,
    RoadMissionEvent = 0.15,
}
local GAP_DEFAULT = 0.10

-- Exposed so callers can space their own loops against the same numbers instead
-- of guessing and having every other call quietly rejected as "throttled".
function Net.gap_of(name)
    return GAP[name] or GAP_DEFAULT
end

function Net.canFire(name)
    local gap = GAP[name] or GAP_DEFAULT
    local now = os.clock()
    local last = lastFired[name]
    if last and (now - last) < gap then return false end
    lastFired[name] = now
    fireCount[name] = (fireCount[name] or 0) + 1
    return true
end

function Net.stats()
    return fireCount
end

function Net.resetStats()
    fireCount = {}
end

function Net.fire(name, ...)
    if not Net.enabled then return false, "disabled" end
    local remote = Net.get(name)
    if not remote then return false, "missing" end
    if Net.dryRun then
        U.log("dry-run fire", name)
        return false, "dry-run"
    end
    if not Net.canFire(name) then return false, "throttled" end
    local ok, err = pcall(function(...)
        remote:FireServer(...)
    end, ...)
    if not ok then
        U.log("fire failed", name, tostring(err))
        return false, tostring(err)
    end
    return true
end

-- Waiting variant for things the player asked for by hand (an item button, a
-- quest step). Dropping the call would look like a broken button, so it waits
-- out the gap instead - bounded, so a wedged clock cannot hang the menu.
function Net.wait_gap(name, limit)
    local gap = Net.gap_of(name)
    local now = os.clock or tick
    local deadline = now() + (limit or gap + 0.5)
    while true do
        local last = lastFired[name]
        if not last or (now() - last) >= gap then return true end
        if now() >= deadline then return false end
        task.wait(0.02)
    end
end

function Net.fire_wait(name, ...)
    if not Net.enabled then return false, "disabled" end
    local remote = Net.get(name)
    if not remote then return false, "missing" end
    if Net.dryRun then U.log("dry-run fire", name); return false, "dry-run" end
    if not Net.wait_gap(name) then return false, "throttled" end
    return Net.fire(name, ...)
end

function Net.invoke(name, ...)
    if not Net.enabled then return false, "disabled" end
    local remote = Net.get(name)
    if not remote or not remote:IsA("RemoteFunction") then return false, "missing" end
    if Net.dryRun then return false, "dry-run" end
    local results = table.pack(pcall(function(...)
        return remote:InvokeServer(...)
    end, ...))
    if results[1] then return true, results[2] end
    return false, tostring(results[2])
end

-- ClickDetector and touch, the two non-remote interactions the game exposes.
-- Wrapped because both are executor globals and both can be absent.
function Net.click(detector)
    if not detector or not detector:IsA("ClickDetector") then return false end
    if Net.dryRun then U.log("dry-run click", detector:GetFullName()); return false end
    if type(fireclickdetector) ~= "function" then return false end
    return pcall(fireclickdetector, detector, 1)
end

function Net.touch(part)
    if not part or not part:IsA("BasePart") then return false end
    local char = Net.Player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    if Net.dryRun then U.log("dry-run touch", part:GetFullName()); return false end
    if type(firetouchinterest) ~= "function" then return false end
    local ok = pcall(function()
        firetouchinterest(part, hrp, 0)
        task.wait()
        firetouchinterest(part, hrp, 1)
    end)
    return ok
end

function Net.character()
    local c = Net.Player.Character
    if c and c.Parent then return c end
    return Net.Player.CharacterAdded:Wait()
end

function Net.humanoid()
    local c = Net.character()
    return c and c:FindFirstChildOfClass("Humanoid")
end

function Net.root()
    local c = Net.character()
    return c and c:FindFirstChild("HumanoidRootPart")
end

return Net

end
MODULES["core/util"] = function(require)
-- core/util.lua
-- Helpers shared by every module: notifications, throttled loops, safe calls.
-- Nothing in here touches the network or the menu; it is created first so the
-- rest of the script can log before the window exists.

local U = {}

-- Bumped on every build that ships. The Home tab shows it, so an old file that
-- is still cached somewhere is obvious instead of "the fix did not work".
U.VERSION = "2026.11.23-d"

-- filled in by ui/menu once the Rayfield window exists
U.window = nil
U.pending = {}

function U.notify(title, content)
    if U.window then
        pcall(function()
            U.window:Notify({ title = title, content = content, duration = 4 })
        end)
    else
        table.insert(U.pending, { title, content })
    end
end

function U.flush()
    local q = U.pending
    U.pending = {}
    for _, m in ipairs(q) do U.notify(m[1], m[2]) end
end

function U.log(...)
    print("[breaker]", ...)
end

-- pcall wrapper that never throws and reports once per failure site
local warned = {}
function U.safe(label, fn)
    local ok, err = pcall(fn)
    if not ok and not warned[label] then
        warned[label] = true
        U.log("fail", label, tostring(err))
    end
    return ok, err
end

function U.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- A cancellable loop. Start returns a token; Stop invalidates it, so flipping a
-- toggle twice can never leave two loops firing the same remote.
local loops = {}
function U.loop(name, step, fn)
    U.stop(name)
    local token = {}
    loops[name] = token
    task.spawn(function()
        while loops[name] == token do
            local ok = pcall(fn)
            if not ok then break end
            task.wait(step)
        end
        if loops[name] == token then loops[name] = nil end
    end)
    return token
end

function U.stop(name)
    loops[name] = nil
end

function U.running(name)
    return loops[name] ~= nil
end

function U.stop_all()
    loops = {}
end

function U.loop_names()
    local out = {}
    for k in pairs(loops) do table.insert(out, k) end
    return out
end

return U

end
MODULES["features/combat"] = function(require)
-- features/combat.lua
-- Wave support. The damage remote is HitBadguy(target, damage, hits): the
-- server clamps damage against its own weapon table, so the honest use is
-- firing it with the strongest weapon numbers the game accepts rather than a
-- made-up 1e9.
--
-- Defaults are deliberately mild: every toggle is off, the damage value is the
-- one a Golden Crowbar produces, and the loop is throttled per enemy so a pack
-- of eight minions cannot turn into a remote flood.

local Net = require("core/net")
local Game = require("core/game")
local U = require("core/util")

local Combat = {}

Combat.auto_hit = false
Combat.damage = 64.8      -- golden crowbar tier; server clamps higher anyway
Combat.hits = 4
Combat.interval = 0.25
Combat.max_range = 0       -- 0 = no distance filter
Combat.skip_boss = false

Combat.anchor = false      -- freeze enemies in place, own client only

local hitsSent = 0

-- Boss minions live in BadGuysBoss and the brutes arrive as their own model at
-- the workspace root; matching the name against "Boss" missed both, so the
-- "skip boss" switch did nothing. Match the folder they came from too.
local function is_boss(e)
    if tostring(e.name):lower():find("boss") then return true end
    if tostring(e.name):find("Brute") then return true end
    local box = e.inst and e.inst.Parent
    if box and tostring(box.Name):find("Boss") then return true end
    return false
end
Combat.is_boss = is_boss

function Combat.hit(enemy)
    local target = enemy.inst
    if not target or not target.Parent then return false end
    local ok = Net.fire("HitBadguy", target, Combat.damage, Combat.hits)
    if ok then hitsSent = hitsSent + 1 end
    return ok
end

function Combat.stats()
    return hitsSent
end

-- One sweep over every enemy folder. Exposed as a button so a player can land a
-- single burst instead of arming a loop they forget about.
function Combat.burst(passes)
    passes = passes or 1
    local n = 0
    for _ = 1, passes do
        for _, e in ipairs(Game.enemies()) do
            if not (Combat.skip_boss and is_boss(e)) then
                if Combat.hit(e) then n = n + 1 end
            end
        end
        task.wait(Combat.interval)
    end
    return n
end

local function in_range(e)
    if Combat.max_range <= 0 then return true end
    local root = Net.root()
    if not root or not e.root then return true end
    return (root.Position - e.root.Position).Magnitude <= Combat.max_range
end

function Combat.start()
    if U.running("combat") then return end
    U.loop("combat", Combat.interval, function()
        if not Combat.auto_hit then U.stop("combat"); return end
        local root = Net.root()
        if not root then return end
        for _, e in ipairs(Game.enemies()) do
            if not (Combat.skip_boss and is_boss(e)) and in_range(e) then
                Combat.hit(e)
            end
        end
    end)
end

function Combat.stop()
    Combat.auto_hit = false
    U.stop("combat")
end

-- Freezing enemies is a local, visual change: anchoring their root part stops
-- the client-side replication of their walk but the server still owns their
-- position, so a minion can snap back. It exists for the boss phases where the
-- player cannot keep up, and it is clearly labelled as client-side.
function Combat.freeze(state)
    Combat.anchor = state
    local n = 0
    for _, e in ipairs(Game.enemies()) do
        if e.root then
            pcall(function()
                e.root.Anchored = state
                n = n + 1
            end)
        end
    end
    return n
end

-- Unanchors anything left frozen, including enemies that spawned after the
-- toggle was flipped off.
function Combat.thaw_all()
    local n = 0
    for _, e in ipairs(Game.enemies()) do
        if e.root and e.root.Anchored then
            pcall(function()
                e.root.Anchored = false
                n = n + 1
            end)
        end
    end
    Combat.anchor = false
    return n
end

return Combat

end
MODULES["features/esp"] = function(require)
-- features/esp.lua
-- Enemy list with distance and health, drawn on the Rayfield side as text plus
-- a Highlight per enemy. Roblox has no drawing-API guarantee across executors,
-- so the visual is a Highlight instance (engine-supported, no exploit drawing
-- library needed) and the textual list carries the numbers.
--
-- There is no local enemy ESP that a server can see; a Highlight is a
-- client-side instance like a BillboardGui. It is still visible to anyone
-- looking at the player's screen, which is the same class of risk as any ESP.

local Net = require("core/net")
local Game = require("core/game")

local Esp = {}

Esp.enabled = false
Esp.show_distance = true
Esp.show_health = true
Esp.color = Color3.fromRGB(255, 60, 60)

local highlights = {}

-- CoreGui is protected for most executors; a Highlight there can be refused.
-- Falling back to the player's own PlayerGui keeps the feature working (a
-- ScreenGui-less Highlight still draws in 3D) instead of silently doing nothing.
local function highlight_parent()
    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then
        local fine = pcall(function()
            local probe = Instance.new("Folder")
            probe.Parent = core
            probe:Destroy()
        end)
        if fine then return core end
    end
    local p = Net.Player or game:GetService("Players").LocalPlayer
    local pg = p and p:FindFirstChild("PlayerGui")
    return pg
end

local parentOnce = nil

local function make_highlight(inst)
    local h = highlights[inst]
    if h and h.Parent then return h end
    if parentOnce == nil then parentOnce = highlight_parent() end
    local parent = parentOnce
    if not parent then return nil end
    local ok, created = pcall(function()
        local hi = Instance.new("Highlight")
        hi.FillColor = Esp.color
        hi.FillTransparency = 0.65
        hi.OutlineColor = Esp.color
        hi.OutlineTransparency = 0
        hi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hi.Adornee = inst
        hi.Parent = parent
        return hi
    end)
    if ok then
        highlights[inst] = created
        return created
    end
    return nil
end

local function clear_highlight(inst)
    local h = highlights[inst]
    if h then
        pcall(function() h:Destroy() end)
        highlights[inst] = nil
    end
end

function Esp.clear()
    for inst in pairs(highlights) do clear_highlight(inst) end
    highlights = {}
end

-- Returns a snapshot the menu renders: name, distance, health, and whether the
-- entry is close enough to matter. Called on a timer by the HUD, not per frame.
function Esp.read()
    local root = Net.root()
    local list = {}
    for _, e in ipairs(Game.enemies()) do
        local dist = nil
        if root and e.root then
            dist = math.floor((root.Position - e.root.Position).Magnitude)
        end
        table.insert(list, {
            name = e.name,
            dist = dist,
            hp = e.hp,
            alive = (e.hp == nil) or e.hp > 0,
            inst = e.inst,
        })
    end
    table.sort(list, function(a, b)
        return (a.dist or 99999) < (b.dist or 99999)
    end)
    return list
end

function Esp.apply(list)
    if not Esp.enabled then return end
    local live = {}
    for _, e in ipairs(list) do
        if e.alive then
            live[e.inst] = true
            make_highlight(e.inst)
        end
    end
    for inst in pairs(highlights) do
        if not live[inst] or not inst.Parent then clear_highlight(inst) end
    end
end

function Esp.set_enabled(state)
    Esp.enabled = state
    if not state then Esp.clear() end
end

function Esp.summary(list)
    local parts = {}
    for i, e in ipairs(list) do
        if i > 8 then
            table.insert(parts, "+" .. (#list - 8) .. " mas")
            break
        end
        local piece = e.name
        if Esp.show_distance and e.dist then piece = piece .. " " .. e.dist .. "m" end
        if Esp.show_health and e.hp then piece = piece .. " " .. math.floor(e.hp) .. "hp" end
        table.insert(parts, piece)
    end
    if #parts == 0 then return "sin enemigos" end
    return table.concat(parts, "  |  ")
end

return Esp

end
MODULES["features/items"] = function(require)
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
local U = require("core/util")

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

-- Weapons are the one route nobody agrees on. Every public script fires
-- Vending(3, name, "Weapons", X, 1) but X is written differently in each:
-- the player's name, the Player object, or nothing at all. Rather than pick one
-- and hope, the variants are tried in order and the one that produced a tool is
-- cached - so the first weapon costs a few extra calls and every later one is a
-- single fire.
local WEAPON_VARIANTS = {
    { label = "name", args = function(id) return 3, strip(id), "Weapons", player_name(), 1 end },
    { label = "player", args = function(id) return 3, strip(id), "Weapons", Net.Player, 1 end },
    { label = "no-count", args = function(id) return 3, strip(id), "Weapons", player_name() end },
    { label = "bare", args = function(id) return 3, strip(id), "Weapons" end },
}

Items.weapon_variant = nil   -- remembered once one of them works
Items.weapon_variant_log = {} -- label -> "ok" | "nothing", for the UI

local function fire_weapon(id)
    if Items.weapon_variant then
        local v = WEAPON_VARIANTS[Items.weapon_variant]
        return Net.fire_wait("Vending", v.args(id))
    end
    for index, v in ipairs(WEAPON_VARIANTS) do
        local fired = Net.fire_wait("Vending", v.args(id))
        if fired and Items.await(id, 0.7) then
            Items.weapon_variant = index
            Items.weapon_variant_log[v.label] = "ok"
            U.log("weapon variant", v.label)
            return true
        end
        Items.weapon_variant_log[v.label] = fired and "nothing" or "not fired"
        task.wait(Net.gap_of("Vending") + 0.05)
    end
    return false
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
    if Items.has(id) then
        -- already holding it; giving again is how duplicates are made, so skip
        return true, "already held"
    end

    if entry.route == "weapon" then
        local ok = fire_weapon(id)
        if ok then return true, "weapon (" .. WEAPON_VARIANTS[Items.weapon_variant].label .. ")" end
        return false, "ninguna variante de Vending entrego el arma"
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

-- Every tool the character or backpack holds, de-duplicated and sorted, so the
-- menu does not have to walk the instances itself.
function Items.held()
    local out, seen = {}, {}
    for _, box in ipairs(containers()) do
        for _, child in ipairs(box:GetChildren()) do
            if child:IsA("Tool") and not seen[child.Name] then
                seen[child.Name] = true
                table.insert(out, child.Name)
            end
        end
    end
    table.sort(out)
    return out
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

-- Thin delegates: the energy mechanics moved to features/shield.lua, but the
-- names are kept so older call sites (and saved menus) keep working.
function Items.energy(amount, food)
    local Shield = require("features/shield")
    if food and Shield.energy_variant == 1 then
        return Net.fire("Energy", amount, food)
    end
    return Shield.add_energy(amount, 1.0)
end

function Items.god_tick()
    return require("features/shield").god_tick()
end

-- Energy lives in features/shield.lua now: the heal does not need a food, so
-- the food path stays here and the "+25 out of nowhere" path lives there.
function Items.heal_self()
    local Shield = require("features/shield")
    local ok = Shield.add_energy(25, 1.2)
    if ok then return true end
    -- last resort: eat something, if the remote path is refused
    return Items.eat("Pizza")
end

-- Heal every other player on the server. HealTheNoobs only heals a noob who is
-- asking, and it needs the golden apple in hand, so the apple is equipped once
-- and the remote is fired per asking player. Returns ok, reason.
function Items.heal_all()
    if not Items.obtain("GoldenApple", 1.2) then
        return false, "no pude obtener la golden apple"
    end
    Items.unequip_all()
    task.wait(0.1)
    if not Items.equip_if_present("GoldenApple") then
        return false, "no pude equipar la golden apple"
    end
    if not Net.fire_wait("HealTheNoobs") then
        return false, "HealTheNoobs no respondio"
    end
    return true, "HealTheNoobs enviado"
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

end
MODULES["features/move"] = function(require)
-- features/move.lua
-- Movement, all local. Nothing here fires a remote, so none of it is visible to
-- the server beyond the normal position updates a fast player already sends.
-- WalkSpeed is capped well under Roblox's anti-teleport threshold, and fly is a
-- low, smooth body-velocity push instead of a CFrame teleport loop.

local Net = require("core/net")

local Move = {}

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

Move.base_walk = 16
Move.base_jump = 50

Move.speed = false
Move.speed_value = 40
Move.jump = false
Move.jump_value = 80
Move.noclip = false
Move.fly = false
Move.fly_value = 60

local conns = {}
local flyBody = nil
local flyGyro = nil
local flyConn = nil

local function clearConns()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
end

-- Noclip used to add a fresh Stepped connection every time the toggle was
-- switched on, so on/off/on left two loops writing every part each frame and
-- the final "off" only cleared the last one. One connection, created once,
-- reading the toggle: flipping it now means flipping a boolean.
local noclipConn = nil
local function ensure_noclip_conn()
    if noclipConn then return end
    noclipConn = RunService.Stepped:Connect(function()
        if not Move.noclip then return end
        local c = Net.Player.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
        end
    end)
end

local function humanoid()
    return Net.humanoid()
end

function Move.apply_speed()
    local hum = humanoid()
    if not hum then return end
    hum.WalkSpeed = Move.speed and Move.speed_value or Move.base_walk
end

function Move.apply_jump()
    local hum = humanoid()
    if not hum then return end
    hum.JumpPower = Move.jump and Move.jump_value or Move.base_jump
    hum.UseJumpPower = true
end

-- Noclip: flip CanCollide on every body part each frame. It is the classic
-- approach and the least destructive one - no part is deleted, nothing is
-- reparented, so turning it off restores the character exactly.
function Move.set_noclip(state)
    Move.noclip = state
    if not state then
        local char = Net.Player.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
            end
        end
        return
    end
    if not Net.Player.Character then return end
    ensure_noclip_conn()
end

-- Fly: a BodyVelocity towards the camera's look vector plus a BodyGyro to hold
-- the character upright. Velocity, not CFrame, so the server sees ordinary
-- movement and the player can be shot at normally.
function Move.set_fly(state)
    Move.fly = state
    local char = Net.Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
    if flyBody then pcall(function() flyBody:Destroy() end); flyBody = nil end
    if flyGyro then pcall(function() flyGyro:Destroy() end); flyGyro = nil end
    if not state or not root then return end

    flyBody = Instance.new("BodyVelocity")
    flyBody.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBody.Velocity = Vector3.zero
    flyBody.Parent = root

    flyGyro = Instance.new("BodyGyro")
    flyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyGyro.P = 1000
    flyGyro.Parent = root

    if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
    flyConn = RunService.RenderStepped:Connect(function()
        if not Move.fly then return end
        local c = Net.Player.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not r or not cam or not flyBody then return end
        -- no compound assignment: the shipped bundle is compiled for Lua 5.1,
        -- where `dir += v` is a syntax error
        local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + look end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - look end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - right end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + right end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.yAxis end
        flyBody.Velocity = dir.Magnitude > 0 and dir.Unit * Move.fly_value or Vector3.zero
        flyGyro.CFrame = CFrame.new(Vector3.zero, cam.CFrame.LookVector)
    end)
end

function Move.fly_supported()
    -- fly rides on body movers, which the game's own antigrav areas also use;
    -- if the character has a Humanoid the movers will work.
    return humanoid() ~= nil
end

function Move.reset()
    Move.speed = false
    Move.jump = false
    Move.noclip = false
    Move.fly = false
    clearConns()
    if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
    if flyBody then pcall(function() flyBody:Destroy() end); flyBody = nil end
    if flyGyro then pcall(function() flyGyro:Destroy() end); flyGyro = nil end
    Move.apply_speed()
    Move.apply_jump()
end

-- Re-apply on respawn: the character is replaced, so the old humanoid's values
-- die with it. Everything is idempotent, so calling this twice is harmless.
Net.Player.CharacterAdded:Connect(function()
    task.wait(1)
    if Move.speed then Move.apply_speed() end
    if Move.jump then Move.apply_jump() end
    if Move.fly then Move.set_fly(true) end
    if Move.noclip then Move.set_noclip(true) end
end)

return Move

end
MODULES["features/npc"] = function(require)
-- features/npc.lua
-- The four objectives the game actually checks: Uncle Pete's key, Louise for
-- Detective Beans, Twado's food, and the tree roadblock in front of the Golden
-- Apple. Each one is a single fired remote, so each is a single click.
--
-- Louise and the key need the tool equipped first; the server validates the
-- character's equipped tool, not the backpack.

local Net = require("core/net")
local Items = require("features/items")
local Pet = require("features/pet")
local Game = require("core/game")
local U = require("core/util")

local Npc = {}

-- Obtain, then equip. Items.obtain already waits for the tool to appear, which
-- is what the old version got wrong: it reparented before the tool existed.
local function equip(name)
    if not Items.obtain(name, 1.0) then return false end
    task.wait(0.15)
    return Items.equip(name)
end

function Npc.uncle_pete()
    if not equip("Key") then
        U.notify("Uncle Pete", "no pude equipar la llave")
        return false
    end
    task.wait(0.25)
    return Net.fire("KeyEvent")
end

function Npc.detective()
    if not equip("Louise") then
        U.notify("Detective", "no pude equipar a Louise")
        return false
    end
    task.wait(0.25)
    return Net.fire("LouiseGive", 2)
end

-- Twado is handled by features/pet.lua, which reads both UI sources and can
-- also watch him on its own. This stays as the one-shot step for the NPC tab.
function Npc.twado()
    local ok, why = Pet.try_feed()
    if not ok then U.notify("Twado", tostring(why)) end
    return ok
end

-- FallenTrees holds the road mission props; RoadMissionEvent reads
-- (missionId, hitPart, strength). Firing it 20x per tree is what the old
-- scripts did to clear the road in one frame.
function Npc.clear_road_blocks(passes)
    local fallen = Game.folder("fallenTrees", true)
    if not fallen then
        U.notify("Road", "no hay arboles caidos ahora")
        return 0
    end
    passes = passes or 20
    local fired = 0
    for _, tree in ipairs(fallen:GetChildren()) do
        local hitPart = tree:FindFirstChild("TreeHitPart")
        if hitPart then
            for _ = 1, passes do
                if Net.fire("RoadMissionEvent", 1, hitPart, 5) then fired = fired + 1 end
                task.wait(0.1)
            end
        end
    end
    return fired
end

-- Both NPCs live at fixed spots on the base map. Teleporting is the one thing
-- that shows up in someone else's screen instantly, so it is a button, not a
-- toggle, and it warns first.
Npc.SPOTS = {
    pete   = CFrame.new(-246.653229, 30.4500484, -847.319275),
    louise = CFrame.new(-294.208923, 63.4182587, -737.712036),
    gym    = CFrame.new(-255.521988, 62.7139359, -723.436035),
    kitchen = CFrame.new(-249.753555, 30.4500484, -732.703125),
    apple  = CFrame.new(61.8781624, 29.4499969, -534.381165),
}

function Npc.teleport(key)
    local spot = Npc.SPOTS[key]
    if not spot then return false end
    local root = Net.root()
    if not root then return false end
    root.CFrame = spot + Vector3.new(math.random(-2, 2) * 0.1, 3, math.random(-2, 2) * 0.1)
    return true
end

return Npc

end
MODULES["features/pet"] = function(require)
-- features/pet.lua
-- Twado, the dog. Two jobs: tell you what he wants, and hand it over.
--
-- What he wants is not a constant. The game exposes it in two places depending
-- on how far along you are:
--   * the phone UI: PlayerGui.Phone...DogInfo.TwadoWants.Text (a word)
--   * the note UI:  PlayerGui.Assets.Note.Note.Note, children named
--                   Circle<Item> whose Visible flag marks the wanted food
-- Older scripts read only one of those, so the button did nothing until the
-- player happened to open the right screen. This reads both, every time, and
-- also watches the dog's own billboard for a "!"/"?" state so a request can be
-- detected without the phone being open at all.
--
-- Feeding is a two-step the game validates: GiveTool the food, equip it, then
-- CatFed with the item name. Giving the wrong food costs 10 energy, so the
-- thing is read first, never guessed.

local Net = require("core/net")
local Items = require("features/items")
local U = require("core/util")

local Pet = {}

Pet.auto = false            -- watch and feed on its own
Pet.watch_interval = 2.0
Pet.max_attempts = 3        -- per request, then it stops and asks for attention
Pet.attempts = 0
Pet.last_fed = nil
Pet.last_want = nil
Pet.fed_total = 0
Pet.status = "sin pedir nada"

local function pg()
    return Net.Player and Net.Player:FindFirstChild("PlayerGui")
end

-- "Bloxy Cola" -> "BloxyCola"; the remote wants the tool name.
local function normalize(text)
    if type(text) ~= "string" then return nil end
    local clean = text:gsub("%s+", "")
    if clean == "" then return nil end
    return clean
end

-- Every reading of "what does Twado want", most reliable first.
function Pet.wants()
    local out, seen = {}, {}
    local function add(raw)
        local id = normalize(raw)
        if id and not seen[id] then
            seen[id] = true
            table.insert(out, id)
        end
    end

    local gui = pg()
    if not gui then return out end

    -- 1. the phone's dedicated label
    local twado = gui:FindFirstChild("TwadoWants", true)
    if twado and (twado:IsA("TextLabel") or twado:IsA("TextButton")) then
        add(twado.Text)
    end

    -- 2. the note's circle markers
    local assets = gui:FindFirstChild("Assets")
    local holder = assets and assets:FindFirstChild("Note", true)
    if holder then
        for _, v in ipairs(holder:GetDescendants()) do
            if v.Name:match("^Circle") and v.Visible then
                add((v.Name:gsub("Circle", "")))
            end
        end
    end

    return out
end

-- A cheap read of whether the dog is currently asking for anything at all.
-- Twado carries a billboard whose text changes between states; it is not the
-- item name, so it is only used to decide whether to look further.
function Pet.is_asking()
    local gui = pg()
    if gui then
        local twado = gui:FindFirstChild("TwadoWants", true)
        if twado and twado.Visible and normalize(twado.Text) then return true end
    end

    local world = game:GetService("Workspace")
    local dog = world:FindFirstChild("Twado", true)
        or world:FindFirstChild("SmallCat", true)
    if dog then
        local billboard = dog:FindFirstChild("BillboardGui", true)
        if billboard and billboard:IsA("BillboardGui") then
            if billboard.Enabled == false then return false end
            local label = billboard:FindFirstChildWhichIsA("TextLabel", true)
            if label then
                local text = normalize(label.Text)
                if text and text ~= "?" and text ~= "..." then return true end
            end
        end
        -- a bowl or a "wants" part appearing next to the dog means a request
        for _, child in ipairs(dog:GetChildren()) do
            if tostring(child.Name):lower():find("want") then return true end
        end
    end
    return false
end

-- Feed one specific item: give, equip, tell the game.
function Pet.feed(id)
    if not id then return false, "sin comida" end
    if not Items.obtain(id, 1.2) then
        return false, "no pude obtener " .. id
    end
    Items.unequip_all()
    task.wait(0.12)
    if not Items.equip_if_present(id) then
        return false, "no pude equipar " .. id
    end
    task.wait(0.2)
    local ok = Net.fire_wait("CatFed", id)
    if ok then
        Pet.last_fed = id
        Pet.last_want = id
        Pet.fed_total = Pet.fed_total + 1
        Pet.attempts = 0
        Pet.status = "alimentado con " .. id
    end
    return ok, ok and "ok" or "CatFed no respondio"
end

-- Read, then feed. Refusing to guess is deliberate: the wrong food is -10
-- energy, and the dog remembers.
function Pet.try_feed()
    local wants = Pet.wants()
    if #wants == 0 then
        if Pet.is_asking() then
            Pet.status = "pide algo pero la GUI no dice que; abre el telefono"
        else
            Pet.status = "no pide nada ahora"
        end
        return false, Pet.status
    end

    if Pet.attempts >= Pet.max_attempts then
        Pet.status = "me rendi tras " .. Pet.attempts .. " intentos con " .. table.concat(wants, ", ")
        return false, Pet.status
    end

    local tried = {}
    for _, id in ipairs(wants) do
        table.insert(tried, id)
        local ok, why = Pet.feed(id)
        if ok then return true, "alimentado con " .. id end
        U.log("twado: fallo", id, why)
        task.wait(0.25)
    end
    Pet.attempts = Pet.attempts + 1
    Pet.status = "no pude con: " .. table.concat(tried, ", ")
    return false, Pet.status
end

-- The watcher. Polls slowly - this is a once-a-minute event in the game, not a
-- combat loop - and stops itself if the toggle goes off.
function Pet.start()
    Pet.auto = true
    U.loop("twado", Pet.watch_interval, function()
        if not Pet.auto then U.stop("twado"); return end
        if not Pet.is_asking() and #Pet.wants() == 0 then
            Pet.status = "esperando a que pida"
            Pet.attempts = 0
            return
        end
        Pet.try_feed()
    end)
end

function Pet.stop()
    Pet.auto = false
    U.stop("twado")
end

function Pet.summary()
    local wants = Pet.wants()
    if #wants > 0 then
        return "quiere: " .. table.concat(wants, ", ")
    end
    return Pet.status
end

return Pet

end
MODULES["features/roles"] = function(require)
-- features/roles.lua
-- Lobby only. OutsideRole(roleName, flag, flag) unlocks the paid kid roles for
-- the session; the server does not re-check ownership when the round starts.
-- Guarded by a place check so it cannot be fired from the base by accident.

local Net = require("core/net")
local Game = require("core/game")
local U = require("core/util")

local Roles = {}

Roles.list = {
    { label = "Hacker (Phone)", value = "Phone" },
    { label = "Nerd (Book)", value = "Book" },
}

function Roles.unlock(value)
    if Game.where() ~= "lobby" and Game.where() ~= "private" then
        U.notify("Roles", "esto solo funciona en el lobby")
        return false
    end
    -- OutsideRole lives in RemoteEvents, not Events; Net's table covers it, and
    -- fire_wait covers the case where two role buttons are pressed in a row.
    return Net.fire_wait("OutsideRole", value, true, false)
end

function Roles.refresh()
    -- Role pads are TouchInterest parts, but so are hazards: touching every
    -- unnamed "Part" in the workspace would walk the player through the bog.
    -- Only parts whose own name or parent mentions a role are touched.
    if type(firetouchinterest) ~= "function" then return 0 end
    local hrp = Net.root()
    if not hrp then return 0 end
    local n = 0
    for _, v in ipairs(workspace:GetDescendants()) do
        if v:IsA("BasePart") and v:FindFirstChild("TouchInterest") then
            local parentName = v.Parent and v.Parent.Name or ""
            local isRole = v.Name:lower():find("role") or parentName:lower():find("role")
                or v.Name:lower():find("class") or parentName:lower():find("lobby")
            if isRole then
                pcall(function()
                    firetouchinterest(v, hrp, 0)
                    task.wait(0.08)
                    firetouchinterest(v, hrp, 1)
                end)
                n = n + 1
            end
        end
    end
    return n
end

return Roles

end
MODULES["features/shield"] = function(require)
-- features/shield.lua
-- Survival: adding energy out of thin air, and stopping the game from taking it.
--
-- What the game actually does, from the scripts that work against it:
--
--   Events.Energy:FireServer(25, "Pizza")            -- the one BI2 scripts use
--   Events.Energy:FireServer(-amount, false, false)  -- negative SUBTRACTS
--
-- A bare FireServer(999999) does exist, but it is from Break In 1, where the
-- remote lives in ReplicatedStorage.RemoteEvents; that script's other calls
-- (HealPlayer, "Cat") do not exist in BI2. So it is not evidence that BI2
-- accepts an amount on its own, and assuming it was is why the button did
-- nothing. The honest approach is to send the heal the way BI2's own scripts
-- do, and to *check the humanoid*: the client mirrors server health, so either
-- the number went up or the call was ignored. Every shape is tried and the one
-- that moved the bar is cached - and the amount we send is the amount that
-- worked, not a made-up big number.
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

-- The food name is what the BI2 scripts pass; "Pizza" heals 25, "GoldPizza" 75,
-- "GoldenApple" 999. The name and the amount travel together so the server
-- sees a request it recognises, which is the difference between a heal and a
-- silently dropped call.
local function food_for(amount)
    if amount >= 500 then return "GoldenApple" end
    if amount >= 60 then return "GoldPizza" end
    return "Pizza"
end
Shield.food_for = food_for

local ENTRY_POINTS = {
    { label = "amount+food", args = function(amount) return amount, food_for(amount) end },
    { label = "food+amount", args = function(amount) return food_for(amount), amount end },
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

-- When nothing works, this says why in terms the player can act on: it sweeps
-- the argument shapes and a couple of values, records what moved the bar, and
-- leaves the working combination cached. Called from the "por que no sube"
-- button.
function Shield.diagnose()
    local report = {}
    local hp0 = Shield.health()
    if not hp0 then return "sin personaje" end

    local tries = {
        { "25 Pizza", function() return 25, "Pizza" end },
        { "75 GoldPizza", function() return 75, "GoldPizza" end },
        { "999 GoldenApple", function() return 999, "GoldenApple" end },
        { "999999 solo", function() return 999999 end },
        { "25 solo", function() return 25 end },
    }

    for _, entry in ipairs(tries) do
        local before = Shield.health()
        local fired = Net.fire_wait("Energy", entry[2]())
        task.wait(0.35)
        local after = Shield.health()
        local moved = (before and after) and (after - before) or 0
        table.insert(report, string.format("%s -> %s (%+.0f)", entry[1],
            fired and "enviado" or "no enviado", moved))
    end

    local hp1 = Shield.health()
    if hp1 and hp0 and hp1 > hp0 then
        return table.concat(report, "\n") .. "\nalguna forma funciona"
    end
    return table.concat(report, "\n") .. "\nninguna forma movio la barra"
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

end
MODULES["features/train"] = function(require)
-- features/train.lua
-- Strength and Speed, the two stats every objective is gated behind.
--
-- The gym remote is RainbowWhatStat and takes a bare string ("Strength" or
-- "Speed"). The server decides whether the player was actually at a machine, so
-- firing this from across the map is the most visible thing the script does;
-- it is off by default and rate limited to one call per 100 ms per stat.

local Net = require("core/net")
local Game = require("core/game")
local U = require("core/util")

local Train = {}

Train.enabled = false
Train.stats = { Strength = true, Speed = true }
Train.interval = 0.35
Train.target = 5        -- stop at this many pips, 0 = never stop
Train.jitter = true     -- randomise the gap so the timer is not a metronome

local sent = { Strength = 0, Speed = 0 }

function Train.send(stat)
    local ok = Net.fire_wait("RainbowWhatStat", stat)
    if ok then sent[stat] = sent[stat] + 1 end
    return ok
end

function Train.send_all()
    for _, stat in ipairs(Game.STATS) do
        if Train.stats[stat] then Train.send(stat) end
    end
end

function Train.reset()
    sent = { Strength = 0, Speed = 0 }
end

function Train.counter(stat)
    return sent[stat] or 0
end

-- "Burst" is the honest version of an auto-trainer: it fires a fixed number of
-- calls and stops, instead of leaving a loop running for the whole round.
function Train.burst(stat, count)
    count = count or 5
    for i = 1, count do
        if stat == "Both" then
            Train.send_all()
        else
            Train.send(stat)
        end
        task.wait(0.12)
    end
end

function Train.start()
    if U.running("train") then return end
    U.loop("train", Train.interval, function()
        if not Train.enabled then U.stop("train"); return end
        local stats = Game.local_stats()
        for _, stat in ipairs(Game.STATS) do
            if Train.stats[stat] then
                local cur = stats[stat]
                if not (Train.target > 0 and cur and cur >= Train.target) then
                    Train.send(stat)
                end
            end
            if Train.jitter then task.wait(math.random() * 0.05) end
        end
    end)
end

function Train.stop()
    Train.enabled = false
    U.stop("train")
end

-- Sporty's drink doubles gain for ~25 s; firing during the buff window is worth
-- roughly twice as much. Read from the backpack rather than assumed.
function Train.has_boost()
    local bp = Net.Player:FindFirstChild("Backpack")
    if not bp then return false end
    return bp:FindFirstChild("SportsDrink") ~= nil or bp:FindFirstChild("Sports Drink") ~= nil
end

return Train

end
MODULES["features/world"] = function(require)
-- features/world.lua
-- World-side conveniences that are local or one-shot: the cash pickups floating
-- around the base, the mud in the bog, the wind wall, and the fog/colour that
-- makes the boss arena unreadable.
--
-- Deleting parts. `Delete(part)` on the client desyncs that part for this
-- player. It comes back on respawn and does not affect anyone else, but it can
-- make a mission look complete while the server still thinks it is running, so
-- nothing here deletes a mission object - only cosmetic or hazard objects, and
-- only while the toggle is on.

local Net = require("core/net")
local U = require("core/util")

local World = {}

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

World.cash_loop = false
World.anti_mud = false
World.anti_wind = false
World.bright = false

local origProps = nil

-- Cash pickups are invisible parts welded in place with a TouchInterest. The
-- loop touches them one at a time so the server grants each pickup in turn.
function World.collect_cash(maxParts)
    maxParts = maxParts or 60
    local hrp = Net.root()
    if not hrp then return 0 end
    local n = 0
    for _, v in ipairs(Workspace:GetChildren()) do
        if n >= maxParts then break end
        if v.Name == "Part" and v:IsA("BasePart") and v.Transparency >= 1 then
            if v:FindFirstChild("TouchInterest") and v:FindFirstChild("Weld") then
                if type(firetouchinterest) == "function" then
                    pcall(function()
                        firetouchinterest(v, hrp, 0)
                        task.wait(0.02)
                        firetouchinterest(v, hrp, 1)
                    end)
                    n = n + 1
                end
            end
        end
    end
    return n
end

function World.start_cash()
    if U.running("cash") then return end
    U.loop("cash", 1.5, function()
        if not World.cash_loop then U.stop("cash"); return end
        World.collect_cash(40)
    end)
end

function World.stop_cash()
    World.cash_loop = false
    U.stop("cash")
end

-- Mud is a hazard part in BogArea.Bog. CanTouch = false stops the slow without
-- moving or deleting anything, so it fully reverses when toggled off.
function World.set_anti_mud(state)
    World.anti_mud = state
    local bog = Workspace:FindFirstChild("BogArea")
    if not bog then return 0 end
    local n = 0
    for _, v in ipairs(bog:GetDescendants()) do
        if v.Name == "Mud" and v:IsA("BasePart") then
            v.CanTouch = not state
            n = n + 1
        end
    end
    return n
end

-- The wind wall is a single WavePart that pushes the player off the ledge.
function World.set_anti_wind(state)
    World.anti_wind = state
    local wave = Workspace:FindFirstChild("WavePart")
    if not wave then return false end
    wave.CanTouch = not state
    return true
end

-- Boss arenas go dark and red-tinted. Lifting that on the client only changes
-- this player's screen; it is the single biggest quality-of-life win in the
-- Scary Mary fight and the safest thing in the whole script.
function World.set_bright(state)
    World.bright = state
    if state then
        if not origProps then
            origProps = {
                ambient = Lighting.Ambient,
                outdoor = Lighting.OutdoorAmbient,
                brightness = Lighting.Brightness,
                fogEnd = Lighting.FogEnd,
                fogStart = Lighting.FogStart,
                clock = Lighting.ClockTime,
            }
        end
        Lighting.Ambient = Color3.fromRGB(140, 140, 150)
        Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
        Lighting.Brightness = 3
        Lighting.FogEnd = 100000
        Lighting.FogStart = 0
        Lighting.ClockTime = 14
    elseif origProps then
        Lighting.Ambient = origProps.ambient
        Lighting.OutdoorAmbient = origProps.outdoor
        Lighting.Brightness = origProps.brightness
        Lighting.FogEnd = origProps.fogEnd
        Lighting.FogStart = origProps.fogStart
        Lighting.ClockTime = origProps.clock
    end
end

-- Re-applying per frame is what makes brightness survive a boss transition,
-- where the game rewrites Lighting itself. Cheap enough: six assignments.
function World.hold_bright(on)
    if on then
        U.loop("bright", 1, function()
            if not World.bright then U.stop("bright"); return end
            -- reapply only the fields the game rewrites, so origProps stays the
            -- pristine snapshot taken the first time the toggle went on
            Lighting.Brightness = 3
            Lighting.FogEnd = 100000
            Lighting.FogStart = 0
        end)
    else
        U.stop("bright")
    end
end

function World.reset()
    World.stop_cash()
    World.hold_bright(false)
    if World.anti_mud then World.set_anti_mud(false) end
    if World.anti_wind then World.set_anti_wind(false) end
    World.set_bright(false)
end

return World

end
MODULES["main"] = function(require)
-- main.lua — breaker / break in 2
--
-- Entry point, and the last line of defence. Nothing here assumes the menu
-- built: the window, the modules and the automation bridge are three separate
-- things, and each is installed on its own.
--
--   getgenv().breaker          <- the instance (unload, net, loops, modules)
--   getgenv().breaker.run(fn)  <- run a feature function from the console even
--                                 if the UI failed to load
--
-- Every toggle still starts false; loading this never fires a remote.

local function previous_instance()
    local ok, genv = pcall(function() return getgenv() end)
    if not ok or type(genv) ~= "table" then return nil end
    return genv.breaker
end

do
    local previous = previous_instance()
    if type(previous) == "table" then
        pcall(function() previous.unload() end)
    end
end

local U = require("core/util")
local Net = require("core/net")
local Game = require("core/game")
local Menu = require("ui/menu")
local Esp = require("features/esp")

-- remotes first: every feature reports against this table, and a failure here
-- must not stop the UI from coming up
local okResolve, remotes = pcall(Net.resolve)
if not okResolve then
    U.log("resolve failed", tostring(remotes))
    remotes = {}
end

local okMenu, window = pcall(Menu.build)
if not okMenu then
    U.log("menu failed", tostring(window))
    Menu.errors.menu = tostring(window)
    window = nil
end

if window then
    U.notify("breaker " .. U.VERSION .. " cargado",
        string.format("%s | %d remotes | %d ausentes",
            Game.where(), U.count(remotes), #Net.missing))
else
    U.log("breaker cargado sin UI; usa getgenv().breaker.run")
end

if #Net.missing > 0 then
    U.log("remotes ausentes", table.concat(Net.missing, ", "))
end

local function unload()
    U.stop_all()
    Esp.clear()
    if window then pcall(function() window:Unload() end) end
    if getgenv then getgenv().breaker = nil end
end

-- Console escape hatch: getgenv().breaker.run("features/items", "obtain", "Crowbar3")
local function run(moduleName, funcName, ...)
    local okMod, mod = pcall(require, moduleName)
    if not okMod or type(mod) ~= "table" then
        U.log("run: modulo no disponible", moduleName, tostring(mod))
        return false
    end
    local fn = funcName and mod[funcName]
    if type(fn) ~= "function" then
        U.log("run: no existe la funcion", moduleName, tostring(funcName))
        return false
    end
    local ok, result = pcall(fn, ...)
    if not ok then U.log("run: fallo", moduleName, funcName, tostring(result)) end
    return ok, result
end

if getgenv then
    getgenv().breaker = {
        version = U.VERSION,
        unload = unload,
        run = run,
        window = window,
        net = Net,
        menu = Menu,
        errors = Menu.errors,
        loops = function() return U.loop_names() end,
    }
end

U.log("ready", Game.where(), U.count(remotes) .. " remotes",
    next(Menu.errors) and "con fallos" or "sin fallos")

end
MODULES["ui/menu"] = function(require)
-- ui/menu.lua
-- The shell: one guarded require per module, one pcall per tab.
--
-- Before this, a single failing `require` anywhere (Rayfield, a feature module)
-- took the whole chunk down, and one bad callback inside a tab cost the rest of
-- that tab silently. Now:
--   * every require goes through load(), which records what worked. A dead
--     module is logged once and replaced by a stub that answers false to every
--     call, so tabs that mention it still build and their other buttons work.
--   * every tab is built inside a pcall. A tab that throws loses its own card
--     and nothing else; the window, the other tabs and the automation bridge
--     survive, and the failure is listed in the Diagnostics tab.
--   * every callback is wrapped once, at the point where the widget is created,
--     so an error inside one button cannot propagate into the UI's event loop.

local U = require("core/util")

local Menu = {}

-- Loaded modules land here; failures land in Menu.errors as name -> message.
local M = {}
Menu.modules = M
Menu.errors = {}
Menu.ok = {}
-- Element handles that tabs publish for the HUD loop (text lines, stats).
Menu.elements = {}
-- Errors caught inside a wrapped callback. They are swallowed by design (one
-- bad button must not stop the UI), so they are counted and published here;
-- the build gate asserts this stays at zero after firing everything.
Menu.callback_errors = 0
Menu.on_callback_error = nil

local function stub(name)
    return setmetatable({}, {
        __index = function(_, key)
            return function() return false, "module " .. name .. " no cargo" end
        end,
        __call = function() return false, "module " .. name .. " no cargo" end,
    })
end

local function load(name)
    local ok, result = pcall(require, name)
    if ok and type(result) == "table" then
        M[name] = result
        table.insert(Menu.ok, name)
        return result
    end
    local message = ok and ("devolvio " .. type(result)) or tostring(result)
    Menu.errors[name] = message
    M[name] = stub(name)
    U.log("module failed", name, message)
    return M[name]
end

-- The order matters: core first, because everything else reports through it.
local CORE = { "core/util", "core/net", "core/game" }
local FEATURES = {
    "features/train", "features/items", "features/combat", "features/npc",
    "features/move", "features/world", "features/esp", "features/roles",
    "features/pet", "features/shield",
}

-- Tab modules, in the order the rail shows them.
local TABS = {
    "ui/tabs/home", "ui/tabs/training", "ui/tabs/items", "ui/tabs/npcs",
    "ui/tabs/twado", "ui/tabs/combat", "ui/tabs/move", "ui/tabs/world",
    "ui/tabs/enemies", "ui/tabs/roles", "ui/tabs/safety",
}

local function wrap_callbacks(object, label)
    -- Rayfield takes callbacks inside the props table, so wrapping happens on
    -- the way in rather than on the element afterwards.
    if type(object) ~= "table" then return object end
    for key, value in pairs(object) do
        if type(value) == "function" and (key == "callback" or key == "Callback") then
            object[key] = function(...)
                local ok, err = pcall(value, ...)
                if not ok then
                    Menu.callback_errors = Menu.callback_errors + 1
                    U.log("callback failed", label, tostring(err))
                    U.notify("error en " .. tostring(label), tostring(err))
                    if Menu.on_callback_error then
                        pcall(Menu.on_callback_error, label, tostring(err))
                    end
                end
            end
        elseif type(value) == "table" then
            wrap_callbacks(value, label)
        end
    end
    return object
end

-- A tab handle whose element factories wrap callbacks before Rayfield sees them.
local function guarded_tab(tab, label)
    if not tab then return nil end
    local proxy = {}
    local function make(method)
        return function(_, props)
            wrap_callbacks(props, label)
            local ok, element = pcall(tab[method], tab, props)
            if not ok then
                U.log("element failed", label, method, tostring(element))
                return setmetatable({}, { __index = function() return function() end end })
            end
            return element
        end
    end
    for _, method in ipairs({ "CreateToggle", "CreateSlider", "CreateDropdown", "CreateButton",
                              "CreateInput", "CreateKeybind", "CreateColorPicker", "CreateStat",
                              "CreateText", "CreateSection", "CreateGroup", "CreateDivider",
                              "CreateProgress", "CreateConsole" }) do
        proxy[method] = make(method)
    end
    proxy.raw = tab
    return proxy
end

local function guarded_window(window)
    local proxy = {}
    local function make_tab(_, props)
        wrap_callbacks(props, props and props.name or "?")
        local ok, tab = pcall(window.CreateTab, window, props)
        if not ok then
            U.log("tab failed", tostring(props and props.name), tostring(tab))
            Menu.errors["tab:" .. tostring(props and props.name)] = tostring(tab)
            return guarded_tab(nil, "?")
        end
        return guarded_tab(tab, props and props.name or "?")
    end
    proxy.CreateTab = make_tab
    proxy.CreateSection = function(_, props) return window:CreateSection(props) end
    proxy.CreateTag = function(_, props) return window:CreateTag(props) end
    proxy.Notify = function(_, props) return window:Notify(props) end
    proxy.Toast = function(_, props) return window:Toast(props) end
    proxy.Unload = function() return window:Unload() end
    proxy.Get = function(_, flag) return window:Get(flag) end
    proxy.Set = function(_, flag, value) return window:Set(flag, value) end
    proxy.raw = window
    return proxy
end

function Menu.build()
    for _, name in ipairs(CORE) do load(name) end

    local Rayfield = load("ui/rayfield")
    local window = nil

    if Rayfield and type(Rayfield.CreateWindow) == "function" then
        local ok, created = pcall(function()
            return Rayfield:CreateWindow({
                name = "breaker / break in 2",
                subtitle = "nada dispara hasta que lo enciendas",
                sidebarLayout = true,
                profile = "build " .. tostring(U.VERSION),
                theme = "cobalt",
                configuration = {
                    autoSave = true,
                    autoLoad = true,
                    fileName = "breaker_bi2",
                    customFolder = "breaker",
                },
            })
        end)
        if ok then
            window = created
        else
            Menu.errors["window"] = tostring(created)
            U.log("window failed", tostring(created))
        end
    else
        Menu.errors["ui/rayfield"] = Menu.errors["ui/rayfield"] or "no disponible"
    end

    U.window = window
    U.flush()

    if not window then
        -- No UI: the features are still reachable through the automation
        -- bridge, and the failure is reported rather than swallowed.
        U.log("sin ventana; queda el bridge de automatizacion")
        return nil, Menu.errors
    end

    for _, name in ipairs(FEATURES) do load(name) end
    for _, name in ipairs(TABS) do load(name) end

    local ctx = {
        window = guarded_window(window),
        U = M["core/util"], Net = M["core/net"], Game = M["core/game"],
        Train = M["features/train"], Items = M["features/items"],
        Combat = M["features/combat"], Npc = M["features/npc"],
        Move = M["features/move"], World = M["features/world"],
        Esp = M["features/esp"], Roles = M["features/roles"],
        Pet = M["features/pet"], Shield = M["features/shield"],
        Menu = Menu,
        elements = Menu.elements,
    }
    Menu.ctx = ctx

    -- each tab gets its own pcall: one broken tab costs one tab
    for _, name in ipairs(TABS) do
        local mod = M[name]
        local label = name:gsub("ui/tabs/", "")
        local ok, err = pcall(mod.build, ctx)
        if not ok then
            Menu.errors[label] = tostring(err)
            U.log("tab failed", label, tostring(err))
        end
    end

    -- the diagnostics tab is built last, so it can list every failure above
    local okDiag, Diagnostics = pcall(require, "ui/tabs/diagnostics")
    if okDiag and type(Diagnostics) == "table" then
        local ok, err = pcall(Diagnostics.build, ctx)
        if not ok then U.log("diagnostics tab failed", tostring(err)) end
    end

    Menu.hud(ctx)
    return window, Menu.errors
end

-- The HUD loop lives here because it touches elements from several tabs. Each
-- line is guarded on its own: a tab that never built simply has no element to
-- refresh.
function Menu.hud(ctx)
    local U_ = M["core/util"]
    if not U_ then return end
    U_.loop("hud", 1, function()
        local Esp = M["features/esp"]
        local Game = M["core/game"]
        local Net = M["core/net"]
        local Shield = M["features/shield"]
        local Pet = M["features/pet"]
        local els = Menu.elements or {}

        if els.placeLine and Game then pcall(function() els.placeLine:Set(Game.where()) end) end
        if Esp then
            local ok, list = pcall(Esp.read)
            if ok and els.enemyStat then pcall(function() els.enemyStat:Set(#list) end) end
            if ok and els.enemyLine then pcall(function() els.enemyLine:Set(Esp.summary(list)) end) end
            if ok and els.espLine then pcall(function() els.espLine:Set(Esp.summary(list)) end) end
            if ok and Esp.enabled then pcall(Esp.apply, list) end
        end
        if els.remoteStat and Net then pcall(function() els.remoteStat:Set(U_.count(Net.remotes)) end) end
        if els.petLine and Pet then pcall(function() els.petLine:Set(Pet.summary()) end) end
        if els.hpLine and Shield then
            pcall(function()
                local hp, max = Shield.health()
                els.hpLine:Set(hp and string.format("%.0f / %.0f", hp, max) or "sin personaje")
            end)
        end
        if els.godLine and Shield then pcall(function() els.godLine:Set(Shield.status()) end) end
    end)
end

return Menu

end
MODULES["ui/rayfield"] = function(require)
-- ui/rayfield.lua
-- Rayfield Gen2 loader, kept in one place so the loader line, the fallback and
-- the notice all live together.
--
-- Gen2 draws its whole interface in code: no asset id to fingerprint, no model
-- to fetch. Users still report the library name in the console if the executor
-- logs HttpGet, which is why the main script can be wrapped (see build/README).

local U = require("core/util")

local RAYFIELD_GEN2 = "https://sirius.menu/gen2"

local Rayfield

local ok, result = pcall(function()
    return loadstring(game:HttpGet(RAYFIELD_GEN2))()
end)

if ok and type(result) == "table" and type(result.CreateWindow) == "function" then
    Rayfield = result
else
    -- A missing UI library must not mean a half-initialised cheat. The feature
    -- modules are independent of the menu, so the script reports and stops
    -- instead of running blind.
    -- warn is present in Roblox but not in every harness this is tested with;
    -- U.log always works, so the message never gets lost to a missing global
    pcall(function() warn("[breaker] Rayfield Gen2 no cargo: " .. tostring(result)) end)
    U.log("rayfield load failed", tostring(result))
    -- do not error: main still installs the Automation bridge and the menu shows
    -- a failure card. One broken dependency must not take the script with it.
    return nil
end

if Rayfield then
    Rayfield.version = "gen2"
    Rayfield.source = RAYFIELD_GEN2
end

return Rayfield

end
MODULES["ui/tabs/combat"] = function(require)
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

end
MODULES["ui/tabs/diagnostics"] = function(require)
-- ui/tabs/diagnostics.lua
-- Last tab, built after every other one, so it can report what failed.
--
-- This exists because "a feature died" used to be invisible: the tab silently
-- lost half its buttons and the console was the only place that knew. Here it
-- is a card with the module list, the failures, and the remote table.

local Tab = {}

function Tab.build(ctx)
    local Menu = ctx.Menu
    local Net = ctx.Net
    local Shield = ctx.Shield
    local U = ctx.U
    local window = ctx.window


    local tab = window:CreateTab({ name = "Diagnostico" })

    tab:CreateText({
        name = "arquitectura",
        text = "cada modulo se carga aparte y cada pestaña se construye en su propio pcall. " ..
               "si algo falla pierdes esa parte y nada mas.",
    })

    local stateLine = tab:CreateText({ name = "estado", text = "calculando..." })

    local function error_count()
        local n = 0
        for _ in pairs(Menu.errors) do n = n + 1 end
        return n
    end

    local function errors_text()
        local lines, count = {}, 0
        for name, message in pairs(Menu.errors) do
            count = count + 1
            table.insert(lines, name .. ": " .. tostring(message))
        end
        table.sort(lines)
        if count == 0 then return "sin fallos: todos los modulos cargaron" end
        return #lines .. " fallo(s)\n" .. table.concat(lines, "\n")
    end

    local failures = tab:CreateText({ name = "fallos", text = errors_text() })

    tab:CreateButton({
        name = "recalcular",
        callback = function()
            U.log("diagnose", tostring(Menu.errors))
            stateLine:Set(string.format("%d modulos ok, %d fallos, %d elementos vivos",
                #Menu.ok, error_count(), U.count(Menu.elements)))
            failures:Set(errors_text())
        end,
    })

    tab:CreateButton({
        name = "remotes resueltos",
        callback = function()
            local lines = {}
            for name, remote in pairs(Net.remotes) do
                table.insert(lines, name .. (remote and " ok" or " nil"))
            end
            table.sort(lines)
            window:Notify({
                title = "remotes (" .. #lines .. ")",
                content = #lines > 0 and table.concat(lines, ", ") or "ninguno",
                duration = 8,
            })
        end,
    })

    tab:CreateButton({
        name = "remotes ausentes",
        callback = function()
            window:Notify({
                title = "ausentes (" .. #Net.missing .. ")",
                content = #Net.missing > 0 and table.concat(Net.missing, ", ") or "ninguno",
                duration = 8,
            })
        end,
    })

    tab:CreateButton({
        name = "semi godmode / hook",
        callback = function()
            local supported = Shield.hook_supported()
            window:Notify({
                title = "hook " .. (supported and "disponible" or "NO disponible"),
                content = Shield.status() .. " | " .. (supported and
                    "hookmetamethod presente" or "tu executor no lo expone: queda el top-up"),
                duration = 8,
            })
        end,
    })

    tab:CreateButton({
        name = "probar energy (diagnostico)",
        callback = function()
            window:Notify({ title = "probando Energy", content = "5 formas, ~3 s", duration = 3 })
            local report = Shield.diagnose()
            U.log("energy diagnose -> " .. tostring(report))
            window:Notify({ title = "resultado", content = tostring(report), duration = 12 })
        end,
    })

    tab:CreateButton({
        name = "volcar al log",
        callback = function()
            U.log("modulos ok", table.concat(Menu.ok, ", "))
            for name, message in pairs(Menu.errors) do U.log("fallo", name, message) end
        end,
    })

    -- one pass now, so the card is populated before anyone clicks
    stateLine:Set(string.format("%d modulos ok, %d fallos", #Menu.ok, error_count()))

    ctx.elements.diagState = stateLine
    ctx.elements.diagFailures = failures
    return nil
end

return Tab

end
MODULES["ui/tabs/enemies"] = function(require)
-- ui/tabs/enemies.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Esp = ctx.Esp
    local window = ctx.window


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
    -- handles the HUD refreshes; missing ones are simply skipped
    ctx.elements.espLine = espLine
    return nil
end

return Tab

end
MODULES["ui/tabs/home"] = function(require)
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

end
MODULES["ui/tabs/items"] = function(require)
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

end
MODULES["ui/tabs/move"] = function(require)
-- ui/tabs/move.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Move = ctx.Move
    local window = ctx.window


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
    return nil
end

return Tab

end
MODULES["ui/tabs/npcs"] = function(require)
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

end
MODULES["ui/tabs/roles"] = function(require)
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

end
MODULES["ui/tabs/safety"] = function(require)
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

end
MODULES["ui/tabs/training"] = function(require)
-- ui/tabs/training.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local Train = ctx.Train
    local Game = ctx.Game
    local window = ctx.window


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
    return nil
end

return Tab

end
MODULES["ui/tabs/twado"] = function(require)
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

end
MODULES["ui/tabs/world"] = function(require)
-- ui/tabs/world.lua
-- Tab builder. Every tab is wrapped in a pcall by ui/menu, so a module
-- that fails here costs its own tab and nothing else.

local Tab = {}

function Tab.build(ctx)
    local World = ctx.World
    local window = ctx.window


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
    return nil
end

return Tab

end

require("main")
