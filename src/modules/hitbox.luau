--!nocheck
--[[
	Astral :: modules/hitbox

	expansor por eje, con cuatro modos de alcance y hooks por personaje en vez
	de un barrido por timer:

		ChildAdded en el Character  → las partes que streamean después entran solas
		Humanoid.Died               → restaura ese char en el acto
		AncestryChanged en el char  → si sale del workspace, se suelta

	el Size base se captura UNA vez por parte y nunca se pisa, así mover el
	slider compone sobre el original y no sobre el valor ya inflado.

	todo es local: las partes las posee el otro cliente.
]]

local PlayersLib = require(script.Parent.Parent.shared.players)

local Hitbox = {}
Hitbox.__index = Hitbox

-- orden de preferencia por modo
local MODES = {
	all = {
		"HumanoidRootPart", "Head", "Torso",
		"Left Arm", "Right Arm", "Left Leg", "Right Leg",
		"UpperTorso", "LowerTorso",
		"LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot",
	},
	root = { "HumanoidRootPart", "Torso" },
	torso = { "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart" },
	head = { "Head" },
}

Hitbox.MODES = { "all", "torso", "head", "root" }

function Hitbox.new()
	local self = setmetatable({}, Hitbox)
	self.bases = setmetatable({}, { __mode = "k" }) -- part -> Vector3 original
	self.watched = setmetatable({}, { __mode = "k" }) -- char -> true
	self.conns = {} -- char -> { conexiones }
	self.live = setmetatable({}, { __mode = "k" }) -- part -> true, lo que tocamos
	self.dirty = true
	self.state = nil
	return self
end

-- Rayfield entrega los dropdowns como tabla en single mode; el estado
-- guarda un string, pero por si alguien escribe la tabla a mano
local function modeString(v)
	if type(v) == "table" then
		return v[1] or "all"
	end
	if type(v) ~= "string" or MODES[v] == nil then
		return "all"
	end
	return v
end

function Hitbox:settings()
	local s = self.state
	return {
		enabled = s and s.hitEnabled or false,
		mode = modeString(s and s.hitMode),
		visual = s and s.hitVisual ~= false,
		x = (s and s.hitScaleX) or 2,
		y = (s and s.hitScaleY) or 2,
		z = (s and s.hitScaleZ) or 2,
	}
end

-- firma de la configuración actual. si cambia (modo o escala), las partes que
-- quedaron infladas de la config anterior se restauran antes de aplicar la
-- nueva: sin esto, cambiar de "all" a "head" deja brazos y piernas gigantes
function Hitbox:fingerprint(cfg)
	return string.format("%s|%.2f|%.2f|%.2f", cfg.mode, cfg.x, cfg.y, cfg.z)
end

function Hitbox:invalidate()
	self.dirty = true
end

----------------------------------------------------------------------
-- restauración
----------------------------------------------------------------------
function Hitbox:restorePart(part)
	local base = self.bases[part]
	if not base then
		return
	end
	if part.Parent then
		pcall(function()
			part.Size = base
		end)
	end
	self.live[part] = nil
end

function Hitbox:restoreAll()
	for part in pairs(self.live) do
		self:restorePart(part)
	end
	table.clear(self.bases)
	table.clear(self.live)
	self.lastPrint = nil
	self.dirty = true
end

----------------------------------------------------------------------
-- aplicación
----------------------------------------------------------------------
function Hitbox:applyTo(char, cfg)
	local names = MODES[cfg.mode] or MODES.all
	local bases = self.bases
	local touched = 0

	for i = 1, #names do
		local part = char:FindFirstChild(names[i])
		if part and part:IsA("BasePart") then
			local base = bases[part]
			if not base then
				base = part.Size
				bases[part] = base
			end

			local target = Vector3.new(base.X * cfg.x, base.Y * cfg.y, base.Z * cfg.z)
			-- comparar evita escribir Size cada frame: escribir Size despierta
			-- replicación y física en el motor, y con 15 jugadores se nota
			if part.Size ~= target then
				pcall(function()
					part.Size = target
				end)
			end
			self.live[part] = true
			touched = touched + 1
		end
	end

	return touched
end

----------------------------------------------------------------------
-- hooks por personaje
----------------------------------------------------------------------
function Hitbox:unwatch(char)
	local set = self.conns[char]
	if not set then
		return
	end
	for i = 1, #set do
		pcall(function()
			set[i]:Disconnect()
		end)
	end
	self.conns[char] = nil
	self.watched[char] = nil
end

function Hitbox:watch(char)
	if self.watched[char] then
		return
	end
	self.watched[char] = true

	local set = {}
	self.conns[char] = set

	local hum = PlayersLib.humanoid(char)
	if hum then
		set[#set + 1] = hum.Died:Connect(function()
			-- muerto: el cuerpo vuelve a su tamaño y se suelta el personaje
			for part in pairs(self.live) do
				if part:IsDescendantOf(char) then
					self:restorePart(part)
				end
			end
			self:invalidate()
		end)
	end

	set[#set + 1] = char.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			-- parte nueva (accesorio, ragdoll, lo que sea): entra al próximo pase
			self:invalidate()
		end
	end)

	set[#set + 1] = char.AncestryChanged:Connect(function()
		if not char:IsDescendantOf(workspace) then
			for part in pairs(self.live) do
				if part:IsDescendantOf(char) then
					self:restorePart(part)
				end
			end
			self:unwatch(char)
		end
	end)
end

----------------------------------------------------------------------
-- pase
----------------------------------------------------------------------
function Hitbox:step()
	local cfg = self:settings()

	if not cfg.enabled then
		if next(self.live) ~= nil then
			self:restoreAll()
		end
		if next(self.conns) ~= nil then
			for char in pairs(self.conns) do
				self:unwatch(char)
			end
		end
		return 0
	end

	local total = 0

	if self.dirty then
		self.dirty = false
		-- limpiar refs de partes que ya no existen
		for part in pairs(self.bases) do
			if part.Parent == nil then
				self.bases[part] = nil
				self.live[part] = nil
			end
		end
	end

	local print = self:fingerprint(cfg)
	if self.lastPrint ~= nil and self.lastPrint ~= print then
		-- cambio de config: las partes viejas vuelven a su tamaño y la base
		-- se vuelve a capturar limpia
		for part in pairs(self.live) do
			self:restorePart(part)
		end
		table.clear(self.live)
	end
	self.lastPrint = print

	for _, plr in ipairs(PlayersLib.all()) do
		if plr ~= PlayersLib.me then
			local char = plr.Character
			local hum = PlayersLib.humanoid(char)

			if char and hum and hum.Health > 0 then
				self:watch(char)
				total = total + self:applyTo(char, cfg)
			elseif char and self.watched[char] then
				self:unwatch(char)
			end
		end
	end

	return total
end

function Hitbox:destroy()
	for char in pairs(self.conns) do
		self:unwatch(char)
	end
	self:restoreAll()
end

return Hitbox
