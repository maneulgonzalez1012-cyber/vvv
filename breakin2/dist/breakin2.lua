-- breaker / break in 2 - bundle
-- built from 14 modules; regenerate with build/pack.py

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
    for containerName, names in pairs(KNOWN) do
        local box = Net.container(containerName)
        if not box then
            for _, n in ipairs(names) do table.insert(Net.missing, containerName .. "." .. n) end
            continue
        end
        for _, n in ipairs(names) do
            local r = waitChild(box, n, 2)
            if r and (r:IsA("RemoteEvent") or r:IsA("RemoteFunction") or r:IsA("UnreliableRemoteEvent")) then
                Net.remotes[n] = r
            else
                table.insert(Net.missing, containerName .. "." .. n)
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
    GiveTool = 0.15,
    Vending = 0.15,
    HealTheNoobs = 0.50,
    RoadMissionEvent = 0.15,
}
local GAP_DEFAULT = 0.10

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
            if not (Combat.skip_boss and e.name:match("Boss")) then
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
            if not (Combat.skip_boss and e.name:match("Boss")) and in_range(e) then
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

local function make_highlight(inst)
    local h = highlights[inst]
    if h and h.Parent then return h end
    local ok, created = pcall(function()
        local hi = Instance.new("Highlight")
        hi.FillColor = Esp.color
        hi.FillTransparency = 0.65
        hi.OutlineColor = Esp.color
        hi.OutlineTransparency = 0
        hi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hi.Adornee = inst
        hi.Parent = game:GetService("CoreGui")
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
        if Esp.show_distance and e.dist then piece ..= (" " .. e.dist .. "m") end
        if Esp.show_health and e.hp then piece ..= (" " .. math.floor(e.hp) .. "hp") end
        table.insert(parts, piece)
    end
    if #parts == 0 then return "sin enemigos" end
    return table.concat(parts, "  |  ")
end

return Esp

end
MODULES["features/items"] = function(require)
-- features/items.lua
-- Item spawning through the game's own remotes.
--
-- GiveTool takes a single string with no spaces ("GoldenApple", "GoldPizza").
-- Weapons and armour go through Vending instead:
--   Vending:FireServer(3, toolName, category, playerName, 1)
-- Both paths are client-trusted, so the server spawns whatever is asked for.
-- Everything here is a single click: no loop, no auto-equip.

local Net = require("core/net")
local U = require("core/util")

local Items = {}

-- Names verified in the live game; the menu shows these exact labels.
Items.food = {
    "GoldenApple", "GoldPizza", "RainbowPizza", "Pizza", "Cookie", "Chips",
    "Water", "Soda", "MedKit",
}
Items.weapons = {
    "Crowbar1", "Crowbar2", "Crowbar3", "Bat", "Wrench", "Pitchfork", "Hammer", "Broom",
}
Items.armour = { "Armor2" }
Items.misc = { "Key", "Louise", "Phone", "Book" }

local function strip(s)
    return (tostring(s):gsub("%s+", ""))
end

function Items.give(tool)
    return Net.fire("GiveTool", strip(tool))
end

function Items.buy(tool, category)
    local cat = category or "Weapons"
    local name = Net.Player and Net.Player.Name or tostring(Net.Player)
    return Net.fire("Vending", 3, strip(tool), cat, name, 1)
end

function Items.armour_on()
    return Net.fire("Vending", 3, "Armor2", "Armor", tostring(Net.Player), 1)
end

-- Give a stack of one item, spaced so the server does not drop duplicates.
function Items.stack(tool, count)
    count = count or 5
    local ok = 0
    for _ = 1, count do
        if Items.give(tool) then ok = ok + 1 end
        task.wait(0.15)
    end
    return ok
end

function Items.equip(name)
    local char = Net.Player.Character
    local bp = Net.Player:FindFirstChild("Backpack")
    if not char or not bp then return false end
    local tool = bp:FindFirstChild(name)
    if tool and tool:IsA("Tool") then
        tool.Parent = char
        return true
    end
    return false
end

function Items.unequip_all()
    local char = Net.Player.Character
    local bp = Net.Player:FindFirstChild("Backpack")
    if not char or not bp then return false end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then t.Parent = bp end
    end
    return true
end

-- Heals every player. The remote only trusts the server's view of who is
-- holding a Golden Apple, so the tool is given, equipped, and swapped in first.
function Items.heal_all()
    Items.unequip_all()
    task.wait(0.15)
    if not Items.give("GoldenApple") then
        U.notify("Heal all", "GiveTool no respondio")
        return false
    end
    task.wait(0.35)
    Items.equip("GoldenApple")
    task.wait(0.35)
    local ok = Net.fire("HealTheNoobs")
    task.wait(0.35)
    Items.unequip_all()
    return ok
end

function Items.heal_self()
    if not Items.give("Pizza") then return false end
    task.wait(0.2)
    return Net.fire("Energy", 25, "Pizza")
end

-- The game tracks which foods Twado wants as GUI circles in Assets.Note; those
-- names map straight onto GiveTool arguments.
function Items.dog_wants()
    local out = {}
    local pg = Net.Player:FindFirstChild("PlayerGui")
    local note = pg and pg:FindFirstChild("Assets")
    if not note then return out end
    local holder = note:FindFirstChild("Note", true)
    if not holder then return out end
    for _, v in ipairs(holder:GetDescendants()) do
        if v.Name:match("^Circle") and v:IsA("GuiObject") and v.Visible then
            table.insert(out, (v.Name:gsub("Circle", "")))
        end
    end
    return out
end

function Items.feed_dog(want)
    if not Items.give(want) then return false end
    task.wait(0.15)
    Items.equip(want)
    task.wait(0.25)
    return Net.fire("CatFed", want)
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

local function addConn(c)
    table.insert(conns, c)
end

local function clearConns()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
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
    local char = Net.Player.Character
    if not char then return end
    addConn(RunService.Stepped:Connect(function()
        if not Move.noclip then return end
        local c = Net.Player.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end))
end

-- Fly: a BodyVelocity towards the camera's look vector plus a BodyGyro to hold
-- the character upright. Velocity, not CFrame, so the server sees ordinary
-- movement and the player can be shot at normally.
function Move.set_fly(state)
    Move.fly = state
    local char = Net.Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
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

    addConn(RunService.RenderStepped:Connect(function()
        if not Move.fly then return end
        local c = Net.Player.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not r or not cam or not flyBody then return end
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
        flyBody.Velocity = dir.Magnitude > 0 and dir.Unit * Move.fly_value or Vector3.zero
        flyGyro.CFrame = CFrame.new(Vector3.zero, cam.CFrame.LookVector)
    end))
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
local Game = require("core/game")
local U = require("core/util")

local Npc = {}

local function equip(name)
    if not Items.give(name) then return false end
    task.wait(0.2)
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

-- Twado wants one of a rotating set of foods; the GUI circles say which.
-- Asking the game beats guessing, so the wanted item is read first and the
-- first match is fed.
function Npc.twado()
    local wants = Items.dog_wants()
    if #wants == 0 then
        U.notify("Twado", "no hay comida marcada todavia")
        return false
    end
    for _, want in ipairs(wants) do
        if Items.feed_dog(want) then return true end
        task.wait(0.2)
    end
    return false
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
    local remote = Net.get("OutsideRole")
    if not remote then
        -- OutsideRole lives in RemoteEvents, not Events; Net.KNOWN covers it
        return false
    end
    return Net.fire("OutsideRole", value, true, false)
end

function Roles.refresh()
    -- role buttons in the lobby are TouchInterest parts named Part
    if type(firetouchinterest) ~= "function" then return 0 end
    local hrp = Net.root()
    if not hrp then return 0 end
    local n = 0
    for _, v in ipairs(workspace:GetChildren()) do
        if v.Name == "Part" and v:FindFirstChild("TouchInterest") then
            pcall(function()
                firetouchinterest(v, hrp, 0)
                task.wait(0.05)
                firetouchinterest(v, hrp, 1)
            end)
            n = n + 1
        end
    end
    return n
end

return Roles

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
    local ok = Net.fire("RainbowWhatStat", stat)
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
-- Single entry point. Build order matters:
--   1. net.resolve()     so a feature can report a missing remote on load
--   2. menu.build()      so every notification after this point is visible
--   3. nothing else runs on load. Every toggle starts false.
--
-- Each module is a plain table; there is no global leak beyond `getgenv().breaker`,
-- which exists so re-executing the script tears the previous instance down.

-- prevent double-execution: unload the previous window and stop its loops.
-- getgenv is wrapped in a function because the gate runs this body at chunk
-- scope, where getgenv exists but its result does not have to.
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

local remotes = Net.resolve()

local window = Menu.build()

U.notify("breaker cargado",
    string.format("%s | %d remotes | %d ausentes",
        Game.where(), U.count(remotes), #Net.missing))

if #Net.missing > 0 then
    U.notify("remotes ausentes",
        "el juego cambio algo: " .. table.concat(Net.missing, ", "))
end

local function unload()
    U.stop_all()
    Esp.clear()
    pcall(function() window:Unload() end)
    if getgenv then getgenv().breaker = nil end
end

if getgenv then
    getgenv().breaker = {
        version = "1.0.0",
        unload = unload,
        window = window,
        net = Net,
        loops = U.loop_names,
    }
end

U.log("ready", Game.where(), U.count(remotes) .. " remotes")

end
MODULES["ui/menu"] = function(require)
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
        description = "RainbowWhatStat cada 350 ms. el server decide si vale",
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
    local itemsTab = window:CreateTab({ name = "Items" })
    itemsTab:CreateSection({ name = "comida (GiveTool)" })

    itemsTab:CreateDropdown({
        name = "comida",
        flag = "item_food",
        options = Items.food,
        value = "GoldenApple",
        callback = function(sel) Menu.picked_food = sel end,
    })
    itemsTab:CreateButton({
        name = "dar comida",
        callback = function() Items.give(Menu.picked_food or "GoldenApple") end,
    })
    itemsTab:CreateButton({
        name = "x10 comida",
        callback = function()
            Items.stack(Menu.picked_food or "GoldenApple", 10)
            window:Notify({ title = "items", content = "10x " .. (Menu.picked_food or "GoldenApple") })
        end,
    })

    itemsTab:CreateSection({ name = "armas (Vending)" })
    itemsTab:CreateDropdown({
        name = "arma",
        flag = "item_weapon",
        options = Items.weapons,
        value = "Crowbar3",
        callback = function(sel) Menu.picked_weapon = sel end,
    })
    itemsTab:CreateButton({
        name = "comprar arma",
        callback = function() Items.buy(Menu.picked_weapon or "Crowbar3", "Weapons") end,
    })
    itemsTab:CreateButton({
        name = "armadura",
        callback = function() Items.armour_on() end,
    })

    itemsTab:CreateSection({ name = "curas" })
    itemsTab:CreateButton({
        name = "curar(me)",
        callback = function() Items.heal_self() end,
    })
    itemsTab:CreateButton({
        name = "curar a todos",
        description = "golden apple + HealTheNoobs",
        callback = function() Items.heal_all() end,
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
    error("[breaker] UI no disponible; abortando sin tocar el juego", 0)
end

Rayfield.version = "gen2"
Rayfield.source = RAYFIELD_GEN2

return Rayfield

end

require("main")
