--[[
	vvv · spy
	Remote spy con la arquitectura de SimpleSpy v2.2 y UI en Rayfield Gen2.

	Hooks
	  · __namecall (newcclosure + checkcaller)  → FireServer / InvokeServer
	  · hookfunction sobre RemoteEvent.FireServer, UnreliableRemoteEvent.FireServer
	    y RemoteFunction.InvokeServer            → agarra referencias cacheadas
	  · OnClientEvent de cada remote descubierto → tráfico servidor -> cliente

	Herramientas (por entrada): Copy Code, Copy Remote, Run Code, Get Script,
	Function Info, Decompile, Exclude (i)/(n), Block (i)/(n).

	Panel: Clr Logs, Clr Blacklist, Clr Blocklist, Autoblock, Disable Info,
	Toggle Return Values, Key To String, modo de hook (namecall / funciones).

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

local genv = (getgenv and getgenv()) or _G
if genv.VVV_SPY then
	pcall(function() genv.VVV_SPY.shutdown() end)
end

-- =====================================================================
-- Capacidades del executor · se muestran, no se asumen
-- =====================================================================

local function has(name)
	return type(rawget and rawget(_G, name) or _G[name]) == "function"
end

local caps = {
	hookmetamethod   = has("hookmetamethod"),
	hookfunction     = has("hookfunction"),
	newcclosure      = has("newcclosure"),
	checkcaller      = has("checkcaller"),
	getcallingscript = has("getcallingscript"),
	getscriptfromsrc = has("getscriptfromsrc"),
	decompile        = has("decompile"),
	getscriptbytecode= has("getscriptbytecode"),
	getconstants     = has("getconstants") or (debug and type(debug.getconstants) == "function"),
	getupvalues      = has("getupvalues") or (debug and type(debug.getupvalues) == "function"),
	debuginfo        = (debug and type(debug.info) == "function") or has("getinfo"),
	setclipboard     = has("setclipboard") or has("toclipboard") or has("set_clipboard"),
	firetouch        = false,
}

local function cap(name)
	return _G[name]
end

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
	if not has("isexecutorclosure") then return false end
	local ok, r = pcall(cap("isexecutorclosure"), f)
	return ok and r or false
end

local function clip(text)
	if has("setclipboard") then return pcall(cap("setclipboard"), text) end
	if has("toclipboard") then return pcall(cap("toclipboard"), text) end
	if has("set_clipboard") then return pcall(cap("set_clipboard"), text) end
	return false
end

-- =====================================================================
-- Config
-- =====================================================================

local cfg = {
	enabled      = true,
	method       = "both",    -- both | namecall | functions
	logSent      = true,
	logReceived  = true,
	logReturns   = true,
	logExecutors = false,
	collectInfo  = true,      -- Disable Info lo apaga (menos lag)
	keyToString  = false,
	autoblock    = false,
	autoblockRate = 25,       -- disparos/segundo antes de bloquear
	maxLogs      = 250,
	blocked      = {},        -- [Instance | string] = true
	excluded     = {},        -- [Instance | string] = true
	hooks        = {},        -- [Instance] = function(args) -> args
	signals      = {},        -- [Instance] = ScriptSignal
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

-- =====================================================================
-- Serializador
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
		if full:sub(1, 5) == "game." then return full end
		return full
	end
	local okName, name = pcall(function() return inst.Name end)
	return "\"" .. tostring(okName and name or "?") .. "\" --[[instancia fuera del DataModel]]"
end

local function serialize(v, depth, seen)
	depth = depth or 0
	local t = typeof(v)

	if t == "string" then
		return quote(v)
	elseif t == "number" then
		if v ~= v then return "0/0 --[[NaN]]" end
		if v == math.huge then return "math.huge" end
		if v == -math.huge then return "-math.huge" end
		if math.floor(v) == v and math.abs(v) < 1e15 then return string.format("%d", v) end
		return string.format("%.14g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "nil" then
		return "nil"
	elseif t == "Vector3" then
		return string.format("Vector3.new(%s, %s, %s)",
			serialize(v.X), serialize(v.Y), serialize(v.Z))
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
		return tostring(v)
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
		if depth >= MAX_DEPTH then return "{ --[[MAX DEPTH]] }" end
		seen = seen or {}
		if seen[v] then return "{ --[[DUPLICATE]] }" end
		seen[v] = true

		local keys, count = {}, 0
		local limit = maxTable()
		for k in pairs(v) do
			count += 1
			if count > limit then
				seen[v] = nil
				return "{ --[[MAXIMUM TABLE SIZE REACHED: " .. count .. "+ keys; ajustá SimpleSpyMaxTableSize]] }"
			end
			keys[#keys + 1] = k
		end

		local isArray = (count == #v)
		local body = {}
		if isArray then
			for i = 1, #v do
				body[#body + 1] = serialize(v[i], depth + 1, seen)
			end
		else
			for _, k in ipairs(keys) do
				local kt = typeof(k)
				local keyStr
				if kt == "string" then
					if k:match("^[%a_][%w_]*$") then
						keyStr = k
					else
						keyStr = "[" .. quote(k) .. "]"
					end
				elseif cfg.keyToString and (kt == "Instance" or kt == "userdata") then
					-- Key To String: en vez de [tabla opaca] deja una clave legible;
					-- el valor sigue siendo replayeable porque va como [string]
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
		return "{" .. table.concat(body, ", ") .. "}"
	elseif t == "function" then
		if isExecutorClosure(v) then return "--[[executor closure]] function() end" end
		return "--[[function]] function() end"
	elseif t == "RBXScriptSignal" or t == "RBXScriptConnection" then
		return "nil --[[" .. t .. "]]"
	elseif t == "userdata" then
		return "newproxy(true) --[[" .. t .. "]]"
	end

	return "nil --[[" .. tostring(t) .. "]]"
end

local function serializeArgs(args)
	local out = table.create(#args)
	for i = 1, #args do
		out[i] = serialize(args[i])
	end
	return out
end

local function buildScript(remote, args, method, returns)
	local path = instancePath(remote)
	local lines = { "-- generado por vvv·spy", "", "local args = {" }
	for i = 1, #args do
		lines[#lines + 1] = "\t" .. serialize(args[i]) .. ","
	end
	lines[#lines + 1] = "}"
	lines[#lines + 1] = ""
	lines[#lines + 1] = (method == "InvokeServer")
		and (path .. ":InvokeServer(unpack(args))")
		or (path .. ":FireServer(unpack(args))")

	if returns and #returns > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "-- return del servidor:"
		for i = 1, #returns do
			local one = serialize(returns[i]):gsub("\n", " ")
			lines[#lines + 1] = "-- [" .. i .. "] " .. one:sub(1, 400)
		end
	end
	return table.concat(lines, "\n")
end

-- =====================================================================
-- Señales propias (GetRemoteFiredSignal)
-- =====================================================================

local function newSignal()
	local conns = {}
	local sig = { closed = false }

	function sig:Connect(fn)
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
	-- sender -> original -> caller. Se escanea porque newcclosure agrega niveles.
	for level = 2, 6 do
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
	local info = {}
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
	if not info then return "sin datos de función (el executor no expone debug/info)" end
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

-- =====================================================================
-- Log
-- =====================================================================

-- los hooks sólo encolan; el trabajo de UI sale en un solo hilo aparte
local pending = {}

local Spy = {
	running = true,
	logs    = {},
	seq     = 0,
	watched = {},
	rate    = {},
	hookState = { namecall = false, functions = false, received = false },
	originals = {},
}

local function classNameOf(inst)
	local ok, c = pcall(function() return inst.ClassName end)
	return ok and c or "?"
end

function Spy:isBlocked(inst, name)
	return cfg.blocked[inst] == true or (name ~= nil and cfg.blocked[name] == true)
end

function Spy:isExcluded(inst, name)
	return cfg.excluded[inst] == true or (name ~= nil and cfg.excluded[name] == true)
end

-- autoblock: N disparos en una ventana de 1s y el remote se bloquea solo
local function autoblockCheck(name)
	if not cfg.autoblock then return end
	local now = os.clock()
	local r = Spy.rate[name]
	if not r then
		r = { t = now, n = 0 }
		Spy.rate[name] = r
	end
	if now - r.t > 1 then
		r.t = now
		r.n = 0
	end
	r.n += 1
	if r.n > cfg.autoblockRate and not cfg.blocked[name] then
		cfg.blocked[name] = true
		if Spy.onAutoblock then Spy.onAutoblock(name) end
	end
end

function Spy:push(remote, method, args, rets, funcRef, srcRef)
	local okName, name = pcall(function() return remote.Name end)
	name = okName and tostring(name) or "?"

	if self:isExcluded(remote, name) then return nil end

	autoblockCheck(name)
	local blocked = self:isBlocked(remote, name)

	local scriptName, scriptPath = "(main)", nil
	if srcRef then
		local okN, n = pcall(function() return srcRef.Name end)
		local okP, p = pcall(function() return srcRef:GetFullName() end)
		scriptName = okN and tostring(n) or "?"
		scriptPath = okP and tostring(p) or nil
	elseif caps.getcallingscript then
		local ok, s = pcall(cap("getcallingscript"))
		if ok and s then
			local okN, n = pcall(function() return s.Name end)
			local okP, p = pcall(function() return s:GetFullName() end)
			scriptName = okN and tostring(n) or "?"
			scriptPath = okP and tostring(p) or nil
			srcRef = s
		end
	end

	local entry = {
		seq        = self.seq + 1,
		remote     = remote,
		name       = name,
		method     = method,
		cls        = classNameOf(remote),
		args       = args,
		argsText   = serializeArgs(args),
		rets       = rets,
		script     = scriptName,
		scriptRef  = srcRef,
		scriptPath = scriptPath,
		info       = cfg.collectInfo and functionInfo(funcRef) or nil,
		time       = os.clock(),
		type       = (method == "OnClientEvent") and "recv" or "sent",
		blocked    = blocked,
	}
	self.seq += 1
	self.logs[#self.logs + 1] = entry

	local limit = maxRemotes()
	while #self.logs > limit do
		table.remove(self.logs, 1)
	end

	remoteSignal(remote):Fire(entry)
	pending[#pending + 1] = { kind = "log", entry = entry }
	return entry
end

function Spy:clear()
	self.logs = {}
	self.seq = 0
end

function Spy:watchedCount()
	local n = 0
	for _ in pairs(self.watched) do n += 1 end
	return n
end

-- =====================================================================
-- Hook 1 · __namecall
-- =====================================================================

local function installNamecall()
	if not caps.hookmetamethod or Spy.hookState.namecall then return Spy.hookState.namecall end

	local original
	local sender = newcclosure_or(function(self, ...)
		if not cfg.enabled or cfg.method == "functions" then
			return original(self, ...)
		end
		if not cfg.logExecutors and callerIsOurs() then
			return original(self, ...)
		end

		local method = getnamecallmethod()
		if method ~= "FireServer" and method ~= "InvokeServer" then
			return original(self, ...)
		end

		local ok, isRemote = pcall(function()
			return self:IsA("RemoteEvent") or self:IsA("UnreliableRemoteEvent")
				or self:IsA("RemoteFunction")
		end)
		if not ok or not isRemote then return original(self, ...) end

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

		local okN, nm = pcall(function() return self.Name end)
		if Spy:isBlocked(self, okN and nm or nil) then
			task.spawn(function() Spy:push(self, method, args, nil, funcRef, srcRef) end)
			return nil
		end

		if method == "InvokeServer" and cfg.logReturns then
			local co = coroutine.running()
			task.spawn(function()
				local rets = { original(self, unpack(args)) }
				pcall(coroutine.resume, co, unpack(rets))
				pcall(function() Spy:push(self, method, args, rets, funcRef, srcRef) end)
			end)
			return coroutine.yield()
		end

		task.spawn(function()
			pcall(function() Spy:push(self, method, args, nil, funcRef, srcRef) end)
		end)
		return original(self, unpack(args))
	end)

	original = hookmetamethod(game, "__namecall", sender)
	Spy.originals.namecall = original
	Spy.hookState.namecall = true
	return true
end

-- =====================================================================
-- Hook 2 · FireServer / InvokeServer como función
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
			if not cfg.enabled or cfg.method == "namecall" then
				return orig(self, ...)
			end
			if not cfg.logExecutors and callerIsOurs() then
				return orig(self, ...)
			end
			if typeof(self) ~= "Instance" then return orig(self, ...) end

			local args = { ... }
			if cfg.hooks[self] then
				local okH, newArgs = pcall(cfg.hooks[self], args)
				if okH and type(newArgs) == "table" then args = newArgs end
			end

			local okN, nm = pcall(function() return self.Name end)
			if Spy:isBlocked(self, okN and nm or nil) then
				task.spawn(function() Spy:push(self, method, args) end)
				return nil
			end

			task.spawn(function() Spy:push(self, method, args) end)
			return orig(self, unpack(args))
		end)

		hookfunction(orig, sender)
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
-- Hook 3 · OnClientEvent
-- =====================================================================

local function watchRemote(remote)
	if Spy.watched[remote] then return end
	if not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then return end

	local ok = pcall(function()
		remote.OnClientEvent:Connect(function(...)
			if not cfg.enabled or not cfg.logReceived then return end
			local args = { ... }
			task.spawn(function()
				pcall(function() Spy:push(remote, "OnClientEvent", args) end)
			end)
		end)
	end)
	if ok then Spy.watched[remote] = true end
end

local function scanRemotes(root)
	local ok, list = pcall(function()
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent") or d:IsA("RemoteFunction") then
				out[#out + 1] = d
			end
		end
		return out
	end)
	if not ok then return end
	for _, r in ipairs(list) do watchRemote(r) end
end

local function installReceived()
	scanRemotes(game:GetService("ReplicatedStorage"))
	scanRemotes(game:GetService("ReplicatedFirst"))
	pcall(function() scanRemotes(workspace) end)
	Spy.originals.descendant = game.DescendantAdded:Connect(function(d)
		if d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent") then
			watchRemote(d)
		end
	end)
	Spy.hookState.received = true
end

-- =====================================================================
-- Acciones sobre una entrada
-- =====================================================================

local function scriptFor(entry)
	return buildScript(entry.remote, entry.args, entry.method, entry.rets)
end

function Spy:replay(entry)
	if not entry then return false, "sin entrada" end
	local ok, err = pcall(function()
		if entry.method == "InvokeServer" then
			return entry.remote:InvokeServer(unpack(entry.args))
		else
			entry.remote:FireServer(unpack(entry.args))
		end
	end)
	return ok, err
end

function Spy:runCode(entry)
	if not entry then return false, "sin entrada" end
	local code = scriptFor(entry)
	local fn, err = loadstring(code)
	if not fn then return false, "no compila: " .. tostring(err) end
	local ok, res = pcall(fn)
	return ok, res
end

-- =====================================================================
-- UI · Rayfield Gen2
-- =====================================================================

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local window = Rayfield:CreateWindow({
	name = "vvv · spy",
	subtitle = "remote spy · gen2",
	sidebarLayout = true,
	theme = "amethyst",
})

local function notify(title, content, dur)
	pcall(function()
		window:Notify({ title = title, content = content, duration = dur or 5 })
	end)
end

-- ---------------------------- LOG ----------------------------

local logTab = window:CreateTab({ name = "Log" })
logTab:CreateSection({ name = "Eventos" })

local spyToggle = logTab:CreateToggle({
	name = "Spy activo",
	value = true,
	callback = function(v) cfg.enabled = v end,
})

local console = logTab:CreateConsole({
	name = "Remotes",
	height = 250,
	follow = true,
	maxLines = 400,
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
logColB:CreateToggle({ name = "Log del executor", value = false,
	description = "Captura también lo que disparan otros scripts del executor",
	callback = function(v) cfg.logExecutors = v end })

logTab:CreateSlider({
	name = "Máximo de remotes en log",
	range = { 50, 1000 },
	increment = 50,
	value = 250,
	callback = function(v) cfg.maxLogs = v end,
})

logTab:CreateButton({
	name = "Clr Logs",
	callback = function()
		Spy:clear()
		pending = {}
		if console then
			pcall(function() console:Clear() end)
			pcall(function() console:Append("-- log limpio --") end)
		end
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

local codeConsole = detailTab:CreateConsole({
	name = "Script generado",
	height = 200,
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
	if codeConsole then pcall(function() codeConsole:Set(scriptFor(entry)) end) end
	local infoLine = entry.info and describeInfo(entry.info) or "info deshabilitada"
	pcall(function()
		detailText:SetTitle(string.format("#%d · %s · %s", entry.seq, entry.name, entry.cls))
		detailText:Set(string.format(
			"método: %s\nscript: %s\nargs: %d\n%s\n%s",
			entry.method, entry.scriptPath or entry.script, #entry.args,
			infoLine, entry.blocked and "estado: BLOQUEADO" or "estado: enviado"
		))
	end)
end

detailTab:CreateButton({
	name = "Cargar última entrada",
	callback = function()
		if #Spy.logs == 0 then
			notify("Spy", "Todavía no hay logs")
			return
		end
		showEntry(Spy.logs[#Spy.logs])
	end,
})

detailTab:CreateButton({
	name = "Cargar por índice",
	callback = function()
		local n = tonumber(idxInput.value)
		if not n or not Spy.logs[n] then
			notify("Spy", "Índice inválido")
			return
		end
		showEntry(Spy.logs[n])
	end,
})

detailTab:CreateSection({ name = "Herramientas" })

detailTab:CreateButton({
	name = "Copy Code",
	description = "Copia el Lua que replica esta llamada",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local ok = clip(scriptFor(selected))
		notify("Copy Code", ok and "copiado" or "este executor no tiene setclipboard",
			ok and 4 or 8)
	end,
})

detailTab:CreateButton({
	name = "Copy Remote",
	description = "Copia sólo la ruta del RemoteEvent/RemoteFunction",
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
		local ok, res = Spy:runCode(selected)
		notify(ok and "Run Code ok" or "Run Code falló",
			ok and (tostring(res):sub(1, 200)) or tostring(res), 8)
	end,
})

detailTab:CreateButton({
	name = "Get Script",
	description = "Copia la ruta del LocalScript/ModuleScript que originó la llamada",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local path = selected.scriptPath
		if not path and selected.scriptRef then
			local okP, p = pcall(function() return selected.scriptRef:GetFullName() end)
			path = okP and p or nil
		end
		if not path then
			notify("Get Script", "El executor no dio callingscript para esta entrada")
			return
		end
		local ok = clip(path)
		notify("Get Script", ok and path or path, 8)
	end,
})

detailTab:CreateButton({
	name = "Function Info",
	description = "nombre, fuente, constantes y upvalues de la función que disparó",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		if not selected.info then
			notify("Function Info", "No se recolectó (Disable Info activo o executor sin debug)")
			return
		end
		local txt = describeInfo(selected.info)
		if selected.info.constants then
			txt ..= "\nconstantes: " .. serialize(selected.info.constants)
		end
		if selected.info.upvalues then
			txt ..= "\nupvalues: " .. serialize(selected.info.upvalues)
		end
		if codeConsole then pcall(function() codeConsole:Set(txt) end) end
		notify("Function Info", txt:sub(1, 300), 10)
	end,
})

detailTab:CreateButton({
	name = "Decompile",
	description = "Extrae el fuente del script que invocó el remoto",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local script = selected.scriptRef
		if not script and selected.info and selected.info.source then
			script = scriptFromSource(selected.info.source)
		end
		if not script then
			notify("Decompile", "No hay script asociado a esta entrada")
			return
		end
		local src, err = decompileOf(script)
		if not src then
			notify("Decompile", err)
			return
		end
		if codeConsole then pcall(function() codeConsole:Set(src) end) end
		local ok = clip(src)
		notify("Decompile", ok and "fuente copiado" or "fuente en el visor", 6)
	end,
})

detailTab:CreateButton({
	name = "Replay",
	description = "Reenvía el remote con los args exactos",
	callback = function()
		if not selected then notify("Spy", "Seleccioná una entrada primero") return end
		local ok, err = Spy:replay(selected)
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
	description = "namecall cubre :FireServer desde scripts; funciones cubre referencias cacheadas",
	options = { "both", "namecall", "functions" },
	value = "both",
	callback = function(choice)
		cfg.method = choice
		notify("Hook", "modo " .. choice, 4)
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
		notify("Clr Blacklist", "exclusiones limpiadas", 4)
	end,
})

cfgTab:CreateButton({
	name = "Clr Blocklist",
	description = "Desbloquea todos los remotes detenidos",
	callback = function()
		cfg.blocked = {}
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

-- ---------------------------- EXECUTOR ----------------------------

local exTab = window:CreateTab({ name = "Executor" })
exTab:CreateSection({ name = "Capacidades" })

local capText = exTab:CreateText({
	name = "Estado",
	text = "detectando…",
})

local function refreshCaps()
	local function yn(b) return b and "sí" or "NO" end
	local lines = {
		string.format("hookmetamethod %s · hookfunction %s · checkcaller %s",
			yn(caps.hookmetamethod), yn(caps.hookfunction), yn(caps.checkcaller)),
		string.format("newcclosure %s · getcallingscript %s · setclipboard %s",
			yn(caps.newcclosure), yn(caps.getcallingscript), yn(caps.setclipboard)),
		string.format("decompile %s · getscriptbytecode %s · getscriptfromsrc %s",
			yn(caps.decompile), yn(caps.getscriptbytecode), yn(caps.getscriptfromsrc)),
		string.format("debug.info %s · getconstants %s · getupvalues %s",
			yn(caps.debuginfo), yn(caps.getconstants), yn(caps.getupvalues)),
		"",
		string.format("namecall hook %s · function hooks %s · receive watch %s",
			yn(Spy.hookState.namecall), yn(Spy.hookState.functions), yn(Spy.hookState.received)),
		string.format("remotes observados: %d · logs: %d", Spy:watchedCount(), #Spy.logs),
	}
	pcall(function() capText:Set(table.concat(lines, "\n")) end)
end

exTab:CreateButton({
	name = "Re-escanear remotes",
	callback = function()
		scanRemotes(game:GetService("ReplicatedStorage"))
		pcall(function() scanRemotes(workspace) end)
		refreshCaps()
		notify("Spy", "remotes re-escaneados", 4)
	end,
})

exTab:CreateButton({
	name = "Listar remotes (copia al portapapeles)",
	callback = function()
		local ok, list = pcall(function()
			local out, seen = {}, {}
			local container = game:GetService("ReplicatedStorage")
			for _, d in ipairs(container:GetDescendants()) do
				if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")
					or d:IsA("UnreliableRemoteEvent")) and not seen[d.Name] then
					seen[d.Name] = true
					out[#out + 1] = d:GetFullName()
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

exTab:CreateButton({
	name = "Shutdown",
	callback = function()
		if genv.VVV_SPY then genv.VVV_SPY.shutdown() end
	end,
})

-- =====================================================================
-- Wiring del log a la UI
-- =====================================================================

Spy.onAutoblock = function(name)
	pending[#pending + 1] = { kind = "autoblock", name = name }
end

Spy.onLog_ = function(entry)
	if entry.type == "recv" and not cfg.logReceived then return end
	if entry.type == "sent" and not cfg.logSent then return end

	local mark = entry.type == "recv" and "◀" or "▶"
	local line = string.format("#%d %s %s%s", entry.seq, mark,
		entry.blocked and "[BLOCK] " or "", entry.name)
	pcall(function() console:Append(line) end)
end



task.spawn(function()
	local lastCap = 0
	while Spy.running do
		task.wait(0.1)
		if #pending > 0 then
			local batch = pending
			pending = {}
			for i = 1, #batch do
				local item = batch[i]
				if item.kind == "autoblock" then
					notify("Autoblock", item.name .. " bloqueado por spam", 6)
				else
					pcall(Spy.onLog_, item.entry)
				end
			end
		end
		-- refresco de la tab executor cada 2s
		if os.clock() - lastCap > 2 then
			lastCap = os.clock()
			refreshCaps()
		end
	end
end)

-- =====================================================================
-- Instalación
-- =====================================================================

local okNamecall = installNamecall()
local okFn = installFunctionHooks()
installReceived()
refreshCaps()

if not okNamecall and not okFn then
	notify("Spy sin hooks",
		"Este executor no tiene hookmetamethod ni hookfunction: sólo queda el watch de OnClientEvent.", 10)
end

-- =====================================================================
-- API pública · getgenv().VVV_SPY
-- =====================================================================

local API = {}

API.logs = Spy.logs

API.HookRemote = function(remote, fn)
	if typeof(remote) ~= "Instance" then error("Instance expected", 2) end
	if type(fn) ~= "function" then error("function expected", 2) end
	cfg.hooks[remote] = fn
end

API.BlockRemote = function(target)
	cfg.blocked[target] = true
end

API.ExcludeRemote = function(target)
	cfg.excluded[target] = true
end

API.GetRemoteFiredSignal = function(remote)
	if typeof(remote) ~= "Instance" then error("Instance expected", 2) end
	return remoteSignal(remote)
end

API.toggleSpy = function()
	cfg.enabled = not cfg.enabled
	pcall(function() spyToggle:Set(cfg.enabled, true) end)
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

API.shutdown = function()
	Spy.running = false
	if Spy.originals.descendant then
		pcall(function() Spy.originals.descendant:Disconnect() end)
	end
	cfg.signals = {}
	if window and not window.unloaded then
		pcall(function() window:Unload() end)
	end
	if genv.VVV_SPY == API then genv.VVV_SPY = nil end
end

API.genScript = function(remote, args, method)
	return buildScript(remote, args or {}, method or "FireServer")
end

API.ArgsToString = function(args)
	return table.concat(serializeArgs(args or {}), ", ")
end

API.ValueToString = function(value)
	return serialize(value)
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
		lines[#lines + 1] = "local " .. name .. " = " .. serialize(v)
	end
	return table.concat(lines, "\n")
end

API.ValueToVar = function(value, name)
	return "local " .. safeName(name, "v_1") .. " = " .. serialize(value)
end

API.GetFunctionInfo = function(fn)
	if type(fn) ~= "function" then error("function expected", 2) end
	return functionInfo(fn)
end

API.getScriptFromSrc = function(src)
	return scriptFromSource(src)
end

API.decompileScript = function(script)
	return decompileOf(script)
end

API.getplayer = function(inst)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and (inst == p.Character or (typeof(inst) == "Instance" and inst:IsDescendantOf(p.Character))) then
			return p
		end
	end
	return nil
end

API.clear = function() Spy:clear() end
API.notify = notify

genv.VVV_SPY = API

-- compat de globals que algunos scripts esperan
rawset(_G, "SIMPLESPYCONFIG_MaxRemotes", rawget(_G, "SIMPLESPYCONFIG_MaxRemotes") or cfg.maxLogs)
rawset(_G, "SimpleSpyMaxTableSize", rawget(_G, "SimpleSpyMaxTableSize") or MAX_TABLE)

notify("vvv · spy", string.format(
	"namecall:%s · funciones:%s · receive:%s · remotes:%d",
	tostring(Spy.hookState.namecall), tostring(Spy.hookState.functions),
	tostring(Spy.hookState.received), Spy:watchedCount()
), 6)
