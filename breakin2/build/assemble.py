#!/usr/bin/env python3
"""assemble.py — obfuscated parts in, one deliverable out.

    python3 build/assemble.py

Reads build/out/obf/p1.lua .. pN.lua and writes dist/breakin2.obf.lua: the
loader, then each obfuscated part embedded as a long string and called in
order. One file to publish, still small enough per obfuscated function for
LuaJIT.

The embedding level is computed per part, so a part that happens to contain a
`]=]` cannot close its own string early.
"""

import glob
import hashlib
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent
DIST = ROOT.parent / "dist"
OBF = ROOT / "out" / "obf"

HEADER = """-- breaker / break in 2
-- Rayfield Gen2 menu. Everything starts off; nothing fires until a toggle says so.
--
-- Generated file: source in breakin2/src, build in breakin2/build.sh.
-- The parts below are the obfuscated module packs; they register themselves into
-- one table, which the loader then serves through require().

local MODULES = {{}}
local CACHE = {{}}

local function install(part)
    if type(part) ~= "table" then return end
    for name, factory in pairs(part) do MODULES[name] = factory end
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
"""


def embed(index, text):
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return (
        "install((function()\n"
        "    local src = [%s[\n%s\n]%s]\n"
        "    local chunk = loadstring(src, \"@part%d\")\n"
        "    if not chunk then error(\"part %d failed to load\", 0) end\n"
        "    return chunk()\n"
        "end)())\n\n" % (eq, text, eq, index, index)
    )


def main():
    files = sorted(
        glob.glob(str(OBF / "p*.lua")),
        key=lambda p: int(re.search(r"p(\d+)\.lua$", p).group(1)),
    )
    if not files:
        print("no obfuscated parts in", OBF)
        return 1

    out = [HEADER]
    for i, path in enumerate(files, 1):
        text = pathlib.Path(path).read_text(encoding="utf-8").strip("\n")
        out.append(embed(i, text))
    out.append('require("main")\n')

    result = "".join(out)
    target = DIST / "breakin2_v2.obf.lua"
    target.write_text(result, encoding="utf-8")
    print("assembled %s  parts=%d  %d bytes  sha256=%s"
          % (target, len(files), len(result),
             hashlib.sha256(result.encode()).hexdigest()[:32]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
