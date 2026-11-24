--[[
	Aero :: Milonarie Tycoon :: capa de remotes

	Nucleo del exploit: hook de FireServer/InvokeServer para capturar la forma real
	de los argumentos que el juego usa, replay de esos argumentos, y binding
	por accion (collect / buy / rebirth). No depende de conocer los nombres
	del remote: se aprenden en runtime.
]]

Aero = Aero or {}
Aero.remotes = {}

local remotes = Aero.remotes
local util = Aero.util

remotes.records    = {} -- path -> {path, name, class, method, args, count, last, remote}
remotes.discovered = {} -- path -> {path, name, class, remote}
remotes.bindings   = {} -- accion -> path
remotes.suppress   = 0 -- >0 mientras disparamos nosotros (no queremos capturarnos)
remotes.version    = 0 -- sube solo cuando aparece un remote nuevo
remotes.spyInstalled = false

local unpack = table.unpack or unpack

function remotes.fullPath(inst)
	local parts = {}
	local cur = inst
	while cur and cur ~= game do
		table.insert(parts, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(parts, ".")
end

function remotes.scan()
	remotes.discovered = {}
	local seen = {}
	local roots = {
		game:GetService("ReplicatedStorage"),
		game:GetService("Players"),
		game:GetService("Workspace"),
	}
	for _, root in ipairs(roots) do
		for _, inst in ipairs(root:GetDescendants()) do
			local isRemote = inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
			if isRemote and not seen[inst] then
				seen[inst] = true
				local path = remotes.fullPath(inst)
				remotes.discovered[path] = {
					path = path,
					name = inst.Name,
					class = inst.ClassName,
					remote = inst,
				}
			end
		end
	end
	remotes.version = remotes.version + 1
	util.log(string.format("scan: %d remotes encontrados", (function()
		local n = 0
		for _ in pairs(remotes.discovered) do n = n + 1 end
		return n
	end)()))
	return remotes.discovered
end

function remotes.installSpy()
	if remotes.spyInstalled then
		return true
	end
	if type(hookmetamethod) ~= "function" then
		util.log("hookmetamethod no disponible: sin captura automatica de args")
		return false
	end
	local old
	old = hookmetamethod(game, "__index", function(self, key)
		if key == "FireServer" or key == "InvokeServer" then
			return function(remote, ...)
				remotes.record(remote, key, ...)
				return old(self, key)(remote, ...)
			end
		end
		return old(self, key)
	end)
	remotes.spyInstalled = true
	util.log("spy instalado")
	return true
end

function remotes.record(remote, method, ...)
	if remotes.suppress > 0 then
		return
	end
	if remote == nil then
		return
	end
	local ok, isRemote = pcall(function()
		return remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")
	end)
	if not ok or not isRemote then
		return
	end
	local path = remotes.fullPath(remote)
	local rec = remotes.records[path]
	if not rec then
		rec = {
			path = path,
			name = remote.Name,
			class = remote.ClassName,
			method = method,
			args = table.pack(),
			count = 0,
			last = 0,
			remote = remote,
		}
		remotes.records[path] = rec
		remotes.version = remotes.version + 1
		util.log("capturado: " .. path)
	end
	rec.method = method
	rec.args = table.pack(...)
	rec.count = rec.count + 1
	rec.last = util.now()
end

function remotes.fire(rec, overrides)
	if not rec or not rec.remote then
		return false
	end
	local n = rec.args.n or 0
	local args = {}
	for i = 1, n do
		args[i] = rec.args[i]
	end
	if overrides then
		for k, v in pairs(overrides) do
			if type(k) == "number" and k >= 1 and k <= n then
				args[k] = v
			end
		end
	end
	remotes.suppress = remotes.suppress + 1
	local ok, err = pcall(function()
		if rec.method == "InvokeServer" then
			rec.remote:InvokeServer(unpack(args, 1, n))
		else
			rec.remote:FireServer(unpack(args, 1, n))
		end
	end)
	remotes.suppress = remotes.suppress - 1
	if not ok then
		util.log(string.format("fire error en %s: %s", rec.path, tostring(err)))
	end
	return ok
end

function remotes.get(path)
	return remotes.records[path]
end

function remotes.bind(action, path)
	local rec = remotes.records[path]
	if not rec then
		util.log("no hay remote capturado con path " .. tostring(path))
		return false
	end
	remotes.bindings[action] = path
	util.log(string.format("bind %s -> %s", action, path))
	return true
end

function remotes.unbind(action)
	remotes.bindings[action] = nil
end

function remotes.bound(action)
	return remotes.records[remotes.bindings[action]]
end

function remotes.autoBind()
	-- Clasifica por nombre y, a igual patron, gana el remote mas usado.
	local best = {}
	for path, rec in pairs(remotes.records) do
		local action = util.classify(path)
		if action then
			local current = best[action]
			if not current or rec.count > current.count then
				best[action] = rec
			end
		end
	end
	for action, rec in pairs(best) do
		remotes.bindings[action] = rec.path
		util.log(string.format("auto-bind %s -> %s", action, rec.path))
	end
	return best
end

function remotes.clear()
	remotes.records = {}
	remotes.version = remotes.version + 1
end
