-- Aero / Roblox -- loadstring DE URL. Pega esta unica linea en el executor.
-- Trae loader.lua desde la rama; loader.lua trae aero_roblox.lua y lo ejecuta.
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/6922546f-vvv/loader.lua", true))()

-- Para congelar la version no cambies esta linea: en loader.lua pon usePin = true
-- y CFG.sha = el SHA de `git rev-parse HEAD`. El SHA de este propio commit no
-- puede ir aqui (seria autoreferente), por eso el pin vive en el stage 2.

-- Directo al payload, sin la estructura de loader.lua (sin reintentos ni validacion):
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/6922546f-vvv/aero_roblox.lua", true))()
