--[[
Aero / Roblox -- structured URL loader (stage 2).
Stage 1 is loadstring.lua: one line that fetches THIS file from a URL.
Stage 2 (here) fetches the payload aero_roblox.lua from a URL and runs it.

Structure, in order:
  config -> env/guard -> wait for game -> fetch (HttpGet + request fallback,
  retries) -> validate -> compile (named chunk) -> run (xpcall + traceback)
  -> report. Nothing runs twice; nothing runs on a 404 page.

Why each piece:
  - game:HttpGet(url, true): 2nd arg is noCache (GetAsync semantics). Some
    executors implement it inverted, so a cache-bust query is appended too.
  - request fallback chain request / http_request / syn.request / http.request /
    fluxus.request: Infinite Yield `source` head + roblox-executor-mcp loader.
  - loadstring(src, chunkName) wrapped in pcall: syntax errors become messages
    instead of a dead executor; the chunk name shows up in tracebacks.
  - guard flag + game.Loaded:Wait(): Infinite Yield `source` head.
--]]

local CFG = {
    owner = "maneulgonzalez1012-cyber",
    repo = "vvv",
    branch = "arena/6922546f-vvv",
    -- Freeze point. FILL: replace with `git rev-parse HEAD` of the commit you
    -- want to freeze, then usePin = true. No puede ser el SHA de este propio
    -- commit (autoreferente): elige uno ya subido.
    sha = "5bb615475686e477fd79f6c80a0ceb9eec07dda3",
    file = "aero_roblox.lua",
    usePin = false,        -- false = sigue la rama; true = versión congelada
    cacheBust = true,      -- ?t=... porque noCache no es fiable en todos los executors
    retries = 3,
    retryDelay = 1,        -- segundos, backoff lineal
    minBytes = 512,        -- rechaza páginas de error cortas
    marker = "Aero / Roblox",
    chunkName = "=AeroRoblox",
}

local function env()
    local ok, g = pcall(function() return getgenv() end)
    if ok and type(g) == "table" then return g end
    ok, g = pcall(function() return getfenv(0) end)
    if ok and type(g) == "table" then return g end
    return _G
end
local ENV = env()

local function report(msg)
    local line = "[Aero] " .. tostring(msg)
    if type(warn) == "function" then
        pcall(warn, line)
    elseif type(print) == "function" then
        print(line)
    end
end

if ENV.AERO_LOADED and not ENV.AERO_FORCE_RELOAD then
    report("ya cargado; AERO_FORCE_RELOAD = true para recargar")
    return
end
ENV.AERO_LOADED = nil
ENV.AERO_FORCE_RELOAD = nil

local waitFn = (type(task) == "table" and type(task.wait) == "function") and task.wait
    or (type(wait) == "function" and wait)
    or function() end

local function buildUrl()
    local ref = CFG.usePin and CFG.sha or CFG.branch
    local u = "https://raw.githubusercontent.com/" .. CFG.owner .. "/" .. CFG.repo
        .. "/" .. ref .. "/" .. CFG.file
    if CFG.cacheBust and not CFG.usePin then
        u = u .. "?t=" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    end
    return u, ref
end

-- Executors disagree on which request function exists; IY's chain covers them.
local function findRequest()
    for _, n in ipairs({ "request", "http_request" }) do
        local f = rawget(ENV, n)
        if type(f) == "function" then return f end
    end
    local function from(tabName)
        local t = rawget(ENV, tabName)
        if type(t) == "table" then
            local f = rawget(t, "request")
            if type(f) == "function" then return f end
        end
        return nil
    end
    return from("syn") or from("http") or from("fluxus")
end

local function fetch(u)
    local ok, body = pcall(function() return game:HttpGet(u, true) end)
    if ok and type(body) == "string" and #body > 0 then return body end
    local firstErr = ok and "respuesta vacia" or tostring(body)

    local send = findRequest()
    if not send then error("sin HttpGet ni funcion request (" .. firstErr .. ")") end
    local res = send({ Url = u, Method = "GET" })
    if type(res) ~= "table" then error("request devolvio " .. type(res)) end
    local status = tonumber(res.StatusCode or res.Status or res.status_code or res.status)
    if status and status ~= 200 then error("HTTP " .. tostring(status)) end
    local text = res.Body or res.body
    if type(text) ~= "string" or #text == 0 then error("request sin body") end
    return text
end

local function compile(src)
    if type(loadstring) ~= "function" then error("este executor no expone loadstring") end
    local ok, chunk, err = pcall(loadstring, src, CFG.chunkName)
    if ok and type(chunk) == "function" then return chunk end
    if not ok then
        -- some executors reject the second argument
        ok, chunk, err = pcall(loadstring, src)
        if ok and type(chunk) == "function" then return chunk end
    end
    error("compile: " .. tostring(err or chunk))
end

local function errHandler(e)
    if type(debug) == "table" and type(debug.traceback) == "function" then
        return debug.traceback(tostring(e), 2)
    end
    return tostring(e)
end

local function main()
    pcall(function()
        if not game:IsLoaded() then game.Loaded:Wait() end
    end)

    local u, ref = buildUrl()
    local src, lastErr
    for attempt = 1, CFG.retries do
        local ok, res = pcall(fetch, u)
        if ok then
            src = res
            break
        end
        lastErr = res
        if attempt < CFG.retries then waitFn(CFG.retryDelay * attempt) end
    end
    if not src then error("download: " .. tostring(lastErr)) end
    if #src < CFG.minBytes then error("fuente demasiado corta (" .. #src .. " bytes)") end
    if not string.find(src, CFG.marker, 1, true) then
        error("marker no encontrado: 404, HTML o URL equivocada")
    end

    local chunk = compile(src)
    local ok, err = xpcall(chunk, errHandler)
    if not ok then error("runtime: " .. tostring(err)) end
    return ref
end

local ok, res = pcall(main)
if ok then
    report("cargado desde " .. tostring(res))
else
    report("fallo: " .. tostring(res))
end
