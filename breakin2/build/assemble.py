#!/usr/bin/env python3
"""assemble.py — wrap the obfuscated parts into the one file that ships.

    python3 build/assemble.py

Each `build/out/parts/pN.obf.lua` is a chunk that returns a table of module
factories. This script emits a loader that hands each part a `require` that
concatenates those tables, then calls `require("main")`.

Why this shape: Prometheus's Cff pass flattens a chunk into one function, and
LuaJIT rejects a function with more than 65536 constants, so the bundle cannot
be a single obfuscated chunk. Splitting per module group keeps every chunk
under the limit and keeps the shipped file self-contained.
"""

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "out")
PARTS = os.path.join(OUT, "parts")
DIST = os.path.join(ROOT, "..", "dist")
TARGET = os.path.join(DIST, "breakin2_v3.obf.lua")

HEADER = """-- breaker / break in 2 | obfuscated bundle
-- {npart} parts, {nbytes} parts bytes. Each part returns a table of module
-- factories; this loader stitches them together and starts the script.
-- Do not edit: rebuild with build.sh (pack -> gate -> analyze -> obfuscate).
local PARTS = {{}}
"""

LOADER = """
local MODULES = {}
local CACHE = {}

-- collect: run each part, take its table. A part that fails is named, so a
-- broken build is obvious instead of a silent nil in the loader.
for index, chunk in ipairs(PARTS) do
    local ok, produced = pcall(chunk)
    if not ok then
        error("part " .. tostring(index) .. " fallo: " .. tostring(produced), 0)
    end
    if type(produced) ~= "table" then
        error("part " .. tostring(index) .. " no devolvio una tabla", 0)
    end
    for name, factory in pairs(produced) do
        if MODULES[name] then
            error("modulo duplicado: " .. tostring(name), 0)
        end
        MODULES[name] = factory
    end
end

local function require(name)
    local hit = CACHE[name]
    if hit ~= nil then return hit end
    local factory = MODULES[name]
    if not factory then error("missing module: " .. tostring(name), 2) end
    local value = factory(require)
    if value == nil then value = true end
    CACHE[name] = value
    return value
end

require("main")
"""


def main():
    if not os.path.isdir(PARTS):
        print("no parts in", PARTS)
        return 1
    names = sorted(n for n in os.listdir(PARTS) if n.endswith(".obf.lua"))
    if not names:
        print("no obfuscated parts; run the obfuscate step first")
        return 1

    bodies, total = [], 0
    for index, name in enumerate(names, 1):
        with open(os.path.join(PARTS, name), "r", encoding="utf-8") as fh:
            code = fh.read()
        total += len(code)
        # varargs: Prometheus emits `...` at the top level of its VM entry, so
        # the wrapper must accept them or the chunk will not even parse
        bodies.append("PARTS[%d] = function(...)\n%s\nend\n" % (index, code))

    out = (HEADER.format(npart=len(names), nbytes=total)
           + "".join(bodies) + LOADER)

    os.makedirs(DIST, exist_ok=True)
    with open(TARGET, "w", encoding="utf-8") as fh:
        fh.write(out)

    digest = hashlib.sha256(out.encode("utf-8")).hexdigest()
    print("assemble dist/%s  %d bytes  parts=%d  sha=%s"
          % (os.path.basename(TARGET), len(out), len(names), digest[:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
