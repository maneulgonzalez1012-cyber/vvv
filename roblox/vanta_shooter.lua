--[[
	vvv · shooter suite
	ESP (ScreenGui puro) + Hitbox Expander · UI en Rayfield Gen2

	Render: caja, nombre, distancia y barra de vida son Frames/TextLabels
	dentro de un ScreenGui. Cero Drawing API en este archivo.

	Hitbox: agranda parts de otros jugadores del lado del cliente, por frame,
	re-aplicando cuando el servidor revierte la escritura. Modos: Auto, Head,
	HumanoidRootPart, Torso, Limbs, Todo. El botón de diagnóstico dice si el
	juego revierte el Size o si el hitreg corre en el servidor.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local LP = Players.LocalPlayer
if not LP then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LP = Players.LocalPlayer
end
assert(LP, "vanta: sin LocalPlayer")

-- re-ejecución: mata la instancia anterior
local genv = (getgenv and getgenv()) or _G
if genv.VANTA then
	pcall(function() genv.VANTA.destroy() end)
end

-- =====================================================================
-- Config · valores vivos, la UI los escribe por callback
-- =====================================================================

local cfg = {
	esp = {
		enabled     = false,
		box         = true,
		health      = true,
		name        = true,
		distance    = true,
		teamCheck   = true,
		maxDistance = 0,                      -- 0 = sin límite
		thickness   = 1.5,
		color       = Color3.fromRGB(96, 205, 255),
	},
	hitbox = {
		enabled    = false,
		mode       = "Auto",
		noCollide  = true,
		multiplier = 1.6,
		teammates  = false,
	},
}

-- =====================================================================
-- ESP · Instances, sin Drawing
-- =====================================================================

local ESP = {
	gui     = nil,
	root    = nil,
	objects = {},   -- [Player] = { box, stroke, hpBg, hpFill, label }
	cache   = {},   -- [Player] = { char, hum, root, corners, cornersAt }
	running = false,
}

function ESP:mount()
	if self.gui then return end

	local parent
	if type(gethui) == "function" then
		local ok, res = pcall(gethui)
		if ok and res then parent = res end
	end
	parent = parent or LP:FindFirstChild("PlayerGui") or game:GetService("CoreGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "vanta_esp"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true       -- WorldToViewportPoint = viewport; sin inset, gui == viewport
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = gui

	self.gui = gui
	self.root = root
end

function ESP:create(plr)
	local box = Instance.new("Frame")
	box.BorderSizePixel = 0
	box.BackgroundTransparency = 1
	box.Active = false
	box.ZIndex = 3

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Miter
	stroke.Color = cfg.esp.color
	stroke.Thickness = cfg.esp.thickness
	stroke.Parent = box

	local hpBg = Instance.new("Frame")
	hpBg.BorderSizePixel = 0
	hpBg.BackgroundColor3 = Color3.fromRGB(12, 12, 15)
	hpBg.BackgroundTransparency = 0.25
	hpBg.ZIndex = 4

	local hpFill = Instance.new("Frame")
	hpFill.BorderSizePixel = 0
	hpFill.AnchorPoint = Vector2.new(0, 1)
	hpFill.Position = UDim2.fromScale(0, 1)
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.ZIndex = 5
	hpFill.Parent = hpBg

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = cfg.esp.color
	label.TextStrokeTransparency = 0.75
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Size = UDim2.fromOffset(280, 15)
	label.ZIndex = 4
	label.Text = ""

	box.Parent = self.root
	hpBg.Parent = self.root
	label.Parent = self.root

	local o = { box = box, stroke = stroke, hpBg = hpBg, hpFill = hpFill, label = label }
	self.objects[plr] = o
	return o
end

function ESP:object(plr)
	return self.objects[plr] or (self.root and self:create(plr))
end

function ESP:hide(o)
	o.box.Visible = false
	o.hpBg.Visible = false
	o.label.Visible = false
end

function ESP:hideAll()
	for _, o in pairs(self.objects) do
		self:hide(o)
	end
end

-- AABB del personaje -> 8 esquinas en el espacio local del HRP.
-- Se recalcula cada 0.35s; el frame sólo transforma 8 puntos.
local function computeCorners(char, root)
	local ok, cf, size = pcall(function()
		local c, s = char:GetBoundingBox()
		return c, s
	end)
	if not ok or not cf then return nil end

	local hs = size * 0.5
	if hs.X <= 0 or hs.Y <= 0 or hs.Z <= 0 then return nil end

	local corners = table.create(8)
	for ix = -1, 1, 2 do
		for iy = -1, 1, 2 do
			for iz = -1, 1, 2 do
				corners[#corners + 1] = root.CFrame:PointToObjectSpace(
					cf * Vector3.new(hs.X * ix, hs.Y * iy, hs.Z * iz)
				)
			end
		end
	end
	return corners
end

function ESP:refresh(plr)
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and (char.PrimaryPart or char:FindFirstChild("HumanoidRootPart"))

	local e = self.cache[plr]
	if not e then
		e = {}
		self.cache[plr] = e
	end

	if not (char and hum and root and char.Parent and hum.Parent and hum.Health > 0) then
		e.char, e.hum, e.root, e.corners = nil, nil, nil, nil
		return
	end

	e.char, e.hum, e.root = char, hum, root

	local now = os.clock()
	if e.cornersChar ~= char or (e.cornersAt or 0) + 0.35 < now then
		local corners = computeCorners(char, root)
		if corners then
			e.corners = corners
			e.cornersChar = char
			e.cornersAt = now
		end
	end
end

function ESP:draw(plr, e, minX, minY, maxX, maxY, dist)
	local o = self:object(plr)
	if not o then return end

	local w = math.max(maxX - minX, 1)
	local h = math.max(maxY - minY, 1)

	o.box.Visible = cfg.esp.box
	o.box.Position = UDim2.fromOffset(minX, minY)
	o.box.Size = UDim2.fromOffset(w, h)
	o.stroke.Color = cfg.esp.color
	o.stroke.Thickness = cfg.esp.thickness

	o.hpBg.Visible = cfg.esp.health
	o.hpBg.Position = UDim2.fromOffset(minX - 6, minY)
	o.hpBg.Size = UDim2.fromOffset(3, h)

	local hum = e.hum
	local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
	o.hpFill.Size = UDim2.fromScale(1, frac)
	o.hpFill.BackgroundColor3 = Color3.fromHSV(0.33 * frac, 1, 0.95)

	local text = ""
	if cfg.esp.name then
		text = (plr.DisplayName ~= "" and plr.DisplayName) or plr.Name
	end
	if cfg.esp.distance then
		text ..= string.format(" [%d]", math.floor(dist))
	end

	o.label.Visible = text ~= ""
	o.label.Text = text
	o.label.TextColor3 = cfg.esp.color
	o.label.Position = UDim2.fromOffset((minX + maxX) * 0.5, minY - 16)
end

function ESP:render()
	if not cfg.esp.enabled or not self.root then return end

	local cam = Workspace.CurrentCamera
	if not cam then return end

	local camPos = cam.CFrame.Position
	local seen = {}

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local e = self.cache[plr]
			local skip = cfg.esp.teamCheck and LP.Team ~= nil and plr.Team == LP.Team

			if not skip and e and e.char and e.hum and e.root and e.corners then
				local dist = (e.root.Position - camPos).Magnitude

				if cfg.esp.maxDistance <= 0 or dist <= cfg.esp.maxDistance then
					local minX, minY = math.huge, math.huge
					local maxX, maxY = -math.huge, -math.huge
					local visible = false
					local rootCF = e.root.CFrame

					for _, localPt in ipairs(e.corners) do
						local sp = cam:WorldToViewportPoint(rootCF * localPt)
						if sp.Z > 0 then
							visible = true
							if sp.X < minX then minX = sp.X end
							if sp.Y < minY then minY = sp.Y end
							if sp.X > maxX then maxX = sp.X end
							if sp.Y > maxY then maxY = sp.Y end
						end
					end

					if visible then
						self:draw(plr, e, minX, minY, maxX, maxY, dist)
						seen[plr] = true
					end
				end
			end
		end
	end

	for plr, o in pairs(self.objects) do
		if not seen[plr] then
			self:hide(o)
		end
	end
end

function ESP:destroy()
	for plr in pairs(self.objects) do
		self.objects[plr] = nil
	end
	self.cache = {}
	if self.gui then
		pcall(function() self.gui:Destroy() end)
	end
	self.gui = nil
	self.root = nil
end

-- =====================================================================
-- Hitbox expander
-- =====================================================================

local Hitbox = {
	state   = {},    -- [Model] = { mult, mode, builtAt, n, entries = { {p, base, want, cc} } }
	-- tamaño/collision originales por part, sobreviven a rebuilds: si no,
	-- cambiar el multiplicador tomaría el tamaño ya agrandado como base
	originals = {},  -- [BasePart] = Vector3
	origCc    = {},  -- [BasePart] = boolean
	running   = false,
}

-- nombres estándar R6/R15 + variantes sin espacio que usan algunos rigs
local LIMB_NAMES = {
	Head = true,
	Torso = true, UpperTorso = true, LowerTorso = true,
	HumanoidRootPart = true,
	["Left Arm"] = true, ["Right Arm"] = true,
	["Left Leg"] = true, ["Right Leg"] = true,
	LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

local MODES = { "Auto", "Head", "HumanoidRootPart", "Torso", "Limbs", "Todo" }

local function isGear(part)
	return part:FindFirstAncestorOfClass("Accessory") ~= nil
		or part:FindFirstAncestorWhichIsA("Tool") ~= nil
end

local function collect(char, mode)
	local out, seen = {}, {}

	local function add(p)
		if p and p:IsA("BasePart") and not seen[p] and not isGear(p) then
			seen[p] = true
			out[#out + 1] = p
		end
	end

	if mode == "Head" then
		add(char:FindFirstChild("Head"))
	elseif mode == "HumanoidRootPart" then
		add(char:FindFirstChild("HumanoidRootPart"))
	elseif mode == "Torso" then
		add(char:FindFirstChild("UpperTorso"))
		add(char:FindFirstChild("Torso"))
		add(char:FindFirstChild("LowerTorso"))
	elseif mode == "Limbs" then
		for _, d in ipairs(char:GetDescendants()) do
			if LIMB_NAMES[d.Name] then add(d) end
		end
	elseif mode == "Todo" then
		for _, d in ipairs(char:GetDescendants()) do add(d) end
	else
		-- Auto: limbs + HRP. Si el rig no usa nombres estándar, cualquier
		-- BasePart directa del modelo (rigs custom, skinned).
		for _, d in ipairs(char:GetDescendants()) do
			if LIMB_NAMES[d.Name] then add(d) end
		end
		if #out == 0 then
			for _, d in ipairs(char:GetChildren()) do add(d) end
		end
	end

	return out
end

function Hitbox:isEnemy(plr)
	if cfg.hitbox.teammates then return true end
	return not (LP.Team ~= nil and plr.Team == LP.Team)
end

function Hitbox:build(char, mult)
	local parts = collect(char, cfg.hitbox.mode)
	local entries = table.create(#parts)

	for i = 1, #parts do
		local p = parts[i]
		local base = self.originals[p]
		if not base then
			base = p.Size
			self.originals[p] = base
		end
		local cc = self.origCc[p]
		if cc == nil then
			cc = p.CanCollide
			self.origCc[p] = cc
		end
		entries[i] = {
			p = p,
			base = base,
			want = base * mult,
			cc = cc,
		}
	end

	local st = {
		mult = mult,
		mode = cfg.hitbox.mode,
		builtAt = os.clock(),
		n = #entries,
		entries = entries,
	}
	self.state[char] = st
	return st
end

-- hot path: sólo escribe cuando difiere. Comparar tres floats es el costo.
local function applyState(st, noCollide)
	local entries, n = st.entries, st.n
	for i = 1, n do
		local e = entries[i]
		local p = e.p
		if p.Parent then
			if p.Size ~= e.want then
				p.Size = e.want
			end
			if noCollide and p.CanCollide then
				p.CanCollide = false
			end
		end
	end
end

function Hitbox:restore(char)
	local st = self.state[char]
	if not st then return end

	for i = 1, st.n do
		local e = st.entries[i]
		local p = e.p
		if p.Parent then
			pcall(function()
				p.Size = e.base
				p.CanCollide = e.cc
			end)
		end
		self.originals[p] = nil
		self.origCc[p] = nil
	end

	self.state[char] = nil
end

function Hitbox:reset()
	local chars = {}
	for char in pairs(self.state) do
		chars[#chars + 1] = char
	end
	for i = 1, #chars do
		local char = chars[i]
		if char.Parent then
			pcall(self.restore, self, char)
		else
			self.state[char] = nil
		end
	end
end

function Hitbox:prune()
	for char in pairs(self.state) do
		if not char.Parent then
			self.state[char] = nil
		end
	end
	-- parts de personajes que ya no existen: fuera del mapa original
	for part in pairs(self.originals) do
		if not part.Parent then
			self.originals[part] = nil
			self.origCc[part] = nil
		end
	end
end

-- Se llama cada frame: el servidor reescribe Size del personaje de otro
-- jugador cuando su dueño replica, así que una pasada cada 0.25s no alcanza.
function Hitbox:tick()
	if not cfg.hitbox.enabled then return end

	local mult = cfg.hitbox.multiplier
	local mode = cfg.hitbox.mode
	local noCollide = cfg.hitbox.noCollide
	local now = os.clock()

	if now - (self.prunedAt or 0) > 2 then
		self.prunedAt = now
		self:prune()
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local char = plr.Character
			if char and char.Parent and self:isEnemy(plr) then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local st = self.state[char]
					if not st or st.mult ~= mult or st.mode ~= mode or st.builtAt + 2 < now then
						st = self:build(char, mult)
						if st.n > 0 then
							pcall(applyState, st, noCollide)
						end
					elseif st.n > 0 then
						-- un pcall por personaje, no por part
						if not pcall(applyState, st, noCollide) then
							self.state[char] = nil
						end
					end
				end
			elseif self.state[char] then
				pcall(self.restore, self, char)
			end
		end
	end
end

-- Escribe, espera y lee de vuelta: dice si el juego revierte las escrituras
-- o si aguantan. Sin esto se adivina.
function Hitbox:diagnose()
	local target, char
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and self:isEnemy(plr) then
			local c = plr.Character
			if c and c.Parent and c:FindFirstChildOfClass("Humanoid") then
				target, char = plr, c
				break
			end
		end
	end
	if not char then
		return false, "no hay otro jugador con personaje"
	end

	local parts = collect(char, cfg.hitbox.mode)
	if #parts == 0 then
		return false, string.format("0 parts en modo '%s' para %s", cfg.hitbox.mode, target.Name)
	end

	local probe = table.create(#parts)
	for i = 1, #parts do
		probe[i] = { p = parts[i], size = parts[i].Size }
	end

	local blocked = 0
	for i = 1, #probe do
		local s = probe[i]
		local ok = pcall(function()
			s.p.Size = s.size * 1.5
		end)
		if not ok then
			blocked = blocked + 1
		end
	end

	task.wait(0.15)

	local stuck, reverted, gone = 0, 0, 0
	for i = 1, #probe do
		local s = probe[i]
		if not s.p.Parent then
			gone = gone + 1
		else
			local want = s.size * 1.5
			if (s.p.Size - want).Magnitude < 0.05 then
				stuck = stuck + 1
			else
				reverted = reverted + 1
			end
			pcall(function() s.p.Size = s.size end)
		end
	end

	local verdict
	if stuck == 0 then
		verdict = "el cliente escribe Size y el juego lo revierte al frame siguiente"
	elseif reverted > 0 then
		verdict = "parte se queda, parte se revierte: el juego reescribe esos parts"
	else
		verdict = "Size se queda. Si igual no pega, el hitreg del juego corre en el servidor"
	end

	return true, string.format(
		"%s · %d parts · %d quedan · %d revertidas · %d bloqueadas · %d desaparecidas. %s",
		target.Name, #probe, stuck, reverted, blocked, gone, verdict
	)
end

-- =====================================================================
-- UI · Rayfield Gen2
-- =====================================================================

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

local window = Rayfield:CreateWindow({
	name = "vanta",
	subtitle = "shooter suite · gen2",
	sidebarLayout = true,
	theme = "cobalt",
	configuration = {
		autoSave = true,
		autoLoad = true,
		fileName = "vanta_shooter",
	},
})

-- ---------------------------- ESP ----------------------------

local espTab = window:CreateTab({ name = "ESP" })
espTab:CreateSection({ name = "Render" })

local espToggle = espTab:CreateToggle({
	name = "ESP activo",
	flag = "esp_enabled",
	value = false,
	callback = function(v)
		cfg.esp.enabled = v
		if not v then ESP:hideAll() end
	end,
})

local grid = espTab:CreateGroup()
local colA = grid:CreateGroup({ direction = "column" })
colA:CreateToggle({
	name = "Caja", flag = "esp_box", value = true,
	callback = function(v) cfg.esp.box = v end,
})
colA:CreateToggle({
	name = "Nombre", flag = "esp_name", value = true,
	callback = function(v) cfg.esp.name = v end,
})
local colB = grid:CreateGroup({ direction = "column" })
colB:CreateToggle({
	name = "Vida", flag = "esp_health", value = true,
	callback = function(v) cfg.esp.health = v end,
})
colB:CreateToggle({
	name = "Distancia", flag = "esp_dist", value = true,
	callback = function(v) cfg.esp.distance = v end,
})

espTab:CreateToggle({
	name = "Ignorar compañeros",
	flag = "esp_team",
	value = true,
	callback = function(v) cfg.esp.teamCheck = v end,
})

espTab:CreateSlider({
	name = "Distancia máxima",
	description = "0 = sin límite",
	flag = "esp_maxdist",
	range = { 0, 2000 },
	increment = 50,
	value = 0,
	suffix = " st",
	callback = function(v) cfg.esp.maxDistance = v end,
})

espTab:CreateSlider({
	name = "Grosor de caja",
	flag = "esp_thickness",
	range = { 1, 4 },
	increment = 0.5,
	value = 1.5,
	callback = function(v) cfg.esp.thickness = v end,
})

espTab:CreateColorPicker({
	name = "Color",
	flag = "esp_color",
	color = cfg.esp.color,
	callback = function(c) cfg.esp.color = c end,
})

-- ---------------------------- Hitbox ----------------------------

local hbTab = window:CreateTab({ name = "Hitbox" })
hbTab:CreateSection({ name = "Expander" })

local function restartHitbox()
	Hitbox:reset()
	if cfg.hitbox.enabled then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP and Hitbox:isEnemy(plr) then
				local c = plr.Character
				if c and c.Parent and c:FindFirstChildOfClass("Humanoid") then
					Hitbox:build(c, cfg.hitbox.multiplier)
				end
			end
		end
	end
end

local hbToggle = hbTab:CreateToggle({
	name = "Hitbox expander",
	flag = "hb_enabled",
	value = false,
	callback = function(v)
		cfg.hitbox.enabled = v
		if v then
			restartHitbox()
		else
			Hitbox:reset()
		end
	end,
})

hbTab:CreateDropdown({
	name = "Qué agrandar",
	flag = "hb_mode",
	options = MODES,
	value = "Auto",
	callback = function(choice)
		cfg.hitbox.mode = choice
		restartHitbox()
	end,
})

hbTab:CreateSlider({
	name = "Multiplicador",
	flag = "hb_mult",
	range = { 1, 8 },
	increment = 0.1,
	value = 1.6,
	suffix = "x",
	callback = function(v)
		cfg.hitbox.multiplier = v
		if cfg.hitbox.enabled then restartHitbox() end
	end,
})

hbTab:CreateToggle({
	name = "Quitar colisión al hitbox",
	description = "Evita que el cuerpo agrandado empuje o trabe",
	flag = "hb_nocc",
	value = true,
	callback = function(v) cfg.hitbox.noCollide = v end,
})

hbTab:CreateToggle({
	name = "Incluir compañeros",
	flag = "hb_team",
	value = false,
	callback = function(v) cfg.hitbox.teammates = v end,
})

hbTab:CreateButton({
	name = "Restaurar hitboxes ahora",
	callback = function()
		Hitbox:reset()
		if cfg.hitbox.enabled then restartHitbox() end
	end,
})

hbTab:CreateButton({
	name = "Probar si el juego revierte el Size",
	callback = function()
		local ok, msg = Hitbox:diagnose()
		window:Notify({
			title = ok and "Diagnóstico de hitbox" or "Diagnóstico falló",
			content = msg,
			duration = 10,
		})
	end,
})

hbTab:CreateText({
	name = "Si el Size se queda pero no pega",
	text = "El hitreg corre en el servidor y valida contra sus propias hitboxes: no hay nada que el cliente pueda agrandar. Prueba 'Todo' o 'HumanoidRootPart' antes de descartarlo. El diagnóstico dice si las escrituras aguantan.",
})

-- ---------------------------- Config ----------------------------

local cfgTab = window:CreateTab({ name = "Config" })
cfgTab:CreateSection({ name = "Binds" })

cfgTab:CreateKeybind({
	name = "ESP on/off",
	value = Enum.KeyCode.RightShift,
	callback = function()
		espToggle:Set(not espToggle.value)
	end,
})

cfgTab:CreateKeybind({
	name = "Hitbox on/off",
	value = Enum.KeyCode.RightControl,
	callback = function()
		hbToggle:Set(not hbToggle.value)
	end,
})

cfgTab:CreateSection({ name = "Apariencia" })

cfgTab:CreateDropdown({
	name = "Tema",
	options = { "cobalt", "default", "ember", "amethyst", "frost", "rose" },
	value = "cobalt",
	callback = function(choice)
		window:ChangeTheme(choice)
	end,
})

cfgTab:CreateSection({ name = "Sesión" })

cfgTab:CreateButton({
	name = "Desactivar y cerrar",
	callback = function()
		if genv.VANTA then genv.VANTA.destroy() end
	end,
})

-- =====================================================================
-- Runtime
-- =====================================================================

ESP:mount()

ESP.running = true
local renderConn
do
	local ok = pcall(function()
		renderConn = RunService.RenderStepped:Connect(function()
			ESP:render()
		end)
	end)
	if not ok then
		renderConn = RunService.Heartbeat:Connect(function()
			ESP:render()
		end)
	end
end

task.spawn(function()
	while ESP.running do
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP then
				local ok, err = pcall(function() ESP:refresh(plr) end)
				if not ok then warn("vanta esp refresh: " .. tostring(err)) end
			end
		end
		task.wait(0.3)
	end
end)

local removingConn = Players.PlayerRemoving:Connect(function(plr)
	local o = ESP.objects[plr]
	if o then
		o.box:Destroy()
		o.hpBg:Destroy()
		o.label:Destroy()
		ESP.objects[plr] = nil
	end
	ESP.cache[plr] = nil
	if plr.Character then Hitbox:restore(plr.Character) end
end)

-- el servidor reescribe Size cuando el dueño replica: corre por frame.
-- build sólo cuando cambia el multiplicador/modo; escribir, sólo si difiere.
Hitbox.running = true
local hbConn
do
	local ok = pcall(function()
		hbConn = RunService.RenderStepped:Connect(function()
			if Hitbox.running then
				Hitbox:tick()
			end
		end)
	end)
	if not ok then
		hbConn = RunService.Heartbeat:Connect(function()
			if Hitbox.running then
				Hitbox:tick()
			end
		end)
	end
end

genv.VANTA = {
	destroy = function()
		ESP.running = false
		Hitbox.running = false
		if renderConn then pcall(function() renderConn:Disconnect() end) end
		if hbConn then pcall(function() hbConn:Disconnect() end) end
		if removingConn then pcall(function() removingConn:Disconnect() end) end
		Hitbox:reset()
		ESP:destroy()
		if window and not window.unloaded then
			pcall(function() window:Unload() end)
		end
		genv.VANTA = nil
	end,
}

window:Notify({
	title = "vanta",
	content = "ESP + hitbox listos. RightShift / RightControl.",
	duration = 6,
})
