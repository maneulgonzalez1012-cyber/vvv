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
