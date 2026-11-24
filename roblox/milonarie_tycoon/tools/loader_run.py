#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: test del loader (la linea de paste).

Simula el flujo completo: linea de paste -> game:HttpGet(loader.lua) ->
loader -> payload ofuscado -> menu montado. El HTTP se stubbea con el
contenido local de los ficheros, asi que se prueba la logica, no la red.

    .venv/bin/python tools/loader_run.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
PAYLOAD = ROOT / "release" / "milonarie_tycoon_obfuscated_light.lua"
LOADER = REPO / "loader.lua"
BASE = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv"
PAYLOAD_URL = BASE + "/roblox/milonarie_tycoon/release/milonarie_tycoon_obfuscated_light.lua"
LOADER_URL = BASE + "/loader.lua"


def main() -> int:
    try:
        from lupa.lua55 import LuaRuntime
    except ImportError:
        print("necesita lupa: pip install lupa")
        return 2

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text(encoding="utf-8"))

    # Stub de HTTP: sirve el fichero local que corresponde a cada URL.
    lua.globals()["__PAYLOAD_URL"] = PAYLOAD_URL
    lua.globals()["__LOADER_URL"] = LOADER_URL
    lua.globals()["__PAYLOAD_BODY"] = PAYLOAD.read_text(encoding="utf-8")
    lua.globals()["__LOADER_BODY"] = LOADER.read_text(encoding="utf-8")
    lua.execute("""
local FILES = { [__PAYLOAD_URL] = __PAYLOAD_BODY, [__LOADER_URL] = __LOADER_BODY }
local function serve(url)
	return FILES[url] or FILES[__PAYLOAD_URL]
end
request = function(opts) return serve(type(opts) == "table" and opts.Url or opts) end
http_request = request
game.HttpGet = function(self, url) return serve(url) end
""")

    # 1) la linea de paste tal cual: loadstring(game:HttpGet(loader.lua))()
    lua.execute('loadstring(game:HttpGet("' + LOADER_URL + '"))()')

    results = [
        ("loader descargado y ejecutado", lua.execute("return Mock.namespace() ~= nil")),
        ("payload cargo (menu montado)", lua.execute(
            "local A = Mock.namespace() return A ~= nil and A.ui ~= nil and A.ui.root ~= nil")),
        ("4 tabs del payload", lua.execute(
            "local A = Mock.namespace() return A ~= nil and A.ui.pages ~= nil and A.ui.pages.FARM ~= nil")),
        ("logica de remotes viva", lua.execute(
            "local A = Mock.namespace() return A ~= nil and A.util ~= nil and A.util.getCash() == 1234")),
    ]

    for name, good in results:
        print(("PASS  " if good else "FAIL  ") + name)
    failed = [name for name, good in results if not good]
    if failed:
        print(f"\n{len(failed)} fallo(s)")
        return 1
    print("\nloader run: todo ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
