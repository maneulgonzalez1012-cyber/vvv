--[[
	Asserts compartidas: las usa mock_run.py (Lua 5.5) y el verify del build
	con Prometheus (Lua 5.1). Devuelve { passed, failed, failures }.
]]

local results = { passed = 0, failed = 0, failures = {} }

local function check(name, cond)
	if cond then
		results.passed = results.passed + 1
	else
		results.failed = results.failed + 1
		table.insert(results.failures, name)
	end
end

-- El payload ofuscado puede renombrar el namespace global, asi que se busca.
local A = Mock.namespace() or Aero

check("UI construida", A.ui.root ~= nil)
check("4 tabs", A.ui.pages.FARM ~= nil and A.ui.pages.MOVE ~= nil
	and A.ui.pages.TARGET ~= nil and A.ui.pages.CONFIG ~= nil)
check("paginas con widgets", #A.ui.pages.FARM:GetChildren() > 3)
check("cash leido del leaderstats", A.util.getCash() == 1234)
check("scan encuentra remotes", A.remotes.scan() ~= nil)

r = Mock.makeRemote("collectMoney", "RemoteEvent")
A.remotes.record(r, "FireServer", 100, "x")
check("spy capturo el remote", A.remotes.records["ReplicatedStorage.collectMoney"] ~= nil)
check("args capturados", A.remotes.records["ReplicatedStorage.collectMoney"].args[1] == 100)
check("contador de llamadas", A.remotes.records["ReplicatedStorage.collectMoney"].count == 1)

A.remotes.autoBind()
check("auto-bind collect", A.remotes.bindings.collect == "ReplicatedStorage.collectMoney")

A.remotes.fire(A.remotes.bound("collect"), { [1] = 999 })
check("override de cantidad aplicado", r.fired[1] == 999)
check("resto de args intactos", #r.fired == 2 and r.fired[2] == "x")
check("suppress limpio tras fire", A.remotes.suppress == 0)

check("json del config generable", A.ui.configJson():find("collect") ~= nil)
check("defaults guardados", A.defaults ~= nil and A.defaults.farm ~= nil)
check("no hay tasks lanzados infinitos", #Mock.logs() == 6)

return results.passed, results.failed, table.concat(results.failures, "\n")
