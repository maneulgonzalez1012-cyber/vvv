--[[
	Astral loader
	run:

		loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/loader.lua"))()

	`()()` no es un typo: loadstring compila el chunk y devuelve una función,
	la segunda llamada la ejecuta. cambia el ref por un commit hash para
	clavar una build.

	el orden importa: se baja y compila TODO antes de tocar la instancia
	anterior, así un fetch a medias no te deja el script apagado.
]]

local BASE = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/"
local MAIN = "Astral.lua"

if not loadstring then
	error("[Astral] loadstring deshabilitado: el executor no expone scripting", 0)
end

local ok, body = pcall(function()
	return game:HttpGet(BASE .. MAIN)
end)

if not ok or type(body) ~= "string" or #body < 256 then
	error("[Astral] fetch falló: " .. tostring(body), 0)
end

-- un 404 de raw.githubusercontent llega como "404: Not Found", no como error
if body:find("^404") or body:find("^<!DOCTYPE") or body:find("^<html") then
	error("[Astral] fetch devolvió HTML/404 — revisa la URL del loader", 0)
end

local chunk, err = loadstring(body, "Astral")
if not chunk then
	error("[Astral] compile falló: " .. tostring(err), 0)
end

if getgenv then
	local prev = getgenv().Astral
	if type(prev) == "table" and type(prev.unload) == "function" then
		pcall(prev.unload)
	end
end

chunk()
