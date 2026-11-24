-- Aero / Roblox -- EL CORTO: loadstring de una sola linea con link acortado.
-- Pega esta unica linea en el executor.
loadstring(game:HttpGet("https://is.gd/aerovvv", true))()

-- Destino: https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/6922546f-vvv/aero_roblox.lua
-- Otros cortos verificados (redireccion 3xx limpia, sin HTML de por medio):
--   https://tinyurl.com/aero-vvv   mismo payload, alias legible
--   https://is.gd/aeropin          payload congelado en el SHA 5bb6154
--   https://is.gd/aeroldr          loader.lua (reintentos + validacion)
--   https://is.gd/wmQUvu           payload, alias aleatorio de respaldo
-- Si el acortador cae, la URL cruda:
-- loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/6922546f-vvv/aero_roblox.lua", true))()
