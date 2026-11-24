-- ui/menu.lua
-- The shell: one guarded require per module, one pcall per tab.
--
-- Before this, a single failing `require` anywhere (Rayfield, a feature module)
-- took the whole chunk down, and one bad callback inside a tab cost the rest of
-- that tab silently. Now:
--   * every require goes through load(), which records what worked. A dead
--     module is logged once and replaced by a stub that answers false to every
--     call, so tabs that mention it still build and their other buttons work.
--   * every tab is built inside a pcall. A tab that throws loses its own card
--     and nothing else; the window, the other tabs and the automation bridge
--     survive, and the failure is listed in the Diagnostics tab.
--   * every callback is wrapped once, at the point where the widget is created,
--     so an error inside one button cannot propagate into the UI's event loop.

local U = require("core/util")

local Menu = {}

-- Loaded modules land here; failures land in Menu.errors as name -> message.
local M = {}
Menu.modules = M
Menu.errors = {}
Menu.ok = {}
-- Element handles that tabs publish for the HUD loop (text lines, stats).
Menu.elements = {}
-- Errors caught inside a wrapped callback. They are swallowed by design (one
-- bad button must not stop the UI), so they are counted and published here;
-- the build gate asserts this stays at zero after firing everything.
Menu.callback_errors = 0
Menu.on_callback_error = nil

local function stub(name)
    return setmetatable({}, {
        __index = function(_, key)
            return function() return false, "module " .. name .. " no cargo" end
        end,
        __call = function() return false, "module " .. name .. " no cargo" end,
    })
end

local function load(name)
    local ok, result = pcall(require, name)
    if ok and type(result) == "table" then
        M[name] = result
        table.insert(Menu.ok, name)
        return result
    end
    local message = ok and ("devolvio " .. type(result)) or tostring(result)
    Menu.errors[name] = message
    M[name] = stub(name)
    U.log("module failed", name, message)
    return M[name]
end

-- The order matters: core first, because everything else reports through it.
local CORE = { "core/util", "core/net", "core/game" }
local FEATURES = {
    "features/train", "features/items", "features/combat", "features/npc",
    "features/move", "features/world", "features/esp", "features/roles",
    "features/pet", "features/shield",
}

-- Tab modules, in the order the rail shows them.
local TABS = {
    "ui/tabs/home", "ui/tabs/training", "ui/tabs/items", "ui/tabs/npcs",
    "ui/tabs/twado", "ui/tabs/combat", "ui/tabs/move", "ui/tabs/world",
    "ui/tabs/enemies", "ui/tabs/roles", "ui/tabs/safety",
}

local function wrap_callbacks(object, label)
    -- Rayfield takes callbacks inside the props table, so wrapping happens on
    -- the way in rather than on the element afterwards.
    if type(object) ~= "table" then return object end
    for key, value in pairs(object) do
        if type(value) == "function" and (key == "callback" or key == "Callback") then
            object[key] = function(...)
                local ok, err = pcall(value, ...)
                if not ok then
                    Menu.callback_errors = Menu.callback_errors + 1
                    U.log("callback failed", label, tostring(err))
                    U.notify("error en " .. tostring(label), tostring(err))
                    if Menu.on_callback_error then
                        pcall(Menu.on_callback_error, label, tostring(err))
                    end
                end
            end
        elseif type(value) == "table" then
            wrap_callbacks(value, label)
        end
    end
    return object
end

-- A tab handle whose element factories wrap callbacks before Rayfield sees them.
local function guarded_tab(tab, label)
    if not tab then return nil end
    local proxy = {}
    local function make(method)
        return function(_, props)
            wrap_callbacks(props, label)
            local ok, element = pcall(tab[method], tab, props)
            if not ok then
                U.log("element failed", label, method, tostring(element))
                return setmetatable({}, { __index = function() return function() end end })
            end
            return element
        end
    end
    for _, method in ipairs({ "CreateToggle", "CreateSlider", "CreateDropdown", "CreateButton",
                              "CreateInput", "CreateKeybind", "CreateColorPicker", "CreateStat",
                              "CreateText", "CreateSection", "CreateGroup", "CreateDivider",
                              "CreateProgress", "CreateConsole" }) do
        proxy[method] = make(method)
    end
    proxy.raw = tab
    return proxy
end

local function guarded_window(window)
    local proxy = {}
    local function make_tab(_, props)
        wrap_callbacks(props, props and props.name or "?")
        local ok, tab = pcall(window.CreateTab, window, props)
        if not ok then
            U.log("tab failed", tostring(props and props.name), tostring(tab))
            Menu.errors["tab:" .. tostring(props and props.name)] = tostring(tab)
            return guarded_tab(nil, "?")
        end
        return guarded_tab(tab, props and props.name or "?")
    end
    proxy.CreateTab = make_tab
    proxy.CreateSection = function(_, props) return window:CreateSection(props) end
    proxy.CreateTag = function(_, props) return window:CreateTag(props) end
    proxy.Notify = function(_, props) return window:Notify(props) end
    proxy.Toast = function(_, props) return window:Toast(props) end
    proxy.Unload = function() return window:Unload() end
    proxy.Get = function(_, flag) return window:Get(flag) end
    proxy.Set = function(_, flag, value) return window:Set(flag, value) end
    proxy.raw = window
    return proxy
end

function Menu.build()
    for _, name in ipairs(CORE) do load(name) end

    local Rayfield = load("ui/rayfield")
    local window = nil

    if Rayfield and type(Rayfield.CreateWindow) == "function" then
        local ok, created = pcall(function()
            return Rayfield:CreateWindow({
                name = "breaker / break in 2",
                subtitle = "nada dispara hasta que lo enciendas",
                sidebarLayout = true,
                profile = "build " .. tostring(U.VERSION),
                theme = "cobalt",
                configuration = {
                    autoSave = true,
                    autoLoad = true,
                    fileName = "breaker_bi2",
                    customFolder = "breaker",
                },
            })
        end)
        if ok then
            window = created
        else
            Menu.errors["window"] = tostring(created)
            U.log("window failed", tostring(created))
        end
    else
        Menu.errors["ui/rayfield"] = Menu.errors["ui/rayfield"] or "no disponible"
    end

    U.window = window
    U.flush()

    if not window then
        -- No UI: the features are still reachable through the automation
        -- bridge, and the failure is reported rather than swallowed.
        U.log("sin ventana; queda el bridge de automatizacion")
        return nil, Menu.errors
    end

    for _, name in ipairs(FEATURES) do load(name) end
    for _, name in ipairs(TABS) do load(name) end

    local ctx = {
        window = guarded_window(window),
        U = M["core/util"], Net = M["core/net"], Game = M["core/game"],
        Train = M["features/train"], Items = M["features/items"],
        Combat = M["features/combat"], Npc = M["features/npc"],
        Move = M["features/move"], World = M["features/world"],
        Esp = M["features/esp"], Roles = M["features/roles"],
        Pet = M["features/pet"], Shield = M["features/shield"],
        Menu = Menu,
        elements = Menu.elements,
    }
    Menu.ctx = ctx

    -- each tab gets its own pcall: one broken tab costs one tab
    for _, name in ipairs(TABS) do
        local mod = M[name]
        local label = name:gsub("ui/tabs/", "")
        local ok, err = pcall(mod.build, ctx)
        if not ok then
            Menu.errors[label] = tostring(err)
            U.log("tab failed", label, tostring(err))
        end
    end

    -- the diagnostics tab is built last, so it can list every failure above
    local okDiag, Diagnostics = pcall(require, "ui/tabs/diagnostics")
    if okDiag and type(Diagnostics) == "table" then
        local ok, err = pcall(Diagnostics.build, ctx)
        if not ok then U.log("diagnostics tab failed", tostring(err)) end
    end

    Menu.hud(ctx)
    return window, Menu.errors
end

-- The HUD loop lives here because it touches elements from several tabs. Each
-- line is guarded on its own: a tab that never built simply has no element to
-- refresh.
function Menu.hud(ctx)
    local U_ = M["core/util"]
    if not U_ then return end
    U_.loop("hud", 1, function()
        local Esp = M["features/esp"]
        local Game = M["core/game"]
        local Net = M["core/net"]
        local Shield = M["features/shield"]
        local Pet = M["features/pet"]
        local els = Menu.elements or {}

        if els.placeLine and Game then pcall(function() els.placeLine:Set(Game.where()) end) end
        if Esp then
            local ok, list = pcall(Esp.read)
            if ok and els.enemyStat then pcall(function() els.enemyStat:Set(#list) end) end
            if ok and els.enemyLine then pcall(function() els.enemyLine:Set(Esp.summary(list)) end) end
            if ok and els.espLine then pcall(function() els.espLine:Set(Esp.summary(list)) end) end
            if ok and Esp.enabled then pcall(Esp.apply, list) end
        end
        if els.remoteStat and Net then pcall(function() els.remoteStat:Set(U_.count(Net.remotes)) end) end
        if els.petLine and Pet then pcall(function() els.petLine:Set(Pet.summary()) end) end
        if els.hpLine and Shield then
            pcall(function()
                local hp, max = Shield.health()
                els.hpLine:Set(hp and string.format("%.0f / %.0f", hp, max) or "sin personaje")
            end)
        end
        if els.godLine and Shield then pcall(function() els.godLine:Set(Shield.status()) end) end
    end)
end

return Menu
