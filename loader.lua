--[[
	Vanta loader
	put this in the repo root next to Vanta.lua and run:

		loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/main/loader.lua"))()

	`()()` is not a typo: loadstring compiles the chunk and returns a function,
	the second call runs it. swap MAIN for a commit hash if you want to pin a build.
]]

local BASE = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/main/"
local MAIN = "Vanta.lua"

if not loadstring then
	error("[Vanta] loadstring is disabled — the executor has no scripting identity", 0)
end

local ok, body = pcall(function()
	return game:HttpGet(BASE .. MAIN)
end)

if not ok or type(body) ~= "string" or #body < 64 then
	error("[Vanta] fetch failed: " .. tostring(body), 0)
end

local chunk, err = loadstring(body, "Vanta")

if not chunk then
	error("[Vanta] compile failed: " .. tostring(err), 0)
end

if getgenv and getgenv().Vanta and type(getgenv().Vanta.unload) == "function" then
	pcall(getgenv().Vanta.unload)
end

chunk()
