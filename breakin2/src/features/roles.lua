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
