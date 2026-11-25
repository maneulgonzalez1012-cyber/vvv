-- vvv · loader corto
local R = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv"
local F = "roblox/vanta_shooter.lua"
local s
for _, r in ipairs({ "main", "a0b0fae0a04bb7d18cc680f6ecc1a10893a04686" }) do
	local ok, b = pcall(game.HttpGet, game, R .. "/" .. r .. "/" .. F .. "?t=" .. os.time())
	if ok and type(b) == "string" and #b > 64 and b:sub(1, 1) ~= "<" then s = b break end
end
if not s then warn("[vvv] fetch falló") return end
local f, e = loadstring(s)
if not f then warn("[vvv] " .. tostring(e)) return end
local ok, err = pcall(f)
if not ok then warn("[vvv] " .. tostring(err)) end
