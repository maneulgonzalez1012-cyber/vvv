--!nocheck
--[[
	Astral :: modules/hitdebug

	cajas de alambre sobre cada parte que el hitbox tocó. sirve para ver de un
	golpe si el expansor está haciendo algo: si la caja no aparece, no hay
	partes infladas, y el problema es el juego (hit detection en servidor) o el
	personaje, no el script.

	toma las partes directo de Hitbox.live, así no duplica el barrido.
]]

local Hitbox = require(script.Parent.Parent.modules.hitbox)
local Mathx = require(script.Parent.Parent.shared.mathx)

local HitDebug = {}
HitDebug.__index = HitDebug

local COLOR = Color3.fromRGB(120, 220, 255)
-- techo de cajas: 20 partes x 15 jugadores son 300 frames, y eso se siente
local MAX_BOXES = 64

function HitDebug.new(renderer, state, hitbox)
	local self = setmetatable({}, HitDebug)
	self.r = renderer
	self.state = state
	self.hitbox = hitbox
	self.pool = setmetatable({}, { __mode = "k" }) -- part -> object
	return self
end

-- tamaño de pantalla de una parte: se proyectan las 8 esquinas de su caja
-- orientada y se saca el hull, igual que el ESP con el modelo entero
local function partBox(cam, part)
	local ok, cf, size = pcall(function()
		return part.CFrame, part.Size
	end)
	if not ok or not cf then
		return nil
	end

	-- un cubo inflado puede tener esquinas detrás de la cámara: el hull ya
	-- descarta las que no proyectan
	return Mathx.projectBox(cam, cf, size)
end

function HitDebug:step(cam)
	local r = self.r
	local want = self.state.hitEnabled and self.state.hitVisual

	if not want then
		if self.shown then
			for _, o in pairs(self.pool) do
				r.hide(o)
			end
			self.shown = false
		end
		return
	end

	self.shown = true
	local vp = cam.ViewportSize
	local boxes = 0

	for part in pairs(self.hitbox.live) do
		local o = self.pool[part]

		if not part.Parent then
			if o then
				r.destroy(o)
				self.pool[part] = nil
			end
			continue
		end

		local minX, minY, maxX, maxY = partBox(cam, part)

		if not minX or maxX < 0 or maxY < 0 or minX > vp.X or minY > vp.Y then
			if o then
				r.hide(o)
			end
			continue
		end

		if not o then
			if boxes >= MAX_BOXES then
				continue
			end
			o = r.newRect()
			self.pool[part] = o
		end
		boxes = boxes + 1

		r.rect(o, minX, minY, maxX - minX, maxY - minY, COLOR, false, 1, 0, true)
	end

	-- partes que salieron del set (restore, muerte, cambio de modo) dejan su
	-- objeto vivo: se apaga lo que no se tocó este frame
	for part, o in pairs(self.pool) do
		if not self.hitbox.live[part] then
			r.hide(o)
		end
	end
end

function HitDebug:destroy()
	for part, o in pairs(self.pool) do
		self.r.destroy(o)
		self.pool[part] = nil
	end
end

return HitDebug
