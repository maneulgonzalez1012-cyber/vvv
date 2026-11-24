--[[
	Aero :: Milonarie Tycoon :: utilidades
]]

Aero = Aero or {}
Aero.util = {}

local util = Aero.util

function util.now()
	-- tick() es wall-clock en Roblox; os.clock() es tiempo de CPU, no sirve para intervalos.
	if type(tick) == "function" then
		return tick()
	end
	return os.time()
end

function util.getPlayer()
	local Players = game:GetService("Players")
	return Players.LocalPlayer
end

function util.getCharacter()
	local player = util.getPlayer()
	return player and player.Character or nil
end

function util.getHumanoid()
	local char = util.getCharacter()
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

function util.getRootPart()
	local char = util.getCharacter()
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end

function util.isAlive()
	local hum = util.getHumanoid()
	return hum ~= nil and hum.Health > 0
end

function util.log(msg)
	print("[Aero] " .. tostring(msg))
	if Aero.ui and Aero.ui.pushLog then
		Aero.ui.pushLog(tostring(msg))
	end
end

function util.deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = util.deepCopy(v)
	end
	return copy
end

function util.classify(path)
	local patterns = Aero.config.patterns
	local lower = string.lower(path)
	for action, list in pairs(patterns) do
		for _, p in ipairs(list) do
			if string.find(lower, p, 1, true) then
				return action
			end
		end
	end
	return nil
end

function util.getCash()
	-- Devuelve valor y nombre del stat de moneda. Busca por nombre; si no hay,
	-- se queda con el primer NumberValue del leaderstats.
	local player = util.getPlayer()
	if not player then
		return nil, nil
	end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return nil, nil
	end
	local fallback, fallbackName
	for _, v in ipairs(ls:GetChildren()) do
		if v:IsA("IntValue") or v:IsA("NumberValue") then
			local n = string.lower(v.Name)
			if string.find(n, "cash", 1, true)
				or string.find(n, "money", 1, true)
				or string.find(n, "coin", 1, true)
				or string.find(n, "currency", 1, true) then
				return v.Value, v.Name
			end
			fallback = fallback or v
			fallbackName = fallbackName or v.Name
		end
	end
	if fallback then
		return fallback.Value, fallbackName
	end
	return nil, nil
end

function util.stringify(value, depth)
	depth = depth or 0
	local t = string.lower(type(value))
	if t == "string" then
		return string.format("%q", value)
	end
	if t == "number" or t == "boolean" then
		return tostring(value)
	end
	if t == "nil" then
		return "nil"
	end
	if t == "vector3" then
		return string.format("Vector3(%.1f, %.1f, %.1f)", value.X, value.Y, value.Z)
	end
	if t == "cframe" then
		return tostring(value)
	end
	if depth >= 2 then
		return "{...}"
	end
	if t == "table" then
		local parts = {}
		for i, v in ipairs(value) do
			parts[#parts + 1] = util.stringify(v, depth + 1)
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end
	return tostring(value)
end

function util.serializeArgs(args)
	local parts = {}
	for i = 1, (args.n or 0) do
		parts[#parts + 1] = util.stringify(args[i])
	end
	return table.concat(parts, ", ")
end
