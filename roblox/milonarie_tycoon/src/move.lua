--[[
	Aero :: Milonarie Tycoon :: movimiento

	Speed, fly, noclip, infinite jump y anti-AFK.
	Todo pasa por el Humanoid y el HumanoidRootPart: el personaje es propiedad
	del cliente, asi que los cambios de velocidad y posicion los acepta el server.
]]

Aero = Aero or {}
Aero.move = {}

local move = Aero.move
local util = Aero.util

local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

move.originalSpeed = nil

function move.applySpeed()
	local hum = util.getHumanoid()
	if not hum then
		return false
	end
	if move.originalSpeed == nil then
		move.originalSpeed = hum.WalkSpeed
	end
	hum.WalkSpeed = Aero.config.move.speed
	return true
end

function move.resetSpeed()
	local hum = util.getHumanoid()
	if not hum then
		return false
	end
	hum.WalkSpeed = move.originalSpeed or 16
	move.originalSpeed = nil
	return true
end

function move.startFly()
	move.flyConn = RunService.RenderStepped:Connect(function()
		if not Aero.config.move.flyEnabled then
			return
		end
		local char = util.getCharacter()
		if not char then
			return
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		local cam = workspace.CurrentCamera
		if not root or not cam then
			return
		end
		local dir = Vector3.new(0, 0, 0)
		if UIS:IsKeyDown(Enum.KeyCode.W) then
			dir = dir + cam.CFrame.LookVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.S) then
			dir = dir - cam.CFrame.LookVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.D) then
			dir = dir + cam.CFrame.RightVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.A) then
			dir = dir - cam.CFrame.RightVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then
			dir = dir + Vector3.new(0, 1, 0)
		end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
			dir = dir - Vector3.new(0, 1, 0)
		end
		local speed = Aero.config.move.flySpeed
		if dir.Magnitude > 0 then
			root.AssemblyLinearVelocity = dir.Unit * speed
		else
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		end
	end)
end

function move.startNoclip()
	move.noclipConn = RunService.RenderStepped:Connect(function()
		if not Aero.config.move.noclip then
			return
		end
		local char = util.getCharacter()
		if not char then
			return
		end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)
end

function move.startInfiniteJump()
	move.jumpConn = UIS.JumpRequest:Connect(function()
		if not Aero.config.move.infiniteJump then
			return
		end
		local hum = util.getHumanoid()
		if not hum then
			return
		end
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
end

function move.startAntiAfk()
	move.afkConn = RunService.Heartbeat:Connect(function()
		if not Aero.config.move.antiAfk then
			return
		end
		local char = util.getCharacter()
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Sit = false
		end
	end)
	local ok, virtualUser = pcall(function()
		return game:GetService("VirtualUser")
	end)
	if ok and virtualUser then
		pcall(function()
			virtualUser:CaptureController()
		end)
	end
end

function move.teleportTo(targetCFrame)
	local root = util.getRootPart()
	if not root then
		return false
	end
	root.CFrame = targetCFrame
	return true
end

function move.findTycoon()
	-- Busca el base del jugador: hijo del workspace con nombre de tycoon/base/plot
	-- y, dentro, una BasePart.
	local player = util.getPlayer()
	local origin = player and player.Position or Vector3.new(0, 0, 0)
	local best, bestDist
	for _, inst in ipairs(workspace:GetChildren()) do
		local n = string.lower(inst.Name)
		if string.find(n, "tycoon", 1, true)
			or string.find(n, "base", 1, true)
			or string.find(n, "plot", 1, true) then
			local part = nil
			if inst:IsA("BasePart") then
				part = inst
			else
				part = inst:FindFirstChildWhichIsA("BasePart", true)
			end
			if part then
				local d = (part.Position - origin).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = part, d
				end
			end
		end
	end
	return best
end

function move.teleportToTycoon()
	local part = move.findTycoon()
	if not part then
		util.log("no se encontro base/tycoon en el workspace")
		return false
	end
	return move.teleportTo(part.CFrame + Vector3.new(0, 4, 0))
end

function move.teleportToMoney()
	local root = util.getRootPart()
	if not root then
		return false
	end
	if #Aero.farm.moneyParts == 0 then
		Aero.farm.scanWorld()
	end
	local part = Aero.farm.nearestMoneyPart(root.Position)
	if not part then
		util.log("no hay partes de dinero cerca")
		return false
	end
	return move.teleportTo(part.CFrame + Vector3.new(0, 3, 0))
end

function move.teleportToPlayer(target)
	local root = util.getRootPart()
	local char = target and target.Character
	if not root or not char then
		return false
	end
	local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if not head then
		return false
	end
	return move.teleportTo(head.CFrame + Vector3.new(0, 3, 0))
end
