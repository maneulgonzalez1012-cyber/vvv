--!nocheck
--[[
	Astral :: modules/diag

	un renglón en la pestaña Misc que dice qué está pasando de verdad:
	renderer, jugadores vistos, cajas dibujadas, partes infladas.

	existe porque "no hace nada" no dice si el script murió, si el juego no
	expone personajes o si el hitbox no tiene a quién agrandar. con esto se
	ve en un segundo.
]]

local PlayersLib = require(script.Parent.Parent.shared.players)

local Diag = {}
Diag.__index = Diag

local INTERVAL = 1

function Diag.new(renderer, state, counts)
	local self = setmetatable({}, Diag)
	self.state = state
	self.counts = counts -- { esp = fn() -> n, hit = fn() -> n }
	self.next = 0
	self.line = nil
	self.renderer = renderer
	return self
end

function Diag:attach(textHandle)
	self.line = textHandle
end

function Diag:step()
	local now = os.clock()
	if now < self.next then
		return
	end
	self.next = now + INTERVAL
	if not self.line then
		return
	end

	local players = #PlayersLib.all()
	local esp = self.counts.esp and self.counts.esp() or 0
	local hit = self.counts.hit and self.counts.hit() or 0
	local cam = workspace.CurrentCamera

	local parts = {}
	parts[#parts + 1] = string.format("renderer %s", self.renderer.name)
	parts[#parts + 1] = string.format("players %d", players)
	parts[#parts + 1] = string.format("esp %d", esp)
	parts[#parts + 1] = string.format("hit parts %d", hit)
	parts[#parts + 1] = cam and "cam ok" or "cam nil"

	local ok = pcall(function()
		self.line:Set(table.concat(parts, "  ·  "))
	end)
	if not ok then
		self.line = nil
	end
end

function Diag:destroy()
	self.line = nil
end

return Diag
