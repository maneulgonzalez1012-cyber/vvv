-- core/util.lua
-- Helpers shared by every module: notifications, throttled loops, safe calls.
-- Nothing in here touches the network or the menu; it is created first so the
-- rest of the script can log before the window exists.

local U = {}

-- filled in by ui/menu once the Rayfield window exists
U.window = nil
U.pending = {}

function U.notify(title, content)
    if U.window then
        pcall(function()
            U.window:Notify({ title = title, content = content, duration = 4 })
        end)
    else
        table.insert(U.pending, { title, content })
    end
end

function U.flush()
    local q = U.pending
    U.pending = {}
    for _, m in ipairs(q) do U.notify(m[1], m[2]) end
end

function U.log(...)
    print("[breaker]", ...)
end

-- pcall wrapper that never throws and reports once per failure site
local warned = {}
function U.safe(label, fn)
    local ok, err = pcall(fn)
    if not ok and not warned[label] then
        warned[label] = true
        U.log("fail", label, tostring(err))
    end
    return ok, err
end

function U.count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function U.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- A cancellable loop. Start returns a token; Stop invalidates it, so flipping a
-- toggle twice can never leave two loops firing the same remote.
local loops = {}
function U.loop(name, step, fn)
    U.stop(name)
    local token = {}
    loops[name] = token
    task.spawn(function()
        while loops[name] == token do
            local ok = pcall(fn)
            if not ok then break end
            task.wait(step)
        end
        if loops[name] == token then loops[name] = nil end
    end)
    return token
end

function U.stop(name)
    loops[name] = nil
end

function U.running(name)
    return loops[name] ~= nil
end

function U.stop_all()
    loops = {}
end

function U.loop_names()
    local out = {}
    for k in pairs(loops) do table.insert(out, k) end
    return out
end

return U
