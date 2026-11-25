--!nocheck
--[[
	Astral :: modules/aim

	cámara solver. elige el hueso más cercano al centro de la pantalla dentro
	del FOV y gira la cámara hacia él con suavizado exponencial (independiente
	del framerate: alpha = 1 - e^(-k*dt)).

	no toca el mouse del sistema ni escribe en el motor: aplica CFrame a
	workspace.CurrentCamera, así que muere completo en unload.

	nota: los scripts de cámara por defecto de Roblox también escriben CFrame
	cada frame; por eso el giro se aplica en RenderStepped y con alpha alto
	el pulso se nota poco. es el mismo compromiso que usa cualquier solver
	de cámara externo.
]]

local PlayersLib = require(script.Parent.Parent.shared.players)
local Mathx = require(script.Parent.Parent.shared.mathx)

local Aim = {}
Aim.__index = Aim

local UIS = game:GetService("UserInputService")

-- px por radián en el plano de la pantalla, derivado del FOV vertical real
local function fovToPixels(degrees, verticalFov, viewportY)
	local halfTan = math.tan(math.rad(math.clamp(degrees, 0.5, 179) * 0.5))
	local camTan = math.tan(math.rad(math.clamp(verticalFov, 1, 179) * 0.5))
	return (halfTan / camTan) * (viewportY * 0.5)
end

function Aim.new(state, renderer)
	local self = setmetatable({}, Aim)
	self.state = state
	self.r = renderer
	self.circle = renderer.newCircle()
	self.held = false
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.IgnoreWater = true
	self.params.RespectCanCollide = false

	self.conns = {}
	self.conns[#self.conns + 1] = UIS.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.held = true
		end
	end)
	self.conns[#self.conns + 1] = UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.held = false
		end
	end)

	return self
end

-- línea de visión: un raycast, ignorando al jugador local y al objetivo
function Aim:visible(camPos, pos, targetChar)
	local filter = {}
	local myChar = PlayersLib.me.Character
	if myChar then
		filter[#filter + 1] = myChar
	end
	if targetChar then
		filter[#filter + 1] = targetChar
	end
	self.params.FilterDescendantsInstances = filter

	local dir = pos - camPos
	local result = workspace:Raycast(camPos, dir, self.params)
	if not result then
		return true
	end
	return (result.Position - camPos).Magnitude >= dir.Magnitude - 0.5
end

function Aim:pick(cam, radius)
	local s = self.state
	local camPos = cam.CFrame.Position
	local vp = cam.ViewportSize
	local centerX, centerY = vp.X * 0.5, vp.Y * 0.5

	local best, bestScore, bestPos = nil, math.huge, nil

	for _, plr in ipairs(PlayersLib.all()) do
		local char = PlayersLib.target(plr, camPos, s.espTeamCheck)

		if char then
			local bone = PlayersLib.bone(char, s.aimBone)
			if bone then
				local sp = cam:WorldToViewportPoint(bone.Position)
				if sp.Z > 0 then
					local dx, dy = sp.X - centerX, sp.Y - centerY
					local d = math.sqrt(dx * dx + dy * dy)
					if d <= radius and d < bestScore then
						if not s.aimWallCheck or self:visible(camPos, bone.Position, char) then
							best, bestScore, bestPos = plr, d, bone.Position
						end
					end
				end
			end
		end
	end

	return best, bestPos
end

function Aim:step(dt)
	local s = self.state
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	local vp = cam.ViewportSize
	local radius = fovToPixels(s.aimFov, cam.FieldOfView or 70, vp.Y)

	-- círculo de FOV: existe siempre, se prende con el toggle y el módulo
	self.r.circle(self.circle, vp.X * 0.5, vp.Y * 0.5, radius,
		s.aimFovCircleColor or Color3.new(1, 1, 1), 1, false, s.aimEnabled and s.aimFovCircle)

	if not s.aimEnabled or not self.held then
		return
	end

	local _, targetPos = self:pick(cam, radius)
	if not targetPos then
		return
	end

	local camPos = cam.CFrame.Position
	local desired = CFrame.lookAt(camPos, targetPos)
	local smooth = math.max(s.aimSmooth or 0, 0)

	if smooth <= 0 then
		cam.CFrame = desired
		return
	end

	-- 20/smooth rad/s de "velocidad" de convergencia; clamp por si dt explota
	local alpha = 1 - math.exp(-(20 / smooth) * math.min(dt, 0.1))
	cam.CFrame = cam.CFrame:Lerp(desired, Mathx.clamp(alpha, 0, 1))
end

function Aim:destroy()
	for i = 1, #self.conns do
		pcall(function()
			self.conns[i]:Disconnect()
		end)
	end
	table.clear(self.conns)
	if self.circle then
		self.r.destroy(self.circle)
		self.circle = nil
	end
end

return Aim
