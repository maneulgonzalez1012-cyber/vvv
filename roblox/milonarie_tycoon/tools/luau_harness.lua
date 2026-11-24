--[[
	Aero :: Milonarie Tycoon :: harness Luau real.

	Concatena el mock de Roblox + el payload + los asserts y lo ejecuta con el
	binario de Luau (no Lua). Esto verifica la semántica real de Roblox:

	- Luau no tiene debug.getinfo (solo debug.info)
	- Luau no tiene string.dump
	- Luau no tiene load() ni _ENV
	- Luau no tiene unpack global (solo table.unpack)
	- Luau tiene getfenv/setfenv/newproxy/unpack, pero su _G es read-only
	- loadstring existe y compila contra el entorno del caller

	Uso (desde roblox/milonarie_tycoon):
		luau tools/luau_harness.lua <payload.lua>
]]

local MOCK = (function()
	local f = io.open("tools/roblox_mock.lua", "r")
	if not f then
		error("no se encuentra tools/roblox_mock.lua: ejecutar desde roblox/milonarie_tycoon")
	end
	local src = f:read("*a")
	f:close()
	-- El mock acaba con "return Mock": se quita para poder concatenar.
	src = src:gsub("return Mock%s*$", "")
	return src
end)()

local PAYLOAD_PATH = ...
if not PAYLOAD_PATH then
	PAYLOAD_PATH = "dist/milonarie_tycoon.lua"
end

local pf = io.open(PAYLOAD_PATH, "r")
if not pf then
	error("no se encuentra el payload: " .. PAYLOAD_PATH)
end
local payload = pf:read("*a")
pf:close()

local af = io.open("tools/full_assert.lua", "r")
if not af then
	error("no se encuentra tools/full_assert.lua")
end
local asserts = af:read("*a")
af:close()

-- 1) mock
local chunk = loadstring(MOCK, "@mock")
if not chunk then
	error("el mock no compila en Luau")
end
chunk()

-- 2) payload (el mock sustituye loadstring por uno que usa el env de Roblox)
local ok, err = pcall(Mock.runSource, payload)
if not ok then
	print("PAYLOAD ERROR: " .. tostring(err))
	os.exit(1)
end

-- 3) asserts
local passed, failed, details = loadstring(asserts, "@asserts")()
for line in tostring(details or ""):gmatch("[^\n]+") do
	if line:match("%S") then
		print("FAIL  " .. line)
	end
end
print(string.format("%d passed, %d failed", tonumber(passed) or 0, tonumber(failed) or 0))
if (tonumber(failed) or 0) > 0 then
	os.exit(1)
end
