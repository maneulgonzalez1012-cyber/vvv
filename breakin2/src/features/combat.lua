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
