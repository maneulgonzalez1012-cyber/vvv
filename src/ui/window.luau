--!nocheck
--[[
	Astral :: ui/window

	construye la ventana de Rayfield Gen 2 y deja cada control en una tabla
	plana (flags) para que el resto del script no dependa de los handles.

	el estado real vive en `state` (una tabla mutable). los callbacks
	escriben ahí y los módulos leen de ahí: el acoplamiento con Rayfield
	termina en este archivo.
]]

local Config = require(script.Parent.Parent.shared.config)
local Hitbox = require(script.Parent.Parent.modules.hitbox) -- MODES
local PlayersLib = require(script.Parent.Parent.shared.players)

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

	b(hit:CreateDropdown({
		name = "Target",
		flag = "hitMode",
		options = Hitbox.MODES,
		value = state.hitMode,
	}), "hitMode")

	hit:CreateSection({ name = "Per axis" })
	local axes = { "X", "Y", "Z" }
	for _, axis in ipairs(axes) do
		local key = "hitScale" .. axis
		local range, inc = Config.slider(key)
		b(hit:CreateSlider({
			name = "Scale " .. axis,
			flag = key,
			range = range,
			increment = inc,
			value = state[key],
			suffix = "x",
		}), key)
	end

	hit:CreateButton({
		name = "Uniformes",
		callback = function()
			-- copia X a Y y Z, y mueve la UI sin volver a disparar callbacks
			local x = state.hitScaleX
			state.hitScaleY = x
			state.hitScaleZ = x
			if flags.hitScaleY then
				flags.hitScaleY:Set(x, true)
			end
			if flags.hitScaleZ then
				flags.hitScaleZ:Set(x, true)
			end
		end,
	})

	b(hit:CreateToggle({
		name = "Debug boxes",
		flag = "hitVisual",
		value = state.hitVisual,
	}), "hitVisual")

	hit:CreateText({
		name = "Scope",
		text = "El Size base se guarda una vez por parte y se restaura al apagar, "
			.. "al morir el objetivo y al salir del workspace. Las partes nuevas las "
			.. "captura ChildAdded, no un barrido por timer.",
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

	local status = misc:CreateText({
		name = "Status",
		text = "midiendo...",
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

	return { window = window, flags = flags, tabs = tabs, status = status }
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
