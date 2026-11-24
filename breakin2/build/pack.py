#!/usr/bin/env python3
"""pack.py — bundle src/ into parts, plus a readable single-file bundle.

    python3 build/pack.py            # build/out/parts/pN.lua + dist/breakin2.lua
    python3 build/pack.py --check    # bundling only, no gate

Why parts: every module is a factory in a shared table, and the whole thing
used to be one chunk. Prometheus's Cff pass flattens a chunk into a single
function, and LuaJIT refuses a function with more than 65536 constants — the
83 KB bundle crossed that line and the obfuscated output would not even parse
in a LuaJIT-based executor. Splitting the module table across a few small
chunks keeps each obfuscated function inside the limit while the delivered file
is still a single one: build/assemble.py embeds each obfuscated part and the
loader calls them in order.

`dist/breakin2.lua` is the same modules concatenated into one readable file, for
reading and for the analyzer; it is not what ships.
"""

import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "..", "src")
DIST = os.path.join(ROOT, "..", "dist")
OUT = os.path.join(ROOT, "out")
PARTS_DIR = os.path.join(OUT, "parts")

REQUIRE = re.compile(r'require\("([^"]+)"\)')

# 25 KB of source per part leaves plenty of headroom under the constant cap
# (the 83 KB single chunk produced ~70k constants; a part of this size lands
# near a third of the limit).
PART_BYTES = 25000

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


def emit_parts(mods):
    """Split the module table into chunks small enough to survive Cff."""
    order = sorted(mods)
    parts, current, size = [], [], 0
    for name in order:
        body = 'MODULES[%r] = function(require)\n%s\nend\n' % (name, mods[name])
        body = body.replace('"', '"', 1)
        if size and size + len(body) > PART_BYTES:
            parts.append(current)
            current, size = [], 0
        current.append(body)
        size += len(body)
    if current:
        parts.append(current)
    return parts


def part_file(index, bodies):
    head = (
        "-- breaker / break in 2 - part %d\n"
        "-- Registers its modules into a shared table and returns it, so the\n"
        "-- loader can collect every part without any of them knowing the others.\n"
        "local MODULES = {}\n\n" % index
    )
    return head + "".join(bodies) + "\nreturn MODULES\n"


def readable_bundle(mods):
    order = sorted(mods)
    out = ["-- breaker / break in 2 - readable bundle\n"]
    out.append("-- built from %d modules; this file is for reading, dist/breakin2.obf.lua\n" % len(order))
    out.append("-- is what ships (same modules, split into parts, obfuscated).\n")
    out.append(LOADER)
    for name in order:
        out.append('MODULES["%s"] = function(require)\n' % name)
        out.append(mods[name])
        out.append("\nend\n")
    out.append('\nrequire("main")\n')
    return "".join(out)


def gate(mods):
    """A runner for the Luau interpreter: stubs, then every module is loaded and
    its top level executed, then main runs and gets unloaded."""
    order = sorted(mods)
    head = []
    for stub in ("datatypes", "roblox", "scheduler"):
        with open(os.path.join(ROOT, "stub", stub + ".luau"), "r", encoding="utf-8") as fh:
            head.append("do\n" + fh.read() + "\nend\n")
    head.append(LOADER)
    for name in order:
        if name == "main":
            continue
        head.append('MODULES["%s"] = function(require)\n' % name)
        head.append(mods[name])
        head.append("\nend\n")

    head.append("\nlocal loaded = 0\nfor name in pairs(MODULES) do require(name) loaded += 1 end\n")
    head.append('print("modules ok: " .. loaded)\n')
    if "main" in mods:
        head.append("-- main body, run last\n" + mods["main"] + "\n")

    head.append(GATE_CHECKS)
    return "".join(head)


GATE_CHECKS = r'''
-- fire every callback the menu registered, on and off, and report failures.
-- A callback that errors is a real bug: it is what a user clicks.
local fired, failed = 0, 0
for _, el in ipairs(EXERCISE) do
    if el.callback then
        local values = { true, false }
        if el.method == "CreateSlider" then values = { 50, 17 } end
        if el.method == "CreateDropdown" then values = { "Golden Apple", "Crowbar 3 (golden)", "Phone (hacker)" } end
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

-- module-level self checks: cheap assertions the source itself can state
local problems = 0
local okItems, Items = pcall(require, "features/items")
if okItems and Items.check_catalog then
    for _, msg in ipairs(Items.check_catalog()) do
        problems += 1
        print("CATALOG: " .. msg)
    end
    print("items catalogue: " .. #Items.catalog .. " entries")

    -- end-to-end item checks against the stub server, because "did the object
    -- actually arrive" is the bug class that shipped, not a syntax error.
    -- They run in a coroutine: the item flows call task.wait, and the Luau CLI
    -- forbids yielding from a main chunk.
    local flow = coroutine.create(function()
        local sample = { "BloxyCola", "Bottle", "Crowbar3", "Bat", "Key", "Ladder", "GoldenApple" }
        local failures = 0
        for _, id in ipairs(sample) do
            local ok, how = Items.obtain(id, 1.2)
            if not ok or not Items.has(id) then
                failures += 1
                print(string.format("ITEM FAIL %s: %s", id, tostring(how)))
            end
        end
        print(string.format("items end-to-end: %d/%d obtained", #sample - failures, #sample))

        local before = Items.count_of("Cookie")
        local fired, gained = Items.stack("Cookie", 5)
        if Items.count_of("Cookie") - before < 3 then
            print(string.format("STACK FAIL: fired=%d gained=%d", fired, gained))
            return failures + 1
        end
        print(string.format("stack: %d fired, %d added", fired, gained))

        local healed = Items.heal_self()
        print("heal_self: " .. tostring(healed))

        -- every weapon, not just one: that was the reported bug
        local weaponIds = {}
        for _, entry in ipairs(Items.catalog) do
            if entry.group == "armas" then table.insert(weaponIds, entry.id) end
        end
        local weaponFails = 0
        for _, id in ipairs(weaponIds) do
            local ok = Items.obtain(id, 1.0)
            if not ok then
                weaponFails += 1
                print("WEAPON FAIL " .. id)
            end
        end
        print(string.format("weapons: %d/%d obtained, vending variant=%s",
            #weaponIds - weaponFails, #weaponIds, tostring(Items.weapon_variant)))
        failures += weaponFails

        -- semi godmode: no heal above the floor, one heal below it
        local hum = Net.humanoid()
        if hum then
            hum.Health = hum.MaxHealth
            -- the menu callbacks above ran with 50/17 on every slider, so the
            -- floor is whatever the last callback left it at. Pin it here.
            Items.god.floor = 60
            local healedAboveFloor = Items.god_tick()
            hum.Health = 20
            Items.god.enabled = true
            local healedBelowFloor = Items.god_tick()

            Items.god.enabled = false
            print(string.format("god: above-floor=%s below-floor=%s",
                tostring(healedAboveFloor), tostring(healedBelowFloor)))
            if healedAboveFloor or not healedBelowFloor then failures += 1 end
        else
            failures += 1
            print("GOD FAIL: no humanoid")
        end

        -- Twado: read the want, feed it
        local Pet = require("features/pet")
        local wants = Pet.wants()
        print("twado wants: " .. (#wants > 0 and table.concat(wants, ",") or "nothing"))
        if #wants == 0 then
            failures += 1
            print("PET FAIL: want not detected")
        else
            local fed, why = Pet.try_feed()
            print("twado feed: " .. tostring(fed) .. " (" .. tostring(why) .. ")")
            if not fed then failures += 1 end
        end
        return failures
    end)

    local result = 0
    -- the scheduler burns clock time, so this loop needs a real time budget
    local started = os.clock()
    while coroutine.status(flow) == "suspended" and (os.clock() - started) < 120 do
        local ok, value = coroutine.resume(flow)
        if not ok then
            print("ITEM FLOW ERROR: " .. tostring(value))
            result = 1
            break
        end
        if coroutine.status(flow) == "dead" and type(value) == "number" then result = value end
    end
    if coroutine.status(flow) ~= "dead" then
        print("ITEM FLOW TIMEOUT")
        result = result + 1
    end
    problems += result
else
    problems += 1
    print("CATALOG: items module did not load")
end

print("GATE " .. (failed == 0 and problems == 0 and "OK" or "FAILED"))
'''


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

    parts = emit_parts(mods)
    # clear stale parts so a shrinking build cannot leave an orphan behind
    if os.path.isdir(PARTS_DIR):
        for stale in os.listdir(PARTS_DIR):
            if stale.endswith(".lua"):
                os.remove(os.path.join(PARTS_DIR, stale))
    for i, bodies in enumerate(parts, 1):
        write(os.path.join(PARTS_DIR, "p%d.lua" % i), part_file(i, bodies))

    readable = readable_bundle(mods)
    write(os.path.join(DIST, "breakin2.lua"), readable)
    dig = hashlib.sha256(readable.encode("utf-8")).hexdigest()[:16]
    print("bundle   dist/breakin2.lua  %d bytes  modules=%d  parts=%d  sha=%s"
          % (len(readable), len(mods), len(parts), dig))

    if "--check" in sys.argv:
        return 0

    write(os.path.join(OUT, "gate.luau"), gate(mods))
    print("gate     build/out/gate.luau")
    return 0


if __name__ == "__main__":
    sys.exit(main())
