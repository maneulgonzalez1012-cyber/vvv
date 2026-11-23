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
