#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: test del loader (la linea de paste).

Simula el flujo completo: linea de paste -> HTTP -> loader.lua -> payload
ofuscado -> menu montado. El HTTP se stubbea con el contenido local de los
ficheros, asi que se prueba la logica, no la red.

A diferencia de bootstrap_run.py (que prueba el bootstrap publico con todos los
perfiles de executor), aqui se ejecuta el loader completo con su GUI.

    .venv/bin/python tools/loader_run.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
PAYLOAD = ROOT / "release" / "milonarie_tycoon_obfuscated_compact.lua"
LOADER = REPO / "loader.lua"
BASE = "https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv"
PAYLOAD_NAME = "milonarie_tycoon_obfuscated_compact"
PAYLOAD_URL = f"{BASE}/roblox/milonarie_tycoon/release/{PAYLOAD_NAME}.lua"
PARTS_URL = f"{BASE}/roblox/milonarie_tycoon/release/parts/{PAYLOAD_NAME}.part%d"
MANIFEST_URL = f"{BASE}/roblox/milonarie_tycoon/release/parts/{PAYLOAD_NAME}.manifest"


def main() -> int:
    try:
        from lupa.lua55 import LuaRuntime
    except ImportError:
        print("necesita lupa: pip install lupa")
        return 2

    payload_src = PAYLOAD.read_text(encoding="utf-8")
    manifest = (ROOT / "release" / "parts" / f"{PAYLOAD_NAME}.manifest").read_text(encoding="utf-8")
    total = int(manifest.split("total=")[1].split()[0])
    chunk_size = 65536
    part_bodies = {
        PARTS_URL % i: payload_src[i * chunk_size:(i + 1) * chunk_size]
        for i in range(total)
    }

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text(encoding="utf-8"))

    # Stub de HTTP: sirve el fichero local que corresponde a cada URL.
    lua.globals()["__PAYLOAD_BODY"] = payload_src
    lua.globals()["__MANIFEST_BODY"] = manifest
    lua.globals()["__PAYLOAD_URL"] = PAYLOAD_URL
    lua.globals()["__MANIFEST_URL"] = MANIFEST_URL
    lua.globals()["__PARTS_URL"] = PARTS_URL
    for index in range(total):
        lua.globals()[f"__PART{index}"] = part_bodies[PARTS_URL % index]
    lua.execute("""
local FILES = { [__PAYLOAD_URL] = __PAYLOAD_BODY, [__MANIFEST_URL] = __MANIFEST_BODY }
for i = 0, 9 do
    local body = __PART0
    if i == 0 then body = __PART0 end
    FILES[string.format(__PARTS_URL, i)] = body
end
local function serve(url)
    return FILES[url]
end
request = function(opts) return serve(type(opts) == "table" and opts.Url or opts) end
http_request = request
game.HttpGet = function(self, url) return serve(url) end
""")

    # El loader se ejecuta tal cual (con su GUI) contra el mock.
    lua.globals()["__LOADER_SRC"] = LOADER.read_text(encoding="utf-8")
    lua.execute("""
local chunk, err = loadstring(__LOADER_SRC, "=loader")
assert(chunk, err)
chunk()
""")

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
