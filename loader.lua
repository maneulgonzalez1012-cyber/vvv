--[[
	Astral loader
	run this and nothing else:

		loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/loader.lua"))()

	cambia el ref por un commit hash para clavar una build.
]]

local BASE = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/"
local MAIN = "Astral.lua"
local TIMEOUT = 20
local FALLBACK = {
	"https://cdn.jsdelivr.net/gh/maneulgonzalez1012-cyber/vvv@arena/b9dbd63d-vvv/Astral.lua",
	"https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/main/Astral.lua",
}

local function say(msg)
	if print then
		print("[Astral] " .. msg)
	end
end

local function fail(msg)
	error("[Astral] " .. msg, 0)
end

if not loadstring then
	fail("este executor no tiene loadstring habilitado")
end
if not game or not game.HttpGet then
	fail("este executor no tiene game:HttpGet")
end

--[[
	bajar un archivo de GitHub con manejo de errores real. los executors fallan
	de tres formas distintas y todas hay que distinguirlas para que el mensaje
	sirva de algo:

		- HttpGet lanza  → sin red, DNS, el executor bloquea el host
		- HttpGet demora → se aborta por timeout, no se queda colgado
		- devuelve texto → puede ser 404, HTML de error o el archivo
]]
local function fetch(url)
	local done = false
	local body, err

	local function call()
		local ok, res = pcall(function()
			return game:HttpGet(url)
		end)
		if ok then
			body = res
		else
			err = res
		end
		done = true
	end

	-- sin planificador (executor raro) se llama directo: esperar un timeout
	-- sin haber disparado nada sería colgarse 20s para nada
	local spawn = task and task.spawn or (coroutine and coroutine.wrap)
	if spawn then
		spawn(call)
	else
		call()
		return body, err
	end

	local deadline = os.clock() + TIMEOUT
	while not done and os.clock() < deadline do
		if task and task.wait then
			task.wait(0.05)
		elseif wait then
			wait(0.05)
		else
			break
		end
	end

	if not done then
		return nil, "timeout (" .. TIMEOUT .. "s)"
	end
	if err then
		return nil, tostring(err)
	end
	if type(body) ~= "string" then
		return nil, "respuesta no es texto: " .. type(body)
	end
	if body:find("^404") or body:find("^<!DOCTYPE") or body:find("<html") then
		return nil, "el servidor devolvió HTML/404 (la ruta no existe)"
	end
	if #body < 256 then
		return nil, "respuesta demasiado corta (" .. #body .. " bytes)"
	end

	return body
end

local body, why = fetch(BASE .. MAIN)

if not body then
	for _, url in ipairs(FALLBACK) do
		say("falló la fuente principal (" .. why .. "), probando " .. url)
		body, why = fetch(url)
		if body then
			break
		end
	end
end

if not body then
	fail("no pude bajar Astral.lua: " .. tostring(why))
end

local chunk, cerr = loadstring(body, "Astral")
if not chunk then
	fail("Astral.lua no compila: " .. tostring(cerr))
end

-- la instancia vieja NO se toca aquí: init.luau la apaga cuando el arranque
-- nuevo ya está armado. si el arranque revienta, la vieja sigue funcionando.
local ok, result = pcall(chunk)
if not ok then
	fail("Astral.lua reventó al ejecutarse: " .. tostring(result))
end

say("listo — renderer " .. tostring(getgenv and getgenv().Astral and getgenv().Astral.renderer and getgenv().Astral.renderer.name or "?"))
