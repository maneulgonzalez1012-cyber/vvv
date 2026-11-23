#!/usr/bin/env python3
"""pack.py — bundle src/ into one Luau file plus a syntax-gate runner.

    python3 build/pack.py            # writes dist/breakin2.lua and build/out/gate.luau
    python3 build/pack.py --check    # bundling only, no gate

The bundle is a single chunk with a tiny module table at the top; each source
becomes MODULES["path"], so `require("core/net")` resolves without touching the
executor's filesystem and without a second HttpGet at runtime.
"""

import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "..", "src")
DIST = os.path.join(ROOT, "..", "dist")
OUT = os.path.join(ROOT, "out")

REQUIRE = re.compile(r'require\("([^"]+)"\)')


def gather():
    mods = {}
    for base, _, files in os.walk(SRC):
        for name in sorted(files):
            if not name.endswith(".lua"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, SRC).replace(os.sep, "/")[:-4]
            with open(path, "r", encoding="utf-8") as fh:
                mods[rel] = fh.read()
    return mods


def check_requires(mods):
    missing = []
    for name, body in mods.items():
        for dep in REQUIRE.findall(body):
            if dep not in mods:
                missing.append((name, dep))
    return missing


LOADER = """
local MODULES = {}
local CACHE = {}

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


def bundle(mods):
    order = sorted(mods)
    parts = ["-- breaker / break in 2 - bundle\n"]
    parts.append("-- built from %d modules; regenerate with build/pack.py\n" % len(order))
    parts.append(LOADER)
    # Each module is a factory taking `require`, so its top-level `return` is
    # the module's value and no loadstring / filesystem step is needed.
    for name in order:
        parts.append('MODULES["%s"] = function(require)\n' % name)
        parts.append(mods[name])
        parts.append("\nend\n")
    parts.append('\nrequire("main")\n')
    return "".join(parts)


def gate(mods):
    """A runner for the Luau interpreter: stubs, then every module is loaded and
    its top level executed, then main runs and gets unloaded."""
    order = sorted(mods)
    head = []
    with open(os.path.join(ROOT, "stub", "datatypes.luau"), "r", encoding="utf-8") as fh:
        head.append("do\n" + fh.read() + "\nend\n")
    with open(os.path.join(ROOT, "stub", "roblox.luau"), "r", encoding="utf-8") as fh:
        head.append("do\n" + fh.read() + "\nend\n")
    with open(os.path.join(ROOT, "stub", "scheduler.luau"), "r", encoding="utf-8") as fh:
        head.append("do\n" + fh.read() + "\nend\n")
    head.append(LOADER)
    for name in order:
        if name == "main":
            continue
        head.append('MODULES["%s"] = function(require)\n' % name)
        head.append(mods[name])
        head.append("\nend\n")
    # load every module before main so a bad require surfaces by name
    head.append("\nlocal loaded = 0\nfor name in pairs(MODULES) do require(name) loaded += 1 end\n")
    head.append('print("modules ok: " .. loaded)\n')
    if "main" in mods:
        body = mods["main"]
        head.append("-- main body, run last\n" + body + "\n")

    # fire every callback the menu registered, on and off, and report failures.
    # A callback that errors is a real bug: it is what a user clicks.
    head.append("""
local fired, failed = 0, 0
for _, el in ipairs(EXERCISE) do
    if el.callback then
        local values = { true, false }
        if el.method == "CreateSlider" then values = { 50, 17 } end
        if el.method == "CreateDropdown" then values = { "GoldenApple", "Crowbar3", "Phone" } end
        if el.method == "CreateButton" then values = { nil } end
        for _, v in ipairs(values) do
            fired += 1
            local ok, err = pcall(el.callback, v)
            if not ok then
                failed += 1
                print(string.format("CALLBACK FAIL %s/%s: %s",
                    tostring(el.tab), tostring(el.name), tostring(err)))
            end
        end
    end
end
print(string.format("callbacks fired=%d failed=%d", fired, failed))
print("GATE " .. (failed == 0 and "OK" or "FAILED"))
""")
    return "".join(head)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def main():
    mods = gather()
    if not mods:
        print("no sources found under", SRC)
        return 1
    missing = check_requires(mods)
    if missing:
        for name, dep in missing:
            print("MISSING require: %s -> %s" % (name, dep))
        return 1

    out = bundle(mods)
    write(os.path.join(DIST, "breakin2.lua"), out)
    dig = hashlib.sha256(out.encode("utf-8")).hexdigest()[:16]
    print("bundle   dist/breakin2.lua  %d bytes  modules=%d  sha=%s" % (len(out), len(mods), dig))

    if "--check" in sys.argv:
        return 0

    write(os.path.join(OUT, "gate.luau"), gate(mods))
    print("gate     build/out/gate.luau")
    return 0


if __name__ == "__main__":
    sys.exit(main())
