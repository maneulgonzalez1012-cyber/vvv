#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: E2E contra los ficheros PUBLICADOS.

Simula el executor Athena (sin game:HttpGet) sirviendo los ficheros tal y
como los sirve raw.githubusercontent.com: loader, payload, manifest y partes.

Comprueba tres escenarios:
    1. flujo normal con la linea de paste publica
    2. el executor recorta el body del payload -> respaldo por partes
    3. control negativo: la linea ANTIGUA (solo game:HttpGet) debe fallar

Los cuerpos salen de una carpeta con los ficheros ya descargados del raw:

    gh api -H "Accept: application/vnd.github.raw" \\
        repos/OWNER/REPO/contents/loader.lua?ref=BRANCH > loader.lua
    .venv/bin/python tools/e2e_athena.py /tmp/e2e

    .venv/bin/python tools/e2e_athena.py --download
"""
import argparse
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
MOCK = ROOT / "tools" / "roblox_mock.lua"

OWNER = "maneulgonzalez1012-cyber"
REPO_NAME = "vvv"
BRANCH = "arena/5e9deb5f-vvv"
BASE = f"https://raw.githubusercontent.com/{OWNER}/{REPO_NAME}/{BRANCH}"
NAME = "milonarie_tycoon_obfuscated_compact"
PAYLOAD_URL = f"{BASE}/roblox/milonarie_tycoon/release/{NAME}.lua"
MANIFEST_URL = f"{BASE}/roblox/milonarie_tycoon/release/parts/{NAME}.manifest"
PARTS_URL = f"{BASE}/roblox/milonarie_tycoon/release/parts/{NAME}.part%d"
LOADER_URL = f"{BASE}/loader.lua"

# Ficheros que hay que traer del raw y donde se guardan en local.
FILES = {
    "loader.lua": f"repos/{OWNER}/{REPO_NAME}/contents/loader.lua?ref={BRANCH}",
    "bootstrap.lua": f"repos/{OWNER}/{REPO_NAME}/contents/bootstrap.lua?ref={BRANCH}",
    "paste_line.txt": f"repos/{OWNER}/{REPO_NAME}/contents/roblox/milonarie_tycoon/release/paste_line.txt?ref={BRANCH}",
    "compact.lua": f"repos/{OWNER}/{REPO_NAME}/contents/roblox/milonarie_tycoon/release/{NAME}.lua?ref={BRANCH}",
    "manifest.txt": f"repos/{OWNER}/{REPO_NAME}/contents/roblox/milonarie_tycoon/release/parts/{NAME}.manifest?ref={BRANCH}",
}
CHUNK = 65536

OLD_PASTE_LINE = f'loadstring(game:HttpGet("{LOADER_URL}"))()'


def download(work: pathlib.Path) -> None:
    work.mkdir(parents=True, exist_ok=True)
    for local, api in FILES.items():
        proc = subprocess.run(
            ["gh", "api", "-H", "Accept: application/vnd.github.raw", api],
            capture_output=True, text=True, check=True,
        )
        (work / local).write_text(proc.stdout, encoding="utf-8")
        print(f"descargado {local} ({len(proc.stdout.encode('utf-8'))} bytes)")

    manifest = (work / "manifest.txt").read_text(encoding="utf-8")
    total = int(manifest.split("total=")[1].split()[0])
    for index in range(total):
        api = f"repos/{OWNER}/{REPO_NAME}/contents/roblox/milonarie_tycoon/release/parts/{NAME}.part{index}?ref={BRANCH}"
        proc = subprocess.run(
            ["gh", "api", "-H", "Accept: application/vnd.github.raw", api],
            capture_output=True, text=True, check=True,
        )
        (work / f"part{index}.bin").write_text(proc.stdout, encoding="utf-8")
        print(f"descargado part{index}.bin ({len(proc.stdout.encode('utf-8'))} bytes)")


def build_bodies(work: pathlib.Path) -> tuple[dict, str]:
    payload = (work / "compact.lua").read_text(encoding="utf-8")
    manifest = (work / "manifest.txt").read_text(encoding="utf-8")
    total = int(manifest.split("total=")[1].split()[0])
    parts = {
        PARTS_URL % i: (work / f"part{i}.bin").read_text(encoding="utf-8")
        for i in range(total)
    }
    bodies = {
        LOADER_URL: (work / "loader.lua").read_text(encoding="utf-8"),
        PAYLOAD_URL: payload,
        MANIFEST_URL: manifest,
        **parts,
    }
    return bodies, manifest


def make_lua():
    from lupa.lua55 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK.read_text(encoding="utf-8"))
    return lua


ATHENA_ENV = """
__serve = function(url) return __BODIES[url] end
-- ATHENA: request existe y devuelve una TABLA. game:HttpGet NO existe.
request = function(opts)
    local body = __serve(opts and opts.Url or opts)
    if not body then return { Body = "", StatusCode = 404 } end
    return { Body = body, StatusCode = 200 }
end
http_request = nil
syn = nil
http = nil
game.HttpGet = nil
"""


def run_paste(lua, paste: str, bodies: dict, truncate_payload: bool = False):
    served = dict(bodies)
    if truncate_payload:
        served[PAYLOAD_URL] = served[PAYLOAD_URL][:500]
    lua.globals()["__BODIES"] = lua.table_from(served)
    lua.execute(ATHENA_ENV)
    lua.globals()["__PASTE"] = paste
    return lua.execute("""
local chunk, err = loadstring(__PASTE, "=paste")
if not chunk then return "la linea no compila: " .. tostring(err) end
local ok, e = pcall(chunk)
if ok then return nil end
return tostring(e)
""")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--download", action="store_true",
                        help="trae los ficheros del raw con gh api antes de probar")
    parser.add_argument("--work", default="/tmp/e2e")
    args = parser.parse_args()

    work = pathlib.Path(args.work)
    if args.download:
        download(work)

    missing = [name for name in FILES if not (work / name).is_file()]
    if missing:
        print(f"faltan ficheros en {work}: {', '.join(missing)} (usa --download)")
        return 2

    bodies, manifest = build_bodies(work)
    paste = (work / "paste_line.txt").read_text(encoding="utf-8").strip()

    # Integridad: las partes publicadas deben concatenar al payload publicado.
    rejoined = "".join(bodies[PARTS_URL % i] for i in range(int(manifest.split("total=")[1].split()[0])))
    if rejoined != bodies[PAYLOAD_URL]:
        print("FAIL  las partes publicadas no concatenan al payload")
        return 1
    print("PASS  partes publicadas == payload publicado")

    failures = []

    # 1) flujo normal en Athena
    lua = make_lua()
    failure = run_paste(lua, paste, bodies)
    if failure:
        failures.append(f"flujo normal: {failure}")
        print(f"FAIL  flujo normal -> {failure}")
    else:
        mounted = lua.execute("local A = Mock.namespace() return A ~= nil and A.ui ~= nil and A.ui.root ~= nil")
        if not mounted:
            failures.append("flujo normal: el menu no se monto")
            print("FAIL  flujo normal -> el menu no se monto")
        else:
            print("PASS  flujo normal en Athena (sin game:HttpGet) -> menu montado")

    # 2) body recortado -> respaldo por partes
    lua = make_lua()
    failure = run_paste(lua, paste, bodies, truncate_payload=True)
    if failure:
        failures.append(f"body recortado: {failure}")
        print(f"FAIL  body recortado -> {failure}")
    else:
        print("PASS  body recortado -> respaldo por partes -> menu montado")

    # 3) control negativo: la linea antigua debe morir en Athena
    lua = make_lua()
    lua.globals()["__BODIES"] = lua.table_from(bodies)
    lua.execute(ATHENA_ENV)
    lua.globals()["__OLD"] = OLD_PASTE_LINE
    old_result = lua.execute("""
local chunk = loadstring(__OLD)
if not chunk then return "no compila" end
local ok, e = pcall(chunk)
if ok then return "NO FALLO" end
return tostring(e)
""")
    if old_result == "NO FALLO":
        failures.append("control negativo: la linea antigua deberia fallar")
        print("FAIL  control negativo -> la linea antigua NO fallo")
    else:
        print(f"PASS  control negativo (linea antigua falla: {old_result})")

    print()
    if failures:
        print(f"{len(failures)} fallo(s)")
        return 1
    print("e2e athena: todo ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
