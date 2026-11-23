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
