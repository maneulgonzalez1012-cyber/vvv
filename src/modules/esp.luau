--!nocheck
--[[
	Astral :: modules/esp

	un pool de Drawing objects por jugador, creados una vez y reusados.
	nada se destruye en el loop: solo se apaga. el único Destroy pasa en
	PlayerRemoving o en unload, así no hay churn de objetos ni fugas.

	el hull sale de las 8 esquinas del bounding box del modelo, no de
	GetBoundingBox crudo: así la caja no se estira cuando el pj gira.
]]

local Mathx = require(script.Parent.Parent.shared.mathx)
local PlayersLib = require(script.Parent.Parent.shared.players)

local Esp = {}
Esp.__index = Esp

local HP_LOW = Color3.fromRGB(225, 55, 55)
local HP_HIGH = Color3.fromRGB(90, 225, 120)
local SHADOW = Color3.fromRGB(0, 0, 0)
local DIST_COLOR = Color3.fromRGB(215, 215, 222)
local WHITE = Color3.new(1, 1, 1)

function Esp.new(renderer, state)
	local self = setmetatable({}, Esp)
	self.r = renderer
	self.state = state
	self.pool = {}
	self.anyVisible = false
	self.conn = PlayersLib.service.PlayerRemoving:Connect(function(plr)
		self:forget(plr)
	end)
	return self
end

function Esp:create()
	local r = self.r
	local e = {
		fill = r.newRect(),
		box = r.newRect(),
		hpBack = r.newRect(),
		hpFill = r.newRect(),
		tracer = r.newRect(),
		label = r.newText(),
		dist = r.newText(),
	}
	-- orden de creación == orden de dibujo en Drawing: fill debajo del borde
	e.rects = { e.fill, e.box, e.hpBack, e.hpFill, e.tracer }
	e.texts = { e.label, e.dist }
	e.visible = false
	return e
end

function Esp:get(plr)
	local e = self.pool[plr]
	if not e then
		e = self:create()
		self.pool[plr] = e
	end
	return e
end

function Esp:forget(plr)
	local e = self.pool[plr]
	if not e then
		return
	end
	for _, o in ipairs(e.rects) do
		self.r.destroy(o)
	end
	for _, o in ipairs(e.texts) do
		self.r.destroy(o)
	end
	self.pool[plr] = nil
end

function Esp:hide(e)
	if not e.visible then
		return
	end
	for _, o in ipairs(e.rects) do
		self.r.hide(o)
	end
	for _, o in ipairs(e.texts) do
		self.r.hide(o)
	end
	e.visible = false
end

function Esp:hideAll()
	for _, e in pairs(self.pool) do
		self:hide(e)
	end
	self.anyVisible = false
end

-- un solo pase por frame; devuelve la cantidad de cajas dibujadas
function Esp:step(cam)
	local r = self.r
	local s = self.state

	if not s.espEnabled then
		if self.anyVisible then
			self:hideAll()
		end
		return 0
	end

	local camPos = cam.CFrame.Position
	local vp = cam.ViewportSize
	local maxDist = s.espMaxDistance
	local boxColor = s.espBoxColor or WHITE
	local nameColor = s.espNameColor or WHITE
	local fillColor = s.espFillColor or SHADOW
	local drawn = 0

	for _, plr in ipairs(PlayersLib.all()) do
		local char, hum, root, dist = PlayersLib.target(plr, camPos, s.espTeamCheck)
		local e = self.pool[plr]

		if not char or dist > maxDist then
			if e then
				self:hide(e)
			end
			continue
		end

		local ok, cf, size = pcall(char.GetBoundingBox, char)
		local minX, minY, maxX, maxY
		if ok and cf then
			minX, minY, maxX, maxY = Mathx.projectBox(cam, cf, size)
		end

		-- fuera de pantalla o detrás: se apaga, no se dibuja
		if not minX or maxX < 0 or maxY < 0 or minX > vp.X or minY > vp.Y then
			if e then
				self:hide(e)
			end
			continue
		end

		e = e or self:get(plr)
		e.visible = true
		drawn = drawn + 1

		local w, h = maxX - minX, maxY - minY
		local cx = (minX + maxX) * 0.5

		r.rect(e.box, minX, minY, w, h, boxColor, false, 1, 0, s.espBox)

		if s.espFill then
			r.rect(e.fill, minX, minY, w, h, fillColor, true, 1, 0.82, true)
		else
			r.hide(e.fill)
		end

		if s.espHealth then
			local frac = Mathx.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			local barX, barW = minX - 7, 3
			local filled = math.max(h * frac, 1)
			r.rect(e.hpBack, barX - 1, minY - 1, barW + 2, h + 2, SHADOW, true, 1, 0.45, true)
			r.rect(e.hpFill, barX, minY + (h - filled), barW, filled,
				Mathx.lerpColor(HP_LOW, HP_HIGH, frac), true, 1, 0, true)
		else
			r.hide(e.hpBack)
			r.hide(e.hpFill)
		end

		r.text(e.label, PlayersLib.nameOf(plr), cx, minY - 19, 14, nameColor, s.espName)
		r.text(e.dist, string.format("%d studs", math.floor(dist + 0.5)), cx, maxY + 3, 13,
			DIST_COLOR, s.espDistance)

		-- tracer: rect de 1px desde el borde inferior al centro de la caja.
		-- rect rotado no existe, así que es horizontal anclado abajo
		if s.espTracer then
			local fromX = vp.X * 0.5
			r.rect(e.tracer, math.min(fromX, cx), vp.Y - 2,
				math.max(math.abs(cx - fromX), 1), 1, boxColor, true, 1, 0, true)
		else
			r.hide(e.tracer)
		end
	end

	self.anyVisible = drawn > 0
	return drawn
end

function Esp:destroy()
	if self.conn then
		pcall(function()
			self.conn:Disconnect()
		end)
		self.conn = nil
	end
	for plr in pairs(self.pool) do
		self:forget(plr)
	end
end

return Esp
