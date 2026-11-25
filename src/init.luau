--!nocheck
--[[
	Astral :: init

	entry point. arma el estado, los módulos y el loop; nada más.
	cada módulo es un objeto con :step() y :destroy(), así el unload es
	recorrer una lista — no hay conexiones sueltas ni estado global.
]]

local Config = require(script.shared.config)
local PlayersLib = require(script.shared.players)
local Renderer = require(script.shared.renderer)

local Esp = require(script.modules.esp)
local Hitbox = require(script.modules.hitbox)
local Aim = require(script.modules.aim)
local Radar = require(script.modules.radar)
local Window = require(script.ui.window)

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
