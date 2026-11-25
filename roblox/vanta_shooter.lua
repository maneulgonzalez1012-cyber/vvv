--[[
	vvv · shooter suite
	ESP (ScreenGui puro) + Hitbox Expander · UI en Rayfield Gen2

	Render: caja, nombre, distancia y barra de vida son Frames/TextLabels
	dentro de un ScreenGui. Cero Drawing API en este archivo.

	Hitbox: agranda los limb parts de otros jugadores del lado del cliente.
	Rinde donde el hitreg pasa por el cliente (raycast local + RemoteEvent).
	Si el juego valida el daño en el servidor contra sus hitboxes, no hace nada.
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
	originals = {},   -- [BasePart] = Vector3 original
	applied   = {},   -- [Model] = multiplicador aplicado
	walkedAt  = {},   -- [Model] = os.clock del último pase
	running   = false,
}

local LIMBS = {
	-- HRP fuera: casi ningún juego lo usa como hitbox y agrandarlo ensucia el ESP
	Head = true, Torso = true, UpperTorso = true, LowerTorso = true,
	["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
	RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
	RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
}

function Hitbox:isEnemy(plr)
	if cfg.hitbox.teammates then return true end
	return not (LP.Team ~= nil and plr.Team == LP.Team)
end

function Hitbox:expand(char, mult)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local targets = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and LIMBS[d.Name] then
			targets[#targets + 1] = d
		end
	end
	if #targets == 0 then
		-- rig custom sin nombres estándar
		for _, d in ipairs(char:GetChildren()) do
			if d:IsA("BasePart") then
				targets[#targets + 1] = d
			end
		end
	end

	for _, part in ipairs(targets) do
		local original = self.originals[part]
		if not original then
			original = part.Size
			self.originals[part] = original
		end
		local want = original * mult
		if (part.Size - want).Magnitude > 0.01 then
			pcall(function() part.Size = want end)
		end
	end

	self.applied[char] = mult
	self.walkedAt[char] = os.clock()
end

function Hitbox:restore(char)
	for _, d in ipairs(char:GetDescendants()) do
		local original = self.originals[d]
		if original then
			pcall(function() d.Size = original end)
			self.originals[d] = nil
		end
	end
	self.applied[char] = nil
	self.walkedAt[char] = nil
end

function Hitbox:prune()
	for part in pairs(self.originals) do
		if not part.Parent then
			self.originals[part] = nil
		end
	end
	for char in pairs(self.applied) do
		if not char.Parent then
			self.applied[char] = nil
			self.walkedAt[char] = nil
		end
	end
end

function Hitbox:reset()
	for char in pairs(self.applied) do
		if char.Parent then
			self:restore(char)
		end
	end
	self.applied = {}
	self.walkedAt = {}
	self:prune()
end

function Hitbox:step()
	if not cfg.hitbox.enabled then return end
	local mult = cfg.hitbox.multiplier

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local char = plr.Character
			if char and char.Parent then
				if self:isEnemy(plr) then
					local applied = self.applied[char]
					local stale = applied == nil
						or math.abs(applied - mult) > 0.001
						or (self.walkedAt[char] or 0) + 2 < os.clock()
					if stale then
						self:expand(char, mult)
					end
				elseif self.applied[char] then
					self:restore(char)
				end
			end
		end
	end

	self:prune()
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

local hbToggle = hbTab:CreateToggle({
	name = "Hitbox expander",
	flag = "hb_enabled",
	value = false,
	callback = function(v)
		cfg.hitbox.enabled = v
		if not v then Hitbox:reset() end
	end,
})

hbTab:CreateSlider({
	name = "Multiplicador",
	flag = "hb_mult",
	range = { 1, 3 },
	increment = 0.05,
	value = 1.6,
	suffix = "x",
	callback = function(v) cfg.hitbox.multiplier = v end,
})

hbTab:CreateToggle({
	name = "Incluir compañeros",
	flag = "hb_team",
	value = false,
	callback = function(v) cfg.hitbox.teammates = v end,
})

hbTab:CreateButton({
	name = "Restaurar hitboxes ahora",
	callback = function() Hitbox:reset() end,
})

hbTab:CreateText({
	name = "Alcance",
	text = "Head, torso, brazos y piernas, del lado del cliente. Funciona con hitreg local; si el servidor valida contra sus propias hitboxes, no cambia nada. Al apagar restaura el tamaño original.",
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

Hitbox.running = true
task.spawn(function()
	while Hitbox.running do
		local ok, err = pcall(function() Hitbox:step() end)
		if not ok then warn("vanta hitbox: " .. tostring(err)) end
		task.wait(0.25)
	end
end)

genv.VANTA = {
	destroy = function()
		ESP.running = false
		Hitbox.running = false
		if renderConn then pcall(function() renderConn:Disconnect() end) end
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
