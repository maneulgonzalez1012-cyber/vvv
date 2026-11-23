-- features/move.lua
-- Movement, all local. Nothing here fires a remote, so none of it is visible to
-- the server beyond the normal position updates a fast player already sends.
-- WalkSpeed is capped well under Roblox's anti-teleport threshold, and fly is a
-- low, smooth body-velocity push instead of a CFrame teleport loop.

local Net = require("core/net")

local Move = {}

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

Move.base_walk = 16
Move.base_jump = 50

Move.speed = false
Move.speed_value = 40
Move.jump = false
Move.jump_value = 80
Move.noclip = false
Move.fly = false
Move.fly_value = 60

local conns = {}
local flyBody = nil
local flyGyro = nil
local flyConn = nil

local function clearConns()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
end

-- Noclip used to add a fresh Stepped connection every time the toggle was
-- switched on, so on/off/on left two loops writing every part each frame and
-- the final "off" only cleared the last one. One connection, created once,
-- reading the toggle: flipping it now means flipping a boolean.
local noclipConn = nil
local function ensure_noclip_conn()
    if noclipConn then return end
    noclipConn = RunService.Stepped:Connect(function()
        if not Move.noclip then return end
        local c = Net.Player.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
        end
    end)
end

local function humanoid()
    return Net.humanoid()
end

function Move.apply_speed()
    local hum = humanoid()
    if not hum then return end
    hum.WalkSpeed = Move.speed and Move.speed_value or Move.base_walk
end

function Move.apply_jump()
    local hum = humanoid()
    if not hum then return end
    hum.JumpPower = Move.jump and Move.jump_value or Move.base_jump
    hum.UseJumpPower = true
end

-- Noclip: flip CanCollide on every body part each frame. It is the classic
-- approach and the least destructive one - no part is deleted, nothing is
-- reparented, so turning it off restores the character exactly.
function Move.set_noclip(state)
    Move.noclip = state
    if not state then
        local char = Net.Player.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
            end
        end
        return
    end
    if not Net.Player.Character then return end
    ensure_noclip_conn()
end

-- Fly: a BodyVelocity towards the camera's look vector plus a BodyGyro to hold
-- the character upright. Velocity, not CFrame, so the server sees ordinary
-- movement and the player can be shot at normally.
function Move.set_fly(state)
    Move.fly = state
    local char = Net.Player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
    if flyBody then pcall(function() flyBody:Destroy() end); flyBody = nil end
    if flyGyro then pcall(function() flyGyro:Destroy() end); flyGyro = nil end
    if not state or not root then return end

    flyBody = Instance.new("BodyVelocity")
    flyBody.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    flyBody.Velocity = Vector3.zero
    flyBody.Parent = root

    flyGyro = Instance.new("BodyGyro")
    flyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    flyGyro.P = 1000
    flyGyro.Parent = root

    if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
    flyConn = RunService.RenderStepped:Connect(function()
        if not Move.fly then return end
        local c = Net.Player.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not r or not cam or not flyBody then return end
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
        flyBody.Velocity = dir.Magnitude > 0 and dir.Unit * Move.fly_value or Vector3.zero
        flyGyro.CFrame = CFrame.new(Vector3.zero, cam.CFrame.LookVector)
    end)
end

function Move.fly_supported()
    -- fly rides on body movers, which the game's own antigrav areas also use;
    -- if the character has a Humanoid the movers will work.
    return humanoid() ~= nil
end

function Move.reset()
    Move.speed = false
    Move.jump = false
    Move.noclip = false
    Move.fly = false
    clearConns()
    if flyConn then pcall(function() flyConn:Disconnect() end); flyConn = nil end
    if flyBody then pcall(function() flyBody:Destroy() end); flyBody = nil end
    if flyGyro then pcall(function() flyGyro:Destroy() end); flyGyro = nil end
    Move.apply_speed()
    Move.apply_jump()
end

-- Re-apply on respawn: the character is replaced, so the old humanoid's values
-- die with it. Everything is idempotent, so calling this twice is harmless.
Net.Player.CharacterAdded:Connect(function()
    task.wait(1)
    if Move.speed then Move.apply_speed() end
    if Move.jump then Move.apply_jump() end
    if Move.fly then Move.set_fly(true) end
    if Move.noclip then Move.set_noclip(true) end
end)

return Move
