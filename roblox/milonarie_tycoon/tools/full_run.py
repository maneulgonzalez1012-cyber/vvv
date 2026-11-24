#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: cobertura completa del payload.

Carga un payload (plano u ofuscado) contra el mock y llama a TODAS las rutas
publicas: remotes, farm, move, config, callbacks de la UI y los bucles.

Se ejecuta en Lua 5.5 a proposito: Lua 5.5 no tiene getfenv/setfenv/unpack/
newproxy, igual que Luau en Roblox. Si el codigo ofuscado usa algo que Luau no
tiene, aqui peta igual que en el juego.

    .venv/bin/python tools/full_run.py
    .venv/bin/python tools/full_run.py --target release/milonarie_tycoon_obfuscated_light.lua
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main() -> int:
    target = ROOT / "dist" / "milonarie_tycoon.lua"
    args = sys.argv[1:]
    strict = "--strict" in args
    if "--target" in args:
        target = pathlib.Path(args[args.index("--target") + 1])
        if not target.is_absolute():
            target = ROOT / target

    try:
        from lupa.lua55 import LuaRuntime
    except ImportError:
        print("necesita lupa: pip install lupa")
        return 2

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text(encoding="utf-8"))
    lua.execute(f"Mock.setStrictEnv({strict and 'true' or 'false'})")
    lua.globals()["__SRC"] = target.read_text(encoding="utf-8")
    lua.execute("Mock.runSource(__SRC)")
    passed, failed, details = lua.execute((ROOT / "tools" / "full_assert.lua").read_text(encoding="utf-8"))

    print(f"target: {target.name}")
    for failure in (details or "").splitlines():
        if failure.strip():
            print("FAIL  " + failure)
    print(f"{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
