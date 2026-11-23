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
