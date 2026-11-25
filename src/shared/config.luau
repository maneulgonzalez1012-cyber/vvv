--!nocheck
--[[
	Astral :: shared/config

	todo lo que se puede tocar sin entender el resto vive aquí.
	las claves de `defaults` son exactamente los flags de Rayfield y las
	claves de `state`, así que UI y lógica no pueden discrepar.
]]

local Config = {}

Config.version = "2.0.0"
Config.name = "Astral"
Config.subtitle = "esp + hitbox + aim"
Config.configFile = "Astral"
Config.theme = "amethyst"

-- rate limit del hitbox: cada cuánto se re-aplica el Size a las partes
Config.hitboxInterval = 0.5
-- techo de jugadores por pase: un servidor de 60 no te clava el frame
Config.hitboxMaxPlayers = 30

-- { min, max, incremento } de cada slider
Config.ranges = {
	espMaxDistance = { 50, 5000, 50 },
	hitScale = { 1, 10, 0.5 },
	aimFov = { 10, 360, 1 },
	aimSmooth = { 0, 20, 0.5 },
	aimFovCircleRadius = { 20, 400, 1 },
}

function Config.slider(key)
	local r = Config.ranges[key]
	return { r[1], r[2] }, r[3]
end

Config.defaults = {
	-- esp
	espEnabled = false,
	espBox = true,
	espFill = false,
	espHealth = true,
	espName = true,
	espDistance = true,
	espTracer = false,
	espTeamCheck = true,
	espMaxDistance = 750,
	espBoxColor = Color3.fromRGB(255, 255, 255),
	espNameColor = Color3.fromRGB(255, 255, 255),
	espFillColor = Color3.fromRGB(20, 20, 30),

	-- hitbox
	hitEnabled = false,
	hitRootOnly = false,
	hitScale = 2.0,

	-- aim
	aimEnabled = false,
	aimSmooth = 4,
	aimFov = 60,
	aimWallCheck = true,
	aimBone = "Head",
	aimFovCircle = true,
	aimFovCircleColor = Color3.fromRGB(140, 120, 255),
	aimFovCircleRadius = 120,

	-- misc
	radarEnabled = false,
}

return Config
