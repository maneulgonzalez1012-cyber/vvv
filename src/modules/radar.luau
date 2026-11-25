--!nocheck
--[[
	Astral :: modules/radar

	mapa de posiciones en 2D, esquina superior derecha. proyecta el mundo
	sobre el plano XZ relativo a la cámara (forward/right), así el radar gira
	con la vista igual que en los shooters.

	paneles: un Square de fondo + un punto por jugador, reusados del pool.
]]

local PlayersLib = require(script.Parent.Parent.shared.players)
local Mathx = require(script.Parent.Parent.shared.mathx)

local Radar = {}
Radar.__index = Radar

local SIZE = 150
local MARGIN = 16
local RANGE = 250 -- studs que entran en el radio del radar
local SELF_COLOR = Color3.fromRGB(120, 255, 160)
local ENEMY_COLOR = Color3.fromRGB(255, 90, 90)
local BACK_COLOR = Color3.fromRGB(12, 12, 16)

function Radar.new(renderer, state)
	local self = setmetatable({}, Radar)
	self.r = renderer
	self.state = state
	self.pool = {}
	self.back = renderer.newRect()
	self.backline = renderer.newRect()
	self.selfDot = renderer.newRect()
	self.conn = PlayersLib.service.PlayerRemoving:Connect(function(plr)
		self:forget(plr)
	end)
	return self
end

function Radar:dot(plr)
	local d = self.pool[plr]
	if not d then
		d = self.r.newRect()
		self.pool[plr] = d
	end
	return d
end

function Radar:forget(plr)
	local d = self.pool[plr]
	if d then
		self.r.destroy(d)
		self.pool[plr] = nil
	end
end

function Radar:step(cam)
	local r = self.r
	local s = self.state

	if not s.radarEnabled then
		if self.shown then
			r.hide(self.back)
			r.hide(self.backline)
			r.hide(self.selfDot)
			for _, d in pairs(self.pool) do
				r.hide(d)
			end
			self.shown = false
		end
		return
	end

	self.shown = true

	local vp = cam.ViewportSize
	local cx = vp.X - MARGIN - SIZE * 0.5
	local cy = MARGIN + SIZE * 0.5

	r.rect(self.back, cx - SIZE * 0.5, cy - SIZE * 0.5, SIZE, SIZE, BACK_COLOR, true, 1, 0.35, true)
	r.rect(self.backline, cx - SIZE * 0.5, cy - SIZE * 0.5, SIZE, SIZE,
		Color3.fromRGB(80, 80, 100), false, 1, 0, true)
	r.rect(self.selfDot, cx - 1, cy - 1, 2, 2, SELF_COLOR, true, 1, 0, true)

	-- base del radar: la cámara mira hacia -Z en su espacio local
	local look = cam.CFrame.LookVector
	local right = cam.CFrame.RightVector
	local fwdFlat = Vector3.new(look.X, 0, look.Z)
	local rightFlat = Vector3.new(right.X, 0, right.Z)

	if fwdFlat.Magnitude < 1e-3 then
		fwdFlat = Vector3.new(0, 0, -1)
	else
		fwdFlat = fwdFlat.Unit
	end
	if rightFlat.Magnitude < 1e-3 then
		rightFlat = Vector3.new(1, 0, 0)
	else
		rightFlat = rightFlat.Unit
	end

	local camPos = cam.CFrame.Position
	local scale = (SIZE * 0.5) / RANGE
	local teamCheck = s.espTeamCheck

	for _, plr in ipairs(PlayersLib.all()) do
		local _, _, root = PlayersLib.target(plr, nil, teamCheck)
		local dot = self.pool[plr]

		if not root then
			if dot then
				r.hide(dot)
			end
			continue
		end

		local delta = root.Position - camPos
		local forward = delta.X * fwdFlat.X + delta.Z * fwdFlat.Z
		local side = delta.X * rightFlat.X + delta.Z * rightFlat.Z

		local x = Mathx.clamp(side * scale, -SIZE * 0.5 + 2, SIZE * 0.5 - 2)
		local y = Mathx.clamp(-forward * scale, -SIZE * 0.5 + 2, SIZE * 0.5 - 2)

		dot = dot or self:dot(plr)
		r.rect(dot, cx + x - 2, cy + y - 2, 4, 4, ENEMY_COLOR, true, 1, 0, true)
	end
end

function Radar:destroy()
	if self.conn then
		pcall(function()
			self.conn:Disconnect()
		end)
		self.conn = nil
	end
	pcall(function()
		self.r.destroy(self.back)
		self.r.destroy(self.backline)
		self.r.destroy(self.selfDot)
	end)
	for plr in pairs(self.pool) do
		self:forget(plr)
	end
end

return Radar
