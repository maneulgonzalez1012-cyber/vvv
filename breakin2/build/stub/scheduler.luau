-- build/stub/scheduler.luau
-- task.* on top of coroutines, so the sources run under plain Luau for the
-- syntax gate. Never shipped.

local co = coroutine
local unpack_ = table.unpack or unpack

task = {
    wait = function(t)
        local start = os.clock()
        repeat co.yield() until os.clock() - start >= (t or 0)
    end,
    spawn = function(fn, ...)
        local args = { n = select("#", ...), ... }
        local thread = co.create(fn)
        local ok, err = co.resume(thread, unpack_(args, 1, args.n))
        if not ok then warn("task.spawn: " .. tostring(err)) end
        return thread
    end,
    defer = function(fn, ...)
        return task.spawn(fn, ...)
    end,
    delay = function(t, fn, ...)
        local args = { n = select("#", ...), ... }
        task.spawn(function()
            task.wait(t)
            fn(unpack_(args, 1, args.n))
        end)
    end,
}

wait = function(t) return task.wait(t) end
spawn = function(fn) return task.spawn(fn) end
delay = function(t, fn) return task.delay(t, fn) end
