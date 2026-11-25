#!/usr/bin/env python3
"""
Astral :: build

el repo guarda el proyecto partido en modulos (src/), pero el executor solo
entiende un string. esto concatena todo en Astral.lua: cada modulo queda como
una funcion en una tabla y require() se reescribe a un lookup en esa tabla.
sin ModuleScripts, sin cargar del disco en runtime, sin ofuscar.

uso:  python3 build.py
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "Astral.lua"

# orden de concatenacion: dependencias primero; init al final porque publica
# getgenv().Astral y arranca el loop
FILES = [
    "shared/config",
    "shared/mathx",
    "shared/players",
    "shared/renderer",
    "modules/esp",
    "modules/hitbox",
    "modules/aim",
    "modules/radar",
    "modules/hitdebug",
    "modules/diag",
    "ui/window",
    "init",
]

HEADER = """--[[
\tAstral :: single-file build
\tgenerado por build.py desde src/ - no editar a mano.
\tsource of truth: src/ en el repo.

\tloadstring(game:HttpGet(...))() lo carga;
\tgetgenv().Astral.unload() lo apaga.
]]

local __modules = {}
local __cache = {}

local function __require(id)
\tlocal cached = __cache[id]
\tif cached ~= nil then
\t\treturn cached
\tend

\tlocal factory = __modules[id]
\tif not factory then
\t\terror("[Astral] modulo desconocido: " .. tostring(id), 0)
\tend

\tlocal value = factory()
\t__cache[id] = value
\treturn value
end
"""


def resolve(expr: str, current: str):
    """script.Parent.Parent.shared.mathx desde modules/esp -> shared/mathx"""
    segs = expr.split(".")
    if segs[0] != "script":
        return None
    # init vive en la raiz de src/, no dentro de una carpeta: su "script" ya
    # es el contenedor, asi que no hay nivel propio que descontar
    path = [] if current == "init" else current.split("/")
    base = len(path)
    i = 1
    while i < len(segs) and segs[i] == "Parent":
        base -= 1
        i += 1
        if base < 0:
            return None
    resolved = path[:base] + segs[i:]
    return "/".join(resolved)


def rewrite(body: str, mod_id: str) -> str:
    out = []
    i = 0
    key = "require("
    while True:
        j = body.find(key, i)
        if j == -1:
            out.append(body[i:])
            break
        # ignorar el __require( que hayamos podido dejar
        out.append(body[i:j])
        k = j + len(key)
        # espacios
        while k < len(body) and body[k] in " \t":
            k += 1
        start = k
        while k < len(body) and (body[k].isalnum() or body[k] in "_."):
            k += 1
        expr = body[start:k]
        tail = k
        while tail < len(body) and body[tail] in " \t":
            tail += 1
        if tail < len(body) and body[tail] == ")" and expr:
            target = resolve(expr, mod_id)
            if target:
                out.append('__require("%s")' % target)
            else:
                out.append(body[j:tail + 1])
            i = tail + 1
        else:
            out.append(body[j:j + len(key)])
            i = j + len(key)
    return "".join(out)


def strip_pragma(body: str) -> str:
    if body.startswith("--!nocheck"):
        body = body[len("--!nocheck"):]
        if body.startswith("\r\n"):
            body = body[2:]
        elif body.startswith("\n"):
            body = body[1:]
    return body


def main() -> int:
    parts = [HEADER]
    for mod_id in FILES:
        path = ROOT / "src" / (mod_id + ".luau")
        if not path.exists():
            print("falta %s" % path, file=sys.stderr)
            return 1
        body = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        body = rewrite(strip_pragma(body), mod_id)
        parts.append('__modules["%s"] = function()\n%s\nend\n' % (mod_id, body))

    parts.append('\n-- arranque\nreturn __require("init")\n')
    result = "\n".join(parts)
    OUT.write_text(result, encoding="utf-8")
    print("build ok: %s (%d bytes, %d modulos)" % (OUT.name, len(result), len(FILES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
