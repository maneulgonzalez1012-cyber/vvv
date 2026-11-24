#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: run del build contra el mock de Roblox.

No es el juego real, pero carga el script completo, construye la UI y ejercita
la capa de remotes (captura -> auto-bind -> replay con override). Si esto pasa,
el pegable no reventa ni en el menu ni en la logica de farming.

    .venv/bin/python tools/mock_run.py                 # Lua 5.5 (lupa por defecto)
    .venv/bin/python tools/mock_run.py --runtime lua51 # Lua 5.1 (lupa.lua51)
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
DIST = ROOT / "dist" / "milonarie_tycoon.lua"


def make_runtime(kind: str):
    if kind == "lua51":
        from lupa.lua51 import LuaRuntime
    elif kind == "luajit21":
        from lupa.luajit21 import LuaRuntime
    else:
        from lupa.lua55 import LuaRuntime
    return LuaRuntime(unpack_returned_tuples=True)


def main() -> int:
    runtime = "lua55"
    target = DIST
    args = sys.argv[1:]
    if "--runtime" in args:
        runtime = args[args.index("--runtime") + 1]
    if "--target" in args:
        target = pathlib.Path(args[args.index("--target") + 1])
        if not target.is_absolute():
            target = ROOT / target

    lua = make_runtime(runtime)
    lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text(encoding="utf-8"))
    lua.execute(target.read_text(encoding="utf-8"))
    results = lua.execute((ROOT / "tools" / "mock_assert.lua").read_text(encoding="utf-8"))

    print(f"runtime: {runtime}  target: {target.name}")
    for name in results["failures"]:
        print("FAIL  " + name)
    print(f"{results['passed']} passed, {results['failed']} failed")
    if results["failed"]:
        return 1
    print("mock run: todo ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
