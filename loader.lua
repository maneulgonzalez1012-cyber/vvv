--[[
    VANTA | MILONARIE TYCOON
    Loader

    Generado por roblox/milonarie_tycoon/tools/build_loader.py. No editar a mano.

    Se pega en el executor con el juego abierto. NO depende de game:HttpGet:
    Athena (y otros executors) lanzan "HttpGet is not a valid member of
    DataModel" al indexarlo, asi que el cliente HTTP prueba primero las APIs
    del executor y solo usa HttpGet como ultimo recurso.
]]

--[[
	Cliente HTTP compartido entre loader.lua y bootstrap.lua.

	Se inlnea (no se require) porque cada fichero se descarga y ejecuta por
	separado en el executor: no hay un require disponible.

	Cada executor expone el GET de otra forma:
		request({Url=,Method=})         -> string | {Body=,StatusCode=} | (body, ok, code)
		http_request(url)               -> string | {Body=} | (body, ok, code)
		syn.request({Url=,Method=})     -> string | (body, ok, code)
		http.request({Url=,Method=})    -> string | {Body=} | (body, code, msg, headers)
		game:HttpGet(url)               -> string

	Por eso se prueban las dos formas de llamada (tabla y url suelta) y se
	normaliza la respuesta a texto. game:HttpGet va el ULTIMO: Athena (y otros)
	lanza "HttpGet is not a valid member of DataModel" al indexarlo.
]]

local function vantaBodyOf(res, extra)
	if type(res) == "string" and #res > 0 then
		return res
	end
	if type(res) == "table" then
		local body = res.Body or res.body or res.Content or res.content
		if type(body) == "string" and #body > 0 then
			return body
		end
	end
	if type(extra) == "string" and #extra > 0 then
		return extra
	end
	return nil
end

local function vantaHttpGet(url)
	local candidates = {}
	if type(request) == "function" then
		candidates[#candidates + 1] = request
	end
	if type(http_request) == "function" then
		candidates[#candidates + 1] = http_request
	end
	if type(syn) == "table" and type(syn.request) == "function" then
		candidates[#candidates + 1] = syn.request
	end
	if type(http) == "table" and type(http.request) == "function" then
		candidates[#candidates + 1] = http.request
	end

	for _, fn in ipairs(candidates) do
		local ok, a, b = pcall(fn, { Url = url, Method = "GET" })
		if ok then
			local body = vantaBodyOf(a, b)
			if body then
				return body
			end
		end
		local ok2, a2, b2 = pcall(fn, url)
		if ok2 then
			local body = vantaBodyOf(a2, b2)
			if body then
				return body
			end
		end
	end

	-- Ultimo recurso: HttpGet de Roblox (solo dominios en la allowlist del juego).
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" and #body > 0 then
		return body
	end
	return nil
end

-- Compila un fuente. loadstring va primero; algunos executors solo traen load.
local function vantaCompile(source, chunkName)
	local chunk, err
	if type(loadstring) == "function" then
		chunk, err = loadstring(source, chunkName)
	end
	if not chunk and type(load) == "function" then
		chunk, err = load(source, chunkName)
	end
	return chunk, err
end
----------------------------------------------------------------------- URLs
-- Payload ofuscado con Prometheus. Cambia la URL para usar medium/strong:
--   .../milonarie_tycoon_obfuscated.lua        (Medium, register VM)
--   .../milonarie_tycoon_obfuscated_strong.lua  (Strong)
--   .../milonarie_tycoon_obfuscated_light.lua   (Light)
local PAYLOAD_URL = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/roblox/milonarie_tycoon/release/milonarie_tycoon_obfuscated_compact.lua"

-- Respaldo por partes: algunos executors recortan el body de la respuesta.
-- Si el payload truncado no compila, se descargan las partes y se concatenan.
local PAYLOAD_PARTS_URL = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/roblox/milonarie_tycoon/release/parts/milonarie_tycoon_obfuscated_compact.part%d"
local PAYLOAD_MANIFEST_URL = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/roblox/milonarie_tycoon/release/parts/milonarie_tycoon_obfuscated_compact.manifest"

------------------------------------------------------------------- GUI (opcional)
-- La pantalla de carga es cosmetica: si el executor no deja crear GUI, el
-- payload se descarga y se ejecuta igual.
local ScreenGui, Frame, Status

local function setStatus(text)
	if Status then
		pcall(function()
			Status.Text = text
		end)
	end
end

local function buildGui()
	local ok = pcall(function()
		local TweenService = game:GetService("TweenService")
		local CoreGui = game:GetService("CoreGui")

		ScreenGui = Instance.new("ScreenGui")
		ScreenGui.Name = "VANTA_Loader"
		ScreenGui.IgnoreGuiInset = true
		ScreenGui.ResetOnSpawn = false
		ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		ScreenGui.Parent = CoreGui

		Frame = Instance.new("Frame")
		Frame.Size = UDim2.new(1, 0, 1, 0)
		Frame.BackgroundColor3 = Color3.fromRGB(12, 11, 10)
		Frame.BorderSizePixel = 0
		Frame.Parent = ScreenGui

		local Title = Instance.new("TextLabel")
		Title.Size = UDim2.new(1, 0, 0, 40)
		Title.Position = UDim2.new(0, 0, 0.42, 0)
		Title.BackgroundTransparency = 1
		Title.Text = "VANTA"
		Title.TextColor3 = Color3.fromRGB(242, 239, 233)
		Title.TextSize = 32
		Title.Font = Enum.Font.GothamBold
		Title.Parent = Frame

		local Subtitle = Instance.new("TextLabel")
		Subtitle.Size = UDim2.new(1, 0, 0, 24)
		Subtitle.Position = UDim2.new(0, 0, 0.48, 0)
		Subtitle.BackgroundTransparency = 1
		Subtitle.Text = "MILONARIE TYCOON"
		Subtitle.TextColor3 = Color3.fromRGB(160, 155, 145)
		Subtitle.TextSize = 16
		Subtitle.Font = Enum.Font.Gotham
		Subtitle.Parent = Frame

		Status = Instance.new("TextLabel")
		Status.Size = UDim2.new(1, 0, 0, 20)
		Status.Position = UDim2.new(0, 0, 0.58, 0)
		Status.BackgroundTransparency = 1
		Status.Text = "Cargando..."
		Status.TextColor3 = Color3.fromRGB(180, 175, 165)
		Status.TextSize = 14
		Status.Font = Enum.Font.Gotham
		Status.Parent = Frame

		local BarBg = Instance.new("Frame")
		BarBg.Size = UDim2.new(0, 220, 0, 4)
		BarBg.Position = UDim2.new(0.5, -110, 0.63, 0)
		BarBg.BackgroundColor3 = Color3.fromRGB(40, 38, 35)
		BarBg.BorderSizePixel = 0
		BarBg.Parent = Frame

		local Bar = Instance.new("Frame")
		Bar.Size = UDim2.new(0, 0, 1, 0)
		Bar.BackgroundColor3 = Color3.fromRGB(242, 239, 233)
		Bar.BorderSizePixel = 0
		Bar.Parent = BarBg

		TweenService:Create(Bar, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()
	end)
	return ok
end

local function fadeOut()
	if not Frame then
		return
	end
	pcall(function()
		local TweenService = game:GetService("TweenService")
		local fade = TweenService:Create(Frame, TweenInfo.new(0.4), {
			BackgroundTransparency = 1
		})
		for _, child in ipairs(Frame:GetDescendants()) do
			if child:IsA("TextLabel") then
				TweenService:Create(child, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			elseif child:IsA("Frame") and child ~= Frame then
				TweenService:Create(child, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			end
		end
		fade:Play()
		fade.Completed:Wait()
	end)
	pcall(function()
		if ScreenGui then
			ScreenGui:Destroy()
		end
	end)
end

------------------------------------------------------------------ descarga
-- Descarga por partes: el manifest dice cuantas hay y el tamano total.
local function fetchByParts()
	local manifest = vantaHttpGet(PAYLOAD_MANIFEST_URL)
	if not manifest then
		return nil, "sin manifest"
	end
	local total = tonumber(manifest:match("total=(%d+)"))
	local size = tonumber(manifest:match("size=(%d+)"))
	if not total or total < 1 then
		return nil, "manifest invalido"
	end

	local chunks = {}
	for i = 0, total - 1 do
		local part = vantaHttpGet(string.format(PAYLOAD_PARTS_URL, i))
		if not part then
			return nil, "falta la parte " .. i
		end
		chunks[#chunks + 1] = part
	end

	local source = table.concat(chunks)
	if size and #source ~= size then
		return nil, "tamano inesperado: " .. #source .. " != " .. size
	end
	return source
end

--------------------------------------------------------------------- arranque
buildGui()
setStatus("Descargando script...")

local success, err = pcall(function()
	local source = vantaHttpGet(PAYLOAD_URL)
	local chunk, compileErr
	if source then
		chunk, compileErr = vantaCompile(source, "=payload")
	end
	if not chunk then
		-- Puede que el executor haya recortado el body: se reintenta por partes.
		local parts, partsErr = fetchByParts()
		if parts then
			source = parts
			chunk, compileErr = vantaCompile(source, "=payload")
		else
			compileErr = compileErr or partsErr
		end
	end
	if not source then
		error("no se pudo descargar el payload: " .. PAYLOAD_URL)
	end
	if not chunk then
		error("el payload no compila: " .. tostring(compileErr))
	end
	chunk()
end)

if success then
	setStatus("Listo")
	pcall(task.wait, 0.6)
else
	setStatus("Error al cargar")
	pcall(function()
		warn("[VANTA Loader]", err)
	end)
	pcall(task.wait, 2)
end

fadeOut()
