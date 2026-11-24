--[[
	Asserts de cobertura completa: se llama a TODAS las funciones publicas del
	script (incluidos los bucles y los callbacks de la UI), no solo al arranque.

	Sirve sobre todo para el payload ofuscado: Prometheus genera codigo distinto
	segun los steps, y Luau no tiene getfenv/setfenv/unpack/newproxy. Si un
	step genera una llamada a algo que Luau no tiene, aqui revienta.

	Luau 5.5 (lupa) sirve de proxy: Lua 5.5 tampoco tiene esas cuatro.
]]

local results = { passed = 0, failed = 0, failures = {} }

local function record(name, ok, err)
	if ok then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		results.failures[#results.failures + 1] = name .. " -> " .. tostring(err)
	end
end

local function check(name, fn)
	local ok, err = pcall(fn)
	record(name, ok, err)
end

-- Un bucle infinito se corta con el sentinel del mock (task.wait).
local function checkLoop(name, fn)
	local ok, err = pcall(fn)
	if ok then
		record(name, true)
	elseif tostring(err):find("__MOCK_TASK_WAIT_STOP__", 1, true) then
		record(name, true)
	else
		record(name, false, err)
	end
end

local A = Mock.namespace() or Aero

-- arranque ya validado en mock_assert; aqui cobertura de rutas
check("util.deepCopy", function()
	local copy = A.util.deepCopy(A.config)
	assert(copy.farm ~= nil and copy.farm ~= A.config.farm)
end)
check("util.classify", function()
	assert(A.util.classify("ReplicatedStorage.collectMoney") == "collect")
	assert(A.util.classify("ReplicatedStorage.buyUpgrade") == "buy")
	assert(A.util.classify("ReplicatedStorage.rebirth") == "rebirth")
	assert(A.util.classify("ReplicatedStorage.whatever") == nil)
end)
check("util.stringify/serializeArgs", function()
	assert(type(A.util.stringify({ 1, "a" })) == "string")
	assert(type(A.util.serializeArgs(table.pack(1, "a"))) == "string")
end)
check("util.getCash", function()
	assert(A.util.getCash() == 1234)
end)

check("remotes.scan", function()
	assert(A.remotes.scan() ~= nil)
end)
check("remotes.record + fire + bind", function()
	local r = Mock.makeRemote("collectMoney", "RemoteEvent")
	A.remotes.record(r, "FireServer", 100, "x")
	assert(A.remotes.records["ReplicatedStorage.collectMoney"] ~= nil)
	assert(A.remotes.autoBind() ~= nil)
	assert(A.remotes.bind("collect", "ReplicatedStorage.collectMoney"))
	assert(A.remotes.fire(A.remotes.bound("collect"), { [1] = 999 }))
	assert(r.fired[1] == 999)
	assert(A.remotes.suppress == 0)
	A.remotes.unbind("collect")
end)
check("remotes.clear", function()
	A.remotes.clear()
	assert(next(A.remotes.records) == nil)
end)

check("farm.scanWorld", function()
	A.farm.scanWorld()
end)
check("farm.collectPhysical", function()
	A.farm.collectPhysical()
end)
check("farm.firePrompts", function()
	A.farm.firePrompts()
end)
check("farm.collectRemote (sin binding)", function()
	assert(A.farm.collectRemote() == false)
end)
check("farm.buy/rebirth (sin binding)", function()
	assert(A.farm.buy() == false)
	assert(A.farm.rebirth() == false)
end)

check("move.applySpeed/resetSpeed", function()
	A.config.move.speed = 50
	assert(A.move.applySpeed())
	A.move.resetSpeed()
end)
check("move.teleportToTycoon/teleportToMoney", function()
	A.move.teleportToTycoon()
	A.move.teleportToMoney()
end)
check("move.teleportToPlayer", function()
	A.move.teleportToPlayer(game:GetService("Players").LocalPlayer)
end)

check("ui.buildRemoteRows", function()
	A.ui.buildRemoteRows()
end)
check("ui.configJson/saveConfig/loadConfig/resetConfig/copyJson", function()
	assert(type(A.ui.configJson()) == "string")
	A.ui.saveConfig()
	A.ui.loadConfig(true)
	A.ui.resetConfig()
	A.ui.copyJson()
end)

-- callbacks de la UI: disparar los eventos de los widgets montados
check("UI callbacks (toggle/slider/cycle/button)", function()
	local fired = 0
	for _, page in pairs(A.ui.pages) do
		for _, child in ipairs(page:GetChildren()) do
			if child:IsA("Frame") then
				for _, sub in ipairs(child:GetChildren()) do
					if sub:IsA("TextButton") then
						sub:__fire("MouseButton1Click")
						fired = fired + 1
					elseif sub:IsA("TextBox") then
						sub:__fire("FocusLost")
						fired = fired + 1
					elseif sub:IsA("Frame") then
						sub:__fire("InputBegan")
						fired = fired + 1
					end
				end
			end
		end
	end
	assert(fired > 0, "no habia widgets en las paginas")
end)

-- bucles: se cortan con el sentinel
checkLoop("loop farm.loop", function()
	A.farm.loop()
end)
checkLoop("loop ui.refreshTick", function()
	A.ui.refreshTick()
end)
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

checkLoop("loop move.startFly", function()
	A.move.startFly()
	RunService:__fire("RenderStepped")
	RunService:__fire("RenderStepped")
end)
checkLoop("loop move.startNoclip", function()
	A.move.startNoclip()
	RunService:__fire("RenderStepped")
end)
checkLoop("loop move.startInfiniteJump", function()
	A.move.startInfiniteJump()
	UIS:__fire("JumpRequest")
end)
checkLoop("loop move.startAntiAfk", function()
	A.move.startAntiAfk()
	RunService:__fire("Heartbeat")
end)

return results.passed, results.failed, table.concat(results.failures, "\n")
