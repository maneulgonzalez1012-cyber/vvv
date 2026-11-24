-- main.lua — breaker / break in 2
--
-- Entry point, and the last line of defence. Nothing here assumes the menu
-- built: the window, the modules and the automation bridge are three separate
-- things, and each is installed on its own.
--
--   getgenv().breaker          <- the instance (unload, net, loops, modules)
--   getgenv().breaker.run(fn)  <- run a feature function from the console even
--                                 if the UI failed to load
--
-- Every toggle still starts false; loading this never fires a remote.

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

-- remotes first: every feature reports against this table, and a failure here
-- must not stop the UI from coming up
local okResolve, remotes = pcall(Net.resolve)
if not okResolve then
    U.log("resolve failed", tostring(remotes))
    remotes = {}
end

local okMenu, window = pcall(Menu.build)
if not okMenu then
    U.log("menu failed", tostring(window))
    Menu.errors.menu = tostring(window)
    window = nil
end

if window then
    U.notify("breaker " .. U.VERSION .. " cargado",
        string.format("%s | %d remotes | %d ausentes",
            Game.where(), U.count(remotes), #Net.missing))
else
    U.log("breaker cargado sin UI; usa getgenv().breaker.run")
end

if #Net.missing > 0 then
    U.log("remotes ausentes", table.concat(Net.missing, ", "))
end

local function unload()
    U.stop_all()
    Esp.clear()
    if window then pcall(function() window:Unload() end) end
    if getgenv then getgenv().breaker = nil end
end

-- Console escape hatch: getgenv().breaker.run("features/items", "obtain", "Crowbar3")
local function run(moduleName, funcName, ...)
    local okMod, mod = pcall(require, moduleName)
    if not okMod or type(mod) ~= "table" then
        U.log("run: modulo no disponible", moduleName, tostring(mod))
        return false
    end
    local fn = funcName and mod[funcName]
    if type(fn) ~= "function" then
        U.log("run: no existe la funcion", moduleName, tostring(funcName))
        return false
    end
    local ok, result = pcall(fn, ...)
    if not ok then U.log("run: fallo", moduleName, funcName, tostring(result)) end
    return ok, result
end

if getgenv then
    getgenv().breaker = {
        version = U.VERSION,
        unload = unload,
        run = run,
        window = window,
        net = Net,
        menu = Menu,
        errors = Menu.errors,
        loops = function() return U.loop_names() end,
    }
end

U.log("ready", Game.where(), U.count(remotes) .. " remotes",
    next(Menu.errors) and "con fallos" or "sin fallos")
