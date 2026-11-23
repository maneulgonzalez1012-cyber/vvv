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
        if Esp.show_distance and e.dist then piece ..= (" " .. e.dist .. "m") end
        if Esp.show_health and e.hp then piece ..= (" " .. math.floor(e.hp) .. "hp") end
        table.insert(parts, piece)
    end
    if #parts == 0 then return "sin enemigos" end
    return table.concat(parts, "  |  ")
end

return Esp
