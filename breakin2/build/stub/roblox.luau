-- build/stub/roblox.luau
-- A enough-of-Roblox stub for the syntax gate: it lets the whole source tree
-- load without a client. Signals, Instances, enums, datatypes, the services the
-- script touches. Nothing here simulates gameplay; a feature that asks the stub
-- for an enemy folder gets an empty folder and stops, which is the point.

local function newSignal()
    local s = { _conns = {} }
    function s:Connect(fn)
        table.insert(self._conns, fn)
        return { Disconnect = function() end }
    end
    function s:Once(fn) return self:Connect(fn) end
    function s:Wait() return nil end
    function s:Fire(...)
        for _, fn in ipairs(self._conns) do
            local ok, err = pcall(fn, ...)
            if not ok then warn("signal handler: " .. tostring(err)) end
        end
    end
    return s
end

-- global on purpose: the sources call Instance.new at runtime
Instance = {}
Instance.__index = Instance

local function isA(self, class)
    local c = self.ClassName
    if c == class then return true end
    if class == "BasePart" then
        return c == "Part" or c == "MeshPart" or c == "UnionOperation"
    end
    if class == "GuiObject" then
        return (self._gui == true)
    end
    if class == "Tool" then return c == "Tool" end
    return false
end

local function newInstance(class, name)
    local inst = setmetatable({
        ClassName = class,
        Name = name or class,
        _children = {},
        _props = {},
        Parent = nil,
        _gui = (class:match("Frame") or class:match("TextLabel")) ~= nil,
    }, Instance)
    return inst
end

function Instance.new(class, parent)
    local inst = newInstance(class)
    if parent then inst.Parent = parent end
    return inst
end

function Instance:GetChildren()
    local out = {}
    for _, c in ipairs(self._children) do table.insert(out, c) end
    return out
end

function Instance:GetDescendants()
    local out = {}
    local function walk(node)
        for _, c in ipairs(node._children) do
            table.insert(out, c)
            walk(c)
        end
    end
    walk(self)
    return out
end

function Instance:FindFirstChild(name, recursive)
    for _, c in ipairs(self._children) do
        if c.Name == name then return c end
    end
    if recursive then
        for _, c in ipairs(self._children) do
            local hit = c:FindFirstChild(name, true)
            if hit then return hit end
        end
    end
    return nil
end

function Instance:FindFirstChildOfClass(class)
    for _, c in ipairs(self._children) do
        if c.ClassName == class then return c end
    end
    return nil
end

function Instance:FindFirstChildWhichIsA(class, recursive)
    for _, c in ipairs(self._children) do
        if c:IsA(class) then return c end
    end
    if recursive then
        for _, c in ipairs(self._children) do
            local hit = c:FindFirstChildWhichIsA(class, true)
            if hit then return hit end
        end
    end
    return nil
end

function Instance:WaitForChild(name, timeout)
    -- never blocks: the gate runs this at chunk scope, where yielding is illegal.
    -- A module that expects the child to appear gets nil and takes its fallback,
    -- which is exactly the path worth exercising.
    return self:FindFirstChild(name, true)
end

function Instance:IsA(class) return isA(self, class) end
function Instance:Activate()
    self._activated = (self._activated or 0) + 1
end

function Instance:Destroy()
    self.Parent = nil
    self._destroyed = true
end
function Instance:GetFullName() return (self.Parent and self.Parent:GetFullName() .. "." or "") .. self.Name end
function Instance:AddChild(child)
    child.Parent = self
    table.insert(self._children, child)
end

-- properties the script reads/writes; the stub accepts any, but these are the
-- ones that are read before ever being written, so they get sane defaults
Instance.__newindex = function(self, key, value)
    if key == "Parent" then
        rawset(self, "Parent", value)
        if value and value.AddChild then value:AddChild(self) end
        return
    end
    rawset(self, key, value)
end

local Services = {}

local function newService(name)
    local s = newInstance("DataModel_" .. name, name)
    s.ChildAdded = newSignal()
    s.ChildRemoved = newSignal()
    s.PlayerAdded = newSignal()
    s.CharacterAdded = newSignal()
    return s
end

local function makePlayer()
    local p = newInstance("Player", "StubPlayer")
    p.UserId = 1
    p.CharacterAdded = newSignal()
    p.CharacterRemoving = newSignal()
    local bag = newInstance("Backpack", "Backpack")
    p:AddChild(bag)
    local gui = newInstance("PlayerGui", "PlayerGui")
    p:AddChild(gui)
    local char = newInstance("Model", "StubCharacter")
    local hum = newInstance("Humanoid", "Humanoid")
    hum.Health = 100
    hum.MaxHealth = 100
    hum.WalkSpeed = 16
    hum.JumpPower = 50
    char:AddChild(hum)
    local root = newInstance("Part", "HumanoidRootPart")
    root.Position = Vector3.new(0, 0, 0)
    root.CFrame = CFrame.new(0, 0, 0)
    char:AddChild(root)
    p:AddChild(char)
    p.Character = char
    return p
end

local players = newService("Players")
local player = makePlayer()
players.LocalPlayer = player
players:AddChild(player)

local replicated = newService("ReplicatedStorage")
local events = newInstance("Folder", "Events")
replicated:AddChild(events)
local remoteEvents = newInstance("Folder", "RemoteEvents")
replicated:AddChild(remoteEvents)

-- a handful of the real remote names, so net.resolve() goes down its success
-- path instead of its (also worth testing) all-missing path
local function addRemote(folder, class, name)
    local r = newInstance(class, name)
    r.FireServer = function() return nil end
    r.InvokeServer = function() return nil end
    r.OnClientEvent = newSignal()
    folder:AddChild(r)
    return r
end

for _, name in ipairs({ "RainbowWhatStat", "HitBadguy",
                        "HealTheNoobs", "Energy", "KeyEvent", "LouiseGive",
                        "CatFed", "RoadMissionEvent" }) do
    addRemote(events, "RemoteEvent", name)
end
addRemote(remoteEvents, "RemoteEvent", "OutsideRole")

-- GiveTool / Vending craft the tool the way the server does, so the item flows
-- can be tested for "did the object arrive" instead of only "did it not throw".
local function craftTool(name)
    local tool = newInstance("Tool", name)
    tool:AddChild(newInstance("Part", "Handle"))
    local char = player.Character
    local target = char or player:FindFirstChild("Backpack")
    tool.Parent = target
    return tool
end

local give = addRemote(events, "RemoteEvent", "GiveTool")
give.FireServer = function(_, rawName)
    craftTool(tostring(rawName))
end

local vending = addRemote(events, "RemoteEvent", "Vending")
vending.FireServer = function(_, mode, name, category)
    if mode == 3 or mode == 1 then craftTool(tostring(name)) end
end

local world = newService("Workspace")
local cam = newInstance("Camera", "Camera")
cam.ViewportSize = Vector2.new(1920, 1080)
world.CurrentCamera = cam

game = newService("DataModel")
game.PlaceId = 13864667823
game.JobId = "stub"
game.GameId = 1

Services.Players = players
Services.ReplicatedStorage = replicated
Services.Workspace = world
Services.RunService = newService("RunService")
Services.RunService.RenderStepped = newSignal()
Services.RunService.Stepped = newSignal()
Services.RunService.Heartbeat = newSignal()
Services.UserInputService = newService("UserInputService")
Services.TweenService = newService("TweenService")
Services.Lighting = newService("Lighting")
Services.Lighting.Ambient = Color3.fromRGB(0, 0, 0)
Services.Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
Services.Lighting.Brightness = 1
Services.Lighting.FogEnd = 1000
Services.Lighting.FogStart = 0
Services.Lighting.ClockTime = 14
Services.CoreGui = newService("CoreGui")
Services.TeleportService = newService("TeleportService")
Services.HttpService = newService("HttpService")

game.GetService = function(_, name)
    return Services[name] or newService(name)
end
game.FindService = game.GetService
game.CreateInstance = function(_, class, name) return newInstance(class, name) end
game.IsLoaded = function() return true end
game.GetDescendants = function() return {} end

workspace = world
game.Workspace = world
game.Players = players
game.Workspace = world

-- executor globals: present but inert, so a feature that needs them reports a
-- miss instead of erroring
function fireclickdetector(detector) return nil end
function firetouchinterest(part, other, state) return nil end
-- the sandboxed interpreter has _G locked, so the stub keeps its own table;
-- this is what an executor's getgenv() is to the script anyway
-- os.clock is present in every real client; the gate's scheduler prefers tick
function tick()
    return os.clock()
end

local GENV = {}
function getgenv() return GENV end
function getrenv() return GENV end
function identifyexecutor() return "stub", "1.0" end
function isfile() return false end
function writefile() return nil end
function readfile() return "" end

-- Rayfield stand-in: records what the script asked for and returns inert
-- handles, so menu.lua can be loaded and checked end to end.
local function inertHandle()
    local h = {}
    local noop = function() end
    for _, k in ipairs({ "Set", "Refresh", "Add", "Remove", "Lock", "Unlock", "SetTitle",
                         "MoveTo", "MoveUp", "MoveDown", "Select", "Deselect", "Remove" }) do
        h[k] = noop
    end
    h.value = 0
    return h
end

-- every element the menu creates is recorded, so the gate can fire each
-- callback and prove the wiring runs (a nil in a callback is the usual bug)
EXERCISE = {}
local currentTab = "?"

local function record(method, props)
    if type(props) ~= "table" then return end
    table.insert(EXERCISE, {
        method = method,
        tab = currentTab,
        name = props.name,
        flag = props.flag,
        value = props.value,
        callback = props.callback,
    })
end

local function makeTabProxy(tabName)
    currentTab = tabName
    local t = {}
    for _, method in ipairs({ "CreateToggle", "CreateSlider", "CreateDropdown", "CreateButton",
                              "CreateInput", "CreateKeybind", "CreateColorPicker", "CreateStat",
                              "CreateText", "CreateSection", "CreateGroup", "CreateDivider",
                              "CreateProgress", "CreateConsole" }) do
        t[method] = function(_, props)
            record(method, props)
            return inertHandle()
        end
    end
    return t
end

local rayfield = {}
function rayfield:CreateWindow()
    local w = {}
    w.CreateTab = function(_, props)
        return makeTabProxy(props and props.name or "?")
    end
    w.CreateTag = function() return inertHandle() end
    w.CreateSection = function() return inertHandle() end
    w.Notify = function() end
    w.Toast = function() end
    w.Popup = function() return inertHandle() end
    w.Show = function() end
    w.Hide = function() end
    w.ToggleHide = function() end
    w.Unload = function() end
    w.Save = function() return true end
    w.Load = function() return true end
    w.Get = function() return nil end
    w.Set = function() return true end
    w.Flags = {}
    return w
end

local realHttpGet = game.HttpGet
function game:HttpGet(url)
    if tostring(url):find("sirius.menu") then
        return "return __STUB_RAYFIELD"
    end
    return ""
end
__STUB_RAYFIELD = rayfield

-- loadstring: the real executor one parses chunks; here it only ever hands back
-- the Rayfield stub
local realLoad = load or loadstring
function loadstring(chunk, name)
    if tostring(chunk):find("__STUB_RAYFIELD") then
        return function() return __STUB_RAYFIELD end
    end
    -- the module loader hands each source through here, so fall through to the
    -- interpreter's own loader instead of pretending to parse
    return realLoad(chunk, name or "=stub")
end
