--[[
	Aero :: Milonarie Tycoon :: farming

	El farm corre por dos vias:
	  - remote : replay del remote ligado a "collect" con los args capturados por el spy
	  - fisico : caminar a las partes de dinero / disparar los ProximityPrompt
	El modo "hybrid" prueba las dos; la fisica cubre los juegos sin remote de cobro.
]]

Aero = Aero or {}
Aero.farm = {}

local farm = Aero.farm
local util = Aero.util

farm.moneyParts = {}
farm.prompts = {}
farm.lastScan = 0

function farm.scanWorld()
	local cfg = Aero.config.physical
	farm.moneyParts = {}
	farm.prompts = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") then
			local lname = string.lower(inst.Name)
			for _, key in ipairs(cfg.moneyNames) do
				if string.find(lname, key, 1, true) then
					table.insert(farm.moneyParts, inst)
					break
				end
			end
		elseif inst:IsA("ProximityPrompt") then
			local action = string.lower(inst.ActionText or inst.Name or "")
			for _, key in ipairs(cfg.promptActions) do
				if string.find(action, key, 1, true) then
					table.insert(farm.prompts, inst)
					break
				end
			end
		end
	end
	farm.lastScan = util.now()
	return #farm.moneyParts, #farm.prompts
end

function farm.nearestMoneyPart(origin)
	local best, bestDist
	local radius = Aero.config.physical.searchRadius
	for _, part in ipairs(farm.moneyParts) do
		if part.Parent and part:IsDescendantOf(workspace) then
			local d = (part.Position - origin).Magnitude
			if d < radius and (not bestDist or d < bestDist) then
				best, bestDist = part, d
			end
		end
	end
	return best
end

function farm.collectPhysical()
	local root = util.getRootPart()
	if not root then
		return false
	end
	local part = farm.nearestMoneyPart(root.Position)
	if not part then
		return false
	end
	if type(firetouchinterest) == "function" then
		pcall(firetouchinterest, root, part, 0)
		pcall(firetouchinterest, root, part, 1)
		return true
	end
	-- Sin firetouchinterest: el CFrame del personaje si es propiedad del cliente,
	-- asi que el server recibe el movimiento.
	root.CFrame = part.CFrame + Vector3.new(0, 3, 0)
	return true
end

function farm.firePrompts()
	local fired = 0
	for _, prompt in ipairs(farm.prompts) do
		if prompt.Parent and prompt:IsDescendantOf(workspace) then
			if type(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
			else
				local detector = prompt.Parent:FindFirstChildOfClass("ClickDetector")
				if detector and type(fireclickdetector) == "function" then
					pcall(fireclickdetector, detector)
				else
					local root = util.getRootPart()
					if root and prompt.Parent:IsA("BasePart") then
						root.CFrame = prompt.Parent.CFrame + Vector3.new(0, 3, 0)
					end
				end
			end
			fired = fired + 1
			if fired >= 5 then
				break
			end
		end
	end
	return fired
end

function farm.collectRemote()
	local rec = Aero.remotes.bound("collect")
	if not rec then
		return false
	end
	local overrides = nil
	if Aero.config.money.inflate then
		local amount = math.min(Aero.config.money.value, Aero.config.money.cap)
		overrides = { [Aero.config.money.argIndex] = amount }
	end
	return Aero.remotes.fire(rec, overrides)
end

function farm.buy()
	local rec = Aero.remotes.bound("buy")
	if not rec then
		return false
	end
	return Aero.remotes.fire(rec)
end

function farm.rebirth()
	local rec = Aero.remotes.bound("rebirth")
	if not rec then
		return false
	end
	return Aero.remotes.fire(rec)
end

function farm.loop()
	local cfg = Aero.config.farm
	local lastCollect, lastBuy, lastRebirth = 0, 0, 0
	while true do
		local now = util.now()
		if cfg.enabled then
			if now - farm.lastScan >= Aero.config.physical.scanInterval then
				farm.scanWorld()
			end
			if now - lastCollect >= cfg.collectInterval then
				lastCollect = now
				local mode = cfg.mode
				if mode == "remote" or mode == "hybrid" then
					farm.collectRemote()
				end
				if mode == "physical" or mode == "hybrid" then
					if not farm.collectPhysical() then
						farm.firePrompts()
					end
				end
			end
			if cfg.autoBuy and now - lastBuy >= cfg.buyInterval then
				lastBuy = now
				farm.buy()
			end
			if cfg.autoRebirth and now - lastRebirth >= cfg.rebirthInterval then
				lastRebirth = now
				local cash = util.getCash()
				if cash and cash >= cfg.rebirthAt then
					farm.rebirth()
				end
			end
		end
		task.wait(0.05)
	end
end
