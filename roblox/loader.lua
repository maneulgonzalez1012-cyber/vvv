--[[
	vvv · loader
	Único punto de entrada. Ejecuta el script real desde el repo y lo mantiene
	al día: si kindmops cambia el archivo, esto carga la versión nueva sin
	tocar el executor.

	Uso: pega este bloque entero en el executor. Nada más.
]]

local RAW = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv"
local REFS = {
	"arena/04e548ad-vvv",   -- rama de trabajo
	"main",                 -- después del merge
}
local FILE = "roblox/vanta_shooter.lua"

-- cache buster: algunos executors cachean HttpGet por URL
local bust = "?t=" .. tostring(os.time()) .. "&r=" .. tostring(math.random(1e6))

local function fetch(url)
	local ok, body = pcall(game.HttpGet, game, url)
	if ok and type(body) == "string" and #body > 64 then
		-- una página 404 de GitHub es HTML, no Lua
		if body:sub(1, 1) ~= "<" and body:find("local ", 1, true) then
			return body
		end
	end
	return nil
end

local source, err
for _, ref in ipairs(REFS) do
	source = fetch(RAW .. "/" .. ref .. "/" .. FILE .. bust)
	if source then
		err = nil
		break
	end
	err = "no disponible en '" .. ref .. "'"
end

if not source then
	warn("[vvv] loader: " .. tostring(err))
	return
end

local chunk, compileErr = loadstring(source)
if not chunk then
	warn("[vvv] loader: el script no compila — " .. tostring(compileErr))
	return
end

local ok, runErr = pcall(chunk)
if not ok then
	warn("[vvv] loader: error en ejecución — " .. tostring(runErr))
end
