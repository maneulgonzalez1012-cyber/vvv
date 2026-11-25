--!nocheck
--[[
	Astral :: shared/mathx
	geometría de pantalla y utilidades numéricas. sin estado.
]]

local Mathx = {}

-- hull en pantalla de una caja orientada: 8 esquinas al viewport.
-- devuelve minX, minY, maxX, maxY o nil si no hay nada visible.
-- cam:WorldToViewportPoint devuelve (x, y, depth); depth <= 0 está detrás
function Mathx.projectBox(cam, cf, size)
	local corners = Mathx.corners
	local minX, minY, maxX, maxY
	local visible = 0

	for i = 1, 8 do
		local c = corners[i]
		local world = cf * Vector3.new(c[1] * size.X * 0.5, c[2] * size.Y * 0.5, c[3] * size.Z * 0.5)
		local sp = cam:WorldToViewportPoint(world)

		if sp.Z > 0 then
			visible = visible + 1
			minX = (not minX or sp.X < minX) and sp.X or minX
			maxX = (not maxX or sp.X > maxX) and sp.X or maxX
			minY = (not minY or sp.Y < minY) and sp.Y or minY
			maxY = (not maxY or sp.Y > maxY) and sp.Y or maxY
		end
	end

	if visible == 0 or not minX then
		return nil
	end

	return minX, minY, maxX, maxY
end

Mathx.corners = {
	{ -1, -1, -1 }, { 1, -1, -1 }, { -1, 1, -1 }, { 1, 1, -1 },
	{ -1, -1, 1 }, { 1, -1, 1 }, { -1, 1, 1 }, { 1, 1, 1 },
}

function Mathx.clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- lerp de color sin tocarse los ojos con Color3:Lerp (que no existe en todos
-- los executors con Drawing)
function Mathx.lerpColor(a, b, t)
	t = Mathx.clamp(t, 0, 1)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

return Mathx
