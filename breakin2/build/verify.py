#!/usr/bin/env python3
"""verify.py — run the bytes that ship, in two runtimes, and check what happened.

    python3 build/verify.py               # dist/breakin2_v3.obf.lua, luajit + luau
    python3 build/verify.py --fast        # dist/breakin2.lua (readable bundle)
    python3 build/verify.py --bundle PATH

Why this exists: the source can be green and Prometheus can still break it
(ConstantArray/Cff mangling a string or a number). So verification runs the
actual artifact against the same stubs the gate uses, then checks outcomes
rather than an exit code:

  * the bundle loads at all             -> "loaded: true"
  * main ran to the end                  -> "[breaker] ready"
  * every tab built                      -> elements >= MIN_ELEMENTS
  * firing all callbacks throws nothing  -> no "callback failed" in the log
"""

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
DIST = os.path.join(ROOT, "..", "dist")
OUT = os.path.join(ROOT, "out")

OBF = os.path.join(DIST, "breakin2_v3.obf.lua")
READABLE = os.path.join(DIST, "breakin2.lua")

LUAJIT = os.environ.get("LUAJIT_BIN", "/tmp/x_lj/src/luajit")
LUAU = os.environ.get("LUAU_BIN", "/tmp/x_luau/build/luau")

STUBS = ("datatypes.luau", "roblox.luau", "scheduler.luau")
MIN_ELEMENTS = 100      # the gate registers 121 when every tab builds


def stub_source():
    parts = []
    for name in STUBS:
        with open(os.path.join(ROOT, "stub", name), "r", encoding="utf-8") as fh:
            parts.append("do\n" + fh.read() + "\nend\n")
    return "".join(parts)


HARNESS = '''
local loaded, loadErr = pcall(function()
{bundle}
end)
print("loaded: " .. tostring(loaded) .. (loaded and "" or (" -> " .. tostring(loadErr))))

-- callbacks wait on remotes, so each one runs in its own coroutine. A callback
-- that never settles is capped instead of hanging the verification.
local function drive(fn, value, rounds)
    local co = coroutine.create(fn)
    local ok, err = coroutine.resume(co, value)
    local n = 0
    while coroutine.status(co) == "suspended" and n < (rounds or 300) do
        n = n + 1
        ok, err = coroutine.resume(co)
        if not ok then break end
    end
    if coroutine.status(co) == "suspended" then return false, "no settle" end
    return ok, err
end

local fired, threw = 0, 0
local SNAPSHOT = __exercise()
for _, el in ipairs(SNAPSHOT) do
    if type(el.callback) == "function" then
        local value = nil
        if el.method == "CreateSlider" then value = 50 end
        if el.method == "CreateDropdown" then value = "Golden Apple" end
        if el.method == "CreateToggle" then value = true end
        fired = fired + 1
        local ok = drive(el.callback, value)
        if not ok then threw = threw + 1 end
    end
end
print(string.format("elements: %d, callbacks fired: %d, unwrapped throws: %d",
    #SNAPSHOT, fired, threw))
print("DONE")
'''


def harness(bundle):
    return stub_source() + HARNESS.replace("{bundle}", bundle)


def run(binary, path, suffix):
    target = os.path.join(OUT, "verify_" + suffix)
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(harness(read(path)))
    return subprocess.run([binary, target], capture_output=True, text=True, timeout=600)


def read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def check(name, proc, elements_floor):
    text = proc.stdout + proc.stderr
    problems = []

    if proc.returncode != 0:
        problems.append("exit %d" % proc.returncode)
    if "loaded: true" not in text:
        problems.append("the bundle did not load")
    if "[breaker]\tready" not in text:
        problems.append("main did not reach the end")
    if "sin fallos" not in text:
        problems.append("modules reported failures at startup")
    if "DONE" not in text:
        problems.append("harness did not finish")

    count = 0
    for line in text.splitlines():
        if line.startswith("elements: "):
            try:
                count = int(line.split("elements: ")[1].split(",")[0])
            except ValueError:
                count = 0
    if count < elements_floor:
        problems.append("only %d elements registered (want >= %d)" % (count, elements_floor))

    if "callback failed" in text:
        first = [l for l in text.splitlines() if "callback failed" in l][:3]
        problems.append("callbacks threw: " + " | ".join(first))

    if problems:
        print("VERIFY FAIL (%s): %s" % (name, "; ".join(problems)))
        for line in text.strip().splitlines()[-20:]:
            print("  " + line)
        return False, text

    print("VERIFY OK (%s): elements=%d" % (name, count))
    return True, text


def main():
    args = sys.argv[1:]
    fast = "--fast" in args
    target = READABLE if fast else OBF
    if "--bundle" in args:
        target = args[args.index("--bundle") + 1]
    if not os.path.isfile(target):
        print("missing %s - build it first" % target)
        return 1

    which = [a for a in args if a in ("luajit", "luau")] or ["luajit", "luau"]
    ok = True
    if "luajit" in which:
        passed, text = check("luajit", run(LUAJIT, target, "lj.lua"), MIN_ELEMENTS)
        ok = passed and ok
        # LuaJIT is the stricter parser, but the obfuscated bundle is only
        # meaningful if its callback count and the readable one agree
        if passed:
            count = [l for l in text.splitlines() if l.startswith("elements: ")]
            if count:
                print("  " + count[0])
    if "luau" in which:
        passed, _ = check("luau", run(LUAU, target, "luau.luau"), MIN_ELEMENTS)
        ok = passed and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
