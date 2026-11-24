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
