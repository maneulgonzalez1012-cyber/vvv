#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: prueba del bootstrap publico.

Simula el flujo completo tal y como lo ve el executor:

    linea de paste -> HTTP -> payload ofuscado -> menu montado

Lo importante es que se prueban TODAS las firmas de HTTP que usan los
executors, porque cada uno expone el GET de otra forma:

    request({Url=,Method=})        -> string
    request({Url=,Method=})        -> {Body=,StatusCode=}
    request({Url=,Method=})        -> (body, ok, code)
    http_request(url)              -> string
    http_request(url)              -> (body, ok, code)
    syn.request({Url=,Method=})    -> string
    syn.request({Url=,Method=})    -> (body, ok, code)
    http.request({Url=,Method=})   -> {Body=,StatusCode=}
    game:HttpGet(url)              -> string
    game:HttpGet ausente           -> caso Athena ("no es un miembro de DataModel")

El caso "game:HttpGet ausente" es el que rompia la linea de paste publicada:
Athena lanza "HttpGet is not a valid member of DataModel" al indexarlo.

Ademas se prueba el respaldo por partes (body recortado por el executor).

    .venv/bin/python tools/bootstrap_run.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
PAYLOAD = ROOT / "release" / "milonarie_tycoon_obfuscated_compact.lua"
BOOTSTRAP = REPO / "bootstrap.lua"
PASTE_LINE_FILE = ROOT / "release" / "paste_line.txt"
BASE = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv"
PAYLOAD_NAME = "milonarie_tycoon_obfuscated_compact"
PAYLOAD_URL = f"{BASE}/roblox/milonarie_tycoon/release/{PAYLOAD_NAME}.lua"
LOADER_URL = f"{BASE}/loader.lua"
PARTS_URL = f"{BASE}/roblox/milonarie_tycoon/release/parts/{PAYLOAD_NAME}.part%d"
MANIFEST_URL = f"{BASE}/roblox/milonarie_tycoon/release/parts/{PAYLOAD_NAME}.manifest"

# (nombre, codigo Lua que define las funciones HTTP del executor)
PROFILES = [
    ("request -> string", """
request = function(opts) return __serve(opts and opts.Url or opts) end
"""),
    ("request -> {Body,StatusCode}", """
request = function(opts) return { Body = __serve(opts.Url), StatusCode = 200 } end
"""),
    ("request -> (body, ok, code)", """
request = function(opts) return __serve(opts.Url), true, 200 end
"""),
    ("http_request(url) -> string", """
http_request = function(url) return __serve(url) end
"""),
    ("http_request(url) -> (body, ok, code)", """
http_request = function(url) return __serve(url), true, 200 end
"""),
    ("syn.request -> string", """
syn = { request = function(opts) return __serve(opts.Url) end }
"""),
    ("syn.request -> (body, ok, code)", """
syn = { request = function(opts) return __serve(opts.Url), true, 200 end }
"""),
    ("http.request -> {Body,StatusCode}", """
http = { request = function(opts) return { Body = __serve(opts.Url), StatusCode = 200 } end }
"""),
    ("solo game:HttpGet", """
game.HttpGet = function(self, url) return __serve(url) end
"""),
    ("ATHENA: sin HttpGet, solo request", """
request = function(opts) return __serve(opts.Url) end
game.HttpGet = nil
"""),
    ("ATHENA: sin HttpGet, solo syn.request", """
syn = { request = function(opts) return __serve(opts.Url), true, 200 end }
game.HttpGet = nil
"""),
    ("ATHENA: sin HttpGet, solo http.request", """
http = { request = function(opts) return { Body = __serve(opts.Url), StatusCode = 200 } end }
game.HttpGet = nil
"""),
]


def build_lua(lua, bodies: dict) -> None:
    lua.globals()["__BODIES"] = lua.table_from(bodies)
    lua.execute("""
__serve = function(url) return __BODIES[url] end
""")


def run_case(lua, label: str, source: str, profile_code: str, bodies: dict,
             truncate: int = 0, expect_menu: bool = True):
    """Ejecuta un chunk de bootstrap y devuelve (fallo, mensaje)."""
    served = dict(bodies)
    if truncate:
        # El executor recorta el body: el payload llega incompleto.
        served[PAYLOAD_URL] = served[PAYLOAD_URL][:truncate]
    build_lua(lua, served)
    lua.execute(profile_code)
    lua.globals()["__SRC"] = source
    lua.execute("""
local chunk, err = loadstring(__SRC, "=bootstrap")
assert(chunk, err)
__RUN = function() chunk() end
""")
    failure = lua.execute("""
local ok, e = pcall(__RUN)
if ok then return nil end
return tostring(e)
""")
    if failure:
        return failure
    if expect_menu:
        mounted = lua.execute("""
local A = Mock.namespace()
return A ~= nil and A.ui ~= nil and A.ui.root ~= nil
""")
        if not mounted:
            return "el payload corrio pero el menu no se monto"
    return None


def main() -> int:
    try:
        from lupa.lua55 import LuaRuntime
    except ImportError:
        print("necesita lupa: pip install lupa")
        return 2

    mock = (ROOT / "tools" / "roblox_mock.lua").read_text(encoding="utf-8")
    payload_src = PAYLOAD.read_text(encoding="utf-8")
    bootstrap_src = BOOTSTRAP.read_text(encoding="utf-8")
    paste_line = PASTE_LINE_FILE.read_text(encoding="utf-8").strip()

    manifest = (ROOT / "release" / "parts" / f"{PAYLOAD_NAME}.manifest").read_text(encoding="utf-8")
    total = int(manifest.split("total=")[1].split()[0])
    chunk_size = 65536
    part_bodies = {
        PARTS_URL % i: payload_src[i * chunk_size:(i + 1) * chunk_size]
        for i in range(total)
    }

    # El loader se sirve como cuerpo HTTP: el bootstrap lo descarga y lo ejecuta,
    # y el loader a su vez baja el payload (con respaldo por partes).
    loader_src = (REPO / "loader.lua").read_text(encoding="utf-8")

    cases = [
        ("bootstrap.lua", bootstrap_src),
        ("linea de paste", paste_line),
    ]

    failures = []
    checked = 0
    for label, source in cases:
        for profile_name, profile_code in PROFILES:
            lua = LuaRuntime(unpack_returned_tuples=True)
            lua.execute(mock)
            failure = run_case(
                lua, label, source, profile_code,
                {
                    LOADER_URL: loader_src,
                    PAYLOAD_URL: payload_src,
                    MANIFEST_URL: manifest,
                    **part_bodies,
                },
            )
            checked += 1
            if failure:
                failures.append(f"{label} [{profile_name}]: {failure}")
                print(f"FAIL  {label} [{profile_name}] -> {failure}")
            else:
                print(f"PASS  {label} [{profile_name}]")

    # Respaldo por partes: el body del payload llega recortado.
    for label, source in cases:
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(mock)
        failure = run_case(
            lua, label, source,
            "request = function(opts) return __serve(opts.Url) end\ngame.HttpGet = nil\n",
            {
                LOADER_URL: loader_src,
                PAYLOAD_URL: payload_src,
                MANIFEST_URL: manifest,
                **part_bodies,
            },
            truncate=1000,
        )
        checked += 1
        if failure:
            failures.append(f"{label} [body recortado]: {failure}")
            print(f"FAIL  {label} [body recortado] -> {failure}")
        else:
            print(f"PASS  {label} [body recortado]")

    print()
    if failures:
        print(f"{len(failures)} fallo(s) de {checked}")
        return 1
    print(f"bootstrap run: {checked} casos ok ({len(PROFILES)} perfiles de executor)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
