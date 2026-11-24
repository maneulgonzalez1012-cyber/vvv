--[[
	Aero :: Milonarie Tycoon :: bootstrap
]]

Aero = Aero or {}
Aero.main = {}

local main = Aero.main

function main.run()
	local g = Aero.genv
	if g.AeroMilo and g.AeroMilo.destroy then
		pcall(g.AeroMilo.destroy)
	end

	Aero.util.log("Aero :: Milonarie Tycoon :: boot")

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player then
		player = Players.PlayerAdded:Wait()
	end

	-- Copia de los defaults para el boton "Reset defaults" de la tab CONFIG.
	Aero.defaults = Aero.util.deepCopy(Aero.config)

	-- Si hay config guardada de una sesion anterior, se aplica al arrancar.
	Aero.ui.loadConfig(true)

	-- Captura de argumentos: sin esto el replay no sabe que enviarle al server.
	Aero.remotes.installSpy()
	Aero.remotes.scan()

	Aero.ui.build()

	task.spawn(Aero.farm.loop)
	task.spawn(Aero.move.startFly)
	task.spawn(Aero.move.startNoclip)
	task.spawn(Aero.move.startInfiniteJump)
	task.spawn(Aero.move.startAntiAfk)
	task.spawn(Aero.ui.refreshTick)

	player.CharacterAdded:Connect(function()
		task.wait(0.6)
		if Aero.config.move.speedEnabled then
			Aero.move.applySpeed()
		end
		Aero.farm.scanWorld()
	end)

	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		local keyName = Aero.config.ui.toggleKey
		if keyName and input.KeyCode == Enum.KeyCode[keyName] then
			local gui = Aero.ui.root
			if gui then
				gui.Enabled = not gui.Enabled
			end
		end
	end)

	g.AeroMilo = { running = true, destroy = main.destroy }
	Aero.util.log("listo: FARM para farmear, TARGET para ligar remotes, RightShift abre/cierra")
end

function main.destroy()
	local g = Aero.genv
	if Aero.ui and Aero.ui.root then
		Aero.ui.root:Destroy()
		Aero.ui.root = nil
	end
	g.AeroMilo = nil
end

main.run()
