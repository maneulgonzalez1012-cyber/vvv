--[[
	Mock minimo de la API de Roblox para ejecutar el exploit fuera del cliente.
	Sirve para validar en CI que la UI se construye y que la logica de remotes
	no revienta. No pretende ser Roblox: solo cubre lo que el script toca.

	Load order: este archivo primero, luego dist/milonarie_tycoon.lua.
]]

-- Luau: los globales viven en el env del chunk, no en _G (que es read-only).
-- Por eso Mock es global y no local: los asserts lo necesitan.
Mock = {}
local spawned = {}

-- Propiedades que en Roblox devuelven nil cuando no estan puestas. El mock no
-- puede inventar un evento para ellas o los bucles de Parent se rompen.
local REAL_PROPERTIES = {
	Name = true, ClassName = true, Parent = true, Position = true, CFrame = true,
	Size = true, AbsoluteSize = true, AbsolutePosition = true, Text = true,
	TextColor3 = true, TextSize = true, TextXAlignment = true, TextYAlignment = true,
	Font = true, Visible = true, Enabled = true, Value = true, Health = true,
	WalkSpeed = true, AnchorPoint = true, AutomaticCanvasSize = true, CanvasSize = true,
	BackgroundTransparency = true, BackgroundColor3 = true, BorderSizePixel = true,
	CanCollide = true, Rotation = true, Transparency = true, LayoutOrder = true,
	ScrollingDirection = true, ScrollBarThickness = true, ScrollBarImageColor3 = true,
	ZIndexBehavior = true, ResetOnSpawn = true, IgnoreGuiInset = true,
	AutoButtonColor = true, ClearTextOnFocus = true, MultiLine = true, Active = true,
	Sit = true, State = true, Occupant = true, CurrentCamera = true,
	AssemblyLinearVelocity = true, AssemblyAngularVelocity = true,
	RootPriority = true, Health = true,
}

local function eventObj(events, name)
	local e = events[name]
	if not e then
		e = { handlers = {} }
		function e:Connect(fn)
			table.insert(self.handlers, fn)
			return { Disconnect = function() end }
		end
		function e:Once(fn)
			return self:Connect(fn)
		end
		function e:Fire(...)
			for _, fn in ipairs(self.handlers) do
				fn(...)
			end
		end
		function e:Disconnect()
			self.handlers = {}
		end
		function e:Wait()
			return nil
		end
		events[name] = e
	end
	return e
end

local function newInstance(className)
	local children = {}
	local props = { Name = className, ClassName = className }
	local events = {}
	local obj

	local methods = {}

	function methods:IsA(c)
		return className == c
	end

	function methods:FindFirstChild(n)
		for _, c in ipairs(children) do
			if c.Name == n then
				return c
			end
		end
		return nil
	end

	function methods:FindFirstChildOfClass(c)
		for _, ch in ipairs(children) do
			if ch.ClassName == c then
				return ch
			end
		end
		return nil
	end

	function methods:FindFirstChildWhichIsA(c, recursive)
		for _, ch in ipairs(children) do
			if ch:IsA(c) then
				return ch
			end
			if recursive then
				local found = ch:FindFirstChildWhichIsA(c, true)
				if found then
					return found
				end
			end
		end
		return nil
	end

	function methods:GetChildren()
		return children
	end

	function methods:GetDescendants()
		local out = {}
		for _, ch in ipairs(children) do
			table.insert(out, ch)
			for _, sub in ipairs(ch:GetDescendants()) do
				table.insert(out, sub)
			end
		end
		return out
	end

	function methods:WaitForChild(n)
		local found = self:FindFirstChild(n)
		if found then
			return found
		end
		local created = newInstance("Folder")
		created.Name = n
		table.insert(children, created)
		return created
	end

	function methods:Destroy()
		local p = props.Parent
		if p and p.__children then
			for i, c in ipairs(p.__children) do
				if c == obj then
					table.remove(p.__children, i)
					break
				end
			end
		end
	end

	function methods:GetPropertyChangedSignal(n)
		return eventObj(events, n)
	end

	if className == "Humanoid" then
		function methods:ChangeState()
			return nil
		end
		function methods:MoveTo()
			return nil
		end
		function methods:EquipTool()
			return nil
		end
		function methods:GetState()
			return Enum.HumanoidStateType.Jumping
		end
	end

	function methods:__fire(name)
		local e = events[name]
		if not e then
			return 0
		end
		local input = {
			UserInputType = Enum.UserInputType.MouseButton1,
			Position = Vector2.new(10, 10),
			KeyCode = Enum.KeyCode.RightShift,
		}
		for _, fn in ipairs(e.handlers) do
			fn(input)
		end
		return #e.handlers
	end

	obj = setmetatable({}, {
		__index = function(_, k)
			local m = methods[k]
			if m then
				return m
			end
			local v = props[k]
			if v ~= nil then
				return v
			end
			if REAL_PROPERTIES[k] then
				if k == "AbsolutePosition" or k == "AbsoluteSize" then
					return Vector2.new(0, 0)
				end
				if k == "AssemblyLinearVelocity" or k == "AssemblyAngularVelocity" then
					return Vector3.new(0, 0, 0)
				end
				return nil
			end
			return eventObj(events, k)
		end,
		__newindex = function(_, k, v)
			if k == "Parent" then
				local old = props.Parent
				if old and old.__children then
					for i, c in ipairs(old.__children) do
						if c == obj then
							table.remove(old.__children, i)
							break
						end
					end
				end
				props.Parent = v
				if v and v.__children then
					table.insert(v.__children, obj)
				end
				return
			end
			props[k] = v
		end,
	})

	obj.__children = children
	props.__children = children
	return obj
end

Mock.newInstance = newInstance
Mock.eventObj = eventObj

-- Compat Lua 5.1 (el runtime de Prometheus) <-> 5.4+
if not table.pack then
	function table.pack(...)
		return { n = select("#", ...), ... }
	end
end
if not table.unpack then
	table.unpack = unpack
end


-- ---------------------------------------------------------------- primitivas

UDim2 = {
	new = function(a, b, c, d)
		return { X = { Scale = a, Offset = b }, Y = { Scale = c, Offset = d } }
	end,
}
UDim = { new = function(a, b) return { Scale = a, Offset = b } end }
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
Vector3 = {
	new = function(x, y, z)
		return { X = x, Y = y, Z = z, Magnitude = math.sqrt(x * x + y * y + z * z) }
	end,
}
local CFrameMeta = {}
CFrameMeta.__add = function(_, _)
	return CFrame.new()
end
CFrameMeta.__sub = function(_, _)
	return CFrame.new()
end
CFrame = {
	new = function()
		return setmetatable({
			LookVector = Vector3.new(0, 0, -1),
			RightVector = Vector3.new(1, 0, 0),
		}, CFrameMeta)
	end,
}
Color3 = { fromRGB = function(r, g, b) return { R = r, G = g, B = b } end }

Enum = {
	KeyCode = { RightShift = 1, W = 2, S = 3, D = 4, A = 5, Space = 6, LeftControl = 7 },
	UserInputType = { MouseButton1 = 1, MouseMovement = 2, Touch = 3, Keyboard = 4 },
	HumanoidStateType = { Jumping = 1 },
	Font = { Gotham = 1, GothamBold = 2, Code = 3 },
	AutomaticSize = { Y = 1 },
	TextXAlignment = { Left = 0, Center = 1, Right = 2 },
	TextYAlignment = { Top = 0, Center = 1 },
	SortOrder = { LayoutOrder = 0 },
	ScrollingDirection = { Y = 1, X = 2 },
	ZIndexBehavior = { Sibling = 0 },
	Material = { Air = 0 },
	EasingStyle = { Linear = 1, Quad = 2, Sine = 3 },
	EasingDirection = { In = 1, Out = 2, InOut = 3 },
}

Instance = {
	new = function(className)
		return newInstance(className)
	end,
}

tick = function()
	return os.time()
end

-- Roblox expone loadstring (deprecated pero presente); Lua 5.2+ lo elimino.
local rawLoad = load
local rawLoadstring = loadstring
if not loadstring then
	loadstring = rawLoad
end

-- loadstring que compila contra el entorno de Roblox (sin debug.getinfo, etc.)
function loadstring(src, name)
	if rawLoadstring and setfenv and not Mock.luauMode then
		local chunk, err = rawLoadstring(src, name)
		if not chunk then
			return nil, err
		end
		setfenv(chunk, Mock.robloxEnv())
		return chunk
	end
	if rawLoadstring then
		-- Luau: el chunk hereda el env del caller (que ya es el de Roblox).
		return rawLoadstring(src, name or "=payload")
	end
	return rawLoad(src, name or "=payload")
end

-- getgenv() en un executor devuelve el env global COMPARTIDO y escribible.
-- En Luau puro _G es read-only, asi que se usa una tabla propia.
Mock.executorEnv = {}
getgenv = function()
	return Mock.executorEnv
end

-- Executor hooks: presentes solo si el ejecutor los trae.
hookmetamethod = function()
	return function()
		return function()
			return nil
		end
	end
end

local taskWaitCount = 0
local taskWaitLimit = 2000

task = {
	spawn = function(fn, ...)
		table.insert(spawned, fn)
	end,
	defer = function(fn, ...)
		table.insert(spawned, fn)
	end,
	wait = function(t)
		taskWaitCount = taskWaitCount + 1
		if taskWaitCount > taskWaitLimit then
			error("__MOCK_TASK_WAIT_STOP__", 0)
		end
		return t
	end,
	delay = function(t, fn)
		return t
	end,
}

function Mock.setTaskWaitLimit(n)
	taskWaitLimit = n
end

-- ------------------------------------------------------------------ servicios

local services = {}

local function service(name)
	if not services[name] then
		services[name] = newInstance(name)
	end
	return services[name]
end

local playerGui = newInstance("PlayerGui")
local character = newInstance("Model")
character.Name = "Character"

	local humanoid = newInstance("Humanoid")
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	humanoid.Sit = false
	humanoid.Parent = character

	local rootPart = newInstance("BasePart")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Position = Vector3.new(0, 3, 0)
	rootPart.CFrame = CFrame.new()
	rootPart.Parent = character

	local leaderstats = newInstance("Folder")
	leaderstats.Name = "leaderstats"
	local cash = newInstance("IntValue")
	cash.Name = "Cash"
	cash.Value = 1234
	cash.Parent = leaderstats

	local player = newInstance("Player")
	player.Name = "LocalPlayer"
	player.Character = character
	player.Position = Vector3.new(0, 3, 0)
	playerGui.Parent = player
	leaderstats.Parent = player

local Players = service("Players")
Players.LocalPlayer = player

local ReplicatedStorage = service("ReplicatedStorage")
local Workspace = service("Workspace")
Workspace.CurrentCamera = newInstance("Camera")
-- Roblox expone workspace como global
workspace = Workspace

local RunService = service("RunService")
local UIS = service("UserInputService")
UIS.IsKeyDown = function(_, key)
	return false
end

TweenInfo = {
	new = function(duration, easingStyle, easingDirection)
		return { Duration = duration, EasingStyle = easingStyle, EasingDirection = easingDirection }
	end,
}

local TweenService = service("TweenService")
TweenService.Create = function(_, instance, info, props)
	local tween = {
		Instance = instance,
		Info = info,
		Properties = props,
		Play = function() return nil end,
		Cancel = function() return nil end,
		Completed = eventObj({}, "Completed"),
	}
	return tween
end

local VirtualUser = service("VirtualUser")
VirtualUser.CaptureController = function()
	return nil
end

local function encodeValue(v)
	local t = type(v)
	if t == "string" then
		return string.format("%q", v)
	end
	if t == "number" or t == "boolean" then
		return tostring(v)
	end
	if t ~= "table" then
		return "null"
	end
	local items, count = {}, 0
	for k in pairs(v) do
		if type(k) ~= "number" then
			items = nil
			break
		end
		count = count + 1
	end
	if items == nil or count ~= #v then
		local parts = {}
		local keys = {}
		for k in pairs(v) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			parts[#parts + 1] = string.format("%q:%s", tostring(k), encodeValue(v[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	for _, item in ipairs(v) do
		items[#items + 1] = encodeValue(item)
	end
	return "[" .. table.concat(items, ",") .. "]"
end

local HttpService = service("HttpService")
HttpService.JSONEncode = function(_, tbl)
	return encodeValue(tbl)
end
HttpService.JSONDecode = function(_, json)
	return Mock.decodedConfig or {}
end

game = newInstance("DataModel")
game.GetService = function(_, name)
	return service(name)
end
game.PlaceId = 123456789
game.JobId = "mock"

-- ------------------------------------------------------------------ helpers

function Mock.makeRemote(name, className)
	local r = newInstance(className or "RemoteEvent")
	r.Name = name
	r.Parent = ReplicatedStorage
	r.fired = {}
	r.FireServer = function(_, ...)
		r.fired = { ... }
	end
	r.InvokeServer = function(_, ...)
		r.fired = { ... }
		return nil
	end
	return r
end

function Mock.logs()
	return spawned
end

-- Luau NO expone: debug.getinfo, string.dump, unpack global, _ENV.
-- Roblox ademas puede capar getfenv/setfenv/newproxy -> Mock.setStrictEnv(true)
-- reproduce ese caso peor.
-- El env donde viven los globales reales. En Luau es getfenv(); en Lua 5.x
-- es _G (en 5.2+ getfenv no existe).
function Mock.currentEnv()
	if type(getfenv) == "function" then
		local ok, t = pcall(getfenv)
		if ok and type(t) == "table" then
			return t
		end
	end
	return _G
end

function Mock.robloxEnv()
	local env = {}
	for k, v in pairs(Mock.currentEnv()) do
		env[k] = v
	end
	-- Luau real: sin _ENV, sin _G, sin unpack global
	-- Luau real: sin _ENV, sin load(), y su _G es read-only.
	env._ENV = nil
	env._G = nil
	-- Luau real SI tiene unpack global (alias de table.unpack).
	env.unpack = table.unpack
	-- Luau real tiene getfenv/setfenv/newproxy (compatibilidad 5.1).
	env.getfenv = function()
		return env
	end
	env.setfenv = function()
		return nil
	end
	env.newproxy = function(mt)
		local proxy = {}
		if mt then
			setmetatable(proxy, {})
		end
		return proxy
	end
	if Mock.strictEnv then
		env.getfenv = nil
		env.setfenv = nil
		env.newproxy = nil
	end
	-- debug de Luau: sin getinfo (existe debug.info)
	local luauDebug = {}
	for k, v in pairs(debug) do
		if k ~= "getinfo" or Mock.keepGetinfo then
			luauDebug[k] = v
		end
	end
	env.debug = luauDebug
	-- Luau real NO tiene load(); el chunk se compila con loadstring.
	env.load = nil
	-- string sin dump
	local luauString = {}
	for k, v in pairs(string) do
		if k ~= "dump" or Mock.keepDump then
			luauString[k] = v
		end
	end
	env.string = luauString
	-- table con pack/unpack
	local luauTable = {}
	for k, v in pairs(table) do
		luauTable[k] = v
	end
	luauTable.pack = table.pack or function(...)
		return { n = select("#", ...), ... }
	end
	luauTable.unpack = table.unpack
	env.table = luauTable
	Mock.env = env
	return env
end

function Mock.setLuauMode(value)
	Mock.luauMode = value and true or false
end

function Mock.setEnvFlags(keepGetinfo, keepDump, keepUnpack)
	Mock.keepGetinfo = keepGetinfo and true or false
	Mock.keepDump = keepDump and true or false
	Mock.keepUnpack = keepUnpack and true or false
end

function Mock.setStrictEnv(value)
	Mock.strictEnv = value and true or false
end

function Mock.namespace()
	-- El payload deuscado puede renombrar el namespace global; se busca por forma.
	-- remotes.records es la firma: el mock devuelve tablas de evento para cualquier
	-- propiedad desconocida, asi que un simple typeof no filtra.
	local function scan(t)
		if type(t) ~= "table" then
			return nil
		end
		for _, v in pairs(t) do
			if type(v) == "table" and type(v.remotes) == "table"
				and type(v.remotes.records) == "table" and type(v.config) == "table" then
				return v
			end
		end
		return nil
	end
	return scan(Mock.currentEnv()) or scan(Mock.env)
end

-- Cargar el payload contra el entorno de Roblox (no el de Lua).
-- En modo Luau el chunk se compila tal cual: el env del caller ya es el de
-- Roblox (sin debug.getinfo, sin string.dump, sin load, sin _ENV).
function Mock.runSource(src)
	local chunk, err
	if Mock.luauMode then
		chunk, err = rawLoadstring(src, "@payload")
	elseif setfenv then
		chunk, err = rawLoadstring(src)
		if chunk then
			setfenv(chunk, Mock.robloxEnv())
		end
	else
		chunk, err = rawLoad(src, "@payload")
	end
	if not chunk then
		error(err or "el payload no compila")
	end
	return chunk()
end

return Mock
