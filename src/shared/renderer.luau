--!nocheck
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
