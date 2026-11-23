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
