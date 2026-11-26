--[[
	vvv · spy  v3
	Remote spy con la superficie de SimpleSpy v2.2 y la red lo más ancha
	posible por dentro. La diferencia con v2 no son los botones: es dónde
	se engancha y qué se hace cuando el hook dispara.

	Rutas de captura (todas prendidas por defecto)
	  1. __namecall                     remote:FireServer(...) / :InvokeServer(...)
	  2. hookfunction de los métodos    referencias cacheadas, corchetes,
	                                    pcall(remote.FireServer, remote, ...)
	  3. OnClientEvent / OnClientInvoke tráfico servidor -> cliente, incluidos
	                                    remotes creados después de cargar
	  4. todo el DataModel              DescendantAdded sobre game, no sólo RS
	  5. BindableEvent :Fire            red interna cliente-cliente (opt-in)

	Qué hace distinto el hook
	  · no serializa, no hace pcall de UI, no crea threads: encola en un ring
	    O(1) y vuelve. Todo lo caro pasa en el procesador a 20 Hz.
	  · ninguna entrada se pierde porque un argumento no sea serializable:
	    la serialización es perezosa y por argumento.
	  · dedupe de 0.4 ms para los ejecutores donde namecall y hookfunction
	    disparan los dos por la misma llamada.
	  · InvokeServer devuelve valores por las dos rutas, no sólo namecall.

	Diagnóstico
	  Contadores por ruta, pings del hook, motivos por los que algo quedó
	  oculto, top de remotes y descartes del ring. Dos escaneos que SimpleSpy
	  no tiene: getgc / getinstances / getnilinstances (remotes fuera del
	  DataModel) y getreg (scripts vivos del registro de Lua).

	Herramientas por entrada: Copy Code, Copy Args, Copy Return, Copy Remote,
	Run Code, Get Script, Function Info, Decompile, Conexiones, Replay,
	Exclude (i)/(n), Block (i)/(n), Seguir.

	API en getgenv().VVV_SPY — ver el bloque final.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local LP = Players.LocalPlayer
if not LP then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LP = Players.LocalPlayer
end

local genv = (getgenv and getgenv and getgenv()) or _G
if genv.VVV_SPY then
	pcall(function() genv.VVV_SPY.shutdown() end)
end

-- =====================================================================
-- Capacidades del executor · se muestran, no se asumen
-- =====================================================================

-- El entorno del executor expone todo en _G, pero _G puede ser una tabla
-- distinta de la del chunk (o readonly): se prueban _G, getgenv() y las
-- referencias directas, que en Luau se resuelven contra el env del chunk.
local genvRef = pcall(function() return genv end) and genv or _G

local direct = {
	hookmetamethod    = hookmetamethod,
	hookfunction      = hookfunction,
	newcclosure       = newcclosure,
	checkcaller       = checkcaller,
	getcallingscript  = getcallingscript,
	getscriptfromsrc  = getscriptfromsrc,
	decompile         = decompile,
	getscriptbytecode = getscriptbytecode,
	getconstants      = getconstants,
	getupvalues       = getupvalues,
	getnamecallmethod = getnamecallmethod,
	setclipboard      = setclipboard,
	toclipboard       = toclipboard,
	set_clipboard     = set_clipboard,
	getconnections    = getconnections,
	getgc             = getgc,
	getreg            = getreg,
	getinstances      = getinstances,
	getnilinstances   = getnilinstances,
	isexecutorclosure = isexecutorclosure,
	getinfo           = getinfo,
}

local function pick(name)
	local v = direct[name]
	if type(v) == "function" then return v end
	local ok, x = pcall(function() return rawget(_G, name) end)
	if ok and type(x) == "function" then return x end
	ok, x = pcall(function() return genvRef[name] end)
	if ok and type(x) == "function" then return x end
	return nil
end

local function has(name)
	return pick(name) ~= nil
end

local function cap(name)
	return pick(name)
end

local caps = {
	hookmetamethod    = has("hookmetamethod"),
	hookfunction      = has("hookfunction"),
	newcclosure       = has("newcclosure"),
	checkcaller       = has("checkcaller"),
	getcallingscript  = has("getcallingscript"),
	getscriptfromsrc  = has("getscriptfromsrc"),
	decompile         = has("decompile"),
	getscriptbytecode = has("getscriptbytecode"),
	getconstants      = has("getconstants") or (debug and type(debug.getconstants) == "function"),
	getupvalues       = has("getupvalues") or (debug and type(debug.getupvalues) == "function"),
	debuginfo         = (debug and type(debug.info) == "function") or has("getinfo"),
	getnamecallmethod = has("getnamecallmethod") or (type(getnamecallmethod) == "function"),
	setclipboard      = has("setclipboard") or has("toclipboard") or has("set_clipboard"),
	getconnections    = has("getconnections"),
	getgc             = has("getgc"),
	getreg            = has("getreg"),
	getinstances      = has("getinstances"),
	getnilinstances   = has("getnilinstances"),
	isexecutorclosure = has("isexecutorclosure"),
	isyieldable       = (coroutine and type(coroutine.isyieldable) == "function"),
}

caps.getnamecallmethod = caps.getnamecallmethod or (type(getnamecallmethod) == "function")

local function newcclosure_or(fn)
	if caps.newcclosure then
		local ok, wrapped = pcall(cap("newcclosure"), fn)
		if ok and type(wrapped) == "function" then return wrapped end
	end
	return fn
end

local function callerIsOurs()
	if not caps.checkcaller then return false end
	local ok, r = pcall(cap("checkcaller"))
	return ok and r or false
end

local function isExecutorClosure(f)
	if not caps.isexecutorclosure then return false end
	local ok, r = pcall(cap("isexecutorclosure"), f)
	return ok and r or false
end

local function clip(text)
	text = tostring(text)
	if has("setclipboard") then return pcall(cap("setclipboard"), text) end
	if has("toclipboard") then return pcall(cap("toclipboard"), text) end
	if has("set_clipboard") then return pcall(cap("set_clipboard"), text) end
	return false
end

local function namecallMethod()
	if type(getnamecallmethod) ~= "function" then return nil end
	local ok, m = pcall(getnamecallmethod)
	return ok and m or nil
end

local aliasedTypeof = typeof
local function kindOf(v)
	local ok, t = pcall(aliasedTypeof, v)
	return ok and t or type(v)
end

-- =====================================================================
-- Config y contadores
-- =====================================================================

local cfg = {
	enabled       = true,
	method        = "both",   -- both | namecall | functions
	logSent       = true,
	logReceived   = true,
	logReturns    = true,
	logExecutors  = false,   -- deprecado: ahora es hideExec
	hideExec      = true,   -- oculta SOLO en pantalla; se captura igual
	verbose       = false,  -- cuenta todos los métodos de namecall
	collectInfo   = true,
	keyToString   = false,
	autoblock     = false,
	autoblockRate = 25,
	maxLogs       = 250,
	bindables     = false,    -- BindableEvent/Event:Fire, BindableFunction:Invoke
	deepSweep     = true,     -- barrido por getgc cada 15 s
	previewArgs   = true,
	filter        = "",       -- subcadena del nombre; "" = todo
	blocked       = {},
	excluded      = {},
	hooks         = {},       -- [Instance] = function(args) -> args
	signals       = {},
}

local stats = {
	captured = 0,   -- entradas que llegaron al ring
	namecall = 0,
	functions = 0,
	recv     = 0,
	exec     = 0,   -- disparadas por el propio executor
	dropped  = 0,   -- tiradas por ring lleno
	ser      = 0,   -- errores de serialización
	newFound = 0,   -- remotes descubiertos por escaneo profundo
	dedup    = 0,   -- llamadas fusionadas por el dedupe
	err      = 0,   -- errores al finalizar una entrada
	lastErr  = nil,
	rate     = {},  -- [name] = { t, n } para autoblock
	hits     = {},  -- [name] = total de capturas, para el top
	remotes  = 0,
	gcScanned = 0,
	gcNodes   = 0,
	pings     = 0,   -- FireServer/InvokeServer vistos por el hook (salud)
	methods   = {},  -- [method] = n, sólo en verbose
	gate      = { exec = 0, disabled = 0, filter = 0, excluded = 0, offSent = 0, offRecv = 0 },
}

local MAX_STRING = 8000
local MAX_TABLE  = 400
local MAX_DEPTH  = 8

local function maxTable()
	local compat = rawget(_G, "SimpleSpyMaxTableSize")
	return tonumber(compat) or MAX_TABLE
end

local function maxRemotes()
	local compat = rawget(_G, "SIMPLESPYCONFIG_MaxRemotes")
	return tonumber(compat) or cfg.maxLogs
end

local function alen(t)
	return rawget(t, "n") or #t
end

local function unpackArgs(t)
	return table.unpack(t, 1, alen(t))
end

-- =====================================================================
-- Serializador · perezoso y a prueba de argumentos hostiles
--   serializeArgs corre por argumento en pcall: si uno revienta, ese
--   argumento sale como comentario y la entrada se conserva igual.
-- =====================================================================

local function quote(s)
	local out = s:gsub("[%z\1-\31\\\"\n\r\t]", function(c)
		if c == "\\" then return "\\\\" end
		if c == "\"" then return "\\\"" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return string.format("\\%d", c:byte())
	end)
	if #out > MAX_STRING then
		out = out:sub(1, MAX_STRING) .. "\\n--[[ MAXIMUM STRING SIZE REACHED ]]"
	end
	return "\"" .. out .. "\""
end

local function instancePath(inst)
	local ok, full = pcall(function() return inst:GetFullName() end)
	if ok and full then
		if full == "Workspace" then return "workspace" end
		if full:sub(1, 10) == "Workspace." then return "workspace" .. full:sub(10) end
		return full
	end
	local okName, name = pcall(function() return inst.Name end)
	return "\"" .. tostring(okName and name or "?") .. "\" --[[instancia fuera del DataModel]]"
end

local serialize

local function serializeTable(v, depth, seen)
	if depth >= MAX_DEPTH then return "{ --[[MAX DEPTH]] }" end
	seen = seen or {}
	if seen[v] then return "{ --[[DUPLICATE]] }" end
	seen[v] = true

	-- Se recorre entera para saber si es array, pero sólo se guardan las
	-- primeras `limit` claves: una tabla de 5000 elementos no rompe nada y
	-- la llamada sigue siendo replayeable.
	local limit = maxTable()
	local keys, count = {}, 0
	for k in pairs(v) do
		count += 1
		if count <= limit then keys[#keys + 1] = k end
	end

	local isArray = (count == #v)
	local body = {}
	local truncated = count > limit

	if isArray then
		local upto = math.min(count, limit)
		for i = 1, upto do
			body[#body + 1] = serialize(v[i], depth + 1, seen)
		end
		if truncated then
			body[#body + 1] = "--[[+" .. (count - upto) .. " elementos más ("
				.. count .. " total); subí SimpleSpyMaxTableSize]]"
		end
	else
		for _, k in ipairs(keys) do
			local kt = kindOf(k)
			local keyStr
			if kt == "string" then
				if k:match("^[%a_][%w_]*$") then
					keyStr = k
				else
					keyStr = "[" .. quote(k) .. "]"
				end
			elseif cfg.keyToString and (kt == "Instance" or kt == "userdata") then
				local okName, kn = pcall(function() return k.Name end)
				keyStr = string.format("[\"<%s: %s>\" --[[clave original no serializable]]]",
					kt, tostring(okName and kn or k))
			else
				keyStr = "[" .. serialize(k, depth + 1, seen) .. "]"
			end
			body[#body + 1] = keyStr .. " = " .. serialize(v[k], depth + 1, seen)
		end
	end

	seen[v] = nil
	local glue = isArray and ", " or ", "
	return "{" .. table.concat(body, glue) .. "}"
end

serialize = function(v, depth, seen)
	depth = depth or 0
	local t = kindOf(v)

	if t == "string" then
		return quote(v)
	elseif t == "number" then
		if v ~= v then return "0/0 --[[NaN]]" end
		if v == math.huge then return "math.huge" end
		if v == -math.huge then return "-math.huge" end
		if math.floor(v) == v and math.abs(v) < 1e15 then return string.format("%d", v) end
		return string.format("%.14g", v)
	elseif t == "boolean" or t == "nil" then
		return tostring(v)
	elseif t == "Vector3" then
		return string.format("Vector3.new(%s, %s, %s)", serialize(v.X), serialize(v.Y), serialize(v.Z))
	elseif t == "Vector2" then
		return string.format("Vector2.new(%s, %s)", serialize(v.X), serialize(v.Y))
	elseif t == "CFrame" then
		local x, y, z = v:ToEulerAnglesXYZ()
		return string.format("CFrame.new(%s, %s, %s) * CFrame.Angles(%s, %s, %s)",
			serialize(v.X), serialize(v.Y), serialize(v.Z),
			serialize(x), serialize(y), serialize(z))
	elseif t == "Color3" then
		return string.format("Color3.fromRGB(%d, %d, %d)",
			math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255))
	elseif t == "BrickColor" then
		return string.format("BrickColor.new(%d)", v.Number)
	elseif t == "EnumItem" then
		local ok, s = pcall(tostring, v)
		if ok then return s end
		return "nil --[[enum]]"
	elseif t == "UDim" then
		return string.format("UDim.new(%s, %s)", serialize(v.Scale), serialize(v.Offset))
	elseif t == "UDim2" then
		return string.format("UDim2.new(%s, %s, %s, %s)",
			serialize(v.X.Scale), serialize(v.X.Offset),
			serialize(v.Y.Scale), serialize(v.Y.Offset))
	elseif t == "NumberRange" then
		return string.format("NumberRange.new(%s, %s)", serialize(v.Min), serialize(v.Max))
	elseif t == "NumberSequence" then
		local p = {}
		for _, kp in ipairs(v.Keypoints) do
			p[#p + 1] = string.format("NumberSequenceKeypoint.new(%s, %s, %s)",
				serialize(kp.Time), serialize(kp.Value), serialize(kp.Envelope))
		end
		return "NumberSequence.new({" .. table.concat(p, ", ") .. "})"
	elseif t == "ColorSequence" then
		local p = {}
		for _, kp in ipairs(v.Keypoints) do
			p[#p + 1] = string.format("ColorSequenceKeypoint.new(%s, %s)",
				serialize(kp.Time), serialize(kp.Value))
		end
		return "ColorSequence.new({" .. table.concat(p, ", ") .. "})"
	elseif t == "TweenInfo" then
		return string.format(
			"TweenInfo.new(%s, Enum.EasingStyle.%s, Enum.EasingDirection.%s, %s, %s, %s)",
			serialize(v.Time), tostring(v.EasingStyle), tostring(v.EasingDirection),
			serialize(v.RepeatCount), serialize(v.Reverses), serialize(v.DelayTime))
	elseif t == "Rect" then
		return string.format("Rect.new(%s, %s)", serialize(v.Min), serialize(v.Max))
	elseif t == "Instance" then
		return instancePath(v)
	elseif t == "table" then
		return serializeTable(v, depth, seen)
	elseif t == "function" then
		local name
		if caps.debuginfo then
			local okN, n = pcall(debug.info, v, "n")
			if okN and n then name = tostring(n) end
		end
		if isExecutorClosure(v) then
			return "--[[executor closure: " .. (name or "?") .. "]] function() end"
		end
		return "--[[function" .. (name and (": " .. name) or "") .. "]] function() end"
	elseif t == "RBXScriptSignal" or t == "RBXScriptConnection" then
		return "nil --[[ " .. t .. " ]]"
	elseif t == "userdata" then
		local ok, s = pcall(tostring, v)
		return "newproxy(true) --[[userdata" .. (ok and (" " .. s:sub(1, 60)) or "") .. "]]"
	end

	return "nil --[[ " .. tostring(t) .. " ]]"
end

local function serializeOne(v)
	local ok, s = pcall(serialize, v, 0, nil)
	if ok then return s end
	stats.ser += 1
	return "--[[no serializable: " .. tostring(s):sub(1, 100) .. "]]"
end

local function serializeArgs(args)
	local n = alen(args)
	local out = table.create(n)
	for i = 1, n do
		out[i] = serializeOne(args[i])
	end
	return out
end

-- =====================================================================
-- Señales propias · GetRemoteFiredSignal
-- =====================================================================

local function newSignal()
	local conns = {}
	local sig = { closed = false }

	function sig:Connect(fn)
		if sig.closed then
			return { Connected = false, Disconnect = function() end }
		end
		conns[#conns + 1] = fn
		local i = #conns
		return {
			Connected = true,
			Disconnect = function(self)
				conns[i] = nil
				self.Connected = false
			end,
		}
	end

	function sig:Once(fn)
		local c
		c = sig:Connect(function(...)
			c:Disconnect()
			return fn(...)
		end)
		return c
	end

	function sig:Wait()
		local co = coroutine.running()
		local once
		once = self:Connect(function(...)
			local packed = table.pack(...)
			once:Disconnect()
			if coroutine.status(co) == "suspended" then
				task.spawn(coroutine.resume, co, table.unpack(packed, 1, packed.n))
			end
		end)
		return coroutine.yield()
	end

	function sig:Fire(...)
		-- el pack va fuera del closure: Luau rechaza '...' dentro de una
		-- función anidada que no declara sus propios varargs
		local packed = table.pack(...)
		for i = 1, #conns do
			local fn = conns[i]
			if fn then
				task.spawn(function()
					local ok, err = pcall(function()
						fn(table.unpack(packed, 1, packed.n))
					end)
					if not ok then warn("[vvv·spy] signal: " .. tostring(err)) end
				end)
			end
		end
	end

	return sig
end

local function remoteSignal(remote)
	local s = cfg.signals[remote]
	if not s then
		s = newSignal()
		cfg.signals[remote] = s
	end
	return s
end

-- =====================================================================
-- Inspección de funciones
-- =====================================================================

local function callerFunction()
	if not caps.debuginfo then return nil end
	for level = 2, 8 do
		local ok, f = pcall(debug.info, level, "f")
		if ok and type(f) == "function" then
			local okS, src = pcall(debug.info, f, "s")
			if okS and src and src ~= "=[C]" and src ~= "[C]" then
				return f, src
			end
		end
	end
	return nil
end

local function functionInfo(f)
	if not f then return nil end
	local info = { source = nil, name = nil, line = nil }
	if caps.debuginfo then
		local okName, name = pcall(debug.info, f, "n")
		local okSrc, src = pcall(debug.info, f, "s")
		local okLine, line = pcall(debug.info, f, "l")
		info.name = okName and name or nil
		info.source = okSrc and src or nil
		info.line = okLine and line or nil
	end
	if caps.getconstants then
		local ok, consts = pcall(cap("getconstants") or debug.getconstants, f)
		if ok then info.constants = consts end
	end
	if caps.getupvalues then
		local ok, ups = pcall(cap("getupvalues") or debug.getupvalues, f)
		if ok then info.upvalues = ups end
	end
	return info
end

local function describeInfo(info)
	if not info then return "sin datos de función (Disable Info o executor sin debug)" end
	local parts = {}
	if info.name then parts[#parts + 1] = "nombre: " .. tostring(info.name) end
	if info.source then parts[#parts + 1] = "fuente: " .. tostring(info.source) end
	if info.line then parts[#parts + 1] = "línea: " .. tostring(info.line) end
	if info.constants then parts[#parts + 1] = "constantes: " .. #info.constants end
	if info.upvalues then parts[#parts + 1] = "upvalues: " .. #info.upvalues end
	return table.concat(parts, " · ")
end

local function decompileOf(script)
	if not script then return nil, "sin script" end
	if caps.decompile then
		local ok, src = pcall(cap("decompile"), script)
		if ok and type(src) == "string" and #src > 0 then return src end
	end
	if caps.getscriptbytecode then
		local ok, bc = pcall(cap("getscriptbytecode"), script)
		if ok and bc then
			return string.format(
				"-- bytecode disponible (%d bytes), este executor no trae decompilador\n-- decompile(script) no está expuesto",
				#tostring(bc))
		end
	end
	return nil, "este executor no tiene decompile() ni getscriptbytecode()"
end

local function scriptFromSource(src)
	if not caps.getscriptfromsrc then return nil, "getscriptfromsrc no disponible" end
	local ok, script = pcall(cap("getscriptfromsrc"), src)
	if ok then return script end
	return nil, "getscriptfromsrc falló"
end

local function connectionsOf(signal)
	if not caps.getconnections then return nil end
	local ok, list = pcall(cap("getconnections"), signal)
	return ok and list or nil
end

local function describeConnection(c)
	local parts = {}
	local function probe(label, fn)
		local ok, v = pcall(fn)
		if ok and v ~= nil then parts[#parts + 1] = label .. "=" .. tostring(v) end
	end
	probe("enabled", function() return c.Enabled end)
	probe("sync", function() return c.Sync end)
	probe("foreign", function() return c.ForeignState end)
	probe("func", function()
		local f = c.Function
		if type(f) ~= "function" then return nil end
		local okN, n = pcall(debug.info, f, "n")
		return okN and n or "?"
	end)
	probe("script", function()
		local s = c.Script
		if s then return s:GetFullName() end
	end)
	probe("source", function()
		local f = c.Function
		if type(f) ~= "function" then return nil end
		local okS, src = pcall(debug.info, f, "s")
		return okS and src or nil
	end)
	return table.concat(parts, " · ")
end

-- =====================================================================
-- Núcleo · ring de captura
--   El hook sólo hace un insert O(1) acá. Serializar, resolver scripts,
--   pedir upvalues y tocar la UI pasa fuera, a 20 Hz.
-- =====================================================================

local RING = 4096
local ring = table.create(RING)
local ringHead, ringLen = 1, 0

local remoteMeta = setmetatable({}, { __mode = "k" })
local infoCache  = setmetatable({}, { __mode = "k" })
-- reentrancia: cuando namecall hace original(), el método de la clase vuelve
-- a pasar por el Hook 2. Es la MISMA llamada: el flag evita el doble log sin
-- fusionar dos disparos legítimos seguidos (un dedupe por tiempo lo haría).
local reentrant = false

-- checkcaller() miente en varios ejecutores (y en el sandbox del test).
-- En vez de confiar en él, "del executor" se marca sólo dentro de la
-- ventana que abre el propio spy al hacer Replay / Run Code. Todo lo demás
-- se trata como llamada del juego: si el usuario pierde una captura real
-- por un checkcaller optimista, prefirió no tener spy.
local ownWindow = 0
local function isOwnCall()
	return os.clock() < ownWindow
end
local function markOwn(seconds)
	ownWindow = os.clock() + (seconds or 0.75)
end


local function remoteClass(cls)
	return cls == "RemoteEvent" or cls == "UnreliableRemoteEvent" or cls == "RemoteFunction"
		or cls == "BindableEvent" or cls == "BindableFunction"
end

local function remoteMetaOf(inst, label)
	local m = remoteMeta[inst]
	if m then
		if label then m.name = label end
		return m
	end
	local okC, cls = pcall(function() return inst.ClassName end)
	local okN, nm  = pcall(function() return inst.Name end)
	m = {
		cls  = okC and tostring(cls) or "?",
		name = label or (okN and tostring(nm) or "?"),
	}
	remoteMeta[inst] = m
	return m
end

local function record(remote, method, args, rets, funcRef, srcRef, fromExec, blocked, path)
	local item = {
		remote = remote, method = method, args = args, rets = rets,
		funcRef = funcRef, srcRef = srcRef, fromExec = fromExec,
		blocked = blocked, path = path, t = os.clock(), entry = nil,
	}

	if ringLen >= RING then
		ring[ringHead] = nil
		ringHead = (ringHead % RING) + 1
		ringLen -= 1
		stats.dropped += 1
	end
	local idx = ((ringHead + ringLen - 1) % RING) + 1
	ring[idx] = item
	ringLen += 1
	stats.captured += 1
	if fromExec then stats.exec += 1 end
	return item
end

local function attachReturns(item, packed)
	if not item then return end
	item.rets = packed
	if item.entry then
		item.entry.rets = packed
	end
end

local function shiftRaw()
	if ringLen == 0 then return nil end
	local item = ring[ringHead]
	ring[ringHead] = nil
	ringHead = (ringHead % RING) + 1
	ringLen -= 1
	return item
end

-- =====================================================================
-- Spy · log, filtros, autoblock
-- =====================================================================

local notices = {}
local API   -- forward: la UI lo consulta antes de que exista

local Spy = {
	running   = true,
	logs      = {},
	seq       = 0,
	watched   = {},
	invokeWrapped = setmetatable({}, { __mode = "k" }),
	wantReturns = {},
	fnHooked  = {},
	hookState = { namecall = false, functions = false, received = false, instanceNew = false, bindables = false },
	originals = {},
	rate      = {},
	filterRemote = nil,
}

local blockedPaths = {}
local excludedPaths = {}
local pathBlockCount, pathExcludeCount = 0, 0

local function pathOf(inst)
	local ok, full = pcall(function() return inst:GetFullName() end)
	return ok and full or nil
end

local function isBlockedFast(inst, name)
	if cfg.blocked[inst] then return true end
	if name and cfg.blocked[name] then return true end
	if pathBlockCount > 0 then
		local p = pathOf(inst)
		if p and blockedPaths[p] then return true end
	end
	return false
end

local function isExcludedFast(inst, name)
	if cfg.excluded[inst] then return true end
	if name and cfg.excluded[name] then return true end
	if pathExcludeCount > 0 then
		local p = pathOf(inst)
		if p and excludedPaths[p] then return true end
	end
	return false
end

local function autoblockCheck(name)
	if not cfg.autoblock then return end
	local now = os.clock()
	local r = Spy.rate[name]
	if not r then
		r = { t = now, n = 0, total = 0 }
		Spy.rate[name] = r
	end
	if now - r.t > 1 then
		r.t = now
		r.n = 0
	end
	r.n += 1
	r.total += 1
	if r.n > cfg.autoblockRate and not cfg.blocked[name] then
		cfg.blocked[name] = true
		notices[#notices + 1] = name
	end
end

local function scriptLabel(srcRef)
	if not srcRef then return "(main)", nil end
	local okN, n = pcall(function() return srcRef.Name end)
	local p = pathOf(srcRef)
	return okN and tostring(n) or "?", p
end

local function finalize(item)
	local okAll, err = pcall(function()
		local remote = item.remote
		local m = remoteMetaOf(remote)
		local name = m.name
		local gate = stats.gate
		local visible = true
		local reason

		-- El filtro es SÓLO de presentación: se decide una vez y no descarta
		-- nada. El item sigue en el ring, el log interno y la señal del remote.
		if isExcludedFast(remote, name) then
			visible, reason = false, "excluded"
		elseif not cfg.enabled then
			visible, reason = false, "disabled"
		elseif item.fromExec and cfg.hideExec then
			visible, reason = false, "exec"
		elseif item.path == "recv" and not cfg.logReceived then
			visible, reason = false, "offRecv"
		elseif item.path ~= "recv" and not cfg.logSent then
			visible, reason = false, "offSent"
		elseif cfg.filter ~= "" and not tostring(name):lower():find(cfg.filter, 1, true) then
			visible, reason = false, "filter"
		end
		if not visible then
			gate[reason] = (gate[reason] or 0) + 1
			item.hidden = reason
		end
		if not cfg.logReturns and item.rets then item.rets = nil end

		local scriptName, scriptPath = scriptLabel(item.srcRef)

		local entry = {
			seq        = Spy.seq + 1,
			remote     = remote,
			name       = name,
			cls        = m.cls,
			method     = item.method,
			path       = item.path,
			args       = item.args,
			rets       = item.rets,
			script     = scriptName,
			scriptRef  = item.srcRef,
			scriptPath = scriptPath,
			time       = item.t,
			type       = (item.path == "recv") and "recv" or "sent",
			blocked    = item.blocked == true,
			fromExec   = item.fromExec == true,
			funcRef    = item.funcRef,
			hidden     = item.hidden,
		}
		Spy.seq += 1
		item.entry = entry

		if visible then
			Spy.logs[#Spy.logs + 1] = entry
			local limit = maxRemotes()
			while #Spy.logs > limit do
				table.remove(Spy.logs, 1)
			end
		end
		-- todo tiene señal: los scripts que escuchan un remote ven también lo
		-- que el log esconde. Para eso está GetRemoteFiredSignal.
		remoteSignal(remote):Fire(entry)
	end)
	if not okAll then
		stats.err += 1
		stats.lastErr = tostring(err)
	end
end

function Spy:clear()
	self.logs = {}
	self.seq = 0
	stats.rate = {}
end

function Spy:watchedCount()
	local n = 0
	for _ in pairs(self.watched) do n += 1 end
	return n
end

function Spy:push(remote, method, args, rets, funcRef, srcRef)
	-- entrada directa (API / self-test), sin pasar por el ring
	local item = {
		remote = remote, method = method, args = args or {}, rets = rets,
		funcRef = funcRef, srcRef = srcRef, fromExec = false,
		blocked = false, path = "api", t = os.clock(),
	}
	finalize(item)
	return item.entry
end

function Spy:bySeq(n)
	for i = #self.logs, 1, -1 do
		if self.logs[i].seq == n then return self.logs[i] end
	end
	return nil
end

-- valores derivados, calculados sólo cuando los pedís
function Spy.argsText(entry)
	if entry._argsText then return entry._argsText end
	local ok, out = pcall(serializeArgs, entry.args)
	if not ok then out = {} end
	entry._argsText = out
	return out
end

function Spy.retsText(entry)
	if entry._retsText then return entry._retsText end
	local out = {}
	local n = entry.rets and alen(entry.rets) or 0
	for i = 1, n do
		out[i] = serializeOne(entry.rets[i])
	end
	entry._retsText = out
	return out
end

function Spy.entryInfo(entry)
	if entry._info ~= nil then return entry._info or nil end
	if not cfg.collectInfo then return nil end
	local key = entry.funcRef
	local cached = key and infoCache[key]
	if cached ~= nil then
		entry._info = cached or false
		return cached or nil
	end
	local ok, info = pcall(functionInfo, key)
	if ok and info then
		if key then infoCache[key] = info end
		entry._info = info
		return info
	end
	if key then infoCache[key] = false end
	entry._info = false
	return nil
end

-- =====================================================================
-- Hook 1 · __namecall
--   Cubre remote:FireServer(...), :InvokeServer(...) y también
--   remote["FireServer"](remote, ...) que compila a namecall con el mismo
--   method. El hook no serializa ni toca la UI: encola y delega.
-- =====================================================================

local function installNamecall()
	if not caps.hookmetamethod or Spy.hookState.namecall then return Spy.hookState.namecall end

	local original
	local sender = newcclosure_or(function(self, ...)
		if typeof(self) ~= "Instance" then return original(self, ...) end

		local method = namecallMethod()
		if cfg.verbose and method then
			local m = stats.methods
			m[method] = (m[method] or 0) + 1
		end
		if method ~= "FireServer" and method ~= "InvokeServer" then
			return original(self, ...)
		end

		local okC, cls = pcall(function() return self.ClassName end)
		if not okC or not remoteClass(cls) then return original(self, ...) end

		-- El hook ya probó que esto es un remote disparado. A partir de acá
		-- se captura SIEMPRE: el filtrado (executor, disabled, etc.) es de
		-- presentación. La v2 decidía acá y por eso perdía llamadas.
		stats.pings += 1
		local ours = isOwnCall()

		local meta = remoteMetaOf(self)
		local funcRef, srcRef
		if cfg.collectInfo then
			funcRef = callerFunction()
			if caps.getcallingscript then
				local okS, s = pcall(cap("getcallingscript"))
				if okS then srcRef = s end
			end
		end

		local args = { ... }
		if cfg.hooks[self] then
			local okH, newArgs = pcall(cfg.hooks[self], args)
			if okH and type(newArgs) == "table" then args = newArgs end
		end

		local blocked = isBlockedFast(self, meta.name)
		local isInvoke = (method == "InvokeServer")
		stats.namecall += 1
		autoblockCheck(meta.name)

		if isInvoke and (cfg.logReturns or Spy.wantReturns[self]) then
			-- InvokeServer devuelve valores: se corre en una task para poder
			-- capturar el retorno y devolvérselo al que llamó. Si el hilo no
			-- es cedeable (caso raro) se llama directo y se pierde el retorno.
			local co = coroutine.running()
			if co then
				local item = record(self, method, args, nil, funcRef, srcRef, ours, blocked, "sent")
				if blocked then return nil end
				task.spawn(function()
					reentrant = true
					local res = table.pack(original(self, unpackArgs(args)))
					reentrant = false
					attachReturns(item, res)
					pcall(coroutine.resume, co, table.unpack(res, 1, res.n))
				end)
				local y = table.pack(pcall(coroutine.yield))
				if y[1] then return table.unpack(y, 2, y.n) end
				return
			end
		end

		local item = record(self, method, args, nil, funcRef, srcRef, ours, blocked, "sent")
		if blocked then return nil end

		reentrant = true
		local pack = table.pack(original(self, unpackArgs(args)))
		reentrant = false
		if isInvoke and pack.n > 0 then attachReturns(item, pack) end
		if pack.n == 0 then return end
		return table.unpack(pack, 1, pack.n)
	end)

	original = hookmetamethod(game, "__namecall", sender)
	Spy.originals.namecall = original
	Spy.hookState.namecall = true
	return true
end

-- =====================================================================
-- Hook 2 · métodos como función
--   La misma closure nativa la comparten RemoteEvent.FireServer,
--   UnreliableRemoteEvent.FireServer y RemoteFunction.InvokeServer, así que
--   hookfunction sobre el prototipo cubre instancias creadas después.
--   Atrapa el path que namecall nunca ve:
--     local fs = remote.FireServer ; fs(remote, args)
--     pcall(remote.FireServer, remote, args)
--     remote["FireServer"](remote, args)
-- =====================================================================

local function installFunctionHook(class, method)
	if not caps.hookfunction then return false end
	local ok, result = pcall(function()
		local proto = Instance.new(class)
		local orig = proto[method]
		if type(orig) ~= "function" then
			proto:Destroy()
			return false
		end

		local sender = newcclosure_or(function(self, ...)
			if typeof(self) ~= "Instance" then return orig(self, ...) end

			if reentrant then
				-- namecall ya capturó esta misma llamada
				stats.dedup += 1
				return orig(self, ...)
			end

			stats.pings += 1
			local ours = isOwnCall()

			local meta = remoteMetaOf(self)
			local funcRef, srcRef
			if cfg.collectInfo then
				funcRef = callerFunction()
				if caps.getcallingscript then
					local okS, s = pcall(cap("getcallingscript"))
					if okS then srcRef = s end
				end
			end

			local args = { ... }
			if cfg.hooks[self] then
				local okH, newArgs = pcall(cfg.hooks[self], args)
				if okH and type(newArgs) == "table" then args = newArgs end
			end

			local blocked = isBlockedFast(self, meta.name)
			local isInvoke = (method == "InvokeServer")
			stats.functions += 1

			if isInvoke and (cfg.logReturns or Spy.wantReturns[self]) then
				local co = coroutine.running()
				if co then
					local item = record(self, method, args, nil, funcRef, srcRef, ours, blocked, "sent")
					if blocked then return nil end
					task.spawn(function()
						local res = table.pack(orig(self, unpackArgs(args)))
						attachReturns(item, res)
						pcall(coroutine.resume, co, table.unpack(res, 1, res.n))
					end)
					local y = table.pack(pcall(coroutine.yield))
					if y[1] then return table.unpack(y, 2, y.n) end
					return
				end
			end

			local item = record(self, method, args, nil, funcRef, srcRef, ours, blocked, "sent")
			if blocked then return nil end

			reentrant = true
			local pack = table.pack(orig(self, unpackArgs(args)))
			reentrant = false
			if isInvoke and pack.n > 0 then attachReturns(item, pack) end
			if pack.n == 0 then return end
			return table.unpack(pack, 1, pack.n)
		end)

		hookfunction(orig, sender)
		Spy.fnHooked[class .. "." .. method] = true
		proto:Destroy()
		return true
	end)
	return ok and result == true
end

local function installFunctionHooks()
	if not caps.hookfunction or Spy.hookState.functions then
		return Spy.hookState.functions
	end
	local any = false
	any = installFunctionHook("RemoteEvent", "FireServer") or any
	any = installFunctionHook("UnreliableRemoteEvent", "FireServer") or any
	any = installFunctionHook("RemoteFunction", "InvokeServer") or any
	Spy.hookState.functions = any
	return any
end

-- =====================================================================
-- Hook 3 · servidor → cliente
--   SimpleSpy sólo miraba OnClientEvent de remotes ya visibles en
--   ReplicatedStorage. Acá:
--     · OnClientEvent de eventos y UnreliableRemoteEvent
--     · OnClientInvoke de RemoteFunction, envolviendo el handler para ver
--       args Y el valor que devuelve el cliente
--     · remotes creados después de cargar (Instance.new + DescendantAdded)
-- =====================================================================

local function maybeRemoteKind(d)
	local ok, cls = pcall(function() return d.ClassName end)
	if not ok then return nil end
	if cls == "RemoteEvent" or cls == "UnreliableRemoteEvent" then return "event" end
	if cls == "RemoteFunction" then return "function" end
	return nil
end

local wrapClientInvoke

local function watchRemote(remote)
	if Spy.watched[remote] then return end
	local kind = maybeRemoteKind(remote)
	if not kind then return end

	Spy.watched[remote] = kind
	stats.remotes = (stats.remotes or 0) + 1

	if kind == "event" then
		pcall(function()
			remote.OnClientEvent:Connect(function(...)
				stats.recv += 1
				if not cfg.enabled or not cfg.logReceived then return end
				local packed = table.pack(...)
				record(remote, "OnClientEvent", packed, nil, nil, nil, false, false, "recv")
			end)
		end)
	end

	if kind == "function" then
		wrapClientInvoke(remote)
		-- el handler casi siempre se asigna después de crear el remote:
		-- el evento de cambio avisa al instante, y el refresco de 1 s cubre
		-- los ejecutores donde ese signal no dispara
		pcall(function()
			remote:GetPropertyChangedSignal("OnClientInvoke"):Connect(function()
				Spy.invokeWrapped[remote] = nil
				wrapClientInvoke(remote)
			end)
		end)
	end
end

-- El handler de un RemoteFunction suele asignarse DESPUÉS de Instance.new:
-- si se engancha sólo en el momento de descubrir el remote, se pierde.
-- Se reintenta desde el procesador cada segundo.
function wrapClientInvoke(remote)
	if Spy.invokeWrapped[remote] then return end
	local ok = pcall(function()
		local current = remote.OnClientInvoke
		if type(current) ~= "function" then return end
		Spy.invokeWrapped[remote] = true
		local orig = current
		remote.OnClientInvoke = newcclosure_or(function(...)
			stats.recv += 1
			local callArgs = table.pack(...)
			local res = table.pack(orig(table.unpack(callArgs, 1, callArgs.n)))
			record(remote, "OnClientInvoke", callArgs, res, nil, nil, false, false, "recv")
			return table.unpack(res, 1, res.n)
		end)
	end)
	_ = ok
end

function Spy:refreshInvokes()
	for inst, kind in pairs(self.watched) do
		if kind == "function" then
			wrapClientInvoke(inst)
		end
	end
end

local function scanTree(root)
	if not root then return end
	pcall(function()
		for _, d in ipairs(root:GetDescendants()) do
			watchRemote(d)
		end
	end)
	pcall(function() watchRemote(root) end)
end

local function installReceived()
	scanTree(game:GetService("ReplicatedStorage"))
	scanTree(game:GetService("ReplicatedFirst"))
	pcall(function() scanTree(workspace) end)

	-- todo el DataModel, no sólo RS: hay juegos con remotes bajo Workspace,
	-- Character, Lighting, o colgados de Players
	pcall(function()
		Spy.originals.rootAdd = game.DescendantAdded:Connect(function(d)
			watchRemote(d)
		end)
	end)

	-- remotes creados con Instance.new y nunca parenteados: se engancha la
	-- creación para registrarlos aunque no existan en el árbol todavía
	if caps.hookfunction then
		pcall(function()
			local origNew = Instance.new
			local sender = newcclosure_or(function(class, parent)
				local inst
				if parent ~= nil then
					inst = origNew(class, parent)
				else
					inst = origNew(class)
				end
				local okK, kind = pcall(maybeRemoteKind, inst)
				if okK and kind then
					stats.newFound += 1
					task.defer(watchRemote, inst)
				end
				return inst
			end)
			hookfunction(origNew, sender)
			Spy.originals.instanceNew = origNew
			Spy.hookState.instanceNew = true
		end)
	end

	Spy.hookState.received = true
end

-- =====================================================================
-- Hook 4 · BindableEvent / BindableFunction (opt-in)
--   Red interna cliente-cliente: no sale al servidor, pero es de donde
--   salen los remotes reales en juegos que envuelven todo en bindables.
-- =====================================================================

local function installBindableHooks()
	if not caps.hookfunction or Spy.hookState.bindables then return Spy.hookState.bindables end
	local any = false
	local function one(class, method, path)
		local ok, res = pcall(function()
			local proto = Instance.new(class)
			local orig = proto[method]
			if type(orig) ~= "function" then
				proto:Destroy()
				return false
			end
			local sender = newcclosure_or(function(self, ...)
				if typeof(self) ~= "Instance" then return orig(self, ...) end
				if cfg.bindables and cfg.enabled then
					local meta = remoteMetaOf(self)
					local args = { ... }
					task.defer(record, self, method, args, nil, nil, nil,
						callerIsOurs(), false, path)
				end
				return orig(self, ...)
			end)
			hookfunction(orig, sender)
			proto:Destroy()
			return true
		end)
		return ok and res == true
	end
	any = one("BindableEvent", "Fire", "bindable") or any
	Spy.hookState.bindables = any
	return any
end

-- =====================================================================
-- Procesador · el único lugar donde se serializa y se toca la UI
-- =====================================================================

local function processItem(item)
	finalize(item)
	if item.entry then
		-- precalienta los textos acá, en el hilo del procesador, no en el hook
		if cfg.previewArgs then
			pcall(Spy.argsText, item.entry)
		end
		if cfg.logReturns and item.entry.rets then
			pcall(Spy.retsText, item.entry)
		end
	end
end

local function buildScript(remote, args, method, returns)
	local path = instancePath(remote)
	local lines = { "-- generado por vvv·spy", "", "local args = {" }
	local n = alen(args)
	for i = 1, n do
		lines[#lines + 1] = "\t" .. serializeOne(args[i]) .. ","
	end
	lines[#lines + 1] = "}"
	if returns and alen(returns) > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "local rets = { unpack(args) } -- valores que devolvió el servidor (referencia)"
	end
	lines[#lines + 1] = ""
	local call = (method == "InvokeServer" and ":InvokeServer" or ":FireServer")
	lines[#lines + 1] = path .. call .. "(unpack(args))"
	return table.concat(lines, "\n")
end

local function scriptFor(entry)
	return buildScript(entry.remote, entry.args, entry.method, entry.rets)
end

-- =====================================================================
-- Escaneo profundo · remotes que SimpleSpy no ve
--   getgc() recorre todas las tablas y funciones vivas: aparecen remotes
--   que no cuelgan del DataModel y closures que los referencian.
--   getreg() mira el registro de Lua, incluidos upvalues de scripts.
-- =====================================================================

local SWEEP_BUDGET = 250000   -- nodos visitados por barrido, medible y acotado

local function sweepValue(v, depth, found, seen, ctx)
	if depth > 5 or ctx.found >= 400 or ctx.nodes >= SWEEP_BUDGET then return end
	ctx.nodes += 1
	local t = kindOf(v)
	if t == "Instance" then
		local ok, cls = pcall(function() return v.ClassName end)
		if ok and remoteClass(cls) and not found[v] then
			found[v] = true
			ctx.found += 1
		end
		return
	end
	if t ~= "table" then return end
	if seen[v] then return end
	seen[v] = true
	for k, val in pairs(v) do
		if ctx.found >= 400 or ctx.nodes >= SWEEP_BUDGET then break end
		ctx.nodes += 1
		if kindOf(k) == "Instance" then
			sweepValue(k, depth + 1, found, seen, ctx)
		end
		sweepValue(val, depth + 1, found, seen, ctx)
	end
	seen[v] = nil
end

local function sweepGC()
	if not caps.getgc then return 0 end
	local ok, gc = pcall(cap("getgc"), true)
	if not ok or type(gc) ~= "table" then
		ok, gc = pcall(cap("getgc"), false)
	end
	if not ok or type(gc) ~= "table" then return 0, "getgc no devolvió tabla" end

	local found, seen = {}, {}
	local ctx = { found = 0, nodes = 0 }
	local scanned = 0
	for _, v in pairs(gc) do
		scanned += 1
		if scanned > 120000 or ctx.nodes >= SWEEP_BUDGET then break end
		sweepValue(v, 0, found, seen, ctx)
	end

	local fresh = 0
	for inst in pairs(found) do
		if not Spy.watched[inst] then
			watchRemote(inst)
			if Spy.watched[inst] then fresh += 1 end
		end
	end
	stats.newFound += fresh
	stats.gcScanned = scanned
	stats.gcNodes = ctx.nodes
	return fresh, nil
end

-- instancias fuera del árbol: hay juegos que desparentean el remote después
-- de repartir la referencia, y ahí no lo ve ni GetDescendants ni DescendantAdded
local function sweepDetached()
	local fresh = 0
	local function one(fnName)
		if not caps[fnName] then return end
		local ok, list = pcall(cap(fnName))
		if not ok or type(list) ~= "table" then return end
		for _, inst in ipairs(list) do
			if kindOf(inst) == "Instance" and not Spy.watched[inst] then
				local okK, kind = pcall(maybeRemoteKind, inst)
				if okK and kind then
					watchRemote(inst)
					if Spy.watched[inst] then fresh += 1 end
				end
			end
		end
	end
	one("getinstances")
	one("getnilinstances")
	stats.newFound += fresh
	return fresh
end

local function regSweepScripts()
	if not caps.getreg then return 0 end
	local ok, reg = pcall(cap("getreg"))
	if not ok or type(reg) ~= "table" then return 0 end
	local found = 0
	for _, name in ipairs({ "scripts", "script", "loadedscripts" }) do
		local bucket = reg[name]
		if type(bucket) == "table" then
			for k in pairs(bucket) do
				if kindOf(k) == "Instance" then
					found += 1
					scanTree(k)
				end
			end
		end
	end
	return found
end

-- =====================================================================
-- Diagnóstico · números medibles, no adjetivos
-- =====================================================================

local function topRemotes(n)
	local rows = {}
	for name, total in pairs(stats.hits) do
		rows[#rows + 1] = { name = name, total = total }
	end
	table.sort(rows, function(a, b) return a.total > b.total end)
	local out = {}
	for i = 1, math.min(n or 10, #rows) do
		out[#out + 1] = string.format("%d. %s (%d)", i, rows[i].name, rows[i].total)
	end
	return out
end

local function selfTest()
	-- remotes falsos con el mismo contrato que usa el spy
	local out = {}
	local fake = {
		Name = "VVV_SELFTEST",
		ClassName = "RemoteEvent",
		GetFullName = function() return "game.ReplicatedStorage.VVV_SELFTEST" end,
	}
	local item = record(fake, "FireServer", { 1, "hola", { x = 1, y = { 2, 3 } } }, nil,
		nil, nil, false, false, "self")
	local entry = finalize(item)
	_ = entry
	local e = Spy.logs[#Spy.logs]
	if e and e.name == "VVV_SELFTEST" then
		out[#out + 1] = "captura: OK (#" .. e.seq .. ")"
		local txt = Spy.argsText(e)
		out[#out + 1] = "args: " .. table.concat(txt, ", ")
	else
		out[#out + 1] = "captura: FALLÓ (no llegó al log, revisá filtros)"
	end
	if stats.dropped > 0 then
		out[#out + 1] = "descartes de ring: " .. stats.dropped .. " (subí el ring o bajá el trabajo)"
	end
	return table.concat(out, "\n")
end

-- =====================================================================
-- UI · Rayfield Gen2
-- =====================================================================

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local window = Rayfield:CreateWindow({
	name = "vvv · spy",
	subtitle = "remote spy v3 · deep capture",
	sidebarLayout = true,
	theme = "amethyst",
})

local ui = { window = window }

local function notify(title, content, dur)
	pcall(function()
		window:Notify({ title = title, content = content, duration = dur or 5 })
	end)
end

local function showText(txt)
	if ui.codeConsole then pcall(function() ui.codeConsole:Set(txt) end) end
end

local function nextEntry()
	-- Devuelve la última entrada que NO sea del propio executor
	for i = #Spy.logs, 1, -1 do
		if not Spy.logs[i].fromExec then return Spy.logs[i] end
	end
	return Spy.logs[#Spy.logs]
end

-- ---------------------------- LOG ----------------------------

local logTab = window:CreateTab({ name = "Log" })
logTab:CreateSection({ name = "Eventos" })

ui.spyToggle = logTab:CreateToggle({
	name = "Spy activo",
	value = true,
	callback = function(v) cfg.enabled = v end,
})

ui.console = logTab:CreateConsole({
	name = "Remotes",
	height = 250,
	follow = true,
	maxLines = 500,
})

local logGrid = logTab:CreateGroup()
local logColA = logGrid:CreateGroup({ direction = "column" })
logColA:CreateToggle({ name = "FireServer (sent)", value = true,
	callback = function(v) cfg.logSent = v end })
logColA:CreateToggle({ name = "OnClientEvent (recv)", value = true,
	callback = function(v) cfg.logReceived = v end })
local logColB = logGrid:CreateGroup({ direction = "column" })
logColB:CreateToggle({ name = "Return values", value = true,
	callback = function(v) cfg.logReturns = v end })
logColB:CreateToggle({ name = "Ocultar del executor", value = true,
	description = "Las llamadas del propio executor se capturan igual; esto sólo las esconde del log",
	callback = function(v) cfg.hideExec = v end })

logColB:CreateToggle({ name = "Modo verbose", value = false,
	description = "Cuenta todos los métodos de namecall, no sólo FireServer/InvokeServer",
	callback = function(v) cfg.verbose = v end })

logTab:CreateSlider({
	name = "Máximo de remotes en log",
	range = { 50, 1000 },
	increment = 50,
	value = 250,
	callback = function(v) cfg.maxLogs = v end,
})

ui.filterInput = logTab:CreateInput({
	name = "Filtro de nombre",
	placeholder = "vacío = todo",
	value = "",
	callback = function(txt)
		cfg.filter = tostring(txt):lower()
	end,
})

logTab:CreateButton({
	name = "Clr Logs",
	callback = function()
		Spy:clear()
		if ui.console then
			pcall(function() ui.console:Clear() end)
			pcall(function() ui.console:Append("-- log limpio --") end)
		end
	end,
})

logTab:CreateButton({
	name = "Seguir último (auto)",
	description = "Después de cada captura, carga la entrada en Detalle",
	callback = function()
		ui.autoFollow = not ui.autoFollow
		notify("Auto-follow", ui.autoFollow and "prendido" or "apagado", 4)
	end,
})

-- ---------------------------- DETALLE ----------------------------

local detailTab = window:CreateTab({ name = "Detalle" })
detailTab:CreateSection({ name = "Entrada seleccionada" })

local selected = nil

local detailText = detailTab:CreateText({
	name = "Nada seleccionado",
	text = "Elegí una entrada del log (o usá 'Cargar última') para habilitar las acciones.",
})

ui.codeConsole = detailTab:CreateConsole({
	name = "Script generado",
	height = 220,
	follow = false,
})

local idxInput = detailTab:CreateInput({
	name = "Índice de entrada",
	description = "El número #N del log",
	value = "",
	placeholder = "1",
	callback = function() end,
})

local function showEntry(entry)
	selected = entry
	if not entry then return end
	pcall(function() ui.codeConsole:Set(scriptFor(entry)) end)
	local info = Spy.entryInfo(entry)
	local infoLine = info and describeInfo(info) or "info deshabilitada"
	local rets = Spy.retsText(entry)
	pcall(function()
		detailText:SetTitle(string.format("#%d · %s · %s", entry.seq, entry.name, entry.cls))
		detailText:Set(table.concat({
			"método: " .. entry.method .. "  ·  ruta: " .. tostring(entry.path),
			"script: " .. tostring(entry.scriptPath or entry.script),
			"args: " .. alen(entry.args) .. "  ·  returns: " .. #rets,
			infoLine,
			entry.blocked and "estado: BLOQUEADO" or "estado: enviado",
			entry.fromExec and "origen: executor" or "origen: juego",
		}, "\n"))
	end)
end

detailTab:CreateButton({
	name = "Cargar última entrada",
	callback = function()
		if #Spy.logs == 0 then
			notify("Spy", "Todavía no hay logs")
			return
		end
		showEntry(nextEntry())
	end,
})

detailTab:CreateButton({
	name = "Cargar por índice",
	callback = function()
		local n = tonumber(idxInput.value)
		local entry = n and Spy.logs[n]
		if not entry then
			notify("Spy", "Índice inválido")
			return
		end
		showEntry(entry)
	end,
})

detailTab:CreateSection({ name = "Herramientas" })

detailTab:CreateButton({
	name = "Copy Code",
	description = "Copia el Lua que replica esta llamada",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local ok = clip(scriptFor(selected))
		notify("Copy Code", ok and "copiado" or "este executor no tiene setclipboard", ok and 4 or 8)
	end,
})

detailTab:CreateButton({
	name = "Copy Args",
	description = "Sólo los argumentos, en una tabla Lua",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local ok = clip("{\n\t" .. table.concat(Spy.argsText(selected), ",\n\t") .. "\n}")
		notify("Copy Args", ok and "copiado" or "sin setclipboard", 4)
	end,
})

detailTab:CreateButton({
	name = "Copy Return",
	description = "Valores que devolvió el servidor",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local rets = Spy.retsText(selected)
		if #rets == 0 then
			notify("Copy Return", "esta entrada no tiene retorno capturado", 6)
			return
		end
		local ok = clip(table.concat(rets, ",\n"))
		notify("Copy Return", ok and "copiado" or "sin setclipboard", 4)
	end,
})

detailTab:CreateButton({
	name = "Copy Remote",
	description = "Sólo la ruta del RemoteEvent/RemoteFunction",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local path = instancePath(selected.remote)
		local ok = clip(path)
		notify("Copy Remote", ok and path or "sin setclipboard", ok and 6 or 8)
	end,
})

detailTab:CreateButton({
	name = "Run Code",
	description = "Ejecuta el script del visor y muestra qué devuelve",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local ok, res = API.RunCode(selected)
		notify(ok and "Run Code ok" or "Run Code falló", tostring(res):sub(1, 220), 8)
	end,
})

detailTab:CreateButton({
	name = "Get Script",
	description = "Ruta del LocalScript/ModuleScript que originó la llamada",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local path = selected.scriptPath
		if not path then
			notify("Get Script", "El executor no dio callingscript para esta entrada")
			return
		end
		clip(path)
		notify("Get Script", path, 8)
	end,
})

detailTab:CreateButton({
	name = "Function Info",
	description = "nombre, fuente, línea, constantes y upvalues de la función que disparó",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local info = Spy.entryInfo(selected)
		if not info then
			notify("Function Info", "No se recolectó (Disable Info activo o executor sin debug)")
			return
		end
		local lines = { describeInfo(info), "" }
		if info.constants then
			lines[#lines + 1] = "-- constantes"
			lines[#lines + 1] = serializeOne(info.constants)
		end
		if info.upvalues then
			lines[#lines + 1] = "-- upvalues"
			lines[#lines + 1] = serializeOne(info.upvalues)
		end
		showText(table.concat(lines, "\n"))
		notify("Function Info", describeInfo(info):sub(1, 300), 10)
	end,
})

detailTab:CreateButton({
	name = "Decompile",
	description = "Extrae el fuente del script que invocó el remoto",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local sc = selected.scriptRef
		if not sc and selected.info and selected.info.source then
			sc = scriptFromSource(selected.info.source)
		end
		if not sc then
			notify("Decompile", "No hay script asociado a esta entrada")
			return
		end
		local src, err = decompileOf(sc)
		if not src then notify("Decompile", err, 8) return end
		showText(src)
		local ok = clip(src)
		notify("Decompile", ok and "fuente copiado" or "fuente en el visor", 6)
	end,
})

detailTab:CreateButton({
	name = "Conexiones",
	description = "Quién está conectado a este remote (getconnections)",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local sig
		pcall(function() sig = selected.remote.OnClientEvent end)
		if not sig then
			notify("Conexiones", "esta entrada no tiene OnClientEvent (RemoteFunction)", 6)
			return
		end
		local list, err = API and API.GetConnections and API.GetConnections(sig)
		if not list then
			notify("Conexiones", tostring(err or "sin getconnections"), 8)
			return
		end
		local txt = table.concat(list, "\n")
		showText(txt)
		notify("Conexiones", #list .. " conexiones", 5)
	end,
})

detailTab:CreateButton({
	name = "Replay",
	description = "Reenvía el remote con los args exactos (queda marcado como tuyo)",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local ok, err = API.Replay(selected)
		notify(ok and "Replay enviado" or "Replay falló",
			ok and (selected.method .. " · " .. selected.name) or tostring(err), 5)
	end,
})

detailTab:CreateSection({ name = "Filtros sobre esta entrada" })

detailTab:CreateButton({
	name = "Exclude (i)",
	description = "Oculta futuras llamadas de esta instancia, pero siguen saliendo",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		cfg.excluded[selected.remote] = true
		notify("Exclude (i)", selected.name, 4)
	end,
})

detailTab:CreateButton({
	name = "Exclude (n)",
	description = "Oculta futuras llamadas por nombre, pero siguen saliendo",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		cfg.excluded[selected.name] = true
		notify("Exclude (n)", selected.name, 4)
	end,
})

detailTab:CreateButton({
	name = "Block (i)",
	description = "Cancela el envío de esta instancia al servidor",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		cfg.blocked[selected.remote] = true
		notify("Block (i)", selected.name, 4)
	end,
})

detailTab:CreateButton({
	name = "Block (n)",
	description = "Cancela el envío de todos los remotes con ese nombre",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		cfg.blocked[selected.name] = true
		notify("Block (n)", selected.name, 4)
	end,
})

-- ---------------------------- CONFIG ----------------------------

local cfgTab = window:CreateTab({ name = "Config" })
cfgTab:CreateSection({ name = "Comportamiento" })

cfgTab:CreateDropdown({
	name = "Método de hook",
	description = "namecall cubre :FireServer; funciones cubre referencias cacheadas y corchetes",
	options = { "both", "namecall", "functions" },
	value = "both",
	callback = function(choice)
		cfg.method = choice
		notify("Hook", "modo " .. choice, 4)
	end,
})

cfgTab:CreateToggle({
	name = "Captura profunda (GC)",
	description = "getgc + getreg: encuentra remotes que no cuelgan del DataModel",
	value = true,
	callback = function(v) cfg.deepSweep = v end,
})

cfgTab:CreateToggle({
	name = "BindableEvent / BindableFunction",
	description = "Red interna cliente-cliente: de acá salen los remotes reales en juegos con wrappers",
	value = false,
	callback = function(v)
		cfg.bindables = v
		if v then installBindableHooks() end
	end,
})

cfgTab:CreateToggle({
	name = "Autoblock",
	description = "Bloquea remotes que pasan el umbral de disparos por segundo",
	value = false,
	callback = function(v)
		cfg.autoblock = v
		Spy.rate = {}
	end,
})

cfgTab:CreateSlider({
	name = "Umbral de autoblock",
	range = { 5, 200 },
	increment = 5,
	value = 25,
	suffix = "/s",
	callback = function(v) cfg.autoblockRate = v end,
})

cfgTab:CreateToggle({
	name = "Disable Info",
	description = "Apaga la recolección de metadatos de funciones: menos lag",
	value = false,
	callback = function(v) cfg.collectInfo = not v end,
})

cfgTab:CreateToggle({
	name = "Key To String",
	description = "Claves que no son string se muestran legibles en el script generado",
	value = false,
	callback = function(v) cfg.keyToString = v end,
})

cfgTab:CreateToggle({
	name = "Toggle Return Values",
	value = true,
	callback = function(v) cfg.logReturns = v end,
})

cfgTab:CreateSection({ name = "Listas" })

cfgTab:CreateButton({
	name = "Clr Blacklist",
	description = "Restaura los remotes excluidos de la vista",
	callback = function()
		cfg.excluded = {}
		excludedPaths = {}
		pathExcludeCount = 0
		notify("Clr Blacklist", "exclusiones limpiadas", 4)
	end,
})

cfgTab:CreateButton({
	name = "Clr Blocklist",
	description = "Desbloquea todos los remotes detenidos",
	callback = function()
		cfg.blocked = {}
		blockedPaths = {}
		pathBlockCount = 0
		Spy.rate = {}
		notify("Clr Blocklist", "bloqueos limpiados", 4)
	end,
})

cfgTab:CreateButton({
	name = "Clr Hooks",
	description = "Quita los HookRemote activos",
	callback = function()
		cfg.hooks = {}
		notify("Clr Hooks", "hooks limpiados", 4)
	end,
})

-- ---------------------------- DIAGNÓSTICO ----------------------------

local diagTab = window:CreateTab({ name = "Diagnóstico" })
diagTab:CreateSection({ name = "Estado de la captura" })

local diagText = diagTab:CreateText({
	name = "Contadores",
	text = "midiendo…",
})

local function countSet(t)
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

local function refreshDiag()
	local function yn(b) return b and "sí" or "NO" end
	local g = stats.gate
	local hidden = g.exec + g.disabled + g.filter + g.excluded + g.offSent + g.offRecv
	local lines = {
		"== SALUD DEL HOOK ==",
		string.format("pings %d · capturadas %d · visibles %d · ocultas %d",
			stats.pings, stats.captured, #Spy.logs, hidden),
		string.format("  ocultas por: executor %d · apagado %d · filtro %d · exclude %d · toggles %d",
			g.exec, g.disabled, g.filter, g.excluded, g.offSent + g.offRecv),
		string.format("namecall %d · funciones %d · recv %d · del executor %d",
			stats.namecall, stats.functions, stats.recv, stats.exec),
		string.format("ring %d/%d · descartes %d · reentrancia %d · errores %d/%d",
			ringLen, RING, stats.dropped, stats.dedup, stats.err, stats.ser),
		string.format("remotes vigilados %d · nuevos %d · Instance.new %s · invokes envueltos %d",
			Spy:watchedCount(), stats.newFound, yn(Spy.hookState.instanceNew),
			countSet(Spy.invokeWrapped)),
		"",
		"-- capacidades",
		string.format("getgc %s · getreg %s · getinstances %s · getconnections %s",
			yn(caps.getgc), yn(caps.getreg), yn(caps.getinstances), yn(caps.getconnections)),
		string.format("hookmetamethod %s · hookfunction %s · checkcaller %s · newcclosure %s",
			yn(caps.hookmetamethod), yn(caps.hookfunction), yn(caps.checkcaller), yn(caps.newcclosure)),
		string.format("debug.info %s · getconstants %s · getupvalues %s · decompile %s",
			yn(caps.debuginfo), yn(caps.getconstants), yn(caps.getupvalues), yn(caps.decompile)),
	}
	if stats.pings > 0 and stats.captured == 0 then
		lines[#lines + 1] = string.format(
			"!! %d pings y 0 capturas: el hook ve remotes pero se cae antes de registrar. Mandá esto.", stats.pings)
	elseif stats.pings == 0 and Spy.hookState.namecall then
		lines[#lines + 1] = "hook instalado y 0 pings: nadie disparó un remote todavía (o el juego no usa los métodos estándar)"
	end
	if stats.lastErr then
		lines[#lines + 1] = "-- último error: " .. tostring(stats.lastErr):sub(1, 200)
	end
	if cfg.verbose then
		local methods = {}
		for m, n in pairs(stats.methods) do methods[#methods + 1] = m .. "=" .. n end
		table.sort(methods)
		if #methods > 0 then
			lines[#lines + 1] = ""
			lines[#lines + 1] = "-- métodos de namecall vistos"
			lines[#lines + 1] = table.concat(methods, " · ")
		end
	end

	local top = topRemotes(10)
	if #top > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "-- top remotes"
		for _, line in ipairs(top) do lines[#lines + 1] = line end
	end
	pcall(function() diagText:Set(table.concat(lines, "\n")) end)
end

diagTab:CreateButton({
	name = "Probar hook (ping)",
	description = "Dispara un remote real y verifica que el spy lo registre, sin tocar el juego",
	callback = function()
		local lines = {}
		local before = #Spy.logs
		lines[#lines + 1] = selfTest()
		local entry = Spy.logs[#Spy.logs]
		if entry then
			-- replay del último remote viejo, marcado como propio
			local old = nil
			for i = #Spy.logs - 1, 1, -1 do
				if Spy.logs[i].remote and not Spy.logs[i].blocked then old = Spy.logs[i] break end
			end
			if old then
				local ok, err = API.Replay(old)
				lines[#lines + 1] = "replay " .. (ok and "ok" or ("falló: " .. tostring(err)))
			end
		end
		local txt = table.concat(lines, "\n")
		showText(txt)
		notify("Ping", txt:gsub("\n", " | "):sub(1, 300), 12)
		_ = before
	end,
})

diagTab:CreateButton({
	name = "Re-escanear",
	description = "RS + ReplicatedFirst + Workspace con GetDescendants",
	callback = function()
		scanTree(game:GetService("ReplicatedStorage"))
		scanTree(game:GetService("ReplicatedFirst"))
		pcall(function() scanTree(workspace) end)
		refreshDiag()
		notify("Spy", "re-escaneado", 4)
	end,
})

diagTab:CreateButton({
	name = "Escaneo profundo (getgc + getreg)",
	description = "Encuentra remotes fuera del DataModel y scripts en el registro",
	callback = function()
		local ok, fresh, err = pcall(function()
			local a, b = sweepGC()
			local c = regSweepScripts()
			return a, b, c
		end)
		refreshDiag()
		if ok then
			notify("Deep sweep", tostring(fresh) .. " nuevos · " .. tostring(err) .. " scripts", 8)
		else
			notify("Deep sweep", "falló: " .. tostring(fresh), 8)
		end
	end,
})

diagTab:CreateButton({
	name = "Listar remotes (copiar)",
	callback = function()
		local ok, list = pcall(function()
			local out, seen = {}, {}
			for inst in pairs(Spy.watched) do
				local p = pathOf(inst)
				if p and not seen[p] then
					seen[p] = true
					out[#out + 1] = p
				end
			end
			table.sort(out)
			return out
		end)
		if not ok then notify("Spy", "no se pudo listar") return end
		local text = table.concat(list, "\n")
		local copied = clip(text)
		notify("Remotes (" .. #list .. ")", copied and "copiado" or text:sub(1, 250), 8)
	end,
})

diagTab:CreateButton({
	name = "Self-test",
	description = "Inyecta una captura falsa y verifica que llegue al log",
	callback = function()
		local txt = selfTest()
		showText(txt)
		notify("Self-test", txt, 12)
	end,
})

diagTab:CreateButton({
	name = "Shutdown",
	callback = function()
		if genv.VVV_SPY then genv.VVV_SPY.shutdown() end
	end,
})

-- =====================================================================
-- Procesador · 20 Hz. Acá se serializa, se cachea info y se escribe UI.
-- =====================================================================

ui.autoFollow = false

local function drain()
	local batch = {}
	local n = 0
	while n < 300 do
		local item = shiftRaw()
		if not item then break end
		batch[#batch + 1] = item
		n += 1
	end
	if #batch == 0 then return 0 end

	for i = 1, #batch do
		pcall(processItem, batch[i])
	end

	for i = 1, #batch do
		local entry = batch[i].entry
		local shown = entry and ((entry.type == "sent" and cfg.logSent)
			or (entry.type == "recv" and cfg.logReceived))
		if shown then
			local mark = entry.type == "recv" and "◀" or "▶"
			pcall(function()
				ui.console:Append(string.format("#%d %s %s%s · %s%s",
					entry.seq, mark, entry.blocked and "[BLOCK] " or "", entry.name,
					entry.script, entry.fromExec and " (executor)" or ""))
			end)
		end
	end

	if ui.autoFollow and #Spy.logs > 0 then
		local last = Spy.logs[#Spy.logs]
		if last ~= ui.lastFollowed then
			ui.lastFollowed = last
			pcall(showEntry, last)
		end
	end
	return #batch
end

task.spawn(function()
	local lastDiag, lastSweep, lastInvoke = 0, os.clock(), 0
	while Spy.running do
		task.wait(0.05)
		pcall(drain)
		while #notices > 0 do
			local name = table.remove(notices, 1)
			notify("Autoblock", name .. " bloqueado por spam", 6)
		end
		local now = os.clock()
		if now - lastDiag > 2 then
			lastDiag = now
			pcall(refreshDiag)
		end
		if now - lastInvoke > 1 then
			lastInvoke = now
			pcall(Spy.refreshInvokes, Spy)
		end
		if cfg.deepSweep and now - lastSweep > 15 then
			lastSweep = now
			pcall(sweepGC)
		end
	end
end)

-- =====================================================================
-- Instalación
-- =====================================================================

local okNamecall = installNamecall()
local okFn = installFunctionHooks()
installReceived()
refreshDiag()

if not okNamecall and not okFn then
	notify("Spy sin hooks",
		"Este executor no tiene hookmetamethod ni hookfunction: sólo queda el watch de OnClientEvent.", 12)
end

-- =====================================================================
-- API pública · getgenv().VVV_SPY
--   Misma forma que SimpleSpy v2.2 para lo que otros scripts esperan,
--   más lo que esta versión agrega. Nada de esto bloquea al spy: si algo
--   falla acá, la captura sigue.
-- =====================================================================

API = {}

API.version = "3.0"
API.logs    = Spy.logs
API.stats   = stats

API.HookRemote = function(target, fn)
	if typeof(target) ~= "Instance" then error("Instance expected", 2) end
	if type(fn) ~= "function" then error("function expected", 2) end
	cfg.hooks[target] = fn
end

API.BlockRemote = function(target)
	if typeof(target) == "Instance" then
		if not cfg.blocked[target] then pathBlockCount += 0 end
		cfg.blocked[target] = true
	elseif type(target) == "string" then
		cfg.blocked[target] = true
	end
	return true
end

API.UnblockRemote = function(target)
	cfg.blocked[target] = nil
	return true
end

API.BlockPath = function(path)
	if type(path) ~= "string" then error("string expected", 2) end
	blockedPaths[path] = true
	pathBlockCount += 1
	return true
end

API.ExcludeRemote = function(target)
	if typeof(target) == "Instance" or type(target) == "string" then
		cfg.excluded[target] = true
		return true
	end
	return false
end

API.ExcludePath = function(path)
	if type(path) ~= "string" then error("string expected", 2) end
	excludedPaths[path] = true
	pathExcludeCount += 1
	return true
end

API.GetRemoteFiredSignal = function(remote)
	if typeof(remote) ~= "Instance" then error("Instance expected", 2) end
	return remoteSignal(remote)
end

API.CaptureReturns = function(remote, on)
	if typeof(remote) ~= "Instance" then error("Instance expected", 2) end
	Spy.wantReturns[remote] = on ~= false
	return Spy.wantReturns[remote]
end

API.toggleSpy = function()
	cfg.enabled = not cfg.enabled
	if ui.spyToggle then
		pcall(function() ui.spyToggle:Set(cfg.enabled, true) end)
	end
	return cfg.enabled
end

API.toggleSpyMethod = function(mode)
	local order = { "both", "namecall", "functions" }
	if mode and (mode == "both" or mode == "namecall" or mode == "functions") then
		cfg.method = mode
	else
		local idx = table.find(order, cfg.method) or 1
		cfg.method = order[(idx % #order) + 1]
	end
	return cfg.method
end

API.setMethod = function(mode) return API.toggleSpyMethod(mode) end

API.SetBindables = function(on)
	cfg.bindables = on ~= false
	if cfg.bindables then installBindableHooks() end
	return cfg.bindables
end

API.GetStats = function()
	return {
		pings = stats.pings,
		methods = stats.methods,
		gate = stats.gate,
		captured = stats.captured,
		namecall = stats.namecall,
		functions = stats.functions,
		recv = stats.recv,
		exec = stats.exec,
		dropped = stats.dropped,
		dedup = stats.dedup,
		errors = stats.err,
		serErrors = stats.ser,
		newRemotes = stats.newFound,
		gcScanned = stats.gcScanned,
		gcNodes = stats.gcNodes,
		remotes = Spy:watchedCount(),
		logs = #Spy.logs,
		ring = ringLen,
		lastError = stats.lastErr,
	}
end

API.Sweep = function()
	local fresh, err = sweepGC()
	sweepDetached()
	regSweepScripts()
	scanTree(game:GetService("ReplicatedStorage"))
	scanTree(game:GetService("ReplicatedFirst"))
	pcall(function() scanTree(workspace) end)
	if err then return false, err end
	return true, fresh
end

API.SelfTest = selfTest

API.shutdown = function()
	Spy.running = false
	for _, key in ipairs({ "rootAdd", "descendant" }) do
		local c = Spy.originals[key]
		if c and c.Disconnect then pcall(function() c:Disconnect() end) end
	end
	cfg.signals = {}
	if ui.window and not ui.window.unloaded then
		pcall(function() ui.window:Unload() end)
	end
	if genv.VVV_SPY == API then genv.VVV_SPY = nil end
end

API.genScript = function(remote, args, method)
	return buildScript(remote, args or {}, method or "FireServer")
end

API.ArgsToString = function(args, withKeys)
	local t = serializeArgs(args or {})
	return table.concat(t, withKeys and ",\n" or ", ")
end

API.ValueToString = function(value)
	return serializeOne(value)
end

-- nombre de variable válido en Lua; "v_has key" no compila
local function safeName(name, fallback)
	if type(name) == "string" then
		local cleaned = name:gsub("[^%w_]", "_")
		if cleaned:match("^[%a_][%w_]*$") then return cleaned end
		if cleaned:match("^_%w*$") then return cleaned end
	end
	return fallback
end

API.TableToVars = function(tbl)
	if type(tbl) ~= "table" then error("table expected", 2) end
	local lines, i = {}, 0
	for k, v in pairs(tbl) do
		i += 1
		local name = safeName(k, "v_" .. i)
		lines[#lines + 1] = "local " .. name .. " = " .. serializeOne(v)
	end
	return table.concat(lines, "\n")
end

API.ValueToVar = function(value, name)
	return "local " .. safeName(name, "v_1") .. " = " .. serializeOne(value)
end

API.GetFunctionInfo = function(fn)
	if type(fn) ~= "function" then error("function expected", 2) end
	local info = functionInfo(fn)
	return info
end

API.DescribeFunctionInfo = function(fn)
	return describeInfo(functionInfo(fn))
end

API.getScriptFromSrc = function(src)
	return scriptFromSource(src)
end

API.decompileScript = function(script)
	return decompileOf(script)
end

API.GetConnections = function(signal)
	local list = connectionsOf(signal)
	if not list then return nil, "este executor no tiene getconnections" end
	local out = {}
	for i = 1, #list do
		out[i] = describeConnection(list[i])
	end
	return out
end

API.getplayer = function(inst)
	if typeof(inst) ~= "Instance" then return nil end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and (inst == p.Character or inst:IsDescendantOf(p.Character)) then
			return p
		end
	end
	return nil
end

API.Replay = function(entry)
	if not entry then return false, "sin entrada" end
	markOwn()
	local ok, err = pcall(function()
		if entry.method == "InvokeServer" then
			return entry.remote:InvokeServer(unpackArgs(entry.args))
		end
		entry.remote:FireServer(unpackArgs(entry.args))
	end)
	return ok, err
end

API.RunCode = function(entry)
	if not entry then return false, "sin entrada" end
	local code = buildScript(entry.remote, entry.args, entry.method, entry.rets)
	local fn, err = loadstring(code)
	if not fn then return false, "no compila: " .. tostring(err) end
	markOwn()
	local ok, res = pcall(fn)
	return ok, res
end

API.RefreshInvokes = function()
	Spy:refreshInvokes()
	return true
end

API.clear = function() Spy:clear() end
API.notify = function(title, content, dur) notify(title, content, dur) end

API.Follow = function(entry)
	if entry then
		showEntry(entry)
		return true
	end
	return false
end

genv.VVV_SPY = API

-- compat de globals que otros scripts esperan ver. _G puede ser readonly
-- en algunos entornos: si no se puede escribir, se respeta el valor existente.
pcall(function()
	if rawget(_G, "SIMPLESPYCONFIG_MaxRemotes") == nil then
		rawset(_G, "SIMPLESPYCONFIG_MaxRemotes", cfg.maxLogs)
	end
end)
pcall(function()
	if rawget(_G, "SimpleSpyMaxTableSize") == nil then
		rawset(_G, "SimpleSpyMaxTableSize", MAX_TABLE)
	end
end)

notify("vvv · spy v" .. API.version, string.format(
	"namecall:%s · funciones:%s · receive:%s · remotes:%d (Instance.newhook:%s)",
	tostring(Spy.hookState.namecall), tostring(Spy.hookState.functions),
	tostring(Spy.hookState.received), Spy:watchedCount(), tostring(Spy.hookState.instanceNew)
), 8)

if cfg.enabled then
	task.delay(3, function()
		if API.Sweep then pcall(API.Sweep) end
	end)
end
