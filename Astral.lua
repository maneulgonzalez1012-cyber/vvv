--[[
	Astral :: single-file build
	generado por build.py desde src/ - no editar a mano.
	source of truth: src/ en el repo.

	loadstring(game:HttpGet(...))() lo carga;
	getgenv().Astral.unload() lo apaga.
]]

local __modules = {}
local __cache = {}

local function __require(id)
	local cached = __cache[id]
	if cached ~= nil then
		return cached
	end

	local factory = __modules[id]
	if not factory then
		error("[Astral] modulo desconocido: " .. tostring(id), 0)
	end

	local value = factory()
	__cache[id] = value
	return value
end

__modules["shared/config"] = function()
--[[
	Astral :: shared/config

	todo lo que se puede tocar sin entender el resto vive aquí.
	las claves de `defaults` son exactamente los flags de Rayfield y las
	claves de `state`, así que UI y lógica no pueden discrepar.
]]

local Config = {}

Config.version = "2.0.0"
Config.name = "Astral"
Config.subtitle = "esp + hitbox + aim"
Config.configFile = "Astral"
Config.theme = "amethyst"

-- rate limit del hitbox: cada cuánto se re-aplica el Size a las partes
Config.hitboxInterval = 0.5
-- techo de jugadores por pase: un servidor de 60 no te clava el frame
Config.hitboxMaxPlayers = 30

-- { min, max, incremento } de cada slider
Config.ranges = {
	espMaxDistance = { 50, 5000, 50 },
	hitScale = { 1, 10, 0.5 },
	aimFov = { 10, 360, 1 },
	aimSmooth = { 0, 20, 0.5 },
	aimFovCircleRadius = { 20, 400, 1 },
}

function Config.slider(key)
	local r = Config.ranges[key]
	return { r[1], r[2] }, r[3]
end

Config.defaults = {
	-- esp
	espEnabled = false,
	espBox = true,
	espFill = false,
	espHealth = true,
	espName = true,
	espDistance = true,
	espTracer = false,
	espTeamCheck = true,
	espMaxDistance = 750,
	espBoxColor = Color3.fromRGB(255, 255, 255),
	espNameColor = Color3.fromRGB(255, 255, 255),
	espFillColor = Color3.fromRGB(20, 20, 30),

	-- hitbox
	hitEnabled = false,
	hitRootOnly = false,
	hitScale = 2.0,

	-- aim
	aimEnabled = false,
	aimSmooth = 4,
	aimFov = 60,
	aimWallCheck = true,
	aimBone = "Head",
	aimFovCircle = true,
	aimFovCircleColor = Color3.fromRGB(140, 120, 255),
	aimFovCircleRadius = 120,

	-- misc
	radarEnabled = false,
}

return Config

end

__modules["shared/mathx"] = function()
--[[
	Astral :: shared/mathx
	geometría de pantalla y utilidades numéricas. sin estado.
]]

local Mathx = {}

-- hull en pantalla de una caja orientada: 8 esquinas al viewport.
-- devuelve minX, minY, maxX, maxY o nil si no hay nada visible.
-- cam:WorldToViewportPoint devuelve (x, y, depth); depth <= 0 está detrás
function Mathx.projectBox(cam, cf, size)
	local corners = Mathx.corners
	local minX, minY, maxX, maxY
	local visible = 0

	for i = 1, 8 do
		local c = corners[i]
		local world = cf * Vector3.new(c[1] * size.X * 0.5, c[2] * size.Y * 0.5, c[3] * size.Z * 0.5)
		local sp = cam:WorldToViewportPoint(world)

		if sp.Z > 0 then
			visible = visible + 1
			minX = (not minX or sp.X < minX) and sp.X or minX
			maxX = (not maxX or sp.X > maxX) and sp.X or maxX
			minY = (not minY or sp.Y < minY) and sp.Y or minY
			maxY = (not maxY or sp.Y > maxY) and sp.Y or maxY
		end
	end

	if visible == 0 or not minX then
		return nil
	end

	return minX, minY, maxX, maxY
end

Mathx.corners = {
	{ -1, -1, -1 }, { 1, -1, -1 }, { -1, 1, -1 }, { 1, 1, -1 },
	{ -1, -1, 1 }, { 1, -1, 1 }, { -1, 1, 1 }, { 1, 1, 1 },
}

function Mathx.clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

-- lerp de color sin tocarse los ojos con Color3:Lerp (que no existe en todos
-- los executors con Drawing)
function Mathx.lerpColor(a, b, t)
	t = Mathx.clamp(t, 0, 1)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

return Mathx

end

__modules["shared/players"] = function()
--[[
	Astral :: shared/players
	la única fuente de verdad sobre "quién es un objetivo válido" y sobre
	"dónde está su hueso". todos los módulos preguntan aquí en vez de
	repetir la lógica y divergir.

	la lista de jugadores se cachea por frame: Players:GetPlayers() crea una
	tabla nueva en cada llamada y llamarla 3 veces por frame se nota.
]]

local Players = game:GetService("Players")

local PlayersLib = {}
local LP = Players.LocalPlayer

PlayersLib.service = Players
PlayersLib.me = LP

-- alias de huesos: el mismo nombre cubre R6 y R15
local BONE_ALIASES = {
	Head = { "Head" },
	UpperTorso = { "UpperTorso", "Torso" },
	LowerTorso = { "LowerTorso", "Torso" },
	HumanoidRootPart = { "HumanoidRootPart", "Torso" },
	LeftHand = { "LeftHand", "Left Arm" },
	RightHand = { "RightHand", "Right Arm" },
}

PlayersLib.boneNames = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" }

function PlayersLib.humanoid(char)
	if not char then
		return nil
	end
	local ok, hum = pcall(char.FindFirstChildOfClass, char, "Humanoid")
	return ok and hum or nil
end

function PlayersLib.root(char)
	if not char then
		return nil
	end
	local ok, part = pcall(function()
		return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
	end)
	return ok and part or nil
end

-- TeamColor es blanco para todos en juegos sin equipos: solo el objeto Team
function PlayersLib.sameTeam(plr)
	if plr.Team == nil or LP.Team == nil then
		return false
	end
	return plr.Team == LP.Team
end

-- char, hum, root, distance o nil si no es objetivo
function PlayersLib.target(plr, camPos, teamCheck)
	if plr == LP or plr.Character == nil then
		return nil
	end

	local char = plr.Character
	local hum = PlayersLib.humanoid(char)
	if not hum or hum.Health <= 0 then
		return nil
	end

	local root = PlayersLib.root(char)
	if not root or not root:IsA("BasePart") then
		return nil
	end

	if teamCheck and PlayersLib.sameTeam(plr) then
		return nil
	end

	local dist = 0
	if camPos then
		dist = (camPos - root.Position).Magnitude
	end

	return char, hum, root, dist
end

function PlayersLib.bone(char, name)
	local list = BONE_ALIASES[name] or { name }
	for i = 1, #list do
		local part = char:FindFirstChild(list[i], true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local cacheFrame, cacheList = -1, nil

function PlayersLib.all()
	local frame = math.floor(os.clock() * 120)
	if frame ~= cacheFrame then
		cacheFrame = frame
		cacheList = Players:GetPlayers()
	end
	return cacheList
end

function PlayersLib.nameOf(plr)
	local n = plr.DisplayName
	if n == nil or n == "" then
		n = plr.Name
	end
	return n
end

return PlayersLib

end

__modules["shared/renderer"] = function()
--[[
	Astral :: shared/renderer

	fachada de dibujo. dos backends con el mismo contrato:

		newRect() / newText() / newCircle()  crean el objeto
		rect(o, x, y, w, h, color, filled, thickness, transparency, visible)
		text(o, str, x, y, size, color, visible)
		circle(o, x, y, radius, color, thickness, filled, visible)
		hide(o) / destroy(o)

	coordenadas: píxeles, origen arriba-izquierda del viewport, que es lo que
	devuelve cam:WorldToViewportPoint y mide cam.ViewportSize.

	Drawing usa ese origen tal cual. PlayerGui NO: si IgnoreGuiInset está en
	false, el gui empieza debajo de la topbar y las Y cuadran con el viewport;
	con true se dibujaría 36px arriba. CoreGui y gethui() ya cubren la pantalla
	completa, así que ahí IgnoreGuiInset se queda en true.
]]

local Renderer = {}

local function safeCall(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	return nil
end

----------------------------------------------------------------------
-- backend: Drawing
----------------------------------------------------------------------
local function drawingBackend()
	local fonts = Drawing.Fonts
	local font = 2
	if fonts then
		font = fonts.Plex or fonts.SourceSans or 2
	end

	local function make(class)
		return safeCall(function()
			local o = Drawing.new(class)
			if o then
				o.Visible = false
			end
			return o
		end)
	end

	local function set(o, key, value)
		if o then
			pcall(function()
				o[key] = value
			end)
		end
	end

	return {
		name = "Drawing",
		newRect = function()
			return make("Square")
		end,
		newText = function()
			return make("Text")
		end,
		newCircle = function()
			return make("Circle")
		end,
		rect = function(o, x, y, w, h, color, filled, thickness, transparency, visible)
			if not o then
				return
			end
			set(o, "Position", Vector2.new(x, y))
			set(o, "Size", Vector2.new(w, h))
			set(o, "Color", color)
			set(o, "Filled", filled)
			set(o, "Thickness", thickness)
			set(o, "Transparency", transparency)
			set(o, "Visible", visible)
		end,
		text = function(o, str, x, y, size, color, visible)
			if not o then
				return
			end
			set(o, "Text", str)
			set(o, "Position", Vector2.new(x, y))
			set(o, "Size", size)
			set(o, "Color", color)
			set(o, "Center", true)
			set(o, "Outline", true)
			set(o, "Font", font)
			set(o, "Visible", visible)
		end,
		circle = function(o, x, y, radius, color, thickness, filled, visible)
			if not o then
				return
			end
			set(o, "Position", Vector2.new(x, y))
			set(o, "Radius", radius)
			set(o, "Color", color)
			set(o, "Thickness", thickness)
			set(o, "Filled", filled)
			set(o, "Visible", visible)
		end,
		hide = function(o)
			set(o, "Visible", false)
		end,
		destroy = function(o)
			if o then
				pcall(function()
					o:Remove()
				end)
			end
		end,
	}
end

----------------------------------------------------------------------
-- backend: ScreenGui (executors sin Drawing)
----------------------------------------------------------------------
local function guiBackend()
	local parent
	local underPlayerGui = false
	-- el servicio, no el módulo de jugadores: aquí solo se necesita el
	-- LocalPlayer para llegar a PlayerGui
	local playerSvc = game:GetService("Players")

	local probes = {
		{ fn = function()
			return gethui()
		end },
		{ fn = function()
			return game:GetService("CoreGui")
		end },
		{ fn = function()
			local lp = playerSvc.LocalPlayer
			if not lp then
				return nil
			end
			return lp:WaitForChild("PlayerGui", 5)
		end, playerGui = true },
	}

	for _, probe in ipairs(probes) do
		parent = safeCall(probe.fn)
		if parent then
			underPlayerGui = probe.playerGui == true
			break
		end
	end

	if not parent then
		return nil
	end

	local gui = safeCall(function()
		return Instance.new("ScreenGui")
	end)
	if not gui then
		return nil
	end
	gui.Name = "Astral"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 999
	-- true en CoreGui/gethui (pantalla completa), false en PlayerGui (bajo la
	-- topbar) para que el origen coincida con el del viewport
	gui.IgnoreGuiInset = not underPlayerGui
	if not safeCall(function()
		gui.Parent = parent
		return true
	end) then
		gui:Destroy()
		return nil
	end

	local strokes = setmetatable({}, { __mode = "k" })
	local corners = setmetatable({}, { __mode = "k" })

	local function make(class)
		local o = Instance.new(class)
		o.BorderSizePixel = 0
		o.BackgroundTransparency = 1
		o.Visible = false
		o.Parent = gui
		return o
	end

	local function strokeOf(o)
		local s = strokes[o]
		if not s then
			s = Instance.new("UIStroke")
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent = o
			strokes[o] = s
		end
		return s
	end

	local function fill(o, color, transparency)
		o.BackgroundColor3 = color
		o.BackgroundTransparency = transparency or 0
		local s = strokes[o]
		if s then
			s.Enabled = false
		end
	end

	local function outline(o, color, thickness)
		o.BackgroundTransparency = 1
		local s = strokeOf(o)
		s.Enabled = true
		s.Color = color
		s.Thickness = math.max(thickness or 1, 1)
	end

	return {
		name = "ScreenGui",
		gui = gui,
		newRect = function()
			return make("Frame")
		end,
		newText = function()
			local t = make("TextLabel")
			t.Font = Enum.Font.Gotham
			t.TextSize = 13
			t.TextXAlignment = Enum.TextXAlignment.Center
			t.TextYAlignment = Enum.TextYAlignment.Top
			t.TextStrokeTransparency = 0.25
			t.AnchorPoint = Vector2.new(0.5, 0)
			t.TextColor3 = Color3.new(1, 1, 1)
			return t
		end,
		newCircle = function()
			local c = make("Frame")
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = c
			corners[c] = corner
			return c
		end,
		rect = function(o, x, y, w, h, color, filled, thickness, transparency, visible)
			if not o then
				return
			end
			o.Position = UDim2.fromOffset(x, y)
			o.Size = UDim2.fromOffset(math.max(w, 1), math.max(h, 1))
			o.Visible = visible
			if filled then
				fill(o, color, transparency)
			else
				outline(o, color, thickness)
			end
		end,
		text = function(o, str, x, y, size, color, visible)
			if not o then
				return
			end
			o.Text = str
			o.Position = UDim2.fromOffset(x, y)
			o.TextSize = size
			o.TextColor3 = color
			o.Visible = visible
		end,
		circle = function(o, x, y, radius, color, thickness, filled, visible)
			if not o then
				return
			end
			o.AnchorPoint = Vector2.new(0.5, 0.5)
			o.Position = UDim2.fromOffset(x, y)
			o.Size = UDim2.fromOffset(radius * 2, radius * 2)
			o.Visible = visible
			if filled then
				fill(o, color, 0.5)
			else
				outline(o, color, thickness)
				local corner = corners[o]
				if corner then
					corner.CornerRadius = UDim.new(1, 0)
				end
			end
		end,
		hide = function(o)
			if o then
				o.Visible = false
			end
		end,
		destroy = function(o)
			if o then
				safeCall(function()
					o:Destroy()
				end)
			end
		end,
	}
end

----------------------------------------------------------------------
-- selección
----------------------------------------------------------------------
function Renderer.pick()
	if Drawing and Drawing.new then
		local probe = safeCall(function()
			return Drawing.new("Square")
		end)
		if probe then
			pcall(function()
				probe:Remove()
			end)
			return drawingBackend()
		end
	end
	return guiBackend()
end

return Renderer

end

__modules["modules/esp"] = function()
--[[
	Astral :: modules/esp

	un pool de Drawing objects por jugador, creados una vez y reusados.
	nada se destruye en el loop: solo se apaga. el único Destroy pasa en
	PlayerRemoving o en unload, así no hay churn de objetos ni fugas.

	el hull sale de las 8 esquinas del bounding box del modelo, no de
	GetBoundingBox crudo: así la caja no se estira cuando el pj gira.
]]

local Mathx = __require("shared/mathx")
local PlayersLib = __require("shared/players")

local Esp = {}
Esp.__index = Esp

local HP_LOW = Color3.fromRGB(225, 55, 55)
local HP_HIGH = Color3.fromRGB(90, 225, 120)
local SHADOW = Color3.fromRGB(0, 0, 0)
local DIST_COLOR = Color3.fromRGB(215, 215, 222)
local WHITE = Color3.new(1, 1, 1)

function Esp.new(renderer, state)
	local self = setmetatable({}, Esp)
	self.r = renderer
	self.state = state
	self.pool = {}
	self.anyVisible = false
	self.conn = PlayersLib.service.PlayerRemoving:Connect(function(plr)
		self:forget(plr)
	end)
	return self
end

function Esp:create()
	local r = self.r
	local e = {
		fill = r.newRect(),
		box = r.newRect(),
		hpBack = r.newRect(),
		hpFill = r.newRect(),
		tracer = r.newRect(),
		label = r.newText(),
		dist = r.newText(),
	}
	-- orden de creación == orden de dibujo en Drawing: fill debajo del borde
	e.rects = { e.fill, e.box, e.hpBack, e.hpFill, e.tracer }
	e.texts = { e.label, e.dist }
	e.visible = false
	return e
end

function Esp:get(plr)
	local e = self.pool[plr]
	if not e then
		e = self:create()
		self.pool[plr] = e
	end
	return e
end

function Esp:forget(plr)
	local e = self.pool[plr]
	if not e then
		return
	end
	for _, o in ipairs(e.rects) do
		self.r.destroy(o)
	end
	for _, o in ipairs(e.texts) do
		self.r.destroy(o)
	end
	self.pool[plr] = nil
end

function Esp:hide(e)
	if not e.visible then
		return
	end
	for _, o in ipairs(e.rects) do
		self.r.hide(o)
	end
	for _, o in ipairs(e.texts) do
		self.r.hide(o)
	end
	e.visible = false
end

function Esp:hideAll()
	for _, e in pairs(self.pool) do
		self:hide(e)
	end
	self.anyVisible = false
end

-- un solo pase por frame; devuelve la cantidad de cajas dibujadas
function Esp:step(cam)
	local r = self.r
	local s = self.state

	if not s.espEnabled then
		if self.anyVisible then
			self:hideAll()
		end
		return 0
	end

	local camPos = cam.CFrame.Position
	local vp = cam.ViewportSize
	local maxDist = s.espMaxDistance
	local boxColor = s.espBoxColor or WHITE
	local nameColor = s.espNameColor or WHITE
	local fillColor = s.espFillColor or SHADOW
	local drawn = 0

	for _, plr in ipairs(PlayersLib.all()) do
		local char, hum, root, dist = PlayersLib.target(plr, camPos, s.espTeamCheck)
		local e = self.pool[plr]

		if not char or dist > maxDist then
			if e then
				self:hide(e)
			end
			continue
		end

		local ok, cf, size = pcall(char.GetBoundingBox, char)
		local minX, minY, maxX, maxY
		if ok and cf then
			minX, minY, maxX, maxY = Mathx.projectBox(cam, cf, size)
		end

		-- fuera de pantalla o detrás: se apaga, no se dibuja
		if not minX or maxX < 0 or maxY < 0 or minX > vp.X or minY > vp.Y then
			if e then
				self:hide(e)
			end
			continue
		end

		e = e or self:get(plr)
		e.visible = true
		drawn = drawn + 1

		local w, h = maxX - minX, maxY - minY
		local cx = (minX + maxX) * 0.5

		r.rect(e.box, minX, minY, w, h, boxColor, false, 1, 0, s.espBox)

		if s.espFill then
			r.rect(e.fill, minX, minY, w, h, fillColor, true, 1, 0.82, true)
		else
			r.hide(e.fill)
		end

		if s.espHealth then
			local frac = Mathx.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
			local barX, barW = minX - 7, 3
			local filled = math.max(h * frac, 1)
			r.rect(e.hpBack, barX - 1, minY - 1, barW + 2, h + 2, SHADOW, true, 1, 0.45, true)
			r.rect(e.hpFill, barX, minY + (h - filled), barW, filled,
				Mathx.lerpColor(HP_LOW, HP_HIGH, frac), true, 1, 0, true)
		else
			r.hide(e.hpBack)
			r.hide(e.hpFill)
		end

		r.text(e.label, PlayersLib.nameOf(plr), cx, minY - 19, 14, nameColor, s.espName)
		r.text(e.dist, string.format("%d studs", math.floor(dist + 0.5)), cx, maxY + 3, 13,
			DIST_COLOR, s.espDistance)

		-- tracer: rect de 1px desde el borde inferior al centro de la caja.
		-- rect rotado no existe, así que es horizontal anclado abajo
		if s.espTracer then
			local fromX = vp.X * 0.5
			r.rect(e.tracer, math.min(fromX, cx), vp.Y - 2,
				math.max(math.abs(cx - fromX), 1), 1, boxColor, true, 1, 0, true)
		else
			r.hide(e.tracer)
		end
	end

	self.anyVisible = drawn > 0
	return drawn
end

function Esp:destroy()
	if self.conn then
		pcall(function()
			self.conn:Disconnect()
		end)
		self.conn = nil
	end
	for plr in pairs(self.pool) do
		self:forget(plr)
	end
end

return Esp

end

__modules["modules/hitbox"] = function()
--[[
	Astral :: modules/hitbox

	agranda el Size de las partes del personaje en el cliente.
	las partes las posee el otro jugador: el cambio es local, así que esto
	sirve donde el hit detection corre del lado del cliente.

	el Size original se guarda la primera vez que se ve la parte y nunca se
	sobreescribe: así cambiar la escala no compone multiplicaciones.
]]

local PlayersLib = __require("shared/players")

local Hitbox = {}
Hitbox.__index = Hitbox

local BODY_PARTS = {
	"HumanoidRootPart", "Head", "Torso",
	"Left Arm", "Right Arm", "Left Leg", "Right Leg",
	"UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
}

function Hitbox.new(state, limits)
	local self = setmetatable({}, Hitbox)
	self.state = state
	self.interval = limits.interval or 0.5
	self.maxPlayers = limits.maxPlayers or 30
	self.originals = setmetatable({}, { __mode = "k" })
	self.nextPass = 0
	self.applied = {}
	return self
end

function Hitbox:restore()
	for part, size in pairs(self.originals) do
		if part.Parent then
			pcall(function()
				part.Size = size
			end)
		end
	end
	table.clear(self.originals)
	table.clear(self.applied)
	self.nextPass = 0
end

-- fuerza un pase en el siguiente frame aunque el throttle no lo deje
function Hitbox:invalidate()
	self.nextPass = 0
end

function Hitbox:parts(char, rootOnly)
	if rootOnly then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return { root }
		end
		return nil
	end

	local out = {}
	for i = 1, #BODY_PARTS do
		local part = char:FindFirstChild(BODY_PARTS[i])
		if part and part:IsA("BasePart") then
			out[#out + 1] = part
		end
	end
	if #out == 0 then
		return nil
	end
	return out
end

function Hitbox:applyTo(char, scale, rootOnly)
	local parts = self:parts(char, rootOnly)
	if not parts then
		return 0
	end

	local original = self.originals
	local touched = 0

	for i = 1, #parts do
		local part = parts[i]
		local base = original[part]
		if not base then
			base = part.Size
			original[part] = base
		end
		local target = base * scale
		if part.Size ~= target then
			pcall(function()
				part.Size = target
			end)
		end
		touched = touched + 1
	end

	return touched
end

function Hitbox:step()
	local s = self.state

	if not s.hitEnabled then
		if next(self.originals) ~= nil then
			self:restore()
		end
		return
	end

	local now = os.clock()
	if now < self.nextPass then
		return
	end
	self.nextPass = now + self.interval

	-- suelta referencias de partes de personajes que ya murieron o se
	-- respawnearon; sin esto el mapa de originals crece toda la partida
	for part in pairs(self.originals) do
		if part.Parent == nil then
			self.originals[part] = nil
		end
	end

	local scale = math.max(s.hitScale or 1, 1)
	local rootOnly = s.hitRootOnly
	local budget = self.maxPlayers
	local count = 0

	for _, plr in ipairs(PlayersLib.all()) do
		if count >= budget then
			break
		end
		if plr ~= PlayersLib.me then
			local char = plr.Character
			local hum = PlayersLib.humanoid(char)
			if char and hum and hum.Health > 0 then
				self:applyTo(char, scale, rootOnly)
				count = count + 1
			end
		end
	end
end

function Hitbox:destroy()
	self:restore()
end

return Hitbox

end

__modules["modules/aim"] = function()
--[[
	Astral :: modules/aim

	cámara solver. elige el hueso más cercano al centro de la pantalla dentro
	del FOV y gira la cámara hacia él con suavizado exponencial (independiente
	del framerate: alpha = 1 - e^(-k*dt)).

	no toca el mouse del sistema ni escribe en el motor: aplica CFrame a
	workspace.CurrentCamera, así que muere completo en unload.

	nota: los scripts de cámara por defecto de Roblox también escriben CFrame
	cada frame; por eso el giro se aplica en RenderStepped y con alpha alto
	el pulso se nota poco. es el mismo compromiso que usa cualquier solver
	de cámara externo.
]]

local PlayersLib = __require("shared/players")
local Mathx = __require("shared/mathx")

local Aim = {}
Aim.__index = Aim

local UIS = game:GetService("UserInputService")

-- px por radián en el plano de la pantalla, derivado del FOV vertical real
local function fovToPixels(degrees, verticalFov, viewportY)
	local halfTan = math.tan(math.rad(math.clamp(degrees, 0.5, 179) * 0.5))
	local camTan = math.tan(math.rad(math.clamp(verticalFov, 1, 179) * 0.5))
	return (halfTan / camTan) * (viewportY * 0.5)
end

function Aim.new(state, renderer)
	local self = setmetatable({}, Aim)
	self.state = state
	self.r = renderer
	self.circle = renderer.newCircle()
	self.held = false
	self.params = RaycastParams.new()
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.IgnoreWater = true
	self.params.RespectCanCollide = false

	self.conns = {}
	self.conns[#self.conns + 1] = UIS.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.held = true
		end
	end)
	self.conns[#self.conns + 1] = UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			self.held = false
		end
	end)

	return self
end

-- línea de visión: un raycast, ignorando al jugador local y al objetivo
function Aim:visible(camPos, pos, targetChar)
	local filter = {}
	local myChar = PlayersLib.me.Character
	if myChar then
		filter[#filter + 1] = myChar
	end
	if targetChar then
		filter[#filter + 1] = targetChar
	end
	self.params.FilterDescendantsInstances = filter

	local dir = pos - camPos
	local result = workspace:Raycast(camPos, dir, self.params)
	if not result then
		return true
	end
	return (result.Position - camPos).Magnitude >= dir.Magnitude - 0.5
end

function Aim:pick(cam, radius)
	local s = self.state
	local camPos = cam.CFrame.Position
	local vp = cam.ViewportSize
	local centerX, centerY = vp.X * 0.5, vp.Y * 0.5

	local best, bestScore, bestPos = nil, math.huge, nil

	for _, plr in ipairs(PlayersLib.all()) do
		local char = PlayersLib.target(plr, camPos, s.espTeamCheck)

		if char then
			local bone = PlayersLib.bone(char, s.aimBone)
			if bone then
				local sp = cam:WorldToViewportPoint(bone.Position)
				if sp.Z > 0 then
					local dx, dy = sp.X - centerX, sp.Y - centerY
					local d = math.sqrt(dx * dx + dy * dy)
					if d <= radius and d < bestScore then
						if not s.aimWallCheck or self:visible(camPos, bone.Position, char) then
							best, bestScore, bestPos = plr, d, bone.Position
						end
					end
				end
			end
		end
	end

	return best, bestPos
end

function Aim:step(dt)
	local s = self.state
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	local vp = cam.ViewportSize
	local radius = fovToPixels(s.aimFov, cam.FieldOfView or 70, vp.Y)

	-- círculo de FOV: existe siempre, se prende con el toggle y el módulo
	self.r.circle(self.circle, vp.X * 0.5, vp.Y * 0.5, radius,
		s.aimFovCircleColor or Color3.new(1, 1, 1), 1, false, s.aimEnabled and s.aimFovCircle)

	if not s.aimEnabled or not self.held then
		return
	end

	local _, targetPos = self:pick(cam, radius)
	if not targetPos then
		return
	end

	local camPos = cam.CFrame.Position
	local desired = CFrame.lookAt(camPos, targetPos)
	local smooth = math.max(s.aimSmooth or 0, 0)

	if smooth <= 0 then
		cam.CFrame = desired
		return
	end

	-- 20/smooth rad/s de "velocidad" de convergencia; clamp por si dt explota
	local alpha = 1 - math.exp(-(20 / smooth) * math.min(dt, 0.1))
	cam.CFrame = cam.CFrame:Lerp(desired, Mathx.clamp(alpha, 0, 1))
end

function Aim:destroy()
	for i = 1, #self.conns do
		pcall(function()
			self.conns[i]:Disconnect()
		end)
	end
	table.clear(self.conns)
	if self.circle then
		self.r.destroy(self.circle)
		self.circle = nil
	end
end

return Aim

end

__modules["modules/radar"] = function()
--[[
	Astral :: modules/radar

	mapa de posiciones en 2D, esquina superior derecha. proyecta el mundo
	sobre el plano XZ relativo a la cámara (forward/right), así el radar gira
	con la vista igual que en los shooters.

	paneles: un Square de fondo + un punto por jugador, reusados del pool.
]]

local PlayersLib = __require("shared/players")
local Mathx = __require("shared/mathx")

local Radar = {}
Radar.__index = Radar

local SIZE = 150
local MARGIN = 16
local RANGE = 250 -- studs que entran en el radio del radar
local SELF_COLOR = Color3.fromRGB(120, 255, 160)
local ENEMY_COLOR = Color3.fromRGB(255, 90, 90)
local BACK_COLOR = Color3.fromRGB(12, 12, 16)

function Radar.new(renderer, state)
	local self = setmetatable({}, Radar)
	self.r = renderer
	self.state = state
	self.pool = {}
	self.back = renderer.newRect()
	self.backline = renderer.newRect()
	self.selfDot = renderer.newRect()
	self.conn = PlayersLib.service.PlayerRemoving:Connect(function(plr)
		self:forget(plr)
	end)
	return self
end

function Radar:dot(plr)
	local d = self.pool[plr]
	if not d then
		d = self.r.newRect()
		self.pool[plr] = d
	end
	return d
end

function Radar:forget(plr)
	local d = self.pool[plr]
	if d then
		self.r.destroy(d)
		self.pool[plr] = nil
	end
end

function Radar:step(cam)
	local r = self.r
	local s = self.state

	if not s.radarEnabled then
		if self.shown then
			r.hide(self.back)
			r.hide(self.backline)
			r.hide(self.selfDot)
			for _, d in pairs(self.pool) do
				r.hide(d)
			end
			self.shown = false
		end
		return
	end

	self.shown = true

	local vp = cam.ViewportSize
	local cx = vp.X - MARGIN - SIZE * 0.5
	local cy = MARGIN + SIZE * 0.5

	r.rect(self.back, cx - SIZE * 0.5, cy - SIZE * 0.5, SIZE, SIZE, BACK_COLOR, true, 1, 0.35, true)
	r.rect(self.backline, cx - SIZE * 0.5, cy - SIZE * 0.5, SIZE, SIZE,
		Color3.fromRGB(80, 80, 100), false, 1, 0, true)
	r.rect(self.selfDot, cx - 1, cy - 1, 2, 2, SELF_COLOR, true, 1, 0, true)

	-- base del radar: la cámara mira hacia -Z en su espacio local
	local look = cam.CFrame.LookVector
	local right = cam.CFrame.RightVector
	local fwdFlat = Vector3.new(look.X, 0, look.Z)
	local rightFlat = Vector3.new(right.X, 0, right.Z)

	if fwdFlat.Magnitude < 1e-3 then
		fwdFlat = Vector3.new(0, 0, -1)
	else
		fwdFlat = fwdFlat.Unit
	end
	if rightFlat.Magnitude < 1e-3 then
		rightFlat = Vector3.new(1, 0, 0)
	else
		rightFlat = rightFlat.Unit
	end

	local camPos = cam.CFrame.Position
	local scale = (SIZE * 0.5) / RANGE
	local teamCheck = s.espTeamCheck

	for _, plr in ipairs(PlayersLib.all()) do
		local _, _, root = PlayersLib.target(plr, nil, teamCheck)
		local dot = self.pool[plr]

		if not root then
			if dot then
				r.hide(dot)
			end
			continue
		end

		local delta = root.Position - camPos
		local forward = delta.X * fwdFlat.X + delta.Z * fwdFlat.Z
		local side = delta.X * rightFlat.X + delta.Z * rightFlat.Z

		local x = Mathx.clamp(side * scale, -SIZE * 0.5 + 2, SIZE * 0.5 - 2)
		local y = Mathx.clamp(-forward * scale, -SIZE * 0.5 + 2, SIZE * 0.5 - 2)

		dot = dot or self:dot(plr)
		r.rect(dot, cx + x - 2, cy + y - 2, 4, 4, ENEMY_COLOR, true, 1, 0, true)
	end
end

function Radar:destroy()
	if self.conn then
		pcall(function()
			self.conn:Disconnect()
		end)
		self.conn = nil
	end
	pcall(function()
		self.r.destroy(self.back)
		self.r.destroy(self.backline)
		self.r.destroy(self.selfDot)
	end)
	for plr in pairs(self.pool) do
		self:forget(plr)
	end
end

return Radar

end

__modules["ui/window"] = function()
--[[
	Astral :: ui/window

	construye la ventana de Rayfield Gen 2 y deja cada control en una tabla
	plana (flags) para que el resto del script no dependa de los handles.

	el estado real vive en `state` (una tabla mutable). los callbacks
	escriben ahí y los módulos leen de ahí: el acoplamiento con Rayfield
	termina en este archivo.
]]

local Config = __require("shared/config")
local PlayersLib = __require("shared/players")

local Window = {}

local function bind(flags, state, handle, key)
	if handle == nil then
		return nil
	end
	flags[key] = handle
	local cb = handle.callback
	handle.callback = function(value, extra)
		if key == "aimBone" then
			if type(value) == "table" then
				state[key] = value[1] or "Head"
			else
				state[key] = value or "Head"
			end
		else
			state[key] = value
		end
		if cb then
			cb(value, extra)
		end
	end
	local initial = handle.value
	if initial ~= nil then
		if key == "aimBone" and type(initial) == "table" then
			state[key] = initial[1] or "Head"
		else
			state[key] = initial
		end
	end
	return handle
end

function Window.build(Rayfield, state, api)
	local window = Rayfield:CreateWindow({
		name = Config.name,
		subtitle = Config.subtitle,
		sidebarLayout = true,
		theme = Config.theme,
		configuration = {
			autoSave = true,
			autoLoad = true,
			fileName = Config.configFile,
		},
	})

	local tabs = {
		esp = window:CreateTab({ name = "ESP" }),
		hit = window:CreateTab({ name = "Hitbox" }),
		aim = window:CreateTab({ name = "Aim" }),
		misc = window:CreateTab({ name = "Misc" }),
		cfg = window:CreateTab({ name = "Config" }),
	}

	local flags = {}
	local function b(handle, key)
		return bind(flags, state, handle, key)
	end

	------------------------------------------------------------------
	local esp = tabs.esp
	esp:CreateSection({ name = "Visuals" })
	b(esp:CreateToggle({ name = "Enabled", flag = "espEnabled", value = state.espEnabled }), "espEnabled")
	b(esp:CreateToggle({ name = "Box", flag = "espBox", value = state.espBox }), "espBox")
	b(esp:CreateToggle({ name = "Fill", flag = "espFill", value = state.espFill }), "espFill")
	b(esp:CreateToggle({ name = "Health bar", flag = "espHealth", value = state.espHealth }), "espHealth")
	b(esp:CreateToggle({ name = "Name", flag = "espName", value = state.espName }), "espName")
	b(esp:CreateToggle({ name = "Distance", flag = "espDistance", value = state.espDistance }), "espDistance")
	b(esp:CreateToggle({ name = "Tracer", flag = "espTracer", value = state.espTracer }), "espTracer")
	b(esp:CreateToggle({ name = "Team check", flag = "espTeamCheck", value = state.espTeamCheck }), "espTeamCheck")

	local dRange, dInc = Config.slider("espMaxDistance")
	b(esp:CreateSlider({
		name = "Max distance",
		flag = "espMaxDistance",
		range = dRange,
		increment = dInc,
		value = state.espMaxDistance,
		suffix = " studs",
	}), "espMaxDistance")

	esp:CreateDivider()

	b(esp:CreateColorPicker({ name = "Box color", flag = "espBoxColor", color = state.espBoxColor }), "espBoxColor")
	b(esp:CreateColorPicker({ name = "Name color", flag = "espNameColor", color = state.espNameColor }), "espNameColor")
	b(esp:CreateColorPicker({ name = "Fill color", flag = "espFillColor", color = state.espFillColor }), "espFillColor")

	------------------------------------------------------------------
	local hit = tabs.hit
	hit:CreateSection({ name = "Expander" })
	b(hit:CreateToggle({ name = "Enabled", flag = "hitEnabled", value = state.hitEnabled }), "hitEnabled")
	b(hit:CreateToggle({ name = "Root part only", flag = "hitRootOnly", value = state.hitRootOnly }), "hitRootOnly")

	local hRange, hInc = Config.slider("hitScale")
	b(hit:CreateSlider({
		name = "Scale",
		flag = "hitScale",
		range = hRange,
		increment = hInc,
		value = state.hitScale,
		suffix = "x",
	}), "hitScale")

	hit:CreateText({
		name = "Scope",
		text = "El Size se cambia solo en tu cliente: las partes son del otro jugador. "
			.. "Funciona donde el hit detection corre del lado del cliente; en shooters "
			.. "validados por servidor no hace nada. Se restaura al apagar y en unload.",
	})

	------------------------------------------------------------------
	local aim = tabs.aim
	aim:CreateSection({ name = "Camera" })
	b(aim:CreateToggle({ name = "Enabled", flag = "aimEnabled", value = state.aimEnabled }), "aimEnabled")

	local fRange, fInc = Config.slider("aimFov")
	b(aim:CreateSlider({
		name = "FOV",
		flag = "aimFov",
		range = fRange,
		increment = fInc,
		value = state.aimFov,
		suffix = " deg",
	}), "aimFov")

	local sRange, sInc = Config.slider("aimSmooth")
	b(aim:CreateSlider({
		name = "Smooth",
		flag = "aimSmooth",
		range = sRange,
		increment = sInc,
		value = state.aimSmooth,
	}), "aimSmooth")

	b(aim:CreateDropdown({
		name = "Bone",
		flag = "aimBone",
		options = PlayersLib.boneNames,
		value = state.aimBone,
	}), "aimBone")

	b(aim:CreateToggle({ name = "Wall check", flag = "aimWallCheck", value = state.aimWallCheck }), "aimWallCheck")
	b(aim:CreateToggle({ name = "FOV circle", flag = "aimFovCircle", value = state.aimFovCircle }), "aimFovCircle")

	local cRange, cInc = Config.slider("aimFovCircleRadius")
	b(aim:CreateSlider({
		name = "Circle radius",
		flag = "aimFovCircleRadius",
		range = cRange,
		increment = cInc,
		value = state.aimFovCircleRadius,
		suffix = " px",
	}), "aimFovCircleRadius")

	b(aim:CreateColorPicker({
		name = "Circle color",
		flag = "aimFovCircleColor",
		color = state.aimFovCircleColor,
	}), "aimFovCircleColor")

	aim:CreateText({
		name = "Bind",
		text = "Mantén click derecho para apuntar. El giro se aplica a la camara, "
			.. "no al mouse del sistema.",
	})

	------------------------------------------------------------------
	local misc = tabs.misc
	misc:CreateSection({ name = "Radar" })
	b(misc:CreateToggle({ name = "Enabled", flag = "radarEnabled", value = state.radarEnabled }), "radarEnabled")
	misc:CreateText({
		name = "Radar",
		text = "Esquina superior derecha, 250 studs de radio, gira con la vista.",
	})

	------------------------------------------------------------------
	local cfg = tabs.cfg
	cfg:CreateSection({ name = "Configuration" })
	cfg:CreateButton({
		name = "Save",
		callback = function()
			if window:Save() then
				window:Notify({ title = Config.name, content = "config guardada", duration = 3 })
			end
		end,
	})
	cfg:CreateButton({
		name = "Load",
		callback = function()
			if window:Load() then
				Window.sync(flags, state)
				api.onConfigLoaded()
				window:Notify({ title = Config.name, content = "config cargada", duration = 3 })
			end
		end,
	})
	cfg:CreateButton({
		name = "Restore hitboxes",
		callback = function()
			api.onRestoreHitboxes()
			window:Notify({ title = Config.name, content = "hitboxes restauradas", duration = 3 })
		end,
	})
	cfg:CreateButton({
		name = "Unload",
		callback = function()
			api.onUnload()
		end,
	})

	cfg:CreateText({ name = "Info", text = api.infoText or "" })

	return { window = window, flags = flags, tabs = tabs }
end

-- Rayfield puede aplicar el archivo guardado después de crear los elementos
-- sin disparar callbacks: se leen los handles y se escribe el estado.
function Window.sync(flags, state)
	for key, handle in pairs(flags) do
		local v = handle.value
		if v ~= nil then
			if key == "aimBone" then
				state[key] = type(v) == "table" and (v[1] or "Head") or v
			else
				state[key] = v
			end
		end
	end
end

return Window

end

__modules["init"] = function()
--[[
	Astral :: init

	entry point. arma el estado, los módulos y el loop; nada más.
	cada módulo es un objeto con :step() y :destroy(), así el unload es
	recorrer una lista — no hay conexiones sueltas ni estado global.
]]

local Config = __require("shared/config")
local PlayersLib = __require("shared/players")
local Renderer = __require("shared/renderer")

local Esp = __require("modules/esp")
local Hitbox = __require("modules/hitbox")
local Aim = __require("modules/aim")
local Radar = __require("modules/radar")
local Window = __require("ui/window")

local RunService = game:GetService("RunService")

-- una instancia anterior no puede seguir viva: dos loops y dos ventanas
if getgenv then
	local prev = getgenv().Astral
	if type(prev) == "table" and type(prev.unload) == "function" then
		pcall(prev.unload)
	end
end

----------------------------------------------------------------------
-- estado
----------------------------------------------------------------------
local state = {}
for k, v in pairs(Config.defaults) do
	state[k] = v
end

----------------------------------------------------------------------
-- renderer
----------------------------------------------------------------------
local renderer = Renderer.pick()
if not renderer then
	return warn("[Astral] sin renderer: no hay Drawing y no se pudo abrir un ScreenGui")
end

----------------------------------------------------------------------
-- módulos
----------------------------------------------------------------------
local esp = Esp.new(renderer, state)
local hitbox = Hitbox.new(state, {
	interval = Config.hitboxInterval,
	maxPlayers = Config.hitboxMaxPlayers,
})
local radar = Radar.new(renderer, state)
local aim = Aim.new(state, renderer)

local modules = { esp = esp, hitbox = hitbox, radar = radar, aim = aim }
local conns = {}
local unloaded = false

-- declarados antes de unload: si no, unload captura globales nil y el
-- pcall los traga en silencio (nunca cierra la ventana de Rayfield)
local ui, api

----------------------------------------------------------------------
-- ui
----------------------------------------------------------------------
-- si Rayfield falla (sin loadstring, sin red, CDN caído) hay que deshacer lo
-- que ya se creó: los módulos tienen conexiones vivas desde el constructor
local function teardownEarly()
	for _, mod in pairs(modules) do
		pcall(function()
			mod:destroy()
		end)
	end
	if renderer.gui then
		pcall(function()
			renderer.gui:Destroy()
		end)
	end
end

local okLib, Rayfield = pcall(function()
	return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
end)

if not okLib or type(Rayfield) ~= "table" then
	teardownEarly()
	return warn("[Astral] Rayfield Gen 2 no cargó: " .. tostring(Rayfield))
end

local function unload()
	if unloaded then
		return
	end
	unloaded = true

	for i = 1, #conns do
		pcall(function()
			conns[i]:Disconnect()
		end)
	end
	table.clear(conns)

	for _, mod in pairs(modules) do
		pcall(function()
			mod:destroy()
		end)
	end

	if renderer.gui then
		pcall(function()
			renderer.gui:Destroy()
		end)
	end

	pcall(function()
		ui.window:Unload()
	end)

	if getgenv and getgenv().Astral == api then
		getgenv().Astral = nil
	end
end

local function onHitboxChange()
	-- los cambios de escala/alcance se ven en el siguiente pase, no en 0.5s
	hitbox:invalidate()
end

local function onConfigLoaded()
	Window.sync(ui.flags, state)
	hitbox:invalidate()
end

local okUI, built = pcall(Window.build, Rayfield, state, {
	onHitboxChange = onHitboxChange,
	onConfigLoaded = onConfigLoaded,
	onRestoreHitboxes = function()
		hitbox:restore()
	end,
	onUnload = function()
		unload()
	end,
	infoText = string.format("v%s  ·  renderer: %s  ·  %s", Config.version, renderer.name, PlayersLib.me.Name),
})

if not okUI or type(built) ~= "table" then
	-- la ventana a medias no se puede cerrar sin handle: se tira el objeto
	pcall(function()
		if type(Rayfield.Unload) == "function" then
			Rayfield:Unload()
		end
	end)
	teardownEarly()
	return warn("[Astral] la UI falló al construirse: " .. tostring(built))
end

ui = built

api = {
	state = state,
	modules = modules,
	renderer = renderer,
	unload = unload,
}

if getgenv then
	getgenv().Astral = api
end

----------------------------------------------------------------------
-- loop
----------------------------------------------------------------------
local function frame(dt)
	if unloaded then
		return
	end

	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	esp:step(cam)
	hitbox:step()
	radar:step(cam)
	aim:step(dt)
end

conns[#conns + 1] = RunService.RenderStepped:Connect(frame)

-- el autoLoad de Rayfield puede aplicar el archivo un instante después de
-- crear los elementos, sin callbacks: dos lecturas cubren ese hueco
task.defer(function()
	if unloaded then
		return
	end
	Window.sync(ui.flags, state)
	hitbox:invalidate()
end)

task.delay(1, function()
	if unloaded then
		return
	end
	Window.sync(ui.flags, state)
	hitbox:invalidate()
end)

return api

end


-- arranque
return __require("init")
