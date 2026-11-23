-- build/stub/datatypes.luau
-- Vector3 / CFrame / Color3 / Enum: enough for the sources to load and for
-- arithmetic on positions to produce numbers instead of nil.
-- Loaded before roblox.luau, which builds a player position at load time.

-- datatype tables are declared up front: `function Vector3.new` needs the
-- table to exist, and makePlayer below already builds a position
Vector3 = {}
CFrame = {}
Vector2 = {}
Color3 = {}
BrickColor = { fromRGB = function() return {} end, new = function() return {} end }


-- datatypes
function Vector3.new(x, y, z)
    local v = { X = x or 0, Y = y or 0, Z = z or 0 }
    v.x, v.y, v.z = v.X, v.Y, v.Z
    v.Magnitude = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
    function v.Unit()
        local m = v.Magnitude
        if m == 0 then return Vector3.new(0, 0, 0) end
        return Vector3.new(v.X / m, v.Y / m, v.Z / m)
    end
    v.Unit = { __call = function() return v.Unit() end }
    return setmetatable(v, {
        __add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end,
        __sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end,
        __mul = function(a, b)
            if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
            return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
        end,
        __index = function(t, k)
            if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
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
    local c = { Position = Vector3.new(0, 0, 0), LookVector = Vector3.new(0, 0, -1),
                RightVector = Vector3.new(1, 0, 0), UpVector = Vector3.new(0, 1, 0) }
    return setmetatable(c, {
        __add = function(a, b) return CFrame.new() end,
        __mul = function(a, b) return CFrame.new() end,
    })
end

function Color3.fromRGB(r, g, b)
    return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }
end

-- enums: any Enum.X.Y resolves, so a typo in the enum name would slip through
-- the stub. The analyzer catches those; the stub only catches syntax and nil.
local enumProxy = setmetatable({}, {
    __index = function(_, key)
        return setmetatable({}, {
            __index = function(_, k) return { Name = k, Value = 0, EnumType = key } end,
        })
    end,
})
Enum = enumProxy

