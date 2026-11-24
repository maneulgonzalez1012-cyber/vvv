-- ui/tabs/diagnostics.lua
-- Last tab, built after every other one, so it can report what failed.
--
-- This exists because "a feature died" used to be invisible: the tab silently
-- lost half its buttons and the console was the only place that knew. Here it
-- is a card with the module list, the failures, and the remote table.

local Tab = {}

function Tab.build(ctx)
    local Menu = ctx.Menu
    local Net = ctx.Net
    local Shield = ctx.Shield
    local U = ctx.U
    local window = ctx.window


    local tab = window:CreateTab({ name = "Diagnostico" })

    tab:CreateText({
        name = "arquitectura",
        text = "cada modulo se carga aparte y cada pestaña se construye en su propio pcall. " ..
               "si algo falla pierdes esa parte y nada mas.",
    })

    local stateLine = tab:CreateText({ name = "estado", text = "calculando..." })

    local function error_count()
        local n = 0
        for _ in pairs(Menu.errors) do n = n + 1 end
        return n
    end

    local function errors_text()
        local lines, count = {}, 0
        for name, message in pairs(Menu.errors) do
            count = count + 1
            table.insert(lines, name .. ": " .. tostring(message))
        end
        table.sort(lines)
        if count == 0 then return "sin fallos: todos los modulos cargaron" end
        return #lines .. " fallo(s)\n" .. table.concat(lines, "\n")
    end

    local failures = tab:CreateText({ name = "fallos", text = errors_text() })

    tab:CreateButton({
        name = "recalcular",
        callback = function()
            U.log("diagnose", tostring(Menu.errors))
            stateLine:Set(string.format("%d modulos ok, %d fallos, %d elementos vivos",
                #Menu.ok, error_count(), U.count(Menu.elements)))
            failures:Set(errors_text())
        end,
    })

    tab:CreateButton({
        name = "remotes resueltos",
        callback = function()
            local lines = {}
            for name, remote in pairs(Net.remotes) do
                table.insert(lines, name .. (remote and " ok" or " nil"))
            end
            table.sort(lines)
            window:Notify({
                title = "remotes (" .. #lines .. ")",
                content = #lines > 0 and table.concat(lines, ", ") or "ninguno",
                duration = 8,
            })
        end,
    })

    tab:CreateButton({
        name = "remotes ausentes",
        callback = function()
            window:Notify({
                title = "ausentes (" .. #Net.missing .. ")",
                content = #Net.missing > 0 and table.concat(Net.missing, ", ") or "ninguno",
                duration = 8,
            })
        end,
    })

    tab:CreateButton({
        name = "semi godmode / hook",
        callback = function()
            local supported = Shield.hook_supported()
            window:Notify({
                title = "hook " .. (supported and "disponible" or "NO disponible"),
                content = Shield.status() .. " | " .. (supported and
                    "hookmetamethod presente" or "tu executor no lo expone: queda el top-up"),
                duration = 8,
            })
        end,
    })

    tab:CreateButton({
        name = "probar energy (diagnostico)",
        callback = function()
            window:Notify({ title = "probando Energy", content = "5 formas, ~3 s", duration = 3 })
            local report = Shield.diagnose()
            U.log("energy diagnose -> " .. tostring(report))
            window:Notify({ title = "resultado", content = tostring(report), duration = 12 })
        end,
    })

    tab:CreateButton({
        name = "volcar al log",
        callback = function()
            U.log("modulos ok", table.concat(Menu.ok, ", "))
            for name, message in pairs(Menu.errors) do U.log("fallo", name, message) end
        end,
    })

    -- one pass now, so the card is populated before anyone clicks
    stateLine:Set(string.format("%d modulos ok, %d fallos", #Menu.ok, error_count()))

    ctx.elements.diagState = stateLine
    ctx.elements.diagFailures = failures
    return nil
end

return Tab
