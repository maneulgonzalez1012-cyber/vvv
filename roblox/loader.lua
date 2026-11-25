-- vvv · loader corto
local R = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv"
local F = "roblox/vanta_shooter.lua"
local s
for _, r in ipairs({ "main", "3b5f77d189cc200d1110ef443470133b9f99494d" }) do
	local ok, b = pcall(game.HttpGet, game, R .. "/" .. r .. "/" .. F .. "?t=" .. os.time())
	if ok and type(b) == "string" and #b > 64 and b:sub(1, 1) ~= "<" then s = b break end
end
if not s then warn("[vvv] fetch falló") return end
local f, e = loadstring(s)
if not f then warn("[vvv] " .. tostring(e)) return end
local ok, err = pcall(f)
if not ok then warn("[vvv] " .. tostring(err)) end
