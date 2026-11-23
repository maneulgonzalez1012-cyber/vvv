-- ui/rayfield.lua
-- Rayfield Gen2 loader, kept in one place so the loader line, the fallback and
-- the notice all live together.
--
-- Gen2 draws its whole interface in code: no asset id to fingerprint, no model
-- to fetch. Users still report the library name in the console if the executor
-- logs HttpGet, which is why the main script can be wrapped (see build/README).

local U = require("core/util")

local RAYFIELD_GEN2 = "https://sirius.menu/gen2"

local Rayfield

local ok, result = pcall(function()
    return loadstring(game:HttpGet(RAYFIELD_GEN2))()
end)

if ok and type(result) == "table" and type(result.CreateWindow) == "function" then
    Rayfield = result
else
    -- A missing UI library must not mean a half-initialised cheat. The feature
    -- modules are independent of the menu, so the script reports and stops
    -- instead of running blind.
    -- warn is present in Roblox but not in every harness this is tested with;
    -- U.log always works, so the message never gets lost to a missing global
    pcall(function() warn("[breaker] Rayfield Gen2 no cargo: " .. tostring(result)) end)
    U.log("rayfield load failed", tostring(result))
    error("[breaker] UI no disponible; abortando sin tocar el juego", 0)
end

Rayfield.version = "gen2"
Rayfield.source = RAYFIELD_GEN2

return Rayfield
