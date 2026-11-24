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
