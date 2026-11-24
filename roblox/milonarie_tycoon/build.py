#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: build.

Concatena src/ en un unico archivo pegable para executor.

    python3 build.py            # build
    python3 build.py --check    # build + syntax check (necesita lupa)
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "src"
OUT = ROOT / "dist" / "milonarie_tycoon.lua"

ORDER = [
    "config.lua",
    "util.lua",
    "remotes.lua",
    "farm.lua",
    "move.lua",
    "ui.lua",
    "main.lua",
]

HEADER = """--[[
	Aero :: Milonarie Tycoon exploit (single file build)

	Generado por build.py -- no editar a mano, editar src/ y rebuildar.
	Uso: pegarlo en el executor con el juego abierto.

	Flow: el spy captura la forma real de los argumentos que el juego manda por
	los remotes, y el farm hace replay de esos argumentos. Si el auto-bind no
	pilla el remote correcto, se liga a mano en la tab TARGET.
]]
"""


def build() -> str:
    chunks = [HEADER]
    for name in ORDER:
        text = (SRC / name).read_text(encoding="utf-8").rstrip()
        bar = "=" * max(4, 64 - len(name))
        # Cada modulo va en su propio bloque: los `local` de un modulo no pisan
        # los de otro (Prometheus avisaba de "variable already defined in scope").
        chunks.append(f"-- ===== {name} {bar}\ndo\n{text}\nend\n")
    body = "\n".join(chunks)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(body, encoding="utf-8")
    return body


def check(body: str) -> int:
    try:
        from lupa import LuaRuntime
    except ImportError:
        print("lupa no instalado -> pip install lupa (o .venv/bin/python build.py --check)")
        return 2
    lua = LuaRuntime(unpack_returned_tuples=True)
    problems = 0
    for name in ORDER + ["dist"]:
        source = body if name == "dist" else (SRC / name).read_text(encoding="utf-8")
        try:
            lua.compile(source)
        except Exception as exc:  # lupa.LuaError
            print(f"SYNTAX ERROR in {name}:\n{exc}")
            problems += 1
    if problems == 0:
        print("syntax ok (dist + %d modulos)" % len(ORDER))
    return 1 if problems else 0


if __name__ == "__main__":
    body = build()
    print(f"built {OUT} ({len(body.encode('utf-8'))} bytes)")
    if "--check" in sys.argv:
        sys.exit(check(body))
