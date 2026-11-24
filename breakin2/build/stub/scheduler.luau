-- build/stub/scheduler.luau
-- task.* / coroutine / wait for the Luau runner. Everything is cooperative: a
-- task.wait yields, a task.spawn queues, and the gate drains the queue a fixed
-- number of rounds. That is enough to catch "loop calls nil" without ever
-- hanging the build.

local queue = {}
local deferred = {}
local elapsed = 0

wait = function(t)
    elapsed = elapsed + (t or 0)
    coroutine.yield()
end

task = task or {}
function task.wait(t) return wait(t) end
function task.spawn(fn, ...)
    table.insert(queue, { fn = fn, args = table.pack(...) })
    return nil
end
function task.defer(fn, ...)
    table.insert(deferred, { fn = fn, args = table.pack(...) })
    return nil
end
function task.delay(t, fn, ...)
    table.insert(deferred, { fn = fn, args = table.pack(...) })
    return nil
end
function task.cancel() end
function task.synchronize(fn) return fn() end
function task.desynchronize(fn) return fn() end

-- drain: run everything the script scheduled. Each job is pcall'd so a broken
-- loop reports itself instead of killing the build.
function __drain(rounds, budget)
    local errors = {}
    rounds = rounds or 3
    budget = budget or 3000
    for _ = 1, rounds do
        for _ = 1, budget do
            local job = table.remove(queue, 1)
            if not job then break end
            local function run(...)
                local args = table.pack(...)
                local co = coroutine.create(function()
                    job.fn(table.unpack(args, 1, args.n))
                end)
                local ok, err = coroutine.resume(co)
                if not ok then table.insert(errors, tostring(err)) end
            end
            local ok, err = pcall(run, table.unpack(job.args, 1, job.args.n))
            if not ok then table.insert(errors, tostring(err)) end
        end
        local pending = deferred
        deferred = {}
        for _, job in ipairs(pending) do
            local ok, err = pcall(job.fn, table.unpack(job.args, 1, job.args.n))
            if not ok then table.insert(errors, tostring(err)) end
        end
    end
    return errors
end

-- the Luau CLI hands out readonly standard libraries, so nothing here replaces
-- coroutine.* or os.*. Loops that need a safe wrap get one from core/util; the
-- gate only needs the scheduler itself.

-- os is readonly in the runner but the globals are writable, so `os` is
-- shadowed with a view whose clock advances when the gate drives the
-- coroutine. Throttles and timeouts in the features then behave as they would
-- in game instead of waiting on a frozen clock forever.
local REAL_CLOCK = os.clock
os = setmetatable({ clock = function() return REAL_CLOCK() + elapsed end }, { __index = os })
function __advance(t) elapsed = elapsed + (t or 0) end
function __elapsed() return elapsed end

-- The gate runs at chunk scope, where yielding is illegal, but the features
-- wait for remotes. __run gives them a coroutine and drives it to completion:
-- every yield is just "next round", and a loop that never finishes is capped.
function __run(fn, rounds)
    rounds = rounds or 500
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co)
    local n = 0
    while coroutine.status(co) == "suspended" and n < rounds do
        n = n + 1
        elapsed = elapsed + 0.1
        ok, err = coroutine.resume(co)
        if not ok then break end
    end
    if coroutine.status(co) == "suspended" then
        return false, "no termino en " .. rounds .. " tandas"
    end
    if not ok then return false, tostring(err) end
    return true
end
