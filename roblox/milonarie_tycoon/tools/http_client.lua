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
