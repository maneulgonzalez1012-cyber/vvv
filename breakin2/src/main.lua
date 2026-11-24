-- main.lua — breaker / break in 2
--
-- Single entry point. Build order matters:
--   1. net.resolve()     so a feature can report a missing remote on load
--   2. menu.build()      so every notification after this point is visible
--   3. nothing else runs on load. Every toggle starts false.
--
-- Each module is a plain table; there is no global leak beyond `getgenv().breaker`,
-- which exists so re-executing the script tears the previous instance down.

-- prevent double-execution: unload the previous window and stop its loops.
-- getgenv is wrapped in a function because the gate runs this body at chunk
-- scope, where getgenv exists but its result does not have to.
local function previous_instance()
    local ok, genv = pcall(function() return getgenv() end)
    if not ok or type(genv) ~= "table" then return nil end
    return genv.breaker
end

do
    local previous = previous_instance()
    if type(previous) == "table" then
        pcall(function() previous.unload() end)
    end
end

local U = require("core/util")
local Net = require("core/net")
local Game = require("core/game")
local Menu = require("ui/menu")
local Esp = require("features/esp")

local remotes = Net.resolve()

local window = Menu.build()

U.notify("breaker " .. U.VERSION .. " cargado",
    string.format("%s | %d remotes | %d ausentes",
        Game.where(), U.count(remotes), #Net.missing))

if #Net.missing > 0 then
    U.notify("remotes ausentes",
        "el juego cambio algo: " .. table.concat(Net.missing, ", "))
end

local function unload()
    U.stop_all()
    Esp.clear()
    pcall(function() window:Unload() end)
    if getgenv then getgenv().breaker = nil end
end

if getgenv then
    getgenv().breaker = {
        version = "1.0.0",
        unload = unload,
        window = window,
        net = Net,
        loops = U.loop_names,
    }
end

U.log("ready", Game.where(), U.count(remotes) .. " remotes")
