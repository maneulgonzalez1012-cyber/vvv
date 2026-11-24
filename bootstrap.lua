--[[
    VANTA | MILONARIE TYCOON
    Bootstrap publico (la "linea de paste")

    Generado por roblox/milonarie_tycoon/tools/build_loader.py. No editar a mano.

    Este es el unico trozo que se pega a mano en el executor. Es autonomo:
    NO usa game:HttpGet como via principal, porque Athena (y otros executors)
    lanzan "HttpGet is not a valid member of DataModel" al indexarlo.

    Orden de intento:
        1. request({Url=,Method=})      -> string | {Body=} | (body, ok, code)
        2. http_request(url)              -> string | {Body=} | (body, ok, code)
        3. syn.request({Url=,Method=})  -> string | (body, ok, code)
        4. http.request({Url=,Method=}) -> string | {Body=} | (body, code, msg, hdr)
        5. game:HttpGet(url)              -> ultimo recurso

    Descarga loader.lua (GUI + payload con respaldo por partes) y lo ejecuta.

    Si ninguna via responde, avisa con un error claro en vez de fallar en silencio.
]]

--[[
	Cliente HTTP compartido entre loader.lua y bootstrap.lua.

	Se inlnea (no se require) porque cada fichero se descarga y ejecuta por
	separado en el executor: no hay un require disponible.

	Cada executor expone el GET de otra forma:
		request({Url=,Method=})         -> string | {Body=,StatusCode=} | (body, ok, code)
		http_request(url)               -> string | {Body=} | (body, ok, code)
		syn.request({Url=,Method=})     -> string | (body, ok, code)
		http.request({Url=,Method=})    -> string | {Body=} | (body, code, msg, headers)
		game:HttpGet(url)               -> string

	Por eso se prueban las dos formas de llamada (tabla y url suelta) y se
	normaliza la respuesta a texto. game:HttpGet va el ULTIMO: Athena (y otros)
	lanza "HttpGet is not a valid member of DataModel" al indexarlo.
]]

local function vantaBodyOf(res, extra)
	if type(res) == "string" and #res > 0 then
		return res
	end
	if type(res) == "table" then
		local body = res.Body or res.body or res.Content or res.content
		if type(body) == "string" and #body > 0 then
			return body
		end
	end
	if type(extra) == "string" and #extra > 0 then
		return extra
	end
	return nil
end

local function vantaHttpGet(url)
	local candidates = {}
	if type(request) == "function" then
		candidates[#candidates + 1] = request
	end
	if type(http_request) == "function" then
		candidates[#candidates + 1] = http_request
	end
	if type(syn) == "table" and type(syn.request) == "function" then
		candidates[#candidates + 1] = syn.request
	end
	if type(http) == "table" and type(http.request) == "function" then
		candidates[#candidates + 1] = http.request
	end

	for _, fn in ipairs(candidates) do
		local ok, a, b = pcall(fn, { Url = url, Method = "GET" })
		if ok then
			local body = vantaBodyOf(a, b)
			if body then
				return body
			end
		end
		local ok2, a2, b2 = pcall(fn, url)
		if ok2 then
			local body = vantaBodyOf(a2, b2)
			if body then
				return body
			end
		end
	end

	-- Ultimo recurso: HttpGet de Roblox (solo dominios en la allowlist del juego).
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" and #body > 0 then
		return body
	end
	return nil
end

-- Compila un fuente. loadstring va primero; algunos executors solo traen load.
local function vantaCompile(source, chunkName)
	local chunk, err
	if type(loadstring) == "function" then
		chunk, err = loadstring(source, chunkName)
	end
	if not chunk and type(load) == "function" then
		chunk, err = load(source, chunkName)
	end
	return chunk, err
end
----------------------------------------------------------------------- URLs
local LOADER_URL = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/loader.lua"

--------------------------------------------------------------------- arranque
local source = vantaHttpGet(LOADER_URL)
if not source then
	error("[VANTA] no se pudo descargar el loader. Ningun metodo HTTP respondio "
		.. "(request / http_request / syn.request / http.request / game:HttpGet).")
end

local chunk, compileErr = vantaCompile(source, "=loader")
if not chunk then
	error("[VANTA] el loader no compila: " .. tostring(compileErr))
end

chunk()
