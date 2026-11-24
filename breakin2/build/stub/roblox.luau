-- build/stub/roblox.luau
-- Enough of Roblox to load the real source tree without a client: instances,
-- signals, services, and the executor globals the script is allowed to use.
-- Nothing here simulates gameplay beyond what a check needs; a feature that
-- asks for an enemy folder gets an empty folder and takes its fallback, which
-- is the path worth exercising.

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

Instance = {}
local INSTANCE_META = {}
-- namecall simulation: in Roblox every `obj:Method()` goes through the shared
-- __namecall, which is what the semi-godmode hook replaces. Methods and remote
-- verbs are dispatched through here so the hook can actually be observed.
__namecall_method = nil
function __dispatch(obj, method, ...)
    __namecall_method = method
    local fn = INSTANCE_META.__namecall
    if type(fn) ~= "function" then return nil end
    return fn(obj, ...)
end

local function newInstance(class, name)
    return setmetatable({
        ClassName = class,
        Name = name or class,
        _children = {},
        Parent = nil,
        _gui = (class:match("Frame") or class:match("TextLabel")) ~= nil,
    }, INSTANCE_META)
end

function Instance.new(class, parent)
    local inst = newInstance(class)
    if parent then inst.Parent = parent end
    return inst
end

local function isA(self, class)
    local c = self.ClassName
    if c == class then return true end
    if class == "BasePart" then
        return c == "Part" or c == "MeshPart" or c == "UnionOperation"
    end
    if class == "GuiObject" then return self._gui == true end
    return false
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

-- never blocks: the gate runs at chunk scope, where yielding is illegal. A
-- module that expects the child to appear gets nil and takes its fallback.
function Instance:WaitForChild(name)
    return self:FindFirstChild(name, true)
end

function Instance:IsA(class) return isA(self, class) end
function Instance:GetFullName()
    return (self.Parent and self.Parent:GetFullName() .. "." or "") .. self.Name
end
function Instance:Activate()
    self._activated = (self._activated or 0) + 1
end
function Instance:Destroy()
    self.Parent = nil
    self._destroyed = true
end
function Instance:AddChild(child)
    child.Parent = self
    table.insert(self._children, child)
end
function Instance:Clone()
    local copy = newInstance(self.ClassName, self.Name)
    for k, v in pairs(self) do
        if k ~= "_children" and k ~= "Parent" then rawset(copy, k, v) end
    end
    return copy
end
function Instance:PivotTo() end
function Instance:GetPivot() return CFrame.new() end

INSTANCE_META.__index = function(self, key)
    local impl = rawget(self, "_impl")
    if impl and impl[key] then
        return function(obj, ...) return __dispatch(obj, key, ...) end
    end
    if Instance[key] then
        return function(obj, ...) return __dispatch(obj, key, ...) end
    end
    return nil
end

INSTANCE_META.__namecall = function(self, ...)
    local method = __namecall_method
    local impl = rawget(self, "_impl")
    local fn = (impl and impl[method]) or Instance[method]
    if not fn then return nil end
    return fn(self, ...)
end

setmetatable(Instance, { __call = function(_, class, name) return newInstance(class, name) end })
INSTANCE_META.__newindex = function(self, key, value)
    if key == "Parent" then
        rawset(self, "Parent", value)
        if value and value.AddChild then value:AddChild(self) end
        return
    end
    rawset(self, key, value)
end

local function newService(name)
    local s = newInstance("Service_" .. name, name)
    s.ChildAdded = newSignal()
    s.ChildRemoved = newSignal()
    s.PlayerAdded = newSignal()
    s.PlayerRemoving = newSignal()
    s.CharacterAdded = newSignal()
    return s
end

local function makePlayer()
    local p = newInstance("Player", "StubPlayer")
    p.UserId = 1
    p.CharacterAdded = newSignal()
    p.CharacterRemoving = newSignal()
    p:AddChild(newInstance("Backpack", "Backpack"))

    local char = newInstance("Model", "StubCharacter")
    local hum = newInstance("Humanoid", "Humanoid")
    hum.Health = 100
    hum.MaxHealth = 200
    hum.WalkSpeed = 16
    hum.JumpPower = 50
    char:AddChild(hum)
    local root = newInstance("Part", "HumanoidRootPart")
    root.Position = Vector3.new(0, 0, 0)
    root.CFrame = CFrame.new(0, 0, 0)
    char:AddChild(root)
    p:AddChild(char)
    p.Character = char

    local gui = newInstance("PlayerGui", "PlayerGui")
    local wants = newInstance("TextLabel", "TwadoWants")
    wants.Text = "Pizza"
    wants.Visible = true
    gui:AddChild(wants)
    p:AddChild(gui)
    return p
end

local players = newService("Players")
local player = makePlayer()
players.LocalPlayer = player
players:AddChild(player)

local replicated = newService("ReplicatedStorage")
local events = newInstance("Folder", "Events")
replicated:AddChild(events)
replicated:AddChild(newInstance("Folder", "RemoteEvents"))

local world = newService("Workspace")
local cam = newInstance("Camera", "Camera")
cam.ViewportSize = Vector2.new(1920, 1080)
cam.CFrame = CFrame.new()
world.CurrentCamera = cam
world:AddChild(newInstance("Folder", "BadGuys"))
world:AddChild(newInstance("Folder", "BadGuysBoss"))
world:AddChild(newInstance("Folder", "FallenTrees"))

game = newService("DataModel")
game.PlaceId = 13864667823
game.JobId = "stub"
game.GameId = 1

local Services = {}
Services.Players = players
Services.ReplicatedStorage = replicated
Services.Workspace = world
Services.Lighting = newService("Lighting")
Services.Lighting.Ambient = Color3.fromRGB(0, 0, 0)
Services.Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
Services.Lighting.Brightness = 1
Services.Lighting.FogEnd = 1000
Services.Lighting.FogStart = 0
Services.Lighting.ClockTime = 14
Services.RunService = newService("RunService")
Services.RunService.RenderStepped = newSignal()
Services.RunService.Stepped = newSignal()
Services.RunService.Heartbeat = newSignal()
Services.UserInputService = newService("UserInputService")
Services.UserInputService.IsKeyDown = function() return false end
Services.TweenService = newService("TweenService")
Services.CoreGui = newService("CoreGui")
Services.TeleportService = newService("TeleportService")
Services.HttpService = newService("HttpService")
Services.SoundService = newService("SoundService")

game.GetService = function(_, name)
    return Services[name] or newService(name)
end
game.FindService = game.GetService
game.CreateInstance = function(_, class, name) return newInstance(class, name) end
game.IsLoaded = function() return true end

workspace = world
game.Workspace = world
game.Players = players

local function addRemote(folder, name)
    local r = newInstance("RemoteEvent", name)
    r._impl = {
        FireServer = function() return nil end,
        InvokeServer = function() return nil end,
    }
    r.OnClientEvent = newSignal()
    folder:AddChild(r)
    return r
end

for _, name in ipairs({ "RainbowWhatStat", "HitBadguy", "HealTheNoobs", "KeyEvent",
                        "LouiseGive", "CatFed", "RoadMissionEvent", "OnDoorHit",
                        "LarryEndingEvent", "OutsideFood" }) do
    addRemote(events, name)
end
addRemote(replicated:FindFirstChild("RemoteEvents"), "OutsideRole")

-- energy: the server adds or subtracts health by the amount it is given, which
-- is exactly the behaviour the heal relies on
local energy = addRemote(events, "Energy")
energy._impl.FireServer = function(_, amount)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum or type(amount) ~= "number" then return end
    hum.Health = math.clamp(hum.Health + amount, 0, hum.MaxHealth)
end

-- give/vending craft the tool the way the server does, so item flows can be
-- checked for "did the object arrive" instead of only "did it not throw"
local function craftTool(name)
    local tool = newInstance("Tool", name)
    tool:AddChild(newInstance("Part", "Handle"))
    local target = player.Character or player:FindFirstChild("Backpack")
    tool.Parent = target
    return tool
end

local give = addRemote(events, "GiveTool")
give._impl.FireServer = function(_, rawName) craftTool(tostring(rawName)) end

local vending = addRemote(events, "Vending")
vending._impl.FireServer = function(_, mode, name) craftTool(tostring(name)) end

-- executor globals. hookmetamethod is implemented for real: the semi-godmode
-- hook is a decision worth testing, not a decoration.
function fireclickdetector() return nil end
function firetouchinterest() return nil end
local GENV = {}
function getgenv() return GENV end
function getrenv() return GENV end
function identifyexecutor() return "stub", "1.0" end
function isfile() return false end
function writefile() return nil end
function readfile() return "" end

-- getrawmetatable(game).__namecall is what the hook replaces. The stub version
-- dispatches for real, so a hook that blocks a call is visible as "the health
-- did not move", exactly as in game.
__namecall_method = nil

function getnamecallmethod()
    return __namecall_method
end

function getrawmetatable(obj)
    if obj == game then return INSTANCE_META end
    return getmetatable(obj) or {}
end

function setreadonly() return true end
function isreadonly() return false end
function newcclosure(fn) return fn end
function hookmetamethod(_, name, replacement)
    local old = INSTANCE_META[name]
    INSTANCE_META[name] = replacement
    return old
end
function hookfunction(original, replacement) return original end

-- loadstring: the module loader hands sources through `load`, so only the
-- Rayfield stand-in needs intercepting
local realLoad = load or loadstring

local function inertHandle()
    local h = {}
    for _, k in ipairs({ "Set", "SetTitle", "Refresh", "Add", "Remove", "Lock", "Unlock",
                         "Select", "Deselect", "MoveTo" }) do
        h[k] = function() end
    end
    h.value = 0
    return h
end

EXERCISE = {}
function __exercise() return EXERCISE end
local currentTab = "?"

-- EXERCISE is a list of records; when a tab is rebuilt (the isolation check
-- builds Home again) it is replaced, so callers take a snapshot with
-- __exercise() instead of holding the old table.
local function record(method, props)
    if type(props) ~= "table" then return end
    table.insert(EXERCISE, {
        method = method, tab = currentTab, name = props.name,
        flag = props.flag, value = props.value, callback = props.callback,
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
            -- element props are validated the way Rayfield would: a callback
            -- that is not a function is a bug in the tab, not in Rayfield
            if props and props.callback ~= nil and type(props.callback) ~= "function" then
                error("callback is not a function in " .. tostring(props.name), 0)
            end
            return inertHandle()
        end
    end
    return t
end

local rayfield = {}
function rayfield:CreateWindow(props)
    local w = {}
    w.CreateTab = function(_, tabProps) return makeTabProxy(tabProps and tabProps.name or "?") end
    w.CreateTag = function() return inertHandle() end
    w.CreateSection = function() return inertHandle() end
    w.Notify = function() end
    w.Toast = function() end
    w.Popup = function() return inertHandle() end
    w.Show = function() end
    w.Hide = function() end
    w.ToggleHide = function() end
    w.ToggleMinimise = function() end
    w.Navigate = function() end
    w.Unload = function() end
    w.Save = function() return true end
    w.Load = function() return true end
    w.Get = function() return nil end
    w.Set = function() return true end
    w.Flags = {}
    return w
end

__STUB_RAYFIELD = rayfield

function game:HttpGet(url)
    if tostring(url):find("sirius.menu") then return "return __STUB_RAYFIELD" end
    return ""
end

function loadstring(chunk, name)
    if tostring(chunk):find("__STUB_RAYFIELD") then
        return function() return __STUB_RAYFIELD end
    end
    return realLoad(chunk, name or "=stub")
end
