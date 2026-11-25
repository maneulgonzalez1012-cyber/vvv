--[[
	vvv · loader
	Pega este bloque entero en el executor. Carga vanta_shooter.lua desde el repo.

	Orden de resolución:
	  1. main            -> versión estable (después del merge)
	  2. <sha>           -> commit exacto donde vive el script hoy

	Sin refs con slash: raw.githubusercontent resuelve ambiguo con
	nombres tipo arena/xxxx, así que el fallback va por SHA de 40 chars.
]]

local RAW    = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv"
local FILE   = "roblox/vanta_shooter.lua"
local REFS   = {
	"main",
	"5a97fd327e38abdfb0164011b34fad6c1dacf96f",   -- vanta_shooter.lua
}

local bust = "?t=" .. tostring(os.time()) .. tostring(math.random(100000, 999999))

local function fetch(url)
	local ok, body = pcall(game.HttpGet, game, url)
	if not ok or type(body) ~= "string" or #body < 64 then return nil end
	-- un 404 de GitHub vuelve como HTML; el script empieza con "--"
	if body:sub(1, 1) == "<" then return nil end
	if not body:find("local ", 1, true) then return nil end
	return body
end

local source
for _, ref in ipairs(REFS) do
	source = fetch(RAW .. "/" .. ref .. "/" .. FILE .. bust)
	if source then break end
end

if not source then
	warn("[vvv] loader: no pude bajar " .. FILE .. " (main ni SHA)")
	return
end

local chunk, compileErr = loadstring(source)
if not chunk then
	warn("[vvv] loader: no compila — " .. tostring(compileErr))
	return
end

local ok, runErr = pcall(chunk)
if not ok then
	warn("[vvv] loader: error en ejecución — " .. tostring(runErr))
end
