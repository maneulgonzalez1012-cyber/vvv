--!nocheck
--[[
	Astral :: modules/hitbox

	agranda el Size de las partes del personaje en el cliente.
	las partes las posee el otro jugador: el cambio es local, así que esto
	sirve donde el hit detection corre del lado del cliente.

	el Size original se guarda la primera vez que se ve la parte y nunca se
	sobreescribe: así cambiar la escala no compone multiplicaciones.
]]

local PlayersLib = require(script.Parent.Parent.shared.players)

local Hitbox = {}
Hitbox.__index = Hitbox

local BODY_PARTS = {
	"HumanoidRootPart", "Head", "Torso",
	"Left Arm", "Right Arm", "Left Leg", "Right Leg",
	"UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
}

function Hitbox.new(state, limits)
	local self = setmetatable({}, Hitbox)
	self.state = state
	self.interval = limits.interval or 0.5
	self.maxPlayers = limits.maxPlayers or 30
	self.originals = setmetatable({}, { __mode = "k" })
	self.nextPass = 0
	self.applied = {}
	return self
end

function Hitbox:restore()
	for part, size in pairs(self.originals) do
		if part.Parent then
			pcall(function()
				part.Size = size
			end)
		end
	end
	table.clear(self.originals)
	table.clear(self.applied)
	self.nextPass = 0
end

-- fuerza un pase en el siguiente frame aunque el throttle no lo deje
function Hitbox:invalidate()
	self.nextPass = 0
end

function Hitbox:parts(char, rootOnly)
	if rootOnly then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return { root }
		end
		return nil
	end

	local out = {}
	for i = 1, #BODY_PARTS do
		local part = char:FindFirstChild(BODY_PARTS[i])
		if part and part:IsA("BasePart") then
			out[#out + 1] = part
		end
	end
	if #out == 0 then
		return nil
	end
	return out
end

function Hitbox:applyTo(char, scale, rootOnly)
	local parts = self:parts(char, rootOnly)
	if not parts then
		return 0
	end

	local original = self.originals
	local touched = 0

	for i = 1, #parts do
		local part = parts[i]
		local base = original[part]
		if not base then
			base = part.Size
			original[part] = base
		end
		local target = base * scale
		if part.Size ~= target then
			pcall(function()
				part.Size = target
			end)
		end
		touched = touched + 1
	end

	return touched
end

function Hitbox:step()
	local s = self.state

	if not s.hitEnabled then
		if next(self.originals) ~= nil then
			self:restore()
		end
		return
	end

	local now = os.clock()
	if now < self.nextPass then
		return
	end
	self.nextPass = now + self.interval

	-- suelta referencias de partes de personajes que ya murieron o se
	-- respawnearon; sin esto el mapa de originals crece toda la partida
	for part in pairs(self.originals) do
		if part.Parent == nil then
			self.originals[part] = nil
		end
	end

	local scale = math.max(s.hitScale or 1, 1)
	local rootOnly = s.hitRootOnly
	local budget = self.maxPlayers
	local count = 0

	for _, plr in ipairs(PlayersLib.all()) do
		if count >= budget then
			break
		end
		if plr ~= PlayersLib.me then
			local char = plr.Character
			local hum = PlayersLib.humanoid(char)
			if char and hum and hum.Health > 0 then
				self:applyTo(char, scale, rootOnly)
				count = count + 1
			end
		end
	end
end

function Hitbox:destroy()
	self:restore()
end

return Hitbox
