--[[
	Aero :: Milonarie Tycoon :: configuracion

	Todo valor ajustable vive aqui. El codigo de features nunca lleva numeros sueltos,
	asi un update del juego solo toca este archivo y los bindings de remotes.
]]

-- Bootstrap: namespace compartido entre re-ejecuciones del script.
local _genv = (type(getgenv) == "function") and getgenv() or _G
Aero = _genv.Aero or {}
_genv.Aero = Aero

Aero.config = {
	-- Clasificacion de remotes: substring en minusculas contra el path completo del remote.
	-- El primer patron que matchea gana, asi que los especificos van primero.
	patterns = {
		collect = { "updatecollector", "collectmoney", "collect", "money", "cash", "coin", "reward", "earn", "drop" },
		buy     = { "buyupgrade", "buyitem", "buy", "upgrade", "purchase", "unlock", "claim", "open", "equip" },
		rebirth = { "rebirth", "prestige", "ascend" },
	},

	-- Coleccion fisica: prompts y partes de dinero que se tocan para cobrar.
	physical = {
		moneyNames    = { "money", "cash", "coin", "bill", "dollar", "moneybag", "cashstack" },
		promptActions = { "collect", "claim", "earn", "take", "get" },
		searchRadius  = 200,  -- studs
		scanInterval  = 2.0,  -- segundos entre rescans del workspace
	},

	farm = {
		enabled         = false,
		mode            = "hybrid", -- "remote" | "physical" | "hybrid"
		collectInterval = 0.15,
		buyInterval     = 1.2,
		rebirthInterval = 2.5,
		rebirthAt       = 1e9,
		autoBuy         = false,
		autoRebirth     = false,
	},

	-- Inyeccion de cantidad en el remote ligado a "collect".
	money = {
		inflate  = false,
		argIndex = 1,
		value    = 1e9,
		cap      = 1e10, -- el server suele clampear por encima de esto
	},

	move = {
		speedEnabled = false,
		speed        = 32,
		flyEnabled   = false,
		flySpeed     = 70,
		noclip       = false,
		infiniteJump = false,
		antiAfk      = true,
	},

	ui = {
		toggleKey       = "RightShift", -- nombre de Enum.KeyCode
		refreshInterval = 0.25,
		configFile      = "aero_milonarie_config.json",
	},
}
