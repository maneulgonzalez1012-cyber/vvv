--[[
	Astral :: Roblox ESP + Hitbox Expander
	open source, sin ofuscación, sin key system
	UI: Rayfield Gen 2

	run:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/loader.lua"))()

	el menú lo maneja Rayfield (pill colapsado arriba a la izquierda,
	la tecla se cambia en su pestaña de Settings). todo arranca apagado.
]]

----------------------------------------------------------------------
-- services
----------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local LP = Players.LocalPlayer

----------------------------------------------------------------------
-- defaults
-- Rayfield guarda y restaura estos valores desde el archivo de config;
-- esta tabla es solo el punto de partida del primer arranque
----------------------------------------------------------------------
local S = {
	espEnabled = false,
	espBox = true,
	espHealth = true,
	espName = true,
	espDistance = true,
	espTeamCheck = true,
	espMaxDistance = 750,
	espBoxColor = Color3.fromRGB(255, 255, 255),

	hitEnabled = false,
	hitRootOnly = false,
	hitScale = 2.0,
}

----------------------------------------------------------------------
-- renderer facade
-- Drawing cuando el executor lo tiene, ScreenGui cuando no. Mismo
-- contrato en los dos casos: rect(...) y label(...).
-- coordenadas: píxeles desde la esquina superior izquierda del viewport.
----------------------------------------------------------------------
local function drawingBackend()
	local font = 2
	if Drawing.Fonts then
		font = Drawing.Fonts.Plex or Drawing.Fonts.SourceSans or 2
	end

	local function obj(class)
		local ok, o = pcall(Drawing.new, class)
		if ok then
			return o
		end
		return nil
	end

	return {
		name = "Drawing",
		newRect = function()
			return obj("Square")
		end,
		newLabel = function()
			return obj("Text")
		end,
		rect = function(o, x, y, w, h, col, filled, thin, transp, vis)
			if not o then
				return
			end
			o.Position = Vector2.new(x, y)
			o.Size = Vector2.new(w, h)
			o.Color = col
			o.Filled = filled
			o.Thickness = thin
			o.Transparency = transp
			o.Visible = vis
		end,
		label = function(o, text, x, y, size, col, vis)
			if not o then
				return
			end
			o.Text = text
			o.Position = Vector2.new(x, y)
			o.Size = size
			o.Color = col
			o.Outline = true
			o.Center = true
			o.Font = font
			o.Visible = vis
		end,
		setVisible = function(o, vis)
			if o then
				o.Visible = vis
			end
		end,
		remove = function(o)
			if o then
				pcall(function()
					o:Remove()
				end)
			end
		end,
	}
end

local function guiBackend()
	local parent
	for _, fn in ipairs({
		function()
			return gethui()
		end,
		function()
			return LP:WaitForChild("PlayerGui", 5)
		end,
		function()
			return game:GetService("CoreGui")
		end,
		function()
			return LP:WaitForChild("PlayerGui")
		end,
	}) do
		local ok, res = pcall(fn)
		if ok and res then
			parent = res
			break
		end
	end

	local ok, gui = pcall(Instance.new, "ScreenGui")
	if not ok or not parent then
		return nil
	end

	gui.Name = "Astral"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999
	pcall(function()
		gui.Parent = parent
	end)

	local function make(class)
		local o = Instance.new(class)
		o.BorderSizePixel = 0
		o.BackgroundTransparency = 1
		o.Visible = false
		o.Parent = gui
		return o
	end

	local stroke = setmetatable({}, { __mode = "k" })

	return {
		name = "ScreenGui",
		gui = gui,
		newRect = function()
			return make("Frame")
		end,
		newLabel = function()
			local t = make("TextLabel")
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.Gotham
			t.TextXAlignment = Enum.TextXAlignment.Center
			t.TextStrokeTransparency = 0.2
			t.TextColor3 = Color3.new(1, 1, 1)
			t.AnchorPoint = Vector2.new(0.5, 0)
			return t
		end,
		rect = function(o, x, y, w, h, col, filled, thin, transp, vis)
			if not o then
				return
			end
			o.Position = UDim2.fromOffset(x, y)
			o.Size = UDim2.fromOffset(w, h)
			o.Visible = vis
			if filled then
				o.BackgroundColor3 = col
				o.BackgroundTransparency = transp or 0
				local s = stroke[o]
				if s then
					s.Enabled = false
				end
			else
				o.BackgroundTransparency = 1
				local s = stroke[o]
				if not s then
					s = Instance.new("UIStroke")
					s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
					s.Parent = o
					stroke[o] = s
				end
				s.Enabled = true
				s.Color = col
				s.Thickness = thin or 1
			end
		end,
		label = function(o, text, x, y, size, col, vis)
			if not o then
				return
			end
			o.Text = text
			o.Position = UDim2.fromOffset(x, y)
			o.TextSize = size
			o.TextColor3 = col
			o.Visible = vis
		end,
		setVisible = function(o, vis)
			if o then
				o.Visible = vis
			end
		end,
		remove = function(o)
			if o then
				pcall(function()
					o:Destroy()
				end)
			end
		end,
	}
end

local R

local function pickBackend()
	if Drawing and Drawing.new then
		local probe = select(2, pcall(Drawing.new, "Square"))
		if probe then
			pcall(function()
				probe:Remove()
			end)
			return drawingBackend()
		end
	end
	return guiBackend()
end

----------------------------------------------------------------------
-- player helpers
----------------------------------------------------------------------
-- TeamColor es blanco para todos en juegos sin equipos, así que solo
-- se compara el objeto Team
local function sameTeam(plr)
	if plr.Team == nil or LP.Team == nil then
		return false
	end
	return plr.Team == LP.Team
end

local function getHumanoid(char)
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

local function getRoot(char)
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
end

local function lerpColor(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

----------------------------------------------------------------------
-- esp
----------------------------------------------------------------------
local HP_LOW = Color3.fromRGB(225, 55, 55)
local HP_HIGH = Color3.fromRGB(90, 225, 120)

local CORNERS = {
	{ -1, -1, -1 }, { 1, -1, -1 }, { -1, 1, -1 }, { 1, 1, -1 },
	{ -1, -1, 1 },  { 1, -1, 1 },  { -1, 1, 1 },  { 1, 1, 1 },
}

local espOf = {}

local function newESP()
	local e = {
		box = R.newRect(),
		hpBg = R.newRect(),
		hpFill = R.newRect(),
		name = R.newLabel(),
		dist = R.newLabel(),
	}
	e.rects = { e.box, e.hpBg, e.hpFill }
	e.labels = { e.name, e.dist }
	return e
end

local function hideESP(e)
	for _, o in ipairs(e.rects) do
		R.setVisible(o, false)
	end
	for _, o in ipairs(e.labels) do
		R.setVisible(o, false)
	end
end

local function destroyESP(e)
	for _, o in ipairs(e.rects) do
		R.remove(o)
	end
	for _, o in ipairs(e.labels) do
		R.remove(o)
	end
end

local function espFor(plr)
	local e = espOf[plr]
	if not e then
		e = newESP()
		espOf[plr] = e
	end
	return e
end

-- AABB del modelo -> 8 esquinas -> hull en pantalla (origen arriba-izq, Y abajo)
local function screenBox(model, cam)
	local ok, cf, size = pcall(model.GetBoundingBox, model)
	if not ok or not cf or not size then
		return nil
	end

	local center = cam:WorldToViewportPoint(cf.Position)
	if center.Z <= 0 then
		return nil
	end

	local minX, minY, maxX, maxY

	for _, c in ipairs(CORNERS) do
		local world = cf * Vector3.new(c[1] * size.X * 0.5, c[2] * size.Y * 0.5, c[3] * size.Z * 0.5)
		local sp = cam:WorldToViewportPoint(world)

		if sp.Z > 0 then
			minX = (not minX or sp.X < minX) and sp.X or minX
			maxX = (not maxX or sp.X > maxX) and sp.X or maxX
			minY = (not minY or sp.Y < minY) and sp.Y or minY
			maxY = (not maxY or sp.Y > maxY) and sp.Y or maxY
		end
	end

	if not minX then
		return nil
	end

	return minX, minY, maxX, maxY
end

local function updateESP(cam)
	for _, plr in ipairs(Players:GetPlayers()) do
		local e = espOf[plr]
		local visible = false

		if plr ~= LP and S.espEnabled then
			local char = plr.Character
			local hum = getHumanoid(char)
			local root = getRoot(char)

			if char and hum and root and hum.Health > 0 then
				local dist = (cam.CFrame.Position - root.Position).Magnitude
				local skip = dist > S.espMaxDistance or (S.espTeamCheck and sameTeam(plr))

				if not skip then
					local minX, minY, maxX, maxY = screenBox(char, cam)
					if minX then
						e = e or espFor(plr)
						visible = true

						local w, h = maxX - minX, maxY - minY
						local cx = (minX + maxX) * 0.5
						local col = S.espBoxColor

						R.rect(e.box, minX, minY, w, h, col, false, 1, 0, S.espBox)

						local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						local barX = minX - 6
						local barW = 3

						R.rect(e.hpBg, barX, minY, barW, h, Color3.new(0, 0, 0), true, 1, 0.55, S.espHealth)
						R.rect(e.hpFill, barX, minY + h * (1 - hp), barW, math.max(h * hp, 1),
							lerpColor(HP_LOW, HP_HIGH, hp), true, 1, 0, S.espHealth)

						local label = plr.DisplayName
						if label == nil or label == "" then
							label = plr.Name
						end

						R.label(e.name, label, cx, minY - 18, 14, Color3.new(1, 1, 1), S.espName)
						R.label(e.dist, string.format("%d studs", math.floor(dist + 0.5)),
							cx, maxY + 3, 13, Color3.fromRGB(215, 215, 222), S.espDistance)
					end
				end
			end
		end

		if not visible and e then
			hideESP(e)
		end
	end
end

----------------------------------------------------------------------
-- hitbox expander
-- las parts las posee el otro cliente: el cambio es local. sirve en
-- juegos con hit detection del lado del cliente, no en shooters con
-- validación estricta en el servidor.
----------------------------------------------------------------------
local BODY_PARTS = {
	"HumanoidRootPart", "Head", "Torso",
	"Left Arm", "Right Arm", "Left Leg", "Right Leg",
	"UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot",
}

local originalSizes = {}
local nextHitboxPass = 0

local function restoreHitboxes()
	for part, size in pairs(originalSizes) do
		if part.Parent then
			pcall(function()
				part.Size = size
			end)
		end
	end
	table.clear(originalSizes)
end

local function collectParts(char, rootOnly)
	if rootOnly then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return { root }
		end
		return {}
	end

	local out = {}
	for _, name in ipairs(BODY_PARTS) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			out[#out + 1] = part
		end
	end
	return out
end

local function applyHitbox(char)
	for _, part in ipairs(collectParts(char, S.hitRootOnly)) do
		if not originalSizes[part] then
			originalSizes[part] = part.Size
		end
		local base = originalSizes[part]
		pcall(function()
			part.Size = base * S.hitScale
		end)
	end
end

local function updateHitbox()
	if not S.hitEnabled then
		if next(originalSizes) ~= nil then
			restoreHitboxes()
		end
		return
	end

	local now = os.clock()
	if now < nextHitboxPass then
		return
	end
	nextHitboxPass = now + 0.5

	for part in pairs(originalSizes) do
		if part.Parent == nil then
			originalSizes[part] = nil
		end
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP then
			local char = plr.Character
			local hum = getHumanoid(char)
			if char and hum and hum.Health > 0 then
				applyHitbox(char)
			end
		end
	end
end

----------------------------------------------------------------------
-- ui
----------------------------------------------------------------------
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
if not Rayfield then
	return warn("[Astral] Rayfield Gen2 no cargó")
end

R = pickBackend()
if not R then
	return warn("[Astral] sin renderer: el executor no tiene Drawing y no hay acceso a PlayerGui/CoreGui")
end

local window = Rayfield:CreateWindow({
	name = "Astral",
	subtitle = "esp + hitbox",
	sidebarLayout = true,
	theme = "amethyst",
	configuration = {
		autoSave = true,
		autoLoad = true,
		fileName = "Astral",
	},
})

local tabs = {}
tabs.esp = window:CreateTab({ name = "ESP" })
tabs.hit = window:CreateTab({ name = "Hitbox" })
tabs.config = window:CreateTab({ name = "Config" })

local handles = {}

-- la UI restaurada desde disco no siempre dispara callbacks, así que se
-- leen los handles una vez creado todo
local function syncFromUI()
	for key, h in pairs(handles) do
		if h and h.value ~= nil then
			S[key] = h.value
		end
	end
end

local function on(key)
	return function(v)
		S[key] = v
		if key:find("^hit") then
			restoreHitboxes()
		end
	end
end

local esp = tabs.esp

esp:CreateSection({ name = "Visuals" })

handles.espEnabled = esp:CreateToggle({
	name = "Enabled",
	flag = "espEnabled",
	value = S.espEnabled,
	callback = on("espEnabled"),
})

handles.espBox = esp:CreateToggle({
	name = "Box",
	flag = "espBox",
	value = S.espBox,
	callback = on("espBox"),
})

handles.espHealth = esp:CreateToggle({
	name = "Health bar",
	flag = "espHealth",
	value = S.espHealth,
	callback = on("espHealth"),
})

handles.espName = esp:CreateToggle({
	name = "Name",
	flag = "espName",
	value = S.espName,
	callback = on("espName"),
})

handles.espDistance = esp:CreateToggle({
	name = "Distance",
	flag = "espDistance",
	value = S.espDistance,
	callback = on("espDistance"),
})

handles.espTeamCheck = esp:CreateToggle({
	name = "Team check",
	flag = "espTeamCheck",
	value = S.espTeamCheck,
	callback = on("espTeamCheck"),
})

handles.espMaxDistance = esp:CreateSlider({
	name = "Max distance",
	flag = "espMaxDistance",
	range = { 50, 5000 },
	increment = 50,
	value = S.espMaxDistance,
	suffix = " studs",
	callback = on("espMaxDistance"),
})

esp:CreateDivider()

handles.espBoxColor = esp:CreateColorPicker({
	name = "Box color",
	flag = "espBoxColor",
	color = S.espBoxColor,
	callback = function(color)
		S.espBoxColor = color
	end,
})

local hit = tabs.hit

hit:CreateSection({ name = "Expander" })

handles.hitEnabled = hit:CreateToggle({
	name = "Enabled",
	flag = "hitEnabled",
	value = S.hitEnabled,
	callback = on("hitEnabled"),
})

handles.hitRootOnly = hit:CreateToggle({
	name = "Root part only",
	flag = "hitRootOnly",
	value = S.hitRootOnly,
	callback = on("hitRootOnly"),
})

handles.hitScale = hit:CreateSlider({
	name = "Scale",
	flag = "hitScale",
	range = { 1, 10 },
	increment = 0.5,
	value = S.hitScale,
	suffix = "x",
	callback = on("hitScale"),
})

hit:CreateText({
	name = "How it works",
	text = "El tamaño se cambia solo en tu cliente: las parts son del otro jugador. "
		.. "Funciona donde el hit detection corre en el cliente; en shooters validados "
		.. "por servidor no hace nada. Se re-aplica cada 0.5s y se restaura al apagar.",
})

local cfg = tabs.config

cfg:CreateSection({ name = "Configuration" })

cfg:CreateButton({
	name = "Save",
	callback = function()
		if window:Save() then
			window:Notify({ title = "Astral", content = "config guardada", duration = 3 })
		end
	end,
})

cfg:CreateButton({
	name = "Load",
	callback = function()
		if window:Load() then
			syncFromUI()
			restoreHitboxes()
			window:Notify({ title = "Astral", content = "config cargada", duration = 3 })
		end
	end,
})

cfg:CreateButton({
	name = "Reset hitboxes",
	callback = function()
		restoreHitboxes()
		window:Notify({ title = "Astral", content = "hitboxes restauradas", duration = 3 })
	end,
})

cfg:CreateText({
	name = "Info",
	text = "Renderer: " .. (R and R.name or "none")
		.. "  ·  menú: pill colapsado, tecla en Settings de Rayfield",
})

----------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------
local conns = {}

conns[#conns + 1] = Players.PlayerRemoving:Connect(function(plr)
	local e = espOf[plr]
	if e then
		destroyESP(e)
		espOf[plr] = nil
	end
end)

conns[#conns + 1] = RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	updateESP(cam)
	updateHitbox()
end)

task.defer(function()
	syncFromUI()
	restoreHitboxes()
end)

-- el autoLoad de Rayfield puede aplicar el archivo después de crear los
-- elementos; una segunda lectura cubre ese caso sin sondear cada frame
task.delay(1, function()
	syncFromUI()
	restoreHitboxes()
end)

local function unload()
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	for plr, e in pairs(espOf) do
		destroyESP(e)
		espOf[plr] = nil
	end
	restoreHitboxes()
	if R and R.gui then
		pcall(function()
			R.gui:Destroy()
		end)
	end
	pcall(function()
		window:Unload()
	end)
end

if getgenv then
	getgenv().Astral = { unload = unload, Settings = S }
end
