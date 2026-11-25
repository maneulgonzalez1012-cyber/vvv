--[[
	vvv · spy
	Remote spy con la arquitectura de SimpleSpy v2.2, UI en Rayfield Gen2.

	Qué copia de SimpleSpy v2.2:
	  · hook de __namecall con newcclosure + checkcaller (ignora lo que dispara
	    el propio executor)
	  · segundo path: hookfunction sobre RemoteEvent.FireServer /
	    UnreliableRemoteEvent.FireServer / RemoteFunction.InvokeServer, que
	    agarra llamadas hechas con referencia cacheada (remote.FireServer(r, ...))
	  · log por remote: nombre, args serializados, script que lo llamó,
	    return value en InvokeServer
	  · BlockRemote / ExcludeRemote por instancia o por nombre
	  · HookRemote: modifica los args antes de que salgan
	  · generador de script (v2v/v2s: tablas, instancias, CFrame, Enum,
	    userdata typeados) para copiar el disparo y replayearlo
	  · replay del disparo desde la UI
	  · queue con flush diferido, para que el hook no bloquee el hilo del juego
	  · límite de logs para que un remote de spam no cuelgue el cliente

	Diferencias: sin GUI propia (todo en Rayfield Gen2), LogList/CodeBox son
	un Console con follow, y el replay usa pcall en vez de corregir errores.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players    = game:GetService("Players")
local CoreGui    = game:GetService("CoreGui")

local LP = Players.LocalPlayer
if not LP then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LP = Players.LocalPlayer
end

local genv = (getgenv and getgenv()) or _G
if genv.VVV_SPY then
	pcall(function() genv.VVV_SPY.destroy() end)
end

-- =====================================================================
-- Capacidades del executor · se avisa en la UI, no se asume
-- =====================================================================

local caps = {
	hookmetamethod = type(hookmetamethod) == "function",
	hookfunction   = type(hookfunction) == "function",
	newcclosure    = type(newcclosure) == "function",
	checkcaller    = type(checkcaller) == "function",
	getcallingscript = type(getcallingscript) == "function",
	setclipboard   = type(setclipboard) == "function",
	cloneref       = type(cloneref) == "function",
}

local function newcclosure_or(fn)
	return caps.newcclosure and newcclosure(fn) or fn
end

local function callerIsOurs()
	return caps.checkcaller and checkcaller() or false
end

local function isExecutorClosure(f)
	if type(isexecutorclosure) == "function" then
		local ok, r = pcall(isexecutorclosure, f)
		return ok and r
	end
	return false
end

-- =====================================================================
-- Config
-- =====================================================================

local cfg = {
	enabled      = true,
	logExecutors = false,   -- también captura lo que disparan otros scripts del executor
	logSent      = true,    -- FireServer (cliente -> servidor)
	logReceived  = true,    -- OnClientEvent (servidor -> cliente)
	logReturns   = true,    -- return value de InvokeServer
	maxLogs      = 250,
	blocked      = {},      -- ["remote" o nombre] = true
	excluded     = {},      -- ["remote" o nombre] = true
	hooks        = {},      -- [Instance] = function(args) -> args
	autoscroll   = true,
}

-- =====================================================================
-- Serializador · genera Lua ejecutable desde los args
-- portado de SimpleSpy: v2v / v2s / t2s / k2s / u2s / i2p / formatstr
-- =====================================================================

local MAX_STRING = 8000
local MAX_TABLE  = 400
local MAX_DEPTH  = 8

local function quote(s)
	local out = s:gsub("([\\\"\n\r\t\0])", function(c)
		if c == "\\" then return "\\\\" end
		if c == "\"" then return "\\\"" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return "\\0"
	end)
	-- bytes no imprimibles que no cubre el gsub
	out = out:gsub("[%z\1-\31]", function(c)
		return string.format("\\%d", c:byte())
	end)
	if #out > MAX_STRING then
		out = out:sub(1, MAX_STRING) .. "\n--[[ MAXIMUM STRING SIZE REACHED ]]"
	end
	return "\"" .. out .. "\""
end

local function serialize(v, depth, seen)
	-- top-level entra sin depth; sin esta línea, nil >= MAX_DEPTH revienta en Luau
	depth = depth or 0
	local t = typeof(v)

	if t == "string" then
		return quote(v)
	elseif t == "number" then
		if v ~= v then return "0/0 --[[NaN]]" end
		if v == math.huge then return "math.huge" end
		if v == -math.huge then return "-math.huge" end
		if math.floor(v) == v and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.14g", v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "nil" then
		return "nil"
	elseif t == "Vector3" then
		return string.format("Vector3.new(%d, %d, %d)", v.X, v.Y, v.Z)
	elseif t == "Vector2" then
		return string.format("Vector2.new(%d, %d)", v.X, v.Y)
	elseif t == "CFrame" then
		local x, y, z = v:ToEulerAnglesXYZ()
		return string.format(
			"CFrame.new(%s, %s, %s) * CFrame.Angles(%s, %s, %s)",
			serialize(v.X), serialize(v.Y), serialize(v.Z),
			serialize(x), serialize(y), serialize(z)
		)
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
		local parts = {}
		for _, kp in ipairs(v.Keypoints) do
			parts[#parts + 1] = string.format("NumberSequenceKeypoint.new(%s, %s, %s)",
				serialize(kp.Time), serialize(kp.Value), serialize(kp.Envelope))
		end
		return "NumberSequence.new({" .. table.concat(parts, ", ") .. "})"
	elseif t == "ColorSequence" then
		local parts = {}
		for _, kp in ipairs(v.Keypoints) do
			parts[#parts + 1] = string.format("ColorSequenceKeypoint.new(%s, %s)",
				serialize(kp.Time), serialize(kp.Value))
		end
		return "ColorSequence.new({" .. table.concat(parts, ", ") .. "})"
	elseif t == "TweenInfo" then
		return string.format("TweenInfo.new(%s, Enum.EasingStyle.%s, Enum.EasingDirection.%s, %s, %s, %s)",
			serialize(v.Time), tostring(v.EasingStyle), tostring(v.EasingDirection),
			serialize(v.RepeatCount), serialize(v.Reverses), serialize(v.DelayTime))
	elseif t == "Rect" then
		return string.format("Rect.new(%s, %s)", serialize(v.Min), serialize(v.Max))
	elseif t == "Instance" then
		local ok, path = pcall(function() return v:GetFullName() end)
		if ok and path then
			if path:sub(1, 5) == "game." then
				local cls = v.ClassName
				if path == "Workspace" or path:sub(1, 22) == "Workspace." then
					return "workspace" .. path:sub(10)
				end
				return path
			end
		end
		-- instancia fuera del DataModel (nil parent): se busca por nombre+clase
		local okName, name = pcall(function() return v.Name end)
		if okName and name then
			return string.format("--[[nil-parent Instance %s (%s)]] nil", quote(name), v.ClassName)
		end
		return "nil --[[Instance]]"
	elseif t == "table" then
		if depth >= MAX_DEPTH then return "{ --[[MAX DEPTH]] }" end
		seen = seen or {}
		if seen[v] then return "{ --[[DUPLICATE]] }" end
		seen[v] = true

		local keys, count = {}, 0
		for k in pairs(v) do
			count += 1
			if count > MAX_TABLE then
				return "{ --[[MAXIMUM TABLE SIZE REACHED, " .. count .. "+ keys]] }"
			end
			keys[#keys + 1] = k
		end

		local isArray = true
		for i = 1, #v do
			if v[i] == nil then isArray = false break end
		end
		if count ~= #v then isArray = false end

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
				else
					keyStr = "[" .. serialize(k, depth + 1, seen) .. "]"
				end
				body[#body + 1] = keyStr .. " = " .. serialize(v[k], depth + 1, seen)
			end
		end

		seen[v] = nil
		return "{" .. table.concat(body, ", ") .. "}"
	elseif t == "function" then
		if isExecutorClosure(v) then
			return "--[[executor closure]] function() end"
		end
		return "--[[function]] function() end"
	elseif t == "RBXScriptSignal" then
		return "nil --[[RBXScriptSignal]]"
	elseif t == "RBXScriptConnection" then
		return "nil --[[RBXScriptConnection]]"
	elseif t == "userdata" then
		return "newproxy(true) --[[" .. t .. "]]"
	end

	return string.format("nil --[[" .. tostring(t) .. "]]")
end

local function serializeArgs(args)
	local out = {}
	for i = 1, #args do
		out[i] = serialize(args[i])
	end
	return out
end

local function buildScript(remote, args, method, returns)
	local t = typeof(remote)
	local path
	local ok, full = pcall(function() return remote:GetFullName() end)
	if ok and full and full:sub(1, 5) == "game." then
		path = full
	else
		local okName, name = pcall(function() return remote.Name end)
		path = string.format("--[[nil-parent]] game:GetService(\"ReplicatedStorage\"):FindFirstChild(%s)",
			quote(okName and name or "Remote"))
	end

	local lines = {}
	lines[#lines + 1] = "-- generado por vvv·spy"
	lines[#lines + 1] = ""
	lines[#lines + 1] = "local args = {"
	for i = 1, #args do
		lines[#lines + 1] = "\t" .. serialize(args[i]) .. ","
	end
	lines[#lines + 1] = "}"
	lines[#lines + 1] = ""
	lines[#lines + 1] = path .. ":" .. method .. "(unpack(args))"

	if returns and #returns > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "-- return del servidor:"
		for i = 1, #returns do
			lines[#lines + 1] = "-- [" .. i .. "] " ..
				serialize(returns[i]):gsub("\n", " "):sub(1, 400)
		end
	end

	return table.concat(lines, "\n")
end

-- =====================================================================
-- Log
-- =====================================================================

local Spy = {
	running  = true,
	logs     = {},     -- { remote, name, method, argsText, script, returns, time, type, blocked }
	seq      = 0,
	hookState = { namecall = false, functions = false, received = false },
	originals = {},
	maxSeq   = 1500,
}

local function classNameOf(remote)
	local ok, cls = pcall(function() return remote.ClassName end)
	return ok and cls or "?"
end

local function remoteKey(remote)
	local ok, name = pcall(function() return remote.Name end)
	local ok2, cls = pcall(function() return remote.ClassName end)
	return (ok and name or "?") .. " (" .. (ok2 and cls or "?") .. ")"
end

function Spy:isBlocked(remote, name)
	return cfg.blocked[remote] == true or cfg.blocked[name] == true
end

function Spy:isExcluded(remote, name)
	return cfg.excluded[remote] == true or cfg.excluded[name] == true
end

-- entra al log; devuelve la entrada o nil si está filtrado
function Spy:push(remote, method, args, rets)
	local okName, name = pcall(function() return remote.Name end)
	name = okName and tostring(name) or "?"

	if self:isExcluded(remote, name) then return nil end

	local blocked = self:isBlocked(remote, name)

	local script = "?"
	if caps.getcallingscript then
		local ok, s = pcall(getcallingscript)
		if ok and s then
			local okName2, sName = pcall(function() return s.Name end)
			script = okName2 and tostring(sName) or "?"
		else
			script = "(main)"
		end
	end

	local entry = {
		seq = self.seq + 1,
		remote = remote,
		name = name,
		method = method,
		cls = classNameOf(remote),
		args = args,
		argsText = serializeArgs(args),
		rets = rets,
		script = script,
		time = os.clock(),
		type = (method == "OnClientEvent") and "recv" or "sent",
		blocked = blocked,
	}
	self.seq += 1
	self.logs[#self.logs + 1] = entry

	-- tope de logs: el más viejo se va
	while #self.logs > cfg.maxLogs do
		table.remove(self.logs, 1)
	end

	if self.onLog then
		self.onLog(entry)
	end
	return entry
end

-- =====================================================================
-- Hook 1 · __namecall  (cap: FireServer / InvokeServer)
-- =====================================================================

local hookNamecall
local function installNamecall()
	if not caps.hookmetamethod or Spy.hookState.namecall then return false end

	local original
	local sender = newcclosure_or(function(self, ...)
		if not cfg.enabled then return original(self, ...) end
		if not cfg.logExecutors and callerIsOurs() then return original(self, ...) end

		local method = getnamecallmethod()
		if method ~= "FireServer" and method ~= "InvokeServer" then
			return original(self, ...)
		end

		local ok, isRemote = pcall(function()
			return self:IsA("RemoteEvent") or self:IsA("RemoteFunction")
				or self:IsA("UnreliableRemoteEvent")
		end)
		if not ok or not isRemote then return original(self, ...) end

		local args = { ... }

		-- HookRemote: reescribe args antes de salir
		local h = cfg.hooks[self]
		if h then
			local okH, newArgs = pcall(h, args)
			if okH and type(newArgs) == "table" then
				args = newArgs
			end
		end

		local okNameBlk, nameBlk = pcall(function() return self.Name end)
		if Spy:isBlocked(self, okNameBlk and nameBlk or nil) then
			-- bloqueado: no sale al servidor, pero queda en el log con su marca
			task.spawn(function() Spy:push(self, method, args) end)
			return nil
		end

		if method == "InvokeServer" and cfg.logReturns then
			local co = coroutine.running()
			local rets
			task.spawn(function()
				rets = { original(self, unpack(args)) }
				local okR, err = pcall(coroutine.resume, co, unpack(rets))
				if not okR then end
				-- el server ya respondió: ahora sí se loguea
				pcall(function() Spy:push(self, method, args, rets) end)
			end)
			return coroutine.yield()
		end

		task.spawn(function()
			pcall(function() Spy:push(self, method, args) end)
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
-- agarra remote.FireServer(remote, ...), task.spawn(remote.FireServer, remote, ...)
-- y referencias cacheadas al método
-- =====================================================================

local function installFunctionHook(class, method)
	if not caps.hookfunction then return false end
	local proto = Instance.new(class)
	local hadError = false
	local ok, original, hooked = pcall(function()
		local orig = proto[method]
		local sender = newcclosure_or(function(self, ...)
			if not cfg.enabled then return orig(self, ...) end
			-- checkcaller cubre los scripts del propio executor; logExecutors
			-- existe para el caso contrario, cuando se quiere ver también eso
			if not cfg.logExecutors and callerIsOurs() then return orig(self, ...) end

			local args = { ... }
			local h = cfg.hooks[self]
			if h then
				local okH, newArgs = pcall(h, args)
				if okH and type(newArgs) == "table" then args = newArgs end
			end

			if Spy:isBlocked(self, (pcall(function() return self.Name end)) and self.Name or nil) then
				task.spawn(function() Spy:push(self, method, args) end)
				return nil
			end

			task.spawn(function() Spy:push(self, method, args) end)
			return orig(self, unpack(args))
		end)
		hookfunction(orig, sender)
		return orig, sender
	end)
	if not ok then
		hadError = true
	end
	proto:Destroy()
	return not hadError
end

local function installFunctionHooks()
	if not caps.hookfunction or Spy.hookState.functions then return false end
	local any = false
	any = installFunctionHook("RemoteEvent", "FireServer") or any
	any = installFunctionHook("UnreliableRemoteEvent", "FireServer") or any
	any = installFunctionHook("RemoteFunction", "InvokeServer") or any
	Spy.hookState.functions = any
	return any
end

-- =====================================================================
-- Hook 3 · OnClientEvent (servidor -> cliente)
-- Descubre los remotes que usa el juego y escucha lo que llega
-- =====================================================================

local function watchRemote(remote)
	if Spy.watched and Spy.watched[remote] then return end
	Spy.watched = Spy.watched or {}
	if not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then return end
	Spy.watched[remote] = true

	local ok = pcall(function()
		remote.OnClientEvent:Connect(function(...)
			if not cfg.enabled or not cfg.logReceived then return end
			local args = { ... }
			task.spawn(function()
				pcall(function() Spy:push(remote, "OnClientEvent", args) end)
			end)
		end)
	end)
	if not ok then
		Spy.watched[remote] = nil
	end
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
	for _, r in ipairs(list) do
		watchRemote(r)
	end
end

local function installReceived()
	scanRemotes(game:GetService("ReplicatedStorage"))
	scanRemotes(game:GetService("ReplicatedFirst"))
	pcall(function() scanRemotes(workspace) end)

	-- remotes agregados después (streaming, carga perezosa)
	local conn = game.DescendantAdded:Connect(function(d)
		if d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent") or d:IsA("RemoteFunction") then
			watchRemote(d)
		end
	end)
	Spy.originals.descendant = conn
	Spy.hookState.received = true
end

-- =====================================================================
-- Replay y utilidades públicas
-- =====================================================================

-- el replay dispara desde nuestro hilo: checkcaller lo ignora, así no se
-- loguea dos veces ni entra en loop si el remote se re-emite
function Spy:replay(entry)
	if not entry then return false, "sin entrada" end
	local method = entry.method
	local ok, err = pcall(function()
		if method == "InvokeServer" then
			entry.remote:InvokeServer(unpack(entry.args))
		else
			entry.remote:FireServer(unpack(entry.args))
		end
	end)
	return ok, err
end

function Spy:clear()
	self.logs = {}
	self.seq = 0
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
	configuration = {
		autoSave = false,
	},
})

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
	height = 240,
	follow = true,
	maxLines = 400,
})

local listGrid = logTab:CreateGroup()
local colA = listGrid:CreateGroup({ direction = "column" })
colA:CreateToggle({ name = "FireServer (sent)", value = true,
	callback = function(v) cfg.logSent = v end })
colA:CreateToggle({ name = "OnClientEvent (recv)", value = true,
	callback = function(v) cfg.logReceived = v end })
local colB = listGrid:CreateGroup({ direction = "column" })
colB:CreateToggle({ name = "Return de InvokeServer", value = true,
	callback = function(v) cfg.logReturns = v end })
colB:CreateToggle({ name = "Log del executor", description = "Captura también lo que disparan otros scripts del executor",
	value = false, callback = function(v) cfg.logExecutors = v end })

logTab:CreateSlider({
	name = "Máximo de logs",
	range = { 50, 1000 },
	increment = 50,
	value = 250,
	callback = function(v) cfg.maxLogs = v end,
})

logTab:CreateButton({
	name = "Limpiar log",
	callback = function()
		Spy:clear()
		if console then pcall(function() console:Clear() end) end
	end,
})

-- ---------------------------- DETALLE ----------------------------

local detailTab = window:CreateTab({ name = "Detalle" })
detailTab:CreateSection({ name = "Entrada seleccionada" })

local selected = nil

local detailText = detailTab:CreateText({
	name = "Nada seleccionado",
	text = "Elegí una entrada en el log para ver sus args, el script que la disparó y el script para replayarla.",
})

local codeConsole = detailTab:CreateConsole({
	name = "Script generado",
	height = 220,
	follow = false,
})

local idxInput = detailTab:CreateInput({
	name = "Índice de entrada",
	description = "El número que aparece en el log",
	value = "",
	placeholder = "1",
	callback = function() end,
})

local function selectEntry(index)
	local entry = Spy.logs[index]
	if not entry then
		window:Notify({ title = "Spy", content = "No existe la entrada " .. tostring(index), duration = 4 })
		return
	end
	selected = entry
	local script = buildScript(entry.remote, entry.args, entry.method, entry.rets)
	if codeConsole then pcall(function() codeConsole:Set(script) end) end
	pcall(function()
		detailText:SetTitle(string.format("#%d · %s · %s", entry.seq, entry.name, entry.cls))
		detailText:Set(string.format(
			"método %s\nscript %s\nargs %d\n%s",
			entry.method, entry.script, #entry.args,
			entry.blocked and "BLOQUEADO" or "enviado"
		))
	end)
end

detailTab:CreateButton({
	name = "Cargar última entrada",
	callback = function()
		if #Spy.logs == 0 then
			window:Notify({ title = "Spy", content = "Todavía no hay logs", duration = 4 })
			return
		end
		selectEntry(#Spy.logs)
	end,
})

detailTab:CreateButton({
	name = "Cargar entrada por índice",
	callback = function()
		local n = tonumber(idxInput.value)
		if n then selectEntry(n) else
			window:Notify({ title = "Spy", content = "Índice inválido", duration = 4 })
		end
	end,
})

detailTab:CreateButton({
	name = "Copiar script al portapapeles",
	callback = function()
		if not selected then
			window:Notify({ title = "Spy", content = "Seleccioná una entrada primero", duration = 4 })
			return
		end
		local script = buildScript(selected.remote, selected.args, selected.method, selected.rets)
		if caps.setclipboard then
			setclipboard(script)
			window:Notify({ title = "Spy", content = "Script copiado", duration = 4 })
		else
			window:Notify({ title = "Spy", content = "Este executor no tiene setclipboard; copiá del console", duration = 6 })
		end
	end,
})

detailTab:CreateButton({
	name = "Replay de la entrada",
	callback = function()
		if not selected then
			window:Notify({ title = "Spy", content = "Seleccioná una entrada primero", duration = 4 })
			return
		end
		local ok, err = Spy:replay(selected)
		window:Notify({
			title = ok and "Replay enviado" or "Replay falló",
			content = ok and (selected.method .. " · " .. selected.name) or tostring(err),
			duration = 5,
		})
	end,
})

-- ---------------------------- FILTROS ----------------------------

local filterTab = window:CreateTab({ name = "Filtros" })
filterTab:CreateSection({ name = "Bloquear / excluir" })

local targetInput = filterTab:CreateInput({
	name = "Nombre del remote",
	description = "Bloquear corta el envío; excluir sólo lo saca del log",
	value = "",
	placeholder = "WeaponFire",
	callback = function(text) cfg.lastTarget = text end,
})

filterTab:CreateButton({
	name = "Bloquear por nombre",
	callback = function()
		local n = targetInput.value
		if n == "" then return end
		cfg.blocked[n] = true
		window:Notify({ title = "Bloqueado", content = n, duration = 4 })
	end,
})

filterTab:CreateButton({
	name = "Excluir por nombre",
	callback = function()
		local n = targetInput.value
		if n == "" then return end
		cfg.excluded[n] = true
		window:Notify({ title = "Excluido", content = n, duration = 4 })
	end,
})

filterTab:CreateButton({
	name = "Limpiar filtros",
	callback = function()
		cfg.blocked = {}
		cfg.excluded = {}
		cfg.hooks = {}
		window:Notify({ title = "Filtros", content = "Bloqueos, exclusiones y hooks limpiados", duration = 4 })
	end,
})

-- ---------------------------- CAPACIDADES ----------------------------

local capTab = window:CreateTab({ name = "Executor" })
capTab:CreateSection({ name = "Capacidades detectadas" })

local capText = capTab:CreateText({
	name = "Estado",
	text = string.format(
		"hookmetamethod %s · hookfunction %s · checkcaller %s\nnewcclosure %s · getcallingscript %s · setclipboard %s\n\nnamecall hook: %s · function hooks: %s · receive watch: %s",
		caps.hookmetamethod and "sí" or "NO",
		caps.hookfunction and "sí" or "NO",
		caps.checkcaller and "sí" or "NO",
		caps.newcclosure and "sí" or "NO",
		caps.getcallingscript and "sí" or "NO",
		caps.setclipboard and "sí" or "NO",
		Spy.hookState.namecall and "sí" or "no",
		Spy.hookState.functions and "sí" or "no",
		Spy.hookState.received and "sí" or "no"
	),
})

capTab:CreateButton({
	name = "Descargar remotes conocidos",
	callback = function()
		local ok, list = pcall(function()
			local out, seen = {}, {}
			for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
				if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent"))
					and not seen[d.Name] then
					seen[d.Name] = true
					out[#out + 1] = d.Name
				end
			end
			table.sort(out)
			return out
		end)
		if ok then
			window:Notify({
				title = "Remotes (" .. #list .. ")",
				content = #list > 0 and table.concat(list, ", ") or "No hay remotes en ReplicatedStorage",
				duration = 12,
			})
		end
	end,
})

capTab:CreateButton({
	name = "Cerrar spy",
	callback = function()
		if genv.VVV_SPY then genv.VVV_SPY.destroy() end
	end,
})

-- =====================================================================
-- Wiring del log a la UI
-- =====================================================================

Spy.onLog = function(entry)
	if entry.type == "recv" and not cfg.logReceived then return end
	if entry.type == "sent" and not cfg.logSent then return end

	local line = string.format(
		"#%d %s %s %s", entry.seq,
		entry.type == "recv" and "◀" or "▶",
		entry.blocked and "[BLOCK] " or "",
		entry.name
	)
	if console then
		pcall(function() console:Append(line) end)
	end
end

-- flush del queue: los hooks sólo encolan, el trabajo de UI va aparte
local pending = {}
Spy.onLog_ = Spy.onLog
Spy.onLog = function(entry)
	pending[#pending + 1] = entry
end

task.spawn(function()
	while Spy.running ~= false do
		task.wait(0.1)
		if #pending > 0 then
			local batch = pending
			pending = {}
			for i = 1, #batch do
				local entry = batch[i]
				pcall(Spy.onLog_, entry)
			end
		end
	end
end)

-- =====================================================================
-- Instalación
-- =====================================================================

local okNamecall = installNamecall()
local okFn = installFunctionHooks()
installReceived()

if not okNamecall and not okFn then
	window:Notify({
		title = "Spy sin hooks",
		content = "Este executor no expone hookmetamethod ni hookfunction: sólo queda el watch de OnClientEvent.",
		duration = 10,
	})
end

-- =====================================================================
-- API pública (getgenv().VVV_SPY)
-- =====================================================================

genv.VVV_SPY = {
	logs = Spy.logs,
	block = function(name) cfg.blocked[name] = true end,
	exclude = function(name) cfg.excluded[name] = true end,
	hook = function(remote, f) cfg.hooks[remote] = f end,
	replay = function(index) return Spy:replay(Spy.logs[index]) end,
	clear = function() Spy:clear() end,
	destroy = function()
		Spy.running = false
		if Spy.originals.descendant then
			pcall(function() Spy.originals.descendant:Disconnect() end)
		end
		if window and not window.unloaded then
			pcall(function() window:Unload() end)
		end
		genv.VVV_SPY = nil
	end,
}

window:Notify({
	title = "vvv · spy",
	content = string.format(
		"Remotes capturándose. namecall:%s · función:%s · receive:%s",
		tostring(Spy.hookState.namecall),
		tostring(Spy.hookState.functions),
		tostring(Spy.hookState.received)
	),
	duration = 6,
})
