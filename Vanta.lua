--[[
	Vanta :: Roblox ESP + Hitbox Expander
	open source, no obfuscation, no key system

	run it:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/main/loader.lua"))()

	menu: RightShift
	everything starts OFF; nothing fires until you toggle it.
]]

----------------------------------------------------------------------
-- services
----------------------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

if not Drawing then
	return error("[Vanta] this executor has no Drawing API", 0)
end

local LP = Players.LocalPlayer
local MENU_KEY = Enum.KeyCode.RightShift

-- font id differs per executor; 2 is Plex in Synapse-likes, falls back quietly
local FONT = 2
if Drawing.Fonts then
	FONT = Drawing.Fonts.Plex or Drawing.Fonts.SourceSans or 2
end

----------------------------------------------------------------------
-- config
----------------------------------------------------------------------
local DEFAULT_CONFIG = {
	ESP = {
		Enabled = false,
		Box = true,
		Health = true,
		Name = true,
		Distance = true,
		TeamCheck = true,
		MaxDistance = 750,
		BoxColor = { 255, 255, 255 },
	},
	Hitbox = {
		Enabled = false,
		Scale = 2.0,
		RootOnly = false,
	},
}

local Config = HttpService:JSONDecode(HttpService:JSONEncode(DEFAULT_CONFIG))

local CLR = {
	panel = Color3.fromRGB(16, 16, 20),
	border = Color3.fromRGB(58, 58, 70),
	title = Color3.fromRGB(255, 255, 255),
	text = Color3.fromRGB(215, 215, 222),
	dim = Color3.fromRGB(130, 130, 142),
	on = Color3.fromRGB(95, 220, 135),
	off = Color3.fromRGB(58, 58, 68),
	row = Color3.fromRGB(32, 32, 40),
	black = Color3.fromRGB(0, 0, 0),
	hpLow = Color3.fromRGB(225, 55, 55),
	hpHigh = Color3.fromRGB(90, 225, 120),
}

----------------------------------------------------------------------
-- drawing helpers
----------------------------------------------------------------------
local function draw(class, props)
	local ok, obj = pcall(Drawing.new, class)
	if not ok or not obj then
		return nil
	end
	pcall(function()
		obj.Visible = false
	end)
	if props then
		for k, v in pairs(props) do
			pcall(function()
				obj[k] = v
			end)
		end
	end
	return obj
end

local function set(obj, key, value)
	if obj then
		pcall(function()
			obj[key] = value
		end)
	end
end

local function remove(obj)
	if obj then
		pcall(function()
			obj:Remove()
		end)
	end
end

----------------------------------------------------------------------
-- player helpers
----------------------------------------------------------------------
-- team color is white for everyone in non-team games, so only trust the
-- Team object itself
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
local CORNERS = {
	{ -1, -1, -1 }, { 1, -1, -1 }, { -1, 1, -1 }, { 1, 1, -1 },
	{ -1, -1, 1 },  { 1, -1, 1 },  { -1, 1, 1 },  { 1, 1, 1 },
}

local espOf = {}

local function createESP()
	local e = {
		box = draw("Square", { Filled = false, Thickness = 1 }),
		hpBg = draw("Square", { Filled = true, Color = CLR.black, Transparency = 0.55 }),
		hpFill = draw("Square", { Filled = true, Color = CLR.hpHigh }),
		name = draw("Text", { Size = 14, Center = true, Outline = true, Font = FONT }),
		dist = draw("Text", { Size = 13, Center = true, Outline = true, Font = FONT, Color = CLR.text }),
	}
	e.objs = {}
	for _, o in ipairs({ e.box, e.hpBg, e.hpFill, e.name, e.dist }) do
		if o then
			e.objs[#e.objs + 1] = o
		end
	end
	return e
end

local function hideESP(e)
	for _, o in ipairs(e.objs) do
		set(o, "Visible", false)
	end
end

local function destroyESP(e)
	for _, o in ipairs(e.objs) do
		remove(o)
	end
end

local function espFor(plr)
	local e = espOf[plr]
	if not e then
		e = createESP()
		espOf[plr] = e
	end
	return e
end

-- model AABB -> 8 world corners -> screen hull (top-left origin, Y down)
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
		local world = cf
			* Vector3.new(c[1] * size.X * 0.5, c[2] * size.Y * 0.5, c[3] * size.Z * 0.5)
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

		if plr ~= LP and Config.ESP.Enabled then
			local char = plr.Character
			local hum = getHumanoid(char)
			local root = getRoot(char)

			if char and hum and root and hum.Health > 0 then
				local dist = (cam.CFrame.Position - root.Position).Magnitude
				local skip = dist > Config.ESP.MaxDistance
					or (Config.ESP.TeamCheck and sameTeam(plr))

				if not skip then
					local minX, minY, maxX, maxY = screenBox(char, cam)
					if minX then
						e = e or espFor(plr)
						visible = true
						local w, h = maxX - minX, maxY - minY
						local cx = (minX + maxX) * 0.5
						local col = Config.ESP.BoxColor

						set(e.box, "Position", Vector2.new(minX, minY))
						set(e.box, "Size", Vector2.new(w, h))
						set(e.box, "Color", Color3.fromRGB(col[1], col[2], col[3]))
						set(e.box, "Visible", Config.ESP.Box)

						-- health bar, left of the box
						local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						local barW = 3
						local barX = minX - 6

						set(e.hpBg, "Position", Vector2.new(barX, minY))
						set(e.hpBg, "Size", Vector2.new(barW, h))
						set(e.hpBg, "Visible", Config.ESP.Health)

						set(e.hpFill, "Position", Vector2.new(barX, minY + h * (1 - hp)))
						set(e.hpFill, "Size", Vector2.new(barW, math.max(h * hp, 1)))
						set(e.hpFill, "Color", lerpColor(CLR.hpLow, CLR.hpHigh, hp))
						set(e.hpFill, "Visible", Config.ESP.Health)

						local label = plr.DisplayName
						if label == nil or label == "" then
							label = plr.Name
						end

						set(e.name, "Text", label)
						set(e.name, "Position", Vector2.new(cx, minY - 18))
						set(e.name, "Visible", Config.ESP.Name)

						set(e.dist, "Text", string.format("%d studs", math.floor(dist + 0.5)))
						set(e.dist, "Position", Vector2.new(cx, maxY + 3))
						set(e.dist, "Visible", Config.ESP.Distance)
					end
				end
			end
		end

		if not visible then
			if e then
				hideESP(e)
			end
		end
	end
end

----------------------------------------------------------------------
-- hitbox expander
-- NOTE: parts are owned by the other client, so the size change is local
-- only. this works in games whose hit detection runs client-side, and does
-- nothing in strictly server-validated shooters.
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

local function collectParts(char, rootOnly)
	local out = {}

	if rootOnly then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			out[1] = root
		end
		return out
	end

	for _, name in ipairs(BODY_PARTS) do
		local part = char:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			out[#out + 1] = part
		end
	end

	return out
end

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

local function applyHitbox(char)
	local scale = Config.Hitbox.Scale

	for _, part in ipairs(collectParts(char, Config.Hitbox.RootOnly)) do
		if not originalSizes[part] then
			originalSizes[part] = part.Size
		end
		local base = originalSizes[part]
		pcall(function()
			part.Size = base * scale
		end)
	end
end

local nextHitboxPass = 0

local function updateHitbox()
	if not Config.Hitbox.Enabled then
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

	-- drop refs to destroyed parts so respawns don't pile up
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
-- config file
----------------------------------------------------------------------
local CONFIG_DIR = "Vanta"
local CONFIG_PATH = "Vanta/config.json"

local function saveConfig()
	if not writefile or not isfolder or not makefolder then
		return
	end
	if not isfolder(CONFIG_DIR) then
		makefolder(CONFIG_DIR)
	end
	pcall(function()
		writefile(CONFIG_PATH, HttpService:JSONEncode(Config))
	end)
end

local function mergeInto(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			mergeInto(dst[k], v)
		elseif type(dst[k]) == type(v) then
			dst[k] = v
		end
	end
end

local function loadConfig()
	if not readfile or not isfile or not isfile(CONFIG_PATH) then
		return
	end
	pcall(function()
		mergeInto(Config, HttpService:JSONDecode(readfile(CONFIG_PATH)))
	end)
	restoreHitboxes()
end

----------------------------------------------------------------------
-- menu
----------------------------------------------------------------------
local UI = {
	x = 24,
	y = 24,
	w = 240,
	open = false,
	drag = false,
	dragOffset = Vector2.new(0, 0),
	slider = nil,
	widgets = {},
}

local rows = {
	{ kind = "header", label = "ESP" },
	{
		kind = "toggle", label = "enabled",
		get = function() return Config.ESP.Enabled end,
		set = function(v) Config.ESP.Enabled = v end,
	},
	{
		kind = "toggle", label = "box",
		get = function() return Config.ESP.Box end,
		set = function(v) Config.ESP.Box = v end,
	},
	{
		kind = "toggle", label = "health bar",
		get = function() return Config.ESP.Health end,
		set = function(v) Config.ESP.Health = v end,
	},
	{
		kind = "toggle", label = "name",
		get = function() return Config.ESP.Name end,
		set = function(v) Config.ESP.Name = v end,
	},
	{
		kind = "toggle", label = "distance",
		get = function() return Config.ESP.Distance end,
		set = function(v) Config.ESP.Distance = v end,
	},
	{
		kind = "toggle", label = "team check",
		get = function() return Config.ESP.TeamCheck end,
		set = function(v) Config.ESP.TeamCheck = v end,
	},
	{
		kind = "slider", label = "max distance", min = 50, max = 5000, step = 50, decimals = 0,
		get = function() return Config.ESP.MaxDistance end,
		set = function(v) Config.ESP.MaxDistance = v end,
	},

	{ kind = "header", label = "HITBOX" },
	{
		kind = "toggle", label = "enabled",
		get = function() return Config.Hitbox.Enabled end,
		set = function(v) Config.Hitbox.Enabled = v end,
		changed = restoreHitboxes,
	},
	{
		kind = "toggle", label = "root part only",
		get = function() return Config.Hitbox.RootOnly end,
		set = function(v) Config.Hitbox.RootOnly = v end,
		changed = restoreHitboxes,
	},
	{
		kind = "slider", label = "scale", min = 1, max = 10, step = 0.5, decimals = 1, suffix = "x",
		get = function() return Config.Hitbox.Scale end,
		set = function(v) Config.Hitbox.Scale = v end,
		changed = restoreHitboxes,
	},

	{ kind = "header", label = "CONFIG" },
	{ kind = "button", label = "save", act = saveConfig },
	{ kind = "button", label = "load", act = loadConfig },
}

local uiDraw = {
	bg = draw("Square", { Filled = true, Color = CLR.panel, Transparency = 0.08 }),
	border = draw("Square", { Filled = false, Thickness = 1, Color = CLR.border }),
	title = draw("Text", { Size = 14, Font = FONT, Outline = true, Color = CLR.title }),
	hint = draw("Text", { Size = 12, Font = FONT, Outline = true, Color = CLR.dim }),
}

local rowDraw = {}

for i = 1, #rows do
	rowDraw[i] = {
		row = draw("Square", { Filled = true, Color = CLR.row, Transparency = 0.35 }),
		label = draw("Text", { Size = 13, Font = FONT, Outline = true, Color = CLR.text }),
		track = draw("Square", { Filled = true, Color = CLR.off }),
		knob = draw("Square", { Filled = true, Color = CLR.on }),
		value = draw("Text", { Size = 12, Font = FONT, Outline = true, Color = CLR.text }),
	}
end

local function setAllVisible(batch, visible)
	for _, obj in pairs(batch) do
		set(obj, "Visible", visible)
	end
end

local function uiRowHeight(r)
	if r.kind == "header" then
		return 18
	end
	return 21
end

local function sliderStep(r, raw)
	local v = math.clamp(raw, r.min, r.max)
	local steps = math.floor((v - r.min) / r.step + 0.5)
	return math.clamp(r.min + steps * r.step, r.min, r.max)
end

local function renderUI()
	if not UI.open then
		setAllVisible(uiDraw, false)
		for i = 1, #rowDraw do
			setAllVisible(rowDraw[i], false)
		end
		UI.widgets = {}
		return
	end

	local x, y, w = UI.x, UI.y, UI.w
	local titleH = 26
	local total = titleH

	for _, r in ipairs(rows) do
		total = total + uiRowHeight(r)
	end
	total = total + 10

	set(uiDraw.bg, "Visible", true)
	set(uiDraw.bg, "Position", Vector2.new(x, y))
	set(uiDraw.bg, "Size", Vector2.new(w, total))

	set(uiDraw.border, "Visible", true)
	set(uiDraw.border, "Position", Vector2.new(x, y))
	set(uiDraw.border, "Size", Vector2.new(w, total))

	set(uiDraw.title, "Visible", true)
	set(uiDraw.title, "Text", "Vanta")
	set(uiDraw.title, "Position", Vector2.new(x + 10, y + 6))

	set(uiDraw.hint, "Visible", true)
	set(uiDraw.hint, "Text", "RSHIFT toggle  ·  drag title")
	set(uiDraw.hint, "Position", Vector2.new(x + 62, y + 8))

	UI.widgets = {}

	local cursor = y + titleH
	local pad = 10
	local innerW = w - pad * 2

	for i, r in ipairs(rows) do
		local d = rowDraw[i]
		local h = uiRowHeight(r)
		local top = cursor
		cursor = cursor + h

		if r.kind == "header" then
			set(d.row, "Visible", false)
			set(d.track, "Visible", false)
			set(d.knob, "Visible", false)
			set(d.value, "Visible", false)

			set(d.label, "Visible", true)
			set(d.label, "Color", CLR.dim)
			set(d.label, "Text", r.label)
			set(d.label, "Position", Vector2.new(x + pad, top + 3))
		else
			set(d.label, "Color", CLR.text)
			set(d.label, "Text", r.label)
			set(d.label, "Position", Vector2.new(x + pad, top + 4))
			set(d.label, "Visible", true)

			set(d.row, "Visible", true)
			set(d.row, "Position", Vector2.new(x + pad - 4, top))
			set(d.row, "Size", Vector2.new(innerW + 8, h - 2))

			if r.kind == "toggle" then
				local on = r.get() and true or false
				set(d.track, "Visible", true)
				set(d.track, "Position", Vector2.new(x + w - pad - 14, top + 5))
				set(d.track, "Size", Vector2.new(14, 11))
				set(d.track, "Color", on and CLR.on or CLR.off)

				set(d.knob, "Visible", false)
				set(d.value, "Visible", false)

				UI.widgets[#UI.widgets + 1] = {
					x = x + pad - 4, y = top, w = innerW + 8, h = h - 2,
					act = function()
						r.set(not r.get())
						if r.changed then
							r.changed()
						end
					end,
				}
			elseif r.kind == "slider" then
				local value = r.get()
				local t = (value - r.min) / (r.max - r.min)
				local trackX = x + w - pad - 100
				local trackW = 76

				set(d.track, "Visible", true)
				set(d.track, "Position", Vector2.new(trackX, top + 8))
				set(d.track, "Size", Vector2.new(trackW, 3))
				set(d.track, "Color", CLR.off)

				set(d.knob, "Visible", true)
				set(d.knob, "Position", Vector2.new(trackX + trackW * t - 1, top + 5))
				set(d.knob, "Size", Vector2.new(3, 9))
				set(d.knob, "Color", CLR.on)

				local text = r.decimals == 0
					and string.format("%d", value)
					or string.format("%.1f", value)
				set(d.value, "Visible", true)
				set(d.value, "Text", text .. (r.suffix or ""))
				set(d.value, "Position", Vector2.new(trackX + trackW + 6, top + 3))

				local function setFromMouse(mx)
					local raw = r.min + ((mx - trackX) / trackW) * (r.max - r.min)
					r.set(sliderStep(r, raw))
					if r.changed then
						r.changed()
					end
				end

				UI.widgets[#UI.widgets + 1] = {
					x = trackX - 4, y = top, w = trackW + 30, h = h - 2,
					slider = true,
					setFromMouse = setFromMouse,
				}
			else -- button
				set(d.track, "Visible", true)
				set(d.track, "Position", Vector2.new(x + w - pad - 44, top + 4))
				set(d.track, "Size", Vector2.new(44, 12))
				set(d.track, "Color", CLR.off)

				set(d.knob, "Visible", false)
				set(d.value, "Visible", true)
				set(d.value, "Text", "run")
				set(d.value, "Position", Vector2.new(x + w - pad - 34, top + 2))

				UI.widgets[#UI.widgets + 1] = {
					x = x + pad - 4, y = top, w = innerW + 8, h = h - 2,
					act = r.act,
				}
			end
		end
	end
end

----------------------------------------------------------------------
-- input
----------------------------------------------------------------------
local function inside(m, x, y, w, h)
	return m.X >= x and m.X <= x + w and m.Y >= y and m.Y <= y + h
end

local function mouseLocation()
	return UIS:GetMouseLocation()
end

UIS.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == MENU_KEY then
		UI.open = not UI.open
		return
	end

	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	local m = mouseLocation()

	if UI.open and inside(m, UI.x, UI.y, UI.w, 26) then
		UI.drag = true
		UI.dragOffset = Vector2.new(m.X - UI.x, m.Y - UI.y)
		return
	end

	if not UI.open then
		return
	end

	for _, widget in ipairs(UI.widgets) do
		if inside(m, widget.x, widget.y, widget.w, widget.h) then
			if widget.slider then
				UI.slider = widget
				widget.setFromMouse(m.X)
			else
				widget.act()
			end
			return
		end
	end
end)

UIS.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end

	local m = mouseLocation()

	if UI.drag then
		UI.x = math.floor(m.X - UI.dragOffset.X)
		UI.y = math.floor(m.Y - UI.dragOffset.Y)
	end

	if UI.slider then
		UI.slider.setFromMouse(m.X)
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	UI.drag = false
	UI.slider = nil
end)

Players.PlayerRemoving:Connect(function(plr)
	local e = espOf[plr]
	if e then
		destroyESP(e)
		espOf[plr] = nil
	end
end)

----------------------------------------------------------------------
-- loop
----------------------------------------------------------------------
RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	updateESP(cam)
	updateHitbox()
	renderUI()
end)

----------------------------------------------------------------------
-- unload (executor "unload" or just re-execute after this)
----------------------------------------------------------------------
local function unload()
	for plr, e in pairs(espOf) do
		destroyESP(e)
		espOf[plr] = nil
	end
	restoreHitboxes()
	setAllVisible(uiDraw, false)
	for i = 1, #rowDraw do
		setAllVisible(rowDraw[i], false)
	end
end

Vanta = { unload = unload, Config = Config }
