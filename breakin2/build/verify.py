#!/usr/bin/env python3
"""verify.py — run the obfuscated bundle against the Roblox stub.

Prometheus's output is not something to ship on faith: it can fail inside its
own generated runtime before reaching user code. This builds one runner for
LuaJIT (Lua 5.1 semantics, what executors like Synapse and their LuaJIT-based
siblings use) and one for Luau (what Roblox itself runs), and both must print a
success line.

    python3 build/verify.py
    luajit build/out/verify_luajit.lua
    luau   build/out/verify_luau.luau
"""

import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
DIST = ROOT.parent / "dist"
OUT = ROOT / "out"
STUBS = ["datatypes", "roblox", "scheduler"]


def stub_block():
    return "".join(
        "do\n" + (ROOT / "stub" / (name + ".luau")).read_text(encoding="utf-8") + "\nend\n"
        for name in STUBS
    )


def read_bomb(path, name):
    """Embed a file as a long string, picking a bracket level it cannot close."""
    text = path.read_text(encoding="utf-8")
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "%s = [%s[\n%s\n]%s]\n" % (name, eq, text, eq)


def runner(target, interpreter):
    parts = [stub_block()]
    if interpreter == "luajit":
        parts.append("local realLoad = loadstring\n")
        parts.append(read_bomb(target, "SRC"))
        parts.append(
            'local chunk = assert(realLoad(SRC, "@obf"))\n'
            'local ok, err = pcall(chunk)\n'
            'print(ok and "VERIFY OK (luajit)" or ("VERIFY FAIL (luajit): " .. tostring(err)))\n'
            'if not ok then os.exit(1) end\n'
        )
    else:
        # the Luau CLI has no io in a sandbox-safe way, so the source is embedded
        parts.append("local realLoad = load or loadstring\n")
        parts.append(read_bomb(target, "SRC"))
        parts.append(
            'local chunk = assert(realLoad(SRC, "@obf"))\n'
            'local ok, err = pcall(chunk)\n'
            'print(ok and "VERIFY OK (luau)" or ("VERIFY FAIL (luau): " .. tostring(err)))\n'
        )
    return "".join(parts)


def main():
    # an explicit path lets a candidate build be checked before it is promoted
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DIST / "breakin2.obf.lua"
    if not target.exists():
        print("missing", target)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    stem = "" if len(sys.argv) <= 1 else "_" + target.stem
    (OUT / ("verify_luajit%s.lua" % stem)).write_text(runner(target, "luajit"), encoding="utf-8")
    (OUT / ("verify_luau%s.luau" % stem)).write_text(runner(target, "luau"), encoding="utf-8")
    print("wrote build/out/verify_luajit%s.lua and build/out/verify_luau%s.luau" % (stem, stem))
    return 0


if __name__ == "__main__":
    sys.exit(main())
