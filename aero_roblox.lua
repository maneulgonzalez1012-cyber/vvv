--[[
Aero / Roblox -- generic Luau-side ESP + aimbot + triggerbot + radar + fly.
Target: Roblox client (Luau VM / DataModel), any experience.

No static offsets: Roblox exposes instances by name, not by RVA. Regen source is the
Character instance tree itself (R15 / R6 rig names). No cs2-dumper, no Il2CppDumper.
All named constants live in the single `off` block below; nothing is scattered.

World-to-screen: Camera:WorldToViewportPoint -> origin top-left, +Y down, no Y flip.
(unlike Source's row-major w = m[12..15]*p, or Unity's bottom-left projection origin)

AC: Hyperion (Byfron), kernel-mode, handle stripping + client integrity checks +
unsigned-driver block. External OpenProcess/RPM does not survive it. Execution stays
inside the client's Luau script context, because the DataModel only exists there.

Fly: ported from Infinite Yield FE (EdgeIY/infiniteyield, MIT), sFLY()/mobilefly()
in `source` lines 7108-7216 / 7239-7307. BodyVelocity + BodyGyro on
HumanoidRootPart, 9e9 MaxForce/MaxTorque, Humanoid.PlatformStand, gyro locked to
camera.CFrame, Q/E for vertical. Regen source = that file, no dumper.

-- FILL: remotePath = "ReplicatedStorage.<Folder>.<RemoteEvent>" for item spoof or
-- remote spam. Get it per experience with a RemoteSpy: hook __namecall, filter
-- getnamecallmethod() == "FireServer", log the instance's GetFullName() plus
-- debug.traceback(). Lua comments are `--`, not `//`.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Teams = game:GetService("Teams")
local CoreGui = game:GetService("CoreGui")
local lp = Players.LocalPlayer

-- Single-instance guard: loader.lua clears AERO_FORCE_RELOAD before fetching.
do
    local E = _G
    local ok, g = pcall(function() return getgenv() end)
    if ok and type(g) == "table" then E = g end
    if E.AERO_LOADED then return end
    E.AERO_LOADED = true
end

-- Executor globals. Absent on stock Roblox, present on Synapse / Script-Ware /
-- Fluxus. Reading a missing global is nil; every use below degrades gracefully.
local ENV = _G
do
    local ok, res = pcall(function() return getfenv() end)
    if ok and type(res) == "table" then ENV = res end
end
local writefile = rawget(ENV, "writefile")
local readfile = rawget(ENV, "readfile")
local isfile = rawget(ENV, "isfile")
local mousemoverel = rawget(ENV, "mousemoverel")
local mouse1click = rawget(ENV, "mouse1click")
local mouse1press = rawget(ENV, "mouse1press")
local mouse1release = rawget(ENV, "mouse1release")

local off = {
    -- Logical bone -> candidate part names. R15 first, R6 fallback.
    rig = {
        Head = { "Head" },
        UpperTorso = { "UpperTorso", "Torso" },
        LowerTorso = { "LowerTorso", "Torso" },
        LeftUpperArm = { "LeftUpperArm", "Left Arm", "LeftArm" },
        LeftLowerArm = { "LeftLowerArm", "Left Arm", "LeftArm" },
        LeftHand = { "LeftHand", "Left Arm", "LeftArm" },
        RightUpperArm = { "RightUpperArm", "Right Arm", "RightArm" },
        RightLowerArm = { "RightLowerArm", "Right Arm", "RightArm" },
        RightHand = { "RightHand", "Right Arm", "RightArm" },
        LeftUpperLeg = { "LeftUpperLeg", "Left Leg", "LeftLeg" },
        LeftLowerLeg = { "LeftLowerLeg", "Left Leg", "LeftLeg" },
        LeftFoot = { "LeftFoot", "Left Leg", "LeftLeg" },
        RightUpperLeg = { "RightUpperLeg", "Right Leg", "RightLeg" },
        RightLowerLeg = { "RightLowerLeg", "Right Leg", "RightLeg" },
        RightFoot = { "RightFoot", "Right Leg", "RightLeg" },
        HumanoidRootPart = { "HumanoidRootPart", "Torso" },
    },
    skeleton = {
        { "Head", "UpperTorso" },
        { "UpperTorso", "LowerTorso" },
        { "UpperTorso", "LeftUpperArm" },
        { "LeftUpperArm", "LeftLowerArm" },
        { "LeftLowerArm", "LeftHand" },
        { "UpperTorso", "RightUpperArm" },
        { "RightUpperArm", "RightLowerArm" },
        { "RightLowerArm", "RightHand" },
        { "LowerTorso", "LeftUpperLeg" },
        { "LeftUpperLeg", "LeftLowerLeg" },
        { "LeftLowerLeg", "LeftFoot" },
        { "LowerTorso", "RightUpperLeg" },
        { "RightUpperLeg", "RightLowerLeg" },
        { "RightLowerLeg", "RightFoot" },
    },
    bones = { "Head", "UpperTorso", "HumanoidRootPart" },
    colors = {
        box = { 0, 255, 180 },
        skel = { 235, 235, 245 },
        text = { 220, 220, 230 },
        enemy = { 255, 90, 90 },
        fov = { 0, 255, 180 },
    },
    -- Infinite Yield FE fly constants. "infinite field" = 9e9, not math.huge:
    -- IY deliberately uses a finite but huge force so the physics solver stays
    -- stable. Source: EdgeIY/infiniteyield `source` (sFLY / mobilefly).
    fly = {
        maxForce = 9e9,
        maxTorque = 9e9,
        gyroP = 9e4,
        gyroD = 50,
    },
}

-- Everything off at launch. Menu gates the rest.
local cfg = {
    esp = { enabled = false, box = true, skeleton = true, health = true, name = true,
            distance = true, teamCheck = true, snaplines = false },
    aim = { enabled = false, fov = 180, smoothing = 0.18, bone = "Head",
            visCheck = true, useMouseMove = false },
    trigger = { enabled = false, delayMs = 90, range = 300 },
    misc = { fly = false, flySpeed = 60, fovCircle = false, radar = false },
    hotkeys = { menu = "Insert", trigger = "T", fly = "F" },
}
local DEFAULTS = HttpService:JSONDecode(HttpService:JSONEncode(cfg))
local CONFIG_FILE = "aero_roblox_config.json"

local refresh, setStatus

local function col(a) return Color3.fromRGB(a[1], a[2], a[3]) end
local function key(name)
    local ok, k = pcall(function() return Enum.KeyCode[name] end)
    return ok and k or nil
end
local function newParams()
    local p = RaycastParams.new()
    p.IgnoreWater = true
    pcall(function() p.FilterType = Enum.RaycastFilterType.Exclude end)
    pcall(function() p.FilterType = Enum.RaycastFilterType.Blacklist end)
    local t = {}
    if lp.Character then t[1] = lp.Character end
    p.FilterDescendantsInstances = t
    return p
end
local function resolve(char, logical)
    for _, name in ipairs(off.rig[logical] or { logical }) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    return nil
end
local function isTeammate(p)
    if not cfg.esp.teamCheck then return false end
    if p == lp then return true end
    if p.Team and lp.Team then return p.Team == lp.Team end
    local ok, n = pcall(function() return #Teams:GetTeams() end)
    if ok and n and n > 0 then return p.TeamColor == lp.TeamColor end
    return false
end

local function merge(dst, src)
    for k, v in pairs(src) do
        if type(dst[k]) == type(v) then
            if type(v) == "table" then merge(dst[k], v)
            else dst[k] = v end
        end
    end
end
local function saveConfig()
    if not writefile then setStatus("writefile no disponible en este executor"); return end
    local ok = pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(cfg)) end)
    setStatus(ok and ("guardado " .. CONFIG_FILE) or "error al guardar")
end
local function loadConfig()
    if not (readfile and isfile) then setStatus("readfile/isfile no disponible"); return end
    local ok, data = pcall(function()
        if not isfile(CONFIG_FILE) then return nil end
        return HttpService:JSONDecode(readfile(CONFIG_FILE))
    end)
    if ok and type(data) == "table" then
        merge(cfg, data); refresh(); setStatus("config cargada")
    else
        setStatus("sin config previa o JSON invalido")
    end
end

-- GUI ------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "Aero"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
do
    local ok = pcall(function() gui.Parent = CoreGui end)
    if not ok then gui.Parent = lp:WaitForChild("PlayerGui") end
end

local layer = Instance.new("Frame", gui)
layer.BackgroundTransparency = 1
layer.Size = UDim2.fromScale(1, 1)
layer.ZIndex = 1

local radarFrame = Instance.new("Frame", gui)
radarFrame.Size = UDim2.fromOffset(140, 140)
radarFrame.Position = UDim2.new(1, -150, 0, 10)
radarFrame.BackgroundColor3 = Color3.fromRGB(8, 10, 14)
radarFrame.BackgroundTransparency = 0.25
radarFrame.BorderSizePixel = 0
radarFrame.ZIndex = 8
radarFrame.Visible = false
local radarCross = Instance.new("Frame", radarFrame)
radarCross.Size = UDim2.fromOffset(4, 4)
radarCross.AnchorPoint = Vector2.new(0.5, 0.5)
radarCross.Position = UDim2.fromOffset(70, 70)
radarCross.BackgroundColor3 = col(off.colors.box)
radarCross.BorderSizePixel = 0
radarCross.ZIndex = 9

local fovFrame = Instance.new("Frame", gui)
fovFrame.AnchorPoint = Vector2.new(0.5, 0.5)
fovFrame.Position = UDim2.fromScale(0.5, 0.5)
fovFrame.Size = UDim2.fromOffset(cfg.aim.fov * 2, cfg.aim.fov * 2)
fovFrame.BackgroundTransparency = 1
fovFrame.ZIndex = 9
fovFrame.Visible = false
-- UIStroke/UICorner are post-2020 Roblox; if the executor lacks them the circle
-- simply does not draw, everything else still works.
pcall(function()
    local s = Instance.new("UIStroke", fovFrame)
    s.Color = col(off.colors.fov)
    s.Thickness = 1
    s.Transparency = 0.35
    local c = Instance.new("UICorner", fovFrame)
    c.CornerRadius = UDim.new(1, 0)
end)

local main = Instance.new("Frame", gui)
main.Size = UDim2.fromOffset(324, 392)
main.Position = UDim2.fromScale(0.5, 0.5)
main.AnchorPoint = Vector2.new(0.5, 0.5)
main.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
main.BorderSizePixel = 0
main.ZIndex = 50
main.Active = true
main.Visible = false

local title = Instance.new("Frame", main)
title.Size = UDim2.new(1, 0, 0, 28)
title.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
title.BorderSizePixel = 0
title.ZIndex = 51
title.Active = true
local titleText = Instance.new("TextLabel", title)
titleText.Size = UDim2.fromScale(1, 1)
titleText.BackgroundTransparency = 1
titleText.Font = Enum.Font.Code
titleText.Text = "  AERO / ROBLOX"
titleText.TextSize = 13
titleText.TextColor3 = col(off.colors.box)
titleText.TextXAlignment = Enum.TextXAlignment.Left
titleText.ZIndex = 52

local tabNames = { "ESP", "AIMBOT", "MISC", "CONFIG" }
local tabFrames, tabButtons, rows = {}, {}, {}
for i, name in ipairs(tabNames) do
    local b = Instance.new("TextButton", main)
    b.Size = UDim2.fromOffset(77, 24)
    b.Position = UDim2.fromOffset(4 + (i - 1) * 79, 32)
    b.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code
    b.TextSize = 11
    b.Text = name
    b.TextColor3 = Color3.fromRGB(180, 180, 190)
    b.ZIndex = 52
    tabButtons[name] = b

    local f = Instance.new("Frame", main)
    f.Size = UDim2.new(1, -8, 1, -64)
    f.Position = UDim2.fromOffset(4, 60)
    f.BackgroundTransparency = 1
    f.ZIndex = 51
    f.Visible = (i == 1)
    local layout = Instance.new("UIListLayout", f)
    layout.Padding = UDim.new(0, 4)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    tabFrames[name] = f

    b.MouseButton1Click:Connect(function()
        for _, n in ipairs(tabNames) do
            tabFrames[n].Visible = (n == name)
            tabButtons[n].TextColor3 = (n == name) and col(off.colors.box) or Color3.fromRGB(180, 180, 190)
            tabButtons[n].BackgroundColor3 = (n == name) and Color3.fromRGB(36, 36, 44) or Color3.fromRGB(26, 26, 32)
        end
    end)
end
tabButtons.ESP.TextColor3 = col(off.colors.box)
tabButtons.ESP.BackgroundColor3 = Color3.fromRGB(36, 36, 44)

local function addToggle(tab, label, get, set)
    local b = Instance.new("TextButton", tabFrames[tab])
    b.Size = UDim2.new(1, -8, 0, 24)
    b.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code
    b.TextSize = 12
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.ZIndex = 53
    b.LayoutOrder = #rows + 1
    b.MouseButton1Click:Connect(function() set(not get()); refresh() end)
    rows[#rows + 1] = { update = function()
        b.Text = "  " .. (get() and "[x] " or "[ ] ") .. label
        b.TextColor3 = get() and col(off.colors.box) or Color3.fromRGB(185, 185, 195)
    end }
end
local function addNumber(tab, label, get, set, lo, hi)
    local f = Instance.new("Frame", tabFrames[tab])
    f.Size = UDim2.new(1, -8, 0, 24)
    f.BackgroundTransparency = 1
    f.ZIndex = 53
    f.LayoutOrder = #rows + 1
    local l = Instance.new("TextLabel", f)
    l.Size = UDim2.new(0.65, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.Font = Enum.Font.Code
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Text = "  " .. label
    l.TextColor3 = Color3.fromRGB(185, 185, 195)
    l.ZIndex = 54
    local box = Instance.new("TextBox", f)
    box.Size = UDim2.new(0.3, 0, 1, 0)
    box.Position = UDim2.fromScale(0.68, 0)
    box.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
    box.BorderSizePixel = 0
    box.Font = Enum.Font.Code
    box.TextSize = 12
    box.TextColor3 = col(off.colors.box)
    box.ZIndex = 54
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then set(math.clamp(n, lo, hi)) end
        refresh()
    end)
    rows[#rows + 1] = { update = function() box.Text = tostring(get()) end }
end
local function addCycle(tab, label, get, set, list)
    local b = Instance.new("TextButton", tabFrames[tab])
    b.Size = UDim2.new(1, -8, 0, 24)
    b.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code
    b.TextSize = 12
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.ZIndex = 53
    b.LayoutOrder = #rows + 1
    b.MouseButton1Click:Connect(function()
        local cur, idx = get(), 1
        for i, v in ipairs(list) do if v == cur then idx = i end end
        set(list[idx % #list + 1])
        refresh()
    end)
    rows[#rows + 1] = { update = function()
        b.Text = "  " .. label .. ": " .. tostring(get()) .. "  <"
        b.TextColor3 = col(off.colors.box)
    end }
end
local function addButton(tab, label, fn)
    local b = Instance.new("TextButton", tabFrames[tab])
    b.Size = UDim2.new(1, -8, 0, 24)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Code
    b.TextSize = 12
    b.Text = "  " .. label
    b.TextColor3 = col(off.colors.box)
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.ZIndex = 53
    b.LayoutOrder = #rows + 1
    b.MouseButton1Click:Connect(fn)
end

addToggle("ESP", "master esp", function() return cfg.esp.enabled end, function(v) cfg.esp.enabled = v end)
addToggle("ESP", "box", function() return cfg.esp.box end, function(v) cfg.esp.box = v end)
addToggle("ESP", "skeleton", function() return cfg.esp.skeleton end, function(v) cfg.esp.skeleton = v end)
addToggle("ESP", "health", function() return cfg.esp.health end, function(v) cfg.esp.health = v end)
addToggle("ESP", "name", function() return cfg.esp.name end, function(v) cfg.esp.name = v end)
addToggle("ESP", "distance", function() return cfg.esp.distance end, function(v) cfg.esp.distance = v end)
addToggle("ESP", "team check (global)", function() return cfg.esp.teamCheck end, function(v) cfg.esp.teamCheck = v end)
addToggle("ESP", "snaplines", function() return cfg.esp.snaplines end, function(v) cfg.esp.snaplines = v end)

addToggle("AIMBOT", "master aimbot (hold RMB)", function() return cfg.aim.enabled end, function(v) cfg.aim.enabled = v end)
addNumber("AIMBOT", "fov px", function() return cfg.aim.fov end, function(v) cfg.aim.fov = v end, 20, 800)
addNumber("AIMBOT", "smoothing 0.01-1", function() return cfg.aim.smoothing end, function(v) cfg.aim.smoothing = v end, 0.01, 1)
addCycle("AIMBOT", "bone", function() return cfg.aim.bone end, function(v) cfg.aim.bone = v end, off.bones)
addToggle("AIMBOT", "visibility check", function() return cfg.aim.visCheck end, function(v) cfg.aim.visCheck = v end)
addToggle("AIMBOT", "use mousemoverel", function() return cfg.aim.useMouseMove end, function(v) cfg.aim.useMouseMove = v end)
addToggle("AIMBOT", "triggerbot (T)", function() return cfg.trigger.enabled end, function(v) cfg.trigger.enabled = v end)
addNumber("AIMBOT", "trigger delay ms", function() return cfg.trigger.delayMs end, function(v) cfg.trigger.delayMs = v end, 0, 1000)
addNumber("AIMBOT", "trigger range", function() return cfg.trigger.range end, function(v) cfg.trigger.range = v end, 50, 2000)

addToggle("MISC", "fly IY (F / WASD + Q/E + space/ctrl)", function() return cfg.misc.fly end, function(v) cfg.misc.fly = v end)
addNumber("MISC", "fly speed (studs/s)", function() return cfg.misc.flySpeed end, function(v) cfg.misc.flySpeed = v end, 10, 300)
addToggle("MISC", "fov circle", function() return cfg.misc.fovCircle end, function(v) cfg.misc.fovCircle = v end)
addToggle("MISC", "radar", function() return cfg.misc.radar end, function(v) cfg.misc.radar = v end)

local keyList = { "Insert", "Home", "RightShift", "F1", "F2", "T", "F", "Q", "E" }
addCycle("CONFIG", "menu key", function() return cfg.hotkeys.menu end, function(v) cfg.hotkeys.menu = v end, keyList)
addCycle("CONFIG", "trigger key", function() return cfg.hotkeys.trigger end, function(v) cfg.hotkeys.trigger = v end, keyList)
addCycle("CONFIG", "fly key", function() return cfg.hotkeys.fly end, function(v) cfg.hotkeys.fly = v end, keyList)
addButton("CONFIG", "guardar JSON", saveConfig)
addButton("CONFIG", "cargar JSON", loadConfig)
addButton("CONFIG", "reset", function() merge(cfg, DEFAULTS); refresh(); setStatus("reset") end)

local statusLabel = Instance.new("TextLabel", tabFrames.CONFIG)
statusLabel.Size = UDim2.new(1, -8, 0, 24)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Code
statusLabel.TextSize = 11
statusLabel.TextColor3 = Color3.fromRGB(150, 150, 160)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.ZIndex = 53
statusLabel.LayoutOrder = 99
statusLabel.Text = "  listo"

refresh = function()
    for _, r in ipairs(rows) do r.update() end
    fovFrame.Size = UDim2.fromOffset(cfg.aim.fov * 2, cfg.aim.fov * 2)
end
setStatus = function(s) statusLabel.Text = "  " .. s end

-- Draggable menu.
local dragging, dragStart, startPos = false, nil, nil
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, dragStart, startPos = true, input.Position, main.Position
    end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and dragStart and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                  startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- Draw objects ---------------------------------------------------------------
local function newFrame(parent, color, z)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.BackgroundColor3 = color
    f.ZIndex = z or 10
    f.Visible = false
    f.Parent = parent
    return f
end
local function newLine(parent, color)
    local f = newFrame(parent, color, 11)
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    return f
end
local function setLine(f, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then f.Visible = false; return end
    f.Visible = true
    f.Size = UDim2.fromOffset(math.max(len, 1), 1.5)
    f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
    f.Rotation = math.deg(math.atan2(dy, dx))
end
local function newText(parent)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Font = Enum.Font.Code
    t.TextSize = 12
    t.TextColor3 = col(off.colors.text)
    t.TextStrokeTransparency = 0.4
    t.TextStrokeColor3 = Color3.new(0, 0, 0)
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextYAlignment = Enum.TextYAlignment.Bottom
    t.ZIndex = 12
    t.Visible = false
    t.Parent = parent
    return t
end

local BOX_N, SKELETON_N = 4, #off.skeleton
local objects = {}
local function makeObjects()
    local o = {
        box = {}, skel = {},
        hpbg = newFrame(layer, Color3.fromRGB(30, 30, 35), 12),
        hp = newFrame(layer, col(off.colors.box), 13),
        label = newText(layer),
        snap = newLine(layer, col(off.colors.enemy)),
    }
    for i = 1, BOX_N do o.box[i] = newLine(layer, col(off.colors.box)) end
    for i = 1, SKELETON_N do o.skel[i] = newLine(layer, col(off.colors.skel)) end
    return o
end
local function hideObjects(o)
    for _, f in ipairs(o.box) do f.Visible = false end
    for _, f in ipairs(o.skel) do f.Visible = false end
    o.hpbg.Visible, o.hp.Visible = false, false
    o.label.Visible, o.snap.Visible = false, false
end

-- Radar dots are independent of the ESP master toggle (separate MISC tab).
local radarDots = {}
local function radarDot(p)
    local d = radarDots[p]
    if not d then
        d = newFrame(radarFrame, col(off.colors.enemy), 12)
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.Size = UDim2.fromOffset(4, 4)
        radarDots[p] = d
    end
    return d
end
local function dropObjects(p)
    local o = objects[p]
    if o then
        for _, f in ipairs(o.box) do f:Destroy() end
        for _, f in ipairs(o.skel) do f:Destroy() end
        o.hpbg:Destroy(); o.hp:Destroy(); o.label:Destroy(); o.snap:Destroy()
        objects[p] = nil
    end
    if radarDots[p] then radarDots[p]:Destroy(); radarDots[p] = nil end
end
Players.PlayerRemoving:Connect(dropObjects)

local function drawRadar()
    radarFrame.Visible = cfg.misc.radar
    local myChar = lp.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not cfg.misc.radar or not myHrp then
        for _, d in pairs(radarDots) do d.Visible = false end
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        local d = radarDot(p)
        local char = p.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if p == lp or not hrp or not hum or hum.Health <= 0 or isTeammate(p) then
            d.Visible = false
        else
            local rel = hrp.Position - myHrp.Position
            d.Visible = true
            d.Position = UDim2.fromOffset(
                math.clamp(70 + rel.X * 0.5, 2, 138),
                math.clamp(70 + rel.Z * 0.5, 2, 138))
        end
    end
end

-- ESP ------------------------------------------------------------------------
local function boxCorners(char, cam)
    local ok, cf, size = pcall(function() return char:GetBoundingBox() end)
    if not ok or not cf then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil end
        cf, size = hrp.CFrame, Vector3.new(2, 3, 1)
    end
    local pts = 0
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                local w = cf:PointToWorldSpace(Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2))
                local sp, on = cam:WorldToViewportPoint(w)
                if on and sp.Z > 0 then
                    pts = pts + 1
                    if sp.X < minX then minX = sp.X end
                    if sp.Y < minY then minY = sp.Y end
                    if sp.X > maxX then maxX = sp.X end
                    if sp.Y > maxY then maxY = sp.Y end
                end
            end
        end
    end
    if pts < 4 then return nil end
    return minX, minY, maxX, maxY
end

local function drawESP()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local vs = cam.ViewportSize
    local center = Vector2.new(vs.X / 2, vs.Y / 2)

    fovFrame.Visible = cfg.misc.fovCircle
    fovFrame.Size = UDim2.fromOffset(cfg.aim.fov * 2, cfg.aim.fov * 2)

    if not cfg.esp.enabled then
        for _, o in pairs(objects) do hideObjects(o) end
        return
    end

    local myChar = lp.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")

    for _, p in ipairs(Players:GetPlayers()) do
        local o = objects[p]
        local char = p.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local dead = (not hum) or hum.Health <= 0
        local enemy = (p ~= lp) and not isTeammate(p)
        if not char or dead or not enemy then
            if o then hideObjects(o) end
        else
            if not o then o = makeObjects(); objects[p] = o end
            local minX, minY, maxX, maxY = boxCorners(char, cam)
            if not minX then
                hideObjects(o)
            else
                local h = maxY - minY
                if cfg.esp.box then
                    setLine(o.box[1], minX, minY, maxX, minY)
                    setLine(o.box[2], maxX, minY, maxX, maxY)
                    setLine(o.box[3], maxX, maxY, minX, maxY)
                    setLine(o.box[4], minX, maxY, minX, minY)
                else
                    for _, f in ipairs(o.box) do f.Visible = false end
                end

                if cfg.esp.skeleton then
                    for i, pair in ipairs(off.skeleton) do
                        local a, b = resolve(char, pair[1]), resolve(char, pair[2])
                        if a and b then
                            local sa, oa = cam:WorldToViewportPoint(a.Position)
                            local sb, ob = cam:WorldToViewportPoint(b.Position)
                            if oa and ob and sa.Z > 0 and sb.Z > 0 then
                                setLine(o.skel[i], sa.X, sa.Y, sb.X, sb.Y)
                            else
                                o.skel[i].Visible = false
                            end
                        else
                            o.skel[i].Visible = false
                        end
                    end
                else
                    for _, f in ipairs(o.skel) do f.Visible = false end
                end

                if cfg.esp.health and hum.MaxHealth > 0 then
                    local frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                    o.hpbg.Visible, o.hp.Visible = true, true
                    o.hpbg.Size = UDim2.fromOffset(3, math.max(h, 1))
                    o.hpbg.Position = UDim2.fromOffset(minX - 6, minY)
                    o.hp.Size = UDim2.fromOffset(3, math.max(h * frac, 1))
                    o.hp.Position = UDim2.fromOffset(minX - 6, minY + h * (1 - frac))
                    o.hp.BackgroundColor3 = Color3.fromRGB(255 * (1 - frac), 255 * frac, 40)
                else
                    o.hpbg.Visible, o.hp.Visible = false, false
                end

                local text = ""
                if cfg.esp.name then text = p.Name end
                if cfg.esp.distance and myHrp then
                    local hrp = char:FindFirstChild("HumanoidRootPart")
                    local d = hrp and (hrp.Position - myHrp.Position).Magnitude or 0
                    text = (text ~= "" and text .. " | " or "") .. string.format("%dm", math.floor(d + 0.5))
                end
                if text ~= "" then
                    o.label.Visible = true
                    o.label.Text = text
                    o.label.Size = UDim2.fromOffset(200, 14)
                    o.label.Position = UDim2.fromOffset(minX, minY - 14)
                else
                    o.label.Visible = false
                end

                if cfg.esp.snaplines then
                    setLine(o.snap, center.X, vs.Y, (minX + maxX) / 2, maxY)
                else
                    o.snap.Visible = false
                end
            end
        end
    end
end

-- Aimbot / triggerbot --------------------------------------------------------
local function visible(part)
    local cam = workspace.CurrentCamera
    local hit = workspace:Raycast(cam.CFrame.Position, part.Position - cam.CFrame.Position, newParams())
    if not hit then return true end
    local model = part:FindFirstAncestorOfClass("Model")
    return model ~= nil and hit.Instance:IsDescendantOf(model)
end
local function bestTarget()
    local cam = workspace.CurrentCamera
    if not cam then return nil end
    local c = cam.ViewportSize / 2
    local best, bestD = nil, cfg.aim.fov
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= lp and not isTeammate(p) then
            local char = p.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local part = char and resolve(char, cfg.aim.bone)
            if hum and hum.Health > 0 and part then
                local sp, on = cam:WorldToViewportPoint(part.Position)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - c).Magnitude
                    if d < bestD and (not cfg.aim.visCheck or visible(part)) then
                        best, bestD = part, d
                    end
                end
            end
        end
    end
    return best
end
local function applyAim(part)
    local cam = workspace.CurrentCamera
    local a = math.clamp(cfg.aim.smoothing, 0.01, 1)
    if cfg.aim.useMouseMove and mousemoverel then
        local sp = cam:WorldToViewportPoint(part.Position)
        local c = cam.ViewportSize / 2
        mousemoverel((sp.X - c.X) * a, (sp.Y - c.Y) * a)
    else
        cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, part.Position), a)
    end
end

local lastShot = 0
local function fireOnce(x, y)
    if mouse1click then
        pcall(mouse1click)
    elseif mouse1press and mouse1release then
        pcall(mouse1press)
        task.defer(function() pcall(mouse1release) end)
    else
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.defer(function() vim:SendMouseButtonEvent(x, y, 0, false, game, 0) end)
        end)
    end
end
local function trigger()
    if not cfg.trigger.enabled then return end
    local cam = workspace.CurrentCamera
    if not cam then return end
    if os.clock() - lastShot < cfg.trigger.delayMs / 1000 then return end
    local c = cam.ViewportSize / 2
    local ray = cam:ViewportPointToRay(c.X, c.Y, 0)
    local hit = workspace:Raycast(ray.Origin, ray.Direction * cfg.trigger.range, newParams())
    if not hit then return end
    local model = hit.Instance:FindFirstAncestorOfClass("Model")
    local p = model and Players:GetPlayerFromCharacter(model)
    if not p or p == lp or isTeammate(p) then return end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return end
    lastShot = os.clock()
    fireOnce(c.X, c.Y)
end

-- Fly ------------------------------------------------------------------------
-- Infinite Yield FE port (EdgeIY/infiniteyield, MIT), sFLY() / mobilefly():
--   BV + BG on HumanoidRootPart, 9e9 MaxForce/MaxTorque, BG.P = 9e4 / BG.D = 50,
--   BG.CFrame = camera.CFrame every frame, Humanoid.PlatformStand = true,
--   velocity built from camera look/right vectors, Q/E for vertical.
-- IY's speed is `iyflyspeed * 50`; cfg.misc.flySpeed is already studs/s, so
-- `flySpeed 60` is IY's `;flyspeed 1.2`. No math.huge: 9e9 is deliberate.
local flyBV, flyBG, flyHumanoid = nil, nil, nil

local function stopFly()
    if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
    if flyBG then pcall(function() flyBG:Destroy() end); flyBG = nil end
    if flyHumanoid then
        pcall(function() flyHumanoid.PlatformStand = false end)
        flyHumanoid = nil
    end
end

local function updateFly()
    if not cfg.misc.fly then
        if flyBV or flyBG or flyHumanoid then stopFly() end
        return
    end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    -- Re-arm on respawn: root/humanoid instances change, old ones are gone.
    if not flyBV or not flyBG or flyBV.Parent ~= hrp or flyBG.Parent ~= hrp or flyHumanoid ~= hum then
        stopFly()
        flyBV = Instance.new("BodyVelocity")
        flyBV.Name = "AeroFlyBV"
        flyBV.MaxForce = Vector3.new(off.fly.maxForce, off.fly.maxForce, off.fly.maxForce)
        flyBV.Velocity = Vector3.new(0, 0, 0)
        flyBV.Parent = hrp

        flyBG = Instance.new("BodyGyro")
        flyBG.Name = "AeroFlyBG"
        flyBG.MaxTorque = Vector3.new(off.fly.maxTorque, off.fly.maxTorque, off.fly.maxTorque)
        flyBG.P = off.fly.gyroP
        flyBG.D = off.fly.gyroD
        flyBG.CFrame = hrp.CFrame
        flyBG.Parent = hrp
        flyHumanoid = hum
    end

    hum.PlatformStand = true
    local cam = workspace.CurrentCamera
    flyBG.CFrame = cam.CFrame

    local dir = Vector3.new(0, 0, 0)
    if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
    -- IY uses Q/E for vertical; Space/Ctrl kept as Aero aliases.
    if UIS:IsKeyDown(Enum.KeyCode.E) or UIS:IsKeyDown(Enum.KeyCode.Space) then
        dir = dir + Vector3.new(0, 1, 0)
    end
    if UIS:IsKeyDown(Enum.KeyCode.Q) or UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
        dir = dir - Vector3.new(0, 1, 0)
    end
    flyBV.Velocity = (dir.Magnitude > 0) and (dir.Unit * cfg.misc.flySpeed) or Vector3.new(0, 0, 0)
end

-- Main loop ------------------------------------------------------------------
-- Bound after the Camera render priority so the CFrame write is not overwritten
-- by the default camera scripts on the same frame.
local function step()
    if cfg.aim.enabled and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local part = bestTarget()
        if part then applyAim(part) end
    end
    trigger()
    updateFly()
    drawESP()
    drawRadar()
end
RunService:BindToRenderStep("AeroStep", Enum.RenderPriority.Camera.Value + 10, step)

UIS.InputBegan:Connect(function(input, gpe)
    if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local k = input.KeyCode
    if k == key(cfg.hotkeys.menu) then
        main.Visible = not main.Visible
    elseif k == key(cfg.hotkeys.trigger) then
        cfg.trigger.enabled = not cfg.trigger.enabled
        refresh()
    elseif k == key(cfg.hotkeys.fly) then
        cfg.misc.fly = not cfg.misc.fly
        refresh()
    end
end)

refresh()
setStatus("INSERT abre el menu - todo apagado")
