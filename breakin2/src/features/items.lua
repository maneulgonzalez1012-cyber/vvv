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
