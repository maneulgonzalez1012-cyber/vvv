--!nocheck
--[[
	Astral :: shared/renderer

	un solo backend: ScreenGui + TextLabel/Frame + UIStroke. funciona en
	cualquier executor y en cualquier dispositivo, a diferencia de la API
	Drawing (que en varios executors móviles existe pero no pinta nada).

	contrato:
		newRect() / newText() / newCircle()
		rect(o, x, y, w, h, color, filled, thickness, transparency, visible)
		text(o, str, x, y, size, color, visible)
		circle(o, x, y, radius, color, thickness, filled, visible)
		hide(o) / destroy(o)

	coordenadas: píxeles, origen arriba-izquierda del viewport (lo que devuelve
	cam:WorldToViewportPoint y mide cam.ViewportSize).

	el gui vive en gethui() si existe → CoreGui → PlayerGui. con PlayerGui se
	apaga IgnoreGuiInset porque el gui arranca bajo la topbar, y así la Y del
	viewport cuadra sin corregir a mano.

	el inset real se mide al arrancar (GuiService.TopbarInset) y se expone como
	Renderer.inset, por si el juego lo cambia; los módulos no lo usan porque
	PlayerGui ya lo compensa.
]]

local Renderer = {}

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local function safeCall(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then
		return res
	end
	return nil
end

----------------------------------------------------------------------
-- padre del gui
----------------------------------------------------------------------
local function pickParent()
	local probes = {
		{ fn = function()
			return gethui()
		end },
		{ fn = function()
			return game:GetService("CoreGui")
		end },
		{ fn = function()
			return Players.LocalPlayer:WaitForChild("PlayerGui", 5)
		end, playerGui = true },
	}

	for _, probe in ipairs(probes) do
		local parent = safeCall(probe.fn)
		if parent then
			return parent, probe.playerGui == true
		end
	end
	return nil, false
end

----------------------------------------------------------------------
-- construcción
----------------------------------------------------------------------
function Renderer.build()
	local parent, underPlayerGui = pickParent()
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
	gui.IgnoreGuiInset = not underPlayerGui
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- sin esto, un gui dentro de PlayerGui se borra al respawnar aunque
	-- ResetOnSpawn sea false en algunos executors
	pcall(function()
		gui.ClipToDeviceSafeArea = false
	end)

	if not safeCall(function()
		gui.Parent = parent
		return true
	end) then
		gui:Destroy()
		return nil
	end

	local strokes = setmetatable({}, { __mode = "k" })
	local shadows = setmetatable({}, { __mode = "k" })
	local corners = setmetatable({}, { __mode = "k" })

	local function make(class)
		local o = safeCall(function()
			return Instance.new(class)
		end)
		if not o then
			return nil
		end
		o.BorderSizePixel = 0
		o.BackgroundTransparency = 1
		o.Visible = false
		o.Parent = gui
		return o
	end

	local function strokeOf(o)
		local s = strokes[o]
		if not s then
			s = safeCall(function()
				return Instance.new("UIStroke")
			end)
			if not s then
				return nil
			end
			pcall(function()
				s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			end)
			s.Parent = o
			strokes[o] = s
		end
		return s
	end

	local function shadowOf(o)
		local s = shadows[o]
		if not s then
			s = safeCall(function()
				return Instance.new("UIStroke")
			end)
			if not s then
				return nil
			end
			pcall(function()
				s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				s.Thickness = 1
				s.Color = Color3.new(0, 0, 0)
				s.Transparency = 0.4
			end)
			s.Parent = o
			shadows[o] = s
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
		local d = shadows[o]
		if d then
			d.Enabled = false
		end
	end

	local function outline(o, color, thickness)
		o.BackgroundTransparency = 1
		local s = strokeOf(o)
		if s then
			s.Enabled = true
			s.Color = color
			s.Thickness = math.max(thickness or 1, 1)
		end
	end

	local api = {
		name = "ScreenGui",
		gui = gui,
		-- padding real de la topbar en este cliente; 0 cuando el gui cubre
		-- toda la pantalla
		inset = 0,
	}

	pcall(function()
		api.inset = GuiService.TopbarInset and GuiService.TopbarInset.Height or 0
	end)

	function api.newRect()
		return make("Frame")
	end

	function api.newText()
		local t = make("TextLabel")
		if not t then
			return nil
		end
		t.Font = Enum.Font.Gotham
		t.TextSize = 13
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.TextYAlignment = Enum.TextYAlignment.Top
		t.TextStrokeTransparency = 0.2
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.TextColor3 = Color3.new(1, 1, 1)
		return t
	end

	function api.newCircle()
		local c = make("Frame")
		if not c then
			return nil
		end
		local corner = safeCall(function()
			return Instance.new("UICorner")
		end)
		if corner then
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = c
			corners[c] = corner
		end
		return c
	end

	function api.rect(o, x, y, w, h, color, filled, thickness, transparency, visible)
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
	end

	function api.text(o, str, x, y, size, color, visible)
		if not o then
			return
		end
		o.Text = str
		o.Position = UDim2.fromOffset(x, y)
		o.TextSize = size
		o.TextColor3 = color
		o.Visible = visible
	end

	function api.circle(o, x, y, radius, color, thickness, filled, visible)
		if not o then
			return
		end
		o.AnchorPoint = Vector2.new(0.5, 0.5)
		o.Position = UDim2.fromOffset(x, y)
		o.Size = UDim2.fromOffset(radius * 2, radius * 2)
		o.Visible = visible
		if filled then
			fill(o, color, 0.55)
		else
			outline(o, color, thickness)
		end
	end

	function api.hide(o)
		if o then
			o.Visible = false
		end
	end

	function api.destroy(o)
		if o then
			safeCall(function()
				o:Destroy()
			end)
		end
	end

	return api
end

return Renderer
