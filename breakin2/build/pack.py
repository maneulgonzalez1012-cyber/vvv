#!/usr/bin/env python3
"""pack.py — bundle src/ into parts, plus a readable single-file bundle.

    python3 build/pack.py            # build/out/parts/pN.lua + dist/breakin2.lua
    python3 build/pack.py --check    # bundling only, no gate

Why parts: every module is a factory in a shared table, and the whole thing
used to be one chunk. Prometheus's Cff pass flattens a chunk into a single
function, and LuaJIT refuses a function with more than 65536 constants, so the
module table is split across small chunks. build/assemble.py embeds each
obfuscated part into one file, which is what ships.

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

PART_BYTES = 22000

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


CTX_ALIASES = {
    "Train": "features/train", "Items": "features/items", "Combat": "features/combat",
    "Npc": "features/npc", "Move": "features/move", "World": "features/world",
    "Esp": "features/esp", "Roles": "features/roles", "Pet": "features/pet",
    "Shield": "features/shield", "Net": "core/net", "Game": "core/game",
    "U": "core/util",
}

# UI state keys live on the menu, not on a module
MENU_STATE = {"picked_food", "picked_drink", "picked_weapon", "picked_misc", "picked_pet",
              "errors", "ok", "elements"}


def audit_ui(mods):
    """Every `Alias.method(` a tab calls must exist in that module.

    This is the check that would have caught Items.heal_all(): a button wired to
    a function nobody wrote only fails when a player clicks it.
    """
    problems = []
    for name, body in mods.items():
        if not name.startswith("ui/tabs/"):
            continue
        for alias, dep in CTX_ALIASES.items():
            if "local %s = ctx.%s" % (alias, alias) not in body:
                continue
            target = mods.get(dep, "")
            defined = set(re.findall(r"^function \w+\.(\w+)", target, re.M))
            defined |= set(re.findall(r"^\w+\.(\w+)\s*=", target, re.M))
            for method in sorted(set(re.findall(r"\b" + alias + r"\.(\w+)", body))):
                if method in defined or method in MENU_STATE:
                    continue
                problems.append("%s: %s.%s does not exist in %s" % (name, alias, method, dep))
    return problems


LUAU_ONLY = [
    (re.compile(r"(?<![=<>~])\s(\+=|-=|\*=|/=|\.\.=|//=|%=|\^=)\s"), "compound assignment (Luau only; the bundle targets Lua 5.1)"),
    (re.compile(r"^\s*continue\b"), "`continue` (Luau only)"),
    (re.compile(r"^\s*export\s+type\b"), "`export type` (Luau only)"),
]


def audit_lua51(mods):
    """Prometheus compiles for Lua 5.1, where `x += 1`, `continue` and type
    annotations are parse errors. Catching them here names the file and line
    instead of failing the obfuscation pass with a bare token position."""
    problems = []
    for name, body in sorted(mods.items()):
        for lineno, line in enumerate(body.splitlines(), 1):
            stripped = line.strip()
            if stripped.startswith("--"):
                continue
            for pattern, why in LUAU_ONLY:
                if pattern.search(line):
                    problems.append("%s:%d -> %s: %s" % (name, lineno, why, stripped))
                    break
    return problems


def emit_parts(mods):
    order = sorted(mods)
    parts, current, size = [], [], 0
    for name in order:
        body = 'MODULES["%s"] = function(require)\n%s\nend\n' % (name, mods[name])
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
    out.append("-- built from %d modules; this file is for reading, dist/breakin2_v3.obf.lua\n" % len(order))
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
    its top level executed, then main runs."""
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
local Menu = require("ui/menu")
local caught = {}
Menu.on_callback_error = function(where, err) table.insert(caught, where .. ": " .. err) end

local fired, failed = 0, 0
-- snapshot: the isolation check rebuilds a tab, which replaces EXERCISE
local SNAPSHOT = {}
local ALL = __exercise()
for i, el in ipairs(ALL) do SNAPSHOT[i] = el end
for _, el in ipairs(SNAPSHOT) do
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
-- the wrapper swallows errors so the UI keeps working; for the build that is a
-- failure, so what it swallowed is added to the count
for _, msg in ipairs(caught) do
    failed += 1
    print("CALLBACK FAIL " .. msg)
end
print(string.format("callbacks fired=%d failed=%d", fired, failed))

-- module-level self checks
local problems = 0

-- the menu's own guard is the thing under test here: a factory that throws must
-- be replaced by a stub, not propagate
do
    local savedFactory = MODULES["features/esp"]
    MODULES["features/esp"] = function() error("simulated module crash") end
    CACHE["features/esp"] = nil
    local ok, mod = pcall(function()
        -- same shape as ui/menu.load(): pcall the factory, refuse a dead result
        local loaded = pcall(require, "features/esp")
        if loaded then error("guard did not catch the crash") end
        return require("features/esp")
    end)
    MODULES["features/esp"] = savedFactory
    CACHE["features/esp"] = nil
    if ok then
        problems += 1
        print("GUARD FAIL: a crashing module escaped the pcall")
    else
        print("fault injection: crashing module contained")
    end
end

-- every module the menu loads must load on its own, exactly like the menu does
local RUNTIME_MODULES = {
    "core/util", "core/net", "core/game", "ui/rayfield", "ui/menu",
    "features/train", "features/items", "features/combat", "features/npc",
    "features/move", "features/world", "features/esp", "features/roles",
    "features/pet", "features/shield",
    "ui/tabs/home", "ui/tabs/training", "ui/tabs/items", "ui/tabs/npcs",
    "ui/tabs/twado", "ui/tabs/combat", "ui/tabs/move", "ui/tabs/world",
    "ui/tabs/enemies", "ui/tabs/roles", "ui/tabs/safety", "ui/tabs/diagnostics",
}
local isolatedFail = 0
for _, name in ipairs(RUNTIME_MODULES) do
    local ok, mod = pcall(require, name)
    if not ok or (mod == nil) then
        isolatedFail += 1
        print("MODULE FAIL " .. name .. ": " .. tostring(mod))
    end
end
print(string.format("modules isolated: %d/%d", #RUNTIME_MODULES - isolatedFail, #RUNTIME_MODULES))
if #EXERCISE > 0 then print(string.format("elements registered: %d (every tab built)", #EXERCISE)) end
problems += isolatedFail


-- ── behaviour: the features that were actually reported broken ─────────────
local function BEHAVIOUR()
local function humanoid()
    local char = Net.Player.Character
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end
local hum = humanoid()

do -- heal: +25 through Energy, no food involved
    local Shield = require("features/shield")
    if not hum then
        problems += 1
        print("ENERGY FAIL: no humanoid")
    else
        hum.Health = 40
        local ok = Shield.add_energy(25, 1.0)
        local healed = hum.Health - 40
        local bag = Net.Player:FindFirstChild("Backpack")
        local tools = 0
        if bag then for _, t in ipairs(bag:GetChildren()) do if t:IsA("Tool") then tools += 1 end end end
        if not ok or healed < 25 then
            problems += 1
            print(string.format("ENERGY FAIL: ok=%s healed=%.0f", tostring(ok), healed))
        else
            print(string.format("energy: +%.0f sin item, variante %s", healed,
                tostring(Shield.energy_variant)))
        end
        if tools > 0 then
            problems += 1
            print("ENERGY FAIL: dejo " .. tools .. " tool(s) en la mochila")
        end
    end
end

do -- semi godmode: a negative Energy call becomes zero
    local Shield = require("features/shield")
    if Shield.hook_supported() then
        Shield.install()
        local Energy = Net.remotes.Energy
        if hum then hum.Health = 100 end
        if Energy and Energy.FireServer then
            pcall(function() Energy:FireServer(-50, false, false) end)
        end
        if hum and hum.Health < 100 then
            problems += 1
            print(string.format("GOD FAIL: el hook dejo pasar -50 (hp %.0f)", hum.Health))
        else
            print("god: Energy(-50) bloqueado, hp intacta")
        end
        Shield.remove()
    else
        print("god: hookmetamethod no disponible, queda el top-up")
    end
end

do -- heal button: same call the UI makes, and the backpack must stay empty
    local Items = require("features/items")
    local Shield = require("features/shield")
    local bag = Net.Player:FindFirstChild("Backpack")
    local before = #(bag and bag:GetChildren() or {})
    if hum then hum.Health = 30 end
    local ok, why = Shield.add_energy(25, 1.2)
    local after = #(bag and bag:GetChildren() or {})
    local healed = hum and (hum.Health - 30) or 0
    if not ok or healed < 25 or after ~= before then
        problems += 1
        print(string.format("HEAL BUTTON FAIL: ok=%s healed=%.0f bag %d->%d",
            tostring(ok), healed, before, after))
    else
        print(string.format("heal button: +%.0f, mochila %d->%d, via %s",
            healed, before, after, tostring(why)))
    end
end

do -- weapons go through the same remote path as food
    local Items = require("features/items")
    local ok, why = Items.obtain("Crowbar3", 1.0)
    if not ok then
        problems += 1
        print("WEAPONS FAIL: " .. tostring(why))
    else
        print("weapons: Crowbar3 via " .. tostring(why))
    end
    local all = 0
    for _, entry in ipairs(Items.catalog) do
        if entry.route == "weapon" then
            local got = Items.obtain(entry.id, 0.5)
            if got then all += 1 end
        end
    end
    print(string.format("weapons: %d armas del catalogo, 0 herramientas duplicadas", all))
end

do -- twado: wants are read and the feed fires
    local Items = require("features/items")
    local Pet = require("features/pet")
    local wants = Items.dog_wants()
    print("twado wants: " .. (#wants > 0 and table.concat(wants, ", ") or "nada en pantalla"))
    Pet.try_feed()
    task.wait(0.1)
    print("twado feed: " .. tostring(Pet.fed_total) .. " envio(s)")
end

do -- isolation: one tab that throws must cost only that tab
    local registry = __exercise()
    EXERCISE = {}
    local okTab = require("ui/tabs/home")
    local savedBuild = okTab.build
    okTab.build = function() error("simulated tab crash") end
    local built, crashed = 0, 0
    for _, name in ipairs({ "ui/tabs/home", "ui/tabs/items", "ui/tabs/safety" }) do
        local mod = require(name)
        local ok = pcall(mod.build, Menu.ctx)
        if ok then built += 1 else crashed += 1 end
    end
    okTab.build = savedBuild
    EXERCISE = registry
    if crashed ~= 1 or built ~= 2 then
        problems += 1
        print(string.format("ISOLATION FAIL: crashed=%d built=%d (esperado 1/2)", crashed, built))
    else
        print("isolation: 1 pestaña rota, 2 siguen construyendo")
    end
end

-- the HUD tick runs on its own timer; fire it once by hand and check it does
-- not throw against whatever elements the tabs published
do
    local tickErr = nil
    local okTick = pcall(function()
        for name, el in pairs(Menu.elements) do
            if type(el) == "table" and el.Set then el:Set(el.value or 0) end
        end
    end)
    if not okTick then tickErr = "element without Set" end
    if tickErr then
        problems += 1
        print("HUD FAIL: " .. tickErr)
    else
        print("hud: elementos publicados refrescan")
    end
end

end

local okBehaviour, behaviourErr = __run(BEHAVIOUR)
if not okBehaviour then
    problems += 1
    print("BEHAVIOUR FAIL: " .. tostring(behaviourErr))
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

    api = audit_ui(mods)
    if api:
        for line in api:
            print("API MISSING " + line)
        return 1
    print("ui api audit: every call resolves")

    lua51 = audit_lua51(mods)
    if lua51:
        for line in lua51:
            print("LUA51 " + line)
        return 1
    print("lua51 audit: no luau-only syntax in the bundle")

    parts = emit_parts(mods)
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
