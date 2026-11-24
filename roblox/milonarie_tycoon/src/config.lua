--[[
	Aero :: Milonarie Tycoon :: configuracion

	Todo valor ajustable vive aqui. El codigo de features nunca lleva numeros sueltos,
	asi un update del juego solo toca este archivo y los bindings de remotes.
]]

-- Bootstrap: namespace compartido entre re-ejecuciones del script.
-- getgenv() es el env global del executor. Sin executor, getfenv() devuelve el
-- env real de Luau (los globales NO viven en _G, que ademas es read-only).
-- Cualquiera de los dos puede ser read-only: se protege la escritura.
local _genv
if type(getgenv) == "function" then
	local ok, t = pcall(getgenv)
	if ok and type(t) == "table" then
		_genv = t
	end
end
if not _genv and type(getfenv) == "function" then
	local ok, t = pcall(getfenv)
	if ok and type(t) == "table" then
		_genv = t
	end
end
if not _genv then
	_genv = {}
end
Aero = _genv.Aero or {}
pcall(function()
	_genv.Aero = Aero
end)

-- Env global donde se guarda la config y el estado entre ejecuciones.
-- Vive fuera de Aero.config a proposito: deepCopy(config) lo copiaria.
Aero.genv = _genv

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
