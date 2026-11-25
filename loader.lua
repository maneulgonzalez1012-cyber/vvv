--[[
	Astral loader
	put this in the repo root next to Astral.lua and run:

		loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/loader.lua"))()

	`()()` is not a typo: loadstring compiles the chunk and returns a function,
	the second call runs it. swap the ref for a commit hash to pin a build.
]]

local BASE = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/"
local MAIN = "Astral.lua"

if not loadstring then
	error("[Astral] loadstring is disabled — the executor has no scripting identity", 0)
end

local ok, body = pcall(function()
	return game:HttpGet(BASE .. MAIN)
end)

if not ok or type(body) ~= "string" or #body < 64 then
	error("[Astral] fetch failed: " .. tostring(body), 0)
end

local chunk, err = loadstring(body, "Astral")

if not chunk then
	error("[Astral] compile failed: " .. tostring(err), 0)
end

if getgenv and getgenv().Astral and type(getgenv().Astral.unload) == "function" then
	pcall(getgenv().Astral.unload)
end

chunk()
