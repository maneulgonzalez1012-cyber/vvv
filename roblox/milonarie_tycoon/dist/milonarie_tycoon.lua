--[[
	Aero :: Milonarie Tycoon exploit (single file build)

	Generado por build.py -- no editar a mano, editar src/ y rebuildar.
	Uso: pegarlo en el executor con el juego abierto.

	Flow: el spy captura la forma real de los argumentos que el juego manda por
	los remotes, y el farm hace replay de esos argumentos. Si el auto-bind no
	pilla el remote correcto, se liga a mano en la tab TARGET.
]]

-- ===== config.lua ======================================================
do
--[[
	Aero :: Milonarie Tycoon :: configuracion

	Todo valor ajustable vive aqui. El codigo de features nunca lleva numeros sueltos,
	asi un update del juego solo toca este archivo y los bindings de remotes.
]]

-- Bootstrap: namespace compartido entre re-ejecuciones del script.
local _genv = (type(getgenv) == "function") and getgenv() or _G
Aero = _genv.Aero or {}
_genv.Aero = Aero

Aero.config = {
	-- Clasificacion de remotes: substring en minusculas contra el path completo del remote.
	-- El primer patron que matchea gana, asi que los especificos van primero.
	patterns = {
		collect = { "updatecollector", "collectmoney", "collect", "money", "cash", "coin", "reward", "earn", "drop" },
		buy     = { "buyupgrade", "buyitem", "buy", "upgrade", "purchase", "unlock", "claim", "open", "equip" },
		rebirth = { "rebirth", "prestige", "ascend" },
	},

	-- Coleccion fisica: prompts y partes de dinero que se tocan para cobrar.
	physical = {
		moneyNames    = { "money", "cash", "coin", "bill", "dollar", "moneybag", "cashstack" },
		promptActions = { "collect", "claim", "earn", "take", "get" },
		searchRadius  = 200,  -- studs
		scanInterval  = 2.0,  -- segundos entre rescans del workspace
	},

	farm = {
		enabled         = false,
		mode            = "hybrid", -- "remote" | "physical" | "hybrid"
		collectInterval = 0.15,
		buyInterval     = 1.2,
		rebirthInterval = 2.5,
		rebirthAt       = 1e9,
		autoBuy         = false,
		autoRebirth     = false,
	},

	-- Inyeccion de cantidad en el remote ligado a "collect".
	money = {
		inflate  = false,
		argIndex = 1,
		value    = 1e9,
		cap      = 1e10, -- el server suele clampear por encima de esto
	},

	move = {
		speedEnabled = false,
		speed        = 32,
		flyEnabled   = false,
		flySpeed     = 70,
		noclip       = false,
		infiniteJump = false,
		antiAfk      = true,
	},

	ui = {
		toggleKey       = "RightShift", -- nombre de Enum.KeyCode
		refreshInterval = 0.25,
		configFile      = "aero_milonarie_config.json",
	},
}
end

-- ===== util.lua ========================================================
do
--[[
	Aero :: Milonarie Tycoon :: utilidades
]]

Aero = Aero or {}
Aero.util = {}

local util = Aero.util

function util.now()
	-- tick() es wall-clock en Roblox; os.clock() es tiempo de CPU, no sirve para intervalos.
	if type(tick) == "function" then
		return tick()
	end
	return os.time()
end

function util.getPlayer()
	local Players = game:GetService("Players")
	return Players.LocalPlayer
end

function util.getCharacter()
	local player = util.getPlayer()
	return player and player.Character or nil
end

function util.getHumanoid()
	local char = util.getCharacter()
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

function util.getRootPart()
	local char = util.getCharacter()
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end

function util.isAlive()
	local hum = util.getHumanoid()
	return hum ~= nil and hum.Health > 0
end

function util.log(msg)
	print("[Aero] " .. tostring(msg))
	if Aero.ui and Aero.ui.pushLog then
		Aero.ui.pushLog(tostring(msg))
	end
end

function util.deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = util.deepCopy(v)
	end
	return copy
end

function util.classify(path)
	local patterns = Aero.config.patterns
	local lower = string.lower(path)
	for action, list in pairs(patterns) do
		for _, p in ipairs(list) do
			if string.find(lower, p, 1, true) then
				return action
			end
		end
	end
	return nil
end

function util.getCash()
	-- Devuelve valor y nombre del stat de moneda. Busca por nombre; si no hay,
	-- se queda con el primer NumberValue del leaderstats.
	local player = util.getPlayer()
	if not player then
		return nil, nil
	end
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return nil, nil
	end
	local fallback, fallbackName
	for _, v in ipairs(ls:GetChildren()) do
		if v:IsA("IntValue") or v:IsA("NumberValue") then
			local n = string.lower(v.Name)
			if string.find(n, "cash", 1, true)
				or string.find(n, "money", 1, true)
				or string.find(n, "coin", 1, true)
				or string.find(n, "currency", 1, true) then
				return v.Value, v.Name
			end
			fallback = fallback or v
			fallbackName = fallbackName or v.Name
		end
	end
	if fallback then
		return fallback.Value, fallbackName
	end
	return nil, nil
end

function util.stringify(value, depth)
	depth = depth or 0
	local t = string.lower(type(value))
	if t == "string" then
		return string.format("%q", value)
	end
	if t == "number" or t == "boolean" then
		return tostring(value)
	end
	if t == "nil" then
		return "nil"
	end
	if t == "vector3" then
		return string.format("Vector3(%.1f, %.1f, %.1f)", value.X, value.Y, value.Z)
	end
	if t == "cframe" then
		return tostring(value)
	end
	if depth >= 2 then
		return "{...}"
	end
	if t == "table" then
		local parts = {}
		for i, v in ipairs(value) do
			parts[#parts + 1] = util.stringify(v, depth + 1)
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end
	return tostring(value)
end

function util.serializeArgs(args)
	local parts = {}
	for i = 1, (args.n or 0) do
		parts[#parts + 1] = util.stringify(args[i])
	end
	return table.concat(parts, ", ")
end
end

-- ===== remotes.lua =====================================================
do
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
end

-- ===== farm.lua ========================================================
do
--[[
	Aero :: Milonarie Tycoon :: farming

	El farm corre por dos vias:
	  - remote : replay del remote ligado a "collect" con los args capturados por el spy
	  - fisico : caminar a las partes de dinero / disparar los ProximityPrompt
	El modo "hybrid" prueba las dos; la fisica cubre los juegos sin remote de cobro.
]]

Aero = Aero or {}
Aero.farm = {}

local farm = Aero.farm
local util = Aero.util

farm.moneyParts = {}
farm.prompts = {}
farm.lastScan = 0

function farm.scanWorld()
	local cfg = Aero.config.physical
	farm.moneyParts = {}
	farm.prompts = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") then
			local lname = string.lower(inst.Name)
			for _, key in ipairs(cfg.moneyNames) do
				if string.find(lname, key, 1, true) then
					table.insert(farm.moneyParts, inst)
					break
				end
			end
		elseif inst:IsA("ProximityPrompt") then
			local action = string.lower(inst.ActionText or inst.Name or "")
			for _, key in ipairs(cfg.promptActions) do
				if string.find(action, key, 1, true) then
					table.insert(farm.prompts, inst)
					break
				end
			end
		end
	end
	farm.lastScan = util.now()
	return #farm.moneyParts, #farm.prompts
end

function farm.nearestMoneyPart(origin)
	local best, bestDist
	local radius = Aero.config.physical.searchRadius
	for _, part in ipairs(farm.moneyParts) do
		if part.Parent and part:IsDescendantOf(workspace) then
			local d = (part.Position - origin).Magnitude
			if d < radius and (not bestDist or d < bestDist) then
				best, bestDist = part, d
			end
		end
	end
	return best
end

function farm.collectPhysical()
	local root = util.getRootPart()
	if not root then
		return false
	end
	local part = farm.nearestMoneyPart(root.Position)
	if not part then
		return false
	end
	if type(firetouchinterest) == "function" then
		pcall(firetouchinterest, root, part, 0)
		pcall(firetouchinterest, root, part, 1)
		return true
	end
	-- Sin firetouchinterest: el CFrame del personaje si es propiedad del cliente,
	-- asi que el server recibe el movimiento.
	root.CFrame = part.CFrame + Vector3.new(0, 3, 0)
	return true
end

function farm.firePrompts()
	local fired = 0
	for _, prompt in ipairs(farm.prompts) do
		if prompt.Parent and prompt:IsDescendantOf(workspace) then
			if type(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
			else
				local detector = prompt.Parent:FindFirstChildOfClass("ClickDetector")
				if detector and type(fireclickdetector) == "function" then
					pcall(fireclickdetector, detector)
				else
					local root = util.getRootPart()
					if root and prompt.Parent:IsA("BasePart") then
						root.CFrame = prompt.Parent.CFrame + Vector3.new(0, 3, 0)
					end
				end
			end
			fired = fired + 1
			if fired >= 5 then
				break
			end
		end
	end
	return fired
end

function farm.collectRemote()
	local rec = Aero.remotes.bound("collect")
	if not rec then
		return false
	end
	local overrides = nil
	if Aero.config.money.inflate then
		local amount = math.min(Aero.config.money.value, Aero.config.money.cap)
		overrides = { [Aero.config.money.argIndex] = amount }
	end
	return Aero.remotes.fire(rec, overrides)
end

function farm.buy()
	local rec = Aero.remotes.bound("buy")
	if not rec then
		return false
	end
	return Aero.remotes.fire(rec)
end

function farm.rebirth()
	local rec = Aero.remotes.bound("rebirth")
	if not rec then
		return false
	end
	return Aero.remotes.fire(rec)
end

function farm.loop()
	local cfg = Aero.config.farm
	local lastCollect, lastBuy, lastRebirth = 0, 0, 0
	while true do
		local now = util.now()
		if cfg.enabled then
			if now - farm.lastScan >= Aero.config.physical.scanInterval then
				farm.scanWorld()
			end
			if now - lastCollect >= cfg.collectInterval then
				lastCollect = now
				local mode = cfg.mode
				if mode == "remote" or mode == "hybrid" then
					farm.collectRemote()
				end
				if mode == "physical" or mode == "hybrid" then
					if not farm.collectPhysical() then
						farm.firePrompts()
					end
				end
			end
			if cfg.autoBuy and now - lastBuy >= cfg.buyInterval then
				lastBuy = now
				farm.buy()
			end
			if cfg.autoRebirth and now - lastRebirth >= cfg.rebirthInterval then
				lastRebirth = now
				local cash = util.getCash()
				if cash and cash >= cfg.rebirthAt then
					farm.rebirth()
				end
			end
		end
		task.wait(0.05)
	end
end
end

-- ===== move.lua ========================================================
do
--[[
	Aero :: Milonarie Tycoon :: movimiento

	Speed, fly, noclip, infinite jump y anti-AFK.
	Todo pasa por el Humanoid y el HumanoidRootPart: el personaje es propiedad
	del cliente, asi que los cambios de velocidad y posicion los acepta el server.
]]

Aero = Aero or {}
Aero.move = {}

local move = Aero.move
local util = Aero.util

local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

move.originalSpeed = nil

function move.applySpeed()
	local hum = util.getHumanoid()
	if not hum then
		return false
	end
	if move.originalSpeed == nil then
		move.originalSpeed = hum.WalkSpeed
	end
	hum.WalkSpeed = Aero.config.move.speed
	return true
end

function move.resetSpeed()
	local hum = util.getHumanoid()
	if not hum then
		return false
	end
	hum.WalkSpeed = move.originalSpeed or 16
	move.originalSpeed = nil
	return true
end

function move.startFly()
	move.flyConn = RunService.RenderStepped:Connect(function()
		if not Aero.config.move.flyEnabled then
			return
		end
		local char = util.getCharacter()
		if not char then
			return
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		local cam = workspace.CurrentCamera
		if not root or not cam then
			return
		end
		local dir = Vector3.new(0, 0, 0)
		if UIS:IsKeyDown(Enum.KeyCode.W) then
			dir = dir + cam.CFrame.LookVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.S) then
			dir = dir - cam.CFrame.LookVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.D) then
			dir = dir + cam.CFrame.RightVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.A) then
			dir = dir - cam.CFrame.RightVector
		end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then
			dir = dir + Vector3.new(0, 1, 0)
		end
		if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
			dir = dir - Vector3.new(0, 1, 0)
		end
		local speed = Aero.config.move.flySpeed
		if dir.Magnitude > 0 then
			root.AssemblyLinearVelocity = dir.Unit * speed
		else
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		end
	end)
end

function move.startNoclip()
	move.noclipConn = RunService.RenderStepped:Connect(function()
		if not Aero.config.move.noclip then
			return
		end
		local char = util.getCharacter()
		if not char then
			return
		end
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
			end
		end
	end)
end

function move.startInfiniteJump()
	move.jumpConn = UIS.JumpRequest:Connect(function()
		if not Aero.config.move.infiniteJump then
			return
		end
		local hum = util.getHumanoid()
		if not hum then
			return
		end
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
end

function move.startAntiAfk()
	move.afkConn = RunService.Heartbeat:Connect(function()
		if not Aero.config.move.antiAfk then
			return
		end
		local char = util.getCharacter()
		if not char then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Sit = false
		end
	end)
	local ok, virtualUser = pcall(function()
		return game:GetService("VirtualUser")
	end)
	if ok and virtualUser then
		pcall(function()
			virtualUser:CaptureController()
		end)
	end
end

function move.teleportTo(targetCFrame)
	local root = util.getRootPart()
	if not root then
		return false
	end
	root.CFrame = targetCFrame
	return true
end

function move.findTycoon()
	-- Busca el base del jugador: hijo del workspace con nombre de tycoon/base/plot
	-- y, dentro, una BasePart.
	local player = util.getPlayer()
	local origin = player and player.Position or Vector3.new(0, 0, 0)
	local best, bestDist
	for _, inst in ipairs(workspace:GetChildren()) do
		local n = string.lower(inst.Name)
		if string.find(n, "tycoon", 1, true)
			or string.find(n, "base", 1, true)
			or string.find(n, "plot", 1, true) then
			local part = nil
			if inst:IsA("BasePart") then
				part = inst
			else
				part = inst:FindFirstChildWhichIsA("BasePart", true)
			end
			if part then
				local d = (part.Position - origin).Magnitude
				if not bestDist or d < bestDist then
					best, bestDist = part, d
				end
			end
		end
	end
	return best
end

function move.teleportToTycoon()
	local part = move.findTycoon()
	if not part then
		util.log("no se encontro base/tycoon en el workspace")
		return false
	end
	return move.teleportTo(part.CFrame + Vector3.new(0, 4, 0))
end

function move.teleportToMoney()
	local root = util.getRootPart()
	if not root then
		return false
	end
	if #Aero.farm.moneyParts == 0 then
		Aero.farm.scanWorld()
	end
	local part = Aero.farm.nearestMoneyPart(root.Position)
	if not part then
		util.log("no hay partes de dinero cerca")
		return false
	end
	return move.teleportTo(part.CFrame + Vector3.new(0, 3, 0))
end

function move.teleportToPlayer(target)
	local root = util.getRootPart()
	local char = target and target.Character
	if not root or not char then
		return false
	end
	local head = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")
	if not head then
		return false
	end
	return move.teleportTo(head.CFrame + Vector3.new(0, 3, 0))
end
end

-- ===== ui.lua ==========================================================
do
--[[
	Aero :: Milonarie Tycoon :: menu

	GUI inmediata (sin librerias externas), tabbed y arrastrable:
	FARM / MOVE / TARGET / CONFIG. Todo toggle arranca apagado.
]]

Aero = Aero or {}
Aero.ui = {}

local ui = Aero.ui
local util = Aero.util

ui.root = nil
ui.pages = {}
ui.labels = {}
ui.logs = {}
ui.remoteRows = {}
ui.lastRemoteVersion = -1

local COLORS = {
	bg     = Color3.fromRGB(18, 18, 22),
	panel  = Color3.fromRGB(30, 30, 38),
	accent = Color3.fromRGB(80, 150, 255),
	accent2 = Color3.fromRGB(38, 86, 165),
	text   = Color3.fromRGB(228, 228, 235),
	muted  = Color3.fromRGB(138, 138, 155),
	off    = Color3.fromRGB(58, 58, 68),
	row    = Color3.fromRGB(24, 24, 30),
}

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		local ok = pcall(function()
			inst[k] = v
		end)
		if not ok then
			util.log(string.format("prop fail %s.%s", class, tostring(k)))
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function row(parent, height)
	return make("Frame", {
		Size = UDim2.new(1, -12, 0, height or 30),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)
end

local function label(parent, text, size, xalign)
	return make("TextLabel", {
		Size = size or UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = COLORS.text,
		TextXAlignment = xalign or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Font = Enum.Font.Gotham,
		TextSize = 13,
	}, parent)
end

function ui.pushLog(msg)
	table.insert(ui.logs, msg)
	while #ui.logs > 120 do
		table.remove(ui.logs, 1)
	end
end

--[[ widgets ]]--

function ui.toggle(parent, text, getter, setter)
	local holder = row(parent, 28)
	local textLabel = label(holder, text, UDim2.new(1, -60, 1, 0))
	local box = make("TextButton", {
		Size = UDim2.new(0, 38, 0, 20),
		Position = UDim2.new(1, -40, 0.5, -10),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = COLORS.off,
		Text = "",
		AutoButtonColor = false,
	}, holder)
	local knob = make("Frame", {
		Size = UDim2.new(0, 16, 0, 16),
		Position = UDim2.new(0, 2, 0.5, -8),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = COLORS.text,
		BorderSizePixel = 0,
	}, box)
	local function paint()
		local on = getter() and true or false
		box.BackgroundColor3 = on and COLORS.accent or COLORS.off
		knob.Position = UDim2.new(on and 1 or 0, on and -18 or 2, 0.5, -8)
		textLabel.TextColor3 = on and COLORS.text or COLORS.muted
	end
	box.MouseButton1Click:Connect(function()
		setter(not getter())
		paint()
	end)
	paint()
	return holder
end

function ui.slider(parent, text, min, max, getter, setter, step)
	local holder = row(parent, 40)
	label(holder, text, UDim2.new(1, -80, 0, 16))
	local value = make("TextLabel", {
		Size = UDim2.new(0, 70, 0, 16),
		Position = UDim2.new(1, -70, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = COLORS.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		Font = Enum.Font.Gotham,
		TextSize = 12,
	}, holder)
	local bar = make("Frame", {
		Size = UDim2.new(1, -12, 0, 6),
		Position = UDim2.new(0, 6, 0, 24),
		BackgroundColor3 = COLORS.off,
		BorderSizePixel = 0,
	}, holder)
	local fill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = COLORS.accent,
		BorderSizePixel = 0,
	}, bar)

	local UIS = game:GetService("UserInputService")
	local dragging = false

	local function paint()
		local v = getter()
		local pct = (v - min) / (max - min)
		pct = math.max(0, math.min(1, pct))
		fill.Size = UDim2.new(pct, 0, 1, 0)
		value.Text = string.format("%.2f", v)
	end

	local function setFromX(x)
		local pct = (x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X)
		pct = math.max(0, math.min(1, pct))
		local v = min + (max - min) * pct
		if step then
			v = math.floor(v / step) * step
		end
		setter(v)
		paint()
	end

	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UIS.InputEnded:Connect(function()
		dragging = false
	end)
	paint()
	return holder
end

function ui.cycle(parent, text, values, getter, setter)
	local holder = row(parent, 28)
	label(holder, text, UDim2.new(0.5, 0, 1, 0))
	local btn = make("TextButton", {
		Size = UDim2.new(0.45, 0, 0, 22),
		Position = UDim2.new(1, -6, 0.5, -11),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = COLORS.panel,
		Text = tostring(getter()),
		TextColor3 = COLORS.text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		BorderSizePixel = 0,
	}, holder)
	btn.MouseButton1Click:Connect(function()
		local cur = getter()
		local idx = 0
		for i, v in ipairs(values) do
			if v == cur then
				idx = i
			end
		end
		local nv = values[(idx % #values) + 1]
		setter(nv)
		btn.Text = tostring(nv)
	end)
	return holder
end

function ui.button(parent, text, fn)
	local btn = make("TextButton", {
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundColor3 = COLORS.panel,
		Text = text,
		TextColor3 = COLORS.text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		BorderSizePixel = 0,
	}, parent)
	btn.MouseButton1Click:Connect(function()
		fn()
	end)
	return btn
end

function ui.textBox(parent, text, getter, setter)
	local holder = row(parent, 28)
	label(holder, text, UDim2.new(0, 120, 1, 0))
	local box = make("TextBox", {
		Size = UDim2.new(1, -132, 0, 22),
		Position = UDim2.new(1, -126, 0.5, -11),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = COLORS.panel,
		Text = tostring(getter() or ""),
		TextColor3 = COLORS.text,
		TextSize = 12,
		Font = Enum.Font.Code,
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
	}, holder)
	box.FocusLost:Connect(function()
		setter(box.Text)
	end)
	return holder
end

--[[ tabs ]]--

function ui.selectTab(name)
	for n, page in pairs(ui.pages) do
		page.Visible = (n == name)
	end
	ui.activeTab = name
end

--[[ config ]]--

function ui.configJson()
	local ok, HttpService = pcall(function()
		return game:GetService("HttpService")
	end)
	if not ok then
		return "{}"
	end
	local ok2, encoded = pcall(function()
		return HttpService:JSONEncode(Aero.config)
	end)
	if not ok2 then
		return "{}"
	end
	return encoded
end

function ui.saveConfig()
	local json = ui.configJson()
	if type(writefile) == "function" then
		writefile(Aero.config.ui.configFile, json)
		util.log("config guardada: " .. Aero.config.ui.configFile)
	else
		local g = (type(getgenv) == "function") and getgenv() or _G
		g.AeroConfigJson = json
		util.log("writefile no disponible: config en getgenv().AeroConfigJson")
	end
end

function ui.loadConfig(quiet)
	local json
	if type(readfile) == "function" then
		pcall(function()
			json = readfile(Aero.config.ui.configFile)
		end)
	end
	if not json then
		local g = (type(getgenv) == "function") and getgenv() or _G
		json = g.AeroConfigJson
	end
	if not json then
		if not quiet then
			util.log("no hay config guardada")
		end
		return false
	end
	local ok, HttpService = pcall(function()
		return game:GetService("HttpService")
	end)
	if not ok then
		return false
	end
	local ok2, decoded = pcall(function()
		return HttpService:JSONDecode(json)
	end)
	if ok2 and type(decoded) == "table" then
		for k, v in pairs(decoded) do
			Aero.config[k] = v
		end
		util.log("config cargada")
		return true
	end
	util.log("config corrupta")
	return false
end

function ui.resetConfig()
	if not Aero.defaults then
		util.log("sin defaults guardados")
		return
	end
	for k, v in pairs(Aero.defaults) do
		Aero.config[k] = v
	end
	util.log("config reseteada")
end

function ui.copyJson()
	local json = ui.configJson()
	if type(setclipboard) == "function" then
		setclipboard(json)
		util.log("json copiado al clipboard")
	else
		util.log("setclipboard no disponible")
	end
end

--[[ remote rows ]]--

function ui.buildRemoteRows()
	for _, r in ipairs(ui.remoteRows) do
		r:Destroy()
	end
	ui.remoteRows = {}
	local index = 0
	local paths = {}
	for path in pairs(Aero.remotes.records) do
		paths[#paths + 1] = path
	end
	table.sort(paths)
	for _, path in ipairs(paths) do
		local rec = Aero.remotes.records[path]
		index = index + 1
		local holder = make("Frame", {
			Size = UDim2.new(1, -12, 0, 26),
			Position = UDim2.new(0, 6, 0, 0),
			BackgroundColor3 = COLORS.row,
			BorderSizePixel = 0,
			LayoutOrder = 100 + index,
		}, ui.pages.TARGET)
		local text = string.format("%s  (%s x%d)", rec.name, rec.class, rec.count)
		label(holder, text, UDim2.new(1, -120, 1, 0))
		local function bindButton(text, action, x)
			local b = make("TextButton", {
				Size = UDim2.new(0, 30, 0, 18),
				Position = UDim2.new(1, x, 0.5, -9),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = COLORS.accent2,
				Text = text,
				TextColor3 = COLORS.text,
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				BorderSizePixel = 0,
			}, holder)
			b.MouseButton1Click:Connect(function()
				Aero.remotes.bind(action, path)
			end)
		end
		bindButton("C", "collect", -76)
		bindButton("B", "buy", -42)
		bindButton("R", "rebirth", -8)
		table.insert(ui.remoteRows, holder)
	end
end

--[[ refresh ]]--

function ui.refreshTick()
	while true do
		task.wait(Aero.config.ui.refreshInterval)
		if not (ui.root and ui.root.Parent) then
			-- sin GUI activa no hay nada que refrescar
		else
		local cash, cashName = util.getCash()
		if ui.labels.cash then
			if cash then
				ui.labels.cash.Text = string.format("%s: %s", cashName or "cash", tostring(cash))
			else
				ui.labels.cash.Text = "cash: n/d"
			end
		end
		local captured = 0
		for _ in pairs(Aero.remotes.records) do
			captured = captured + 1
		end
		if ui.labels.remotes then
			ui.labels.remotes.Text = string.format("capturados: %d  |  bindings: %s",
				captured, Aero.remotes.bindings.collect or "-")
		end
		if ui.labels.bindings then
			ui.labels.bindings.Text = string.format("collect=%s buy=%s rebirth=%s",
				Aero.remotes.bindings.collect or "-",
				Aero.remotes.bindings.buy or "-",
				Aero.remotes.bindings.rebirth or "-")
		end
		if ui.lastRemoteVersion ~= Aero.remotes.version then
			ui.lastRemoteVersion = Aero.remotes.version
			ui.buildRemoteRows()
		end
		end
	end
end

--[[ build ]]--

function ui.build()
	if ui.root then
		ui.root:Destroy()
		ui.root = nil
	end
	local player = util.getPlayer()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", {
		Name = "AeroMilo",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	ui.root = gui

	local main = make("Frame", {
		Size = UDim2.new(0, 370, 0, 440),
		Position = UDim2.new(0.5, -185, 0.5, -220),
		BackgroundColor3 = COLORS.bg,
		BorderSizePixel = 0,
		Active = true,
	}, gui)

	local title = make("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = COLORS.accent2,
		BorderSizePixel = 0,
	}, main)
	make("TextLabel", {
		Size = UDim2.new(1, -70, 1, 0),
		BackgroundTransparency = 1,
		Text = "Aero :: Milonarie Tycoon",
		TextColor3 = COLORS.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
	}, title)
	local close = make("TextButton", {
		Size = UDim2.new(0, 28, 0, 28),
		Position = UDim2.new(1, -28, 0, 0),
		BackgroundTransparency = 1,
		Text = "X",
		TextColor3 = COLORS.text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
	}, title)
	close.MouseButton1Click:Connect(function()
		gui.Enabled = false
	end)

	-- arrastre
	local UIS = game:GetService("UserInputService")
	title.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local startPos = main.Position
			local startPoint = input.Position
			local conn
			conn = UIS.InputChanged:Connect(function(changed)
				if changed.UserInputType == Enum.UserInputType.MouseMovement
					or changed.UserInputType == Enum.UserInputType.Touch then
					main.Position = UDim2.new(
						startPos.X.Scale, startPos.X.Offset + (changed.Position.X - startPoint.X),
						startPos.Y.Scale, startPos.Y.Offset + (changed.Position.Y - startPoint.Y))
				end
			end)
			UIS.InputEnded:Connect(function()
				conn:Disconnect()
			end)
		end
	end)

	local tabNames = { "FARM", "MOVE", "TARGET", "CONFIG" }
	local tabBar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 0, 28),
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
	}, main)
	local holder = make("Frame", {
		Size = UDim2.new(1, 0, 1, -54),
		Position = UDim2.new(0, 0, 0, 54),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, main)

	ui.pages = {}
	for i, name in ipairs(tabNames) do
		local page = make("ScrollingFrame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = COLORS.accent,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false,
		}, holder)
		make("UIListLayout", {
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, page)
		ui.pages[name] = page
		local btn = make("TextButton", {
			Size = UDim2.new(0.25, -2, 1, 0),
			Position = UDim2.new(0.25 * (i - 1), 2, 0, 0),
			BackgroundColor3 = COLORS.panel,
			Text = name,
			TextColor3 = COLORS.muted,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			BorderSizePixel = 0,
		}, tabBar)
		btn.MouseButton1Click:Connect(function()
			ui.selectTab(name)
		end)
	end

	ui.buildFarmPage()
	ui.buildMovePage()
	ui.buildTargetPage()
	ui.buildConfigPage()
	ui.selectTab("FARM")
	util.log("menu listo")
end

function ui.buildFarmPage()
	local page = ui.pages.FARM
	local cashLabel = make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 20),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		Text = "cash: n/d",
		TextColor3 = COLORS.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
	}, page)
	ui.labels.cash = cashLabel

	ui.toggle(page, "Autofarm", function()
		return Aero.config.farm.enabled
	end, function(v)
		Aero.config.farm.enabled = v
		if v then
			Aero.farm.scanWorld()
		end
	end)

	ui.cycle(page, "Modo", { "hybrid", "remote", "physical" }, function()
		return Aero.config.farm.mode
	end, function(v)
		Aero.config.farm.mode = v
	end)

	ui.toggle(page, "Auto buy", function()
		return Aero.config.farm.autoBuy
	end, function(v)
		Aero.config.farm.autoBuy = v
	end)

	ui.toggle(page, "Auto rebirth", function()
		return Aero.config.farm.autoRebirth
	end, function(v)
		Aero.config.farm.autoRebirth = v
	end)

	ui.slider(page, "Intervalo collect", 0.05, 2, function()
		return Aero.config.farm.collectInterval
	end, function(v)
		Aero.config.farm.collectInterval = v
	end, 0.05)

	ui.slider(page, "Rebirth desde", 1e6, 1e10, function()
		return Aero.config.farm.rebirthAt
	end, function(v)
		Aero.config.farm.rebirthAt = v
	end, 1e6)

	ui.toggle(page, "Inflar cantidad", function()
		return Aero.config.money.inflate
	end, function(v)
		Aero.config.money.inflate = v
	end)

	ui.textBox(page, "Arg index", function()
		return Aero.config.money.argIndex
	end, function(v)
		Aero.config.money.argIndex = tonumber(v) or 1
	end)

	ui.textBox(page, "Cantidad", function()
		return Aero.config.money.value
	end, function(v)
		Aero.config.money.value = tonumber(v) or 0
	end)

	ui.button(page, "Auto-bind remotes", function()
		Aero.remotes.autoBind()
	end)
	ui.button(page, "Rescan remotes", function()
		Aero.remotes.scan()
	end)
end

function ui.buildMovePage()
	local page = ui.pages.MOVE
	ui.toggle(page, "Speed", function()
		return Aero.config.move.speedEnabled
	end, function(v)
		Aero.config.move.speedEnabled = v
		if v then
			Aero.move.applySpeed()
		else
			Aero.move.resetSpeed()
		end
	end)
	ui.slider(page, "WalkSpeed", 16, 200, function()
		return Aero.config.move.speed
	end, function(v)
		Aero.config.move.speed = v
		if Aero.config.move.speedEnabled then
			Aero.move.applySpeed()
		end
	end, 1)

	ui.toggle(page, "Fly", function()
		return Aero.config.move.flyEnabled
	end, function(v)
		Aero.config.move.flyEnabled = v
	end)
	ui.slider(page, "Fly speed", 10, 300, function()
		return Aero.config.move.flySpeed
	end, function(v)
		Aero.config.move.flySpeed = v
	end, 1)

	ui.toggle(page, "Noclip", function()
		return Aero.config.move.noclip
	end, function(v)
		Aero.config.move.noclip = v
	end)
	ui.toggle(page, "Infinite jump", function()
		return Aero.config.move.infiniteJump
	end, function(v)
		Aero.config.move.infiniteJump = v
	end)
	ui.toggle(page, "Anti-AFK", function()
		return Aero.config.move.antiAfk
	end, function(v)
		Aero.config.move.antiAfk = v
	end)

	ui.button(page, "TP a tu tycoon", function()
		Aero.move.teleportToTycoon()
	end)
	ui.button(page, "TP a dinero", function()
		Aero.move.teleportToMoney()
	end)
	ui.button(page, "Reset velocidad", function()
		Aero.move.resetSpeed()
	end)
end

function ui.buildTargetPage()
	local page = ui.pages.TARGET
	local status = make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 18),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		Text = "capturados: 0",
		TextColor3 = COLORS.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
	}, page)
	ui.labels.remotes = status

	local bindings = make("TextLabel", {
		Size = UDim2.new(1, -12, 0, 18),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		Text = "collect=- buy=- rebirth=-",
		TextColor3 = COLORS.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Code,
		TextSize = 11,
	}, page)
	ui.labels.bindings = bindings

	ui.button(page, "Auto-bind", function()
		Aero.remotes.autoBind()
	end)
	ui.button(page, "Rescan", function()
		Aero.remotes.scan()
	end)
	ui.button(page, "Limpiar captura", function()
		Aero.remotes.clear()
	end)
end

function ui.buildConfigPage()
	local page = ui.pages.CONFIG
	ui.button(page, "Guardar config", function()
		ui.saveConfig()
	end)
	ui.button(page, "Cargar config", function()
		ui.loadConfig()
	end)
	ui.button(page, "Copiar JSON", function()
		ui.copyJson()
	end)
	ui.button(page, "Reset defaults", function()
		ui.resetConfig()
	end)

	local box = make("TextBox", {
		Size = UDim2.new(1, -12, 0, 160),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundColor3 = COLORS.row,
		Text = ui.configJson(),
		TextColor3 = COLORS.muted,
		TextSize = 11,
		Font = Enum.Font.Code,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		BorderSizePixel = 0,
	}, page)
	ui.labels.json = box
end
end

-- ===== main.lua ========================================================
do
--[[
	Aero :: Milonarie Tycoon :: bootstrap
]]

Aero = Aero or {}
Aero.main = {}

local main = Aero.main

function main.run()
	local g = (type(getgenv) == "function") and getgenv() or _G
	if g.AeroMilo and g.AeroMilo.destroy then
		pcall(g.AeroMilo.destroy)
	end

	Aero.util.log("Aero :: Milonarie Tycoon :: boot")

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player then
		player = Players.PlayerAdded:Wait()
	end

	-- Copia de los defaults para el boton "Reset defaults" de la tab CONFIG.
	Aero.defaults = Aero.util.deepCopy(Aero.config)

	-- Si hay config guardada de una sesion anterior, se aplica al arrancar.
	Aero.ui.loadConfig(true)

	-- Captura de argumentos: sin esto el replay no sabe que enviarle al server.
	Aero.remotes.installSpy()
	Aero.remotes.scan()

	Aero.ui.build()

	task.spawn(Aero.farm.loop)
	task.spawn(Aero.move.startFly)
	task.spawn(Aero.move.startNoclip)
	task.spawn(Aero.move.startInfiniteJump)
	task.spawn(Aero.move.startAntiAfk)
	task.spawn(Aero.ui.refreshTick)

	player.CharacterAdded:Connect(function()
		task.wait(0.6)
		if Aero.config.move.speedEnabled then
			Aero.move.applySpeed()
		end
		Aero.farm.scanWorld()
	end)

	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local keyName = Aero.config.ui.toggleKey
		if keyName and input.KeyCode == Enum.KeyCode[keyName] then
			local gui = Aero.ui.root
			if gui then
				gui.Enabled = not gui.Enabled
			end
		end
	end)

	g.AeroMilo = { running = true, destroy = main.destroy }
	Aero.util.log("listo: FARM para farmear, TARGET para ligar remotes, RightShift abre/cierra")
end

function main.destroy()
	local g = (type(getgenv) == "function") and getgenv() or _G
	if Aero.ui and Aero.ui.root then
		Aero.ui.root:Destroy()
		Aero.ui.root = nil
	end
	g.AeroMilo = nil
end

main.run()
end
