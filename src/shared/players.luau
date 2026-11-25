--!nocheck
--[[
	Astral :: shared/players
	la única fuente de verdad sobre "quién es un objetivo válido" y sobre
	"dónde está su hueso". todos los módulos preguntan aquí en vez de
	repetir la lógica y divergir.

	la lista de jugadores se cachea por frame: Players:GetPlayers() crea una
	tabla nueva en cada llamada y llamarla 3 veces por frame se nota.
]]

local Players = game:GetService("Players")

local PlayersLib = {}
local LP = Players.LocalPlayer

PlayersLib.service = Players
PlayersLib.me = LP

-- alias de huesos: el mismo nombre cubre R6 y R15
local BONE_ALIASES = {
	Head = { "Head" },
	UpperTorso = { "UpperTorso", "Torso" },
	LowerTorso = { "LowerTorso", "Torso" },
	HumanoidRootPart = { "HumanoidRootPart", "Torso" },
	LeftHand = { "LeftHand", "Left Arm" },
	RightHand = { "RightHand", "Right Arm" },
}

PlayersLib.boneNames = { "Head", "UpperTorso", "LowerTorso", "HumanoidRootPart" }

function PlayersLib.humanoid(char)
	if not char then
		return nil
	end
	local ok, hum = pcall(char.FindFirstChildOfClass, char, "Humanoid")
	return ok and hum or nil
end

function PlayersLib.root(char)
	if not char then
		return nil
	end
	local ok, part = pcall(function()
		return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
	end)
	return ok and part or nil
end

-- TeamColor es blanco para todos en juegos sin equipos: solo el objeto Team
function PlayersLib.sameTeam(plr)
	if plr.Team == nil or LP.Team == nil then
		return false
	end
	return plr.Team == LP.Team
end

-- char, hum, root, distance o nil si no es objetivo
function PlayersLib.target(plr, camPos, teamCheck)
	if plr == LP or plr.Character == nil then
		return nil
	end

	local char = plr.Character
	local hum = PlayersLib.humanoid(char)
	if not hum or hum.Health <= 0 then
		return nil
	end

	local root = PlayersLib.root(char)
	if not root or not root:IsA("BasePart") then
		return nil
	end

	if teamCheck and PlayersLib.sameTeam(plr) then
		return nil
	end

	local dist = 0
	if camPos then
		dist = (camPos - root.Position).Magnitude
	end

	return char, hum, root, dist
end

function PlayersLib.bone(char, name)
	local list = BONE_ALIASES[name] or { name }
	for i = 1, #list do
		local part = char:FindFirstChild(list[i], true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local cacheFrame, cacheList = -1, nil

function PlayersLib.all()
	local frame = math.floor(os.clock() * 120)
	if frame ~= cacheFrame then
		cacheFrame = frame
		cacheList = Players:GetPlayers()
	end
	return cacheList
end

function PlayersLib.nameOf(plr)
	local n = plr.DisplayName
	if n == nil or n == "" then
		n = plr.Name
	end
	return n
end

return PlayersLib
