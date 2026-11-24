-- build/stub/datatypes.luau
-- Vector3 / CFrame / Color3 / Enum: enough for the sources to load and for
-- arithmetic on positions to produce numbers instead of nil.

Vector3 = {}
CFrame = {}
Vector2 = {}
Color3 = {}
BrickColor = { fromRGB = function() return {} end, new = function() return {} end }

-- math.clamp already exists in Luau and its table is readonly there, so this
-- only fills the gap in a plain interpreter (LuaJIT for the minifier check)
pcall(function()
    if not math.clamp then
        math.clamp = function(v, lo, hi)
            if v < lo then return lo end
            if v > hi then return hi end
            return v
        end
    end
end)

function Vector3.new(x, y, z)
    local v = { X = x or 0, Y = y or 0, Z = z or 0 }
    return setmetatable(v, {
        __add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
        __sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
        __mul = function(a, b)
            if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
            return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
        end,
        __index = function(t, k)
            if k == "Magnitude" then
                return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
            end
            if k == "Unit" then
                return function()
                    local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
                    if m == 0 then return Vector3.new(0, 0, 0) end
                    return Vector3.new(t.X / m, t.Y / m, t.Z / m)
                end
            end
            return nil
        end,
    })
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.yAxis = Vector3.new(0, 1, 0)

function Vector2.new(x, y) return { X = x or 0, Y = y or 0 } end

function CFrame.new(...)
    local c = {
        Position = Vector3.new(0, 0, 0),
        LookVector = Vector3.new(0, 0, -1),
        RightVector = Vector3.new(1, 0, 0),
        UpVector = Vector3.new(0, 1, 0),
    }
    return setmetatable(c, {
        __add = function() return CFrame.new() end,
        __mul = function() return CFrame.new() end,
    })
end

function Color3.fromRGB(r, g, b)
    return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }
end

-- any Enum.X.Y resolves; the analyzer is what catches a wrong enum name
Enum = setmetatable({}, {
    __index = function(_, key)
        return setmetatable({}, {
            __index = function(_, k) return { Name = k, Value = 0, EnumType = key } end,
        })
    end,
})

function tick()
    return os.clock()
end

-- table.pack / table.unpack exist in Luau but not in Lua 5.1, and the shipped
-- bundle is also run through LuaJIT. Filling them keeps one source honest in
-- both runtimes; it is a pcall so Luau's readonly table is never touched.
pcall(function()
    if not table.pack then
        table.pack = function(...) return { n = select("#", ...), ... } end
    end
    if not table.unpack then table.unpack = unpack end
end)
