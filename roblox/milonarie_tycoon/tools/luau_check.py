#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: verificacion con el binario de Luau real.

Concatena mock + payload + asserts y lo ejecuta con `luau` (no con Lua).
Luau es el runtime real de Roblox: no tiene debug.getinfo, string.dump, load()
ni _ENV, y su _G es read-only. Un payload que pasa aqui funciona en el juego.

    luau tools/luau_harness.lua dist/milonarie_tycoon.lua

Este script hace lo mismo pero desde python, para CI y para los builds
ofuscados:

    .venv/bin/python tools/luau_check.py
    .venv/bin/python tools/luau_check.py --target release/milonarie_tycoon_obfuscated.lua
"""
import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
LUAU = shutil.which("luau") or "/tmp/luau-src/build/luau"


def long_bracket(text: str) -> str:
    """Empaqueta el texto en un literal Luau con delimitador seguro."""
    level = 0
    while ("]" + "=" * level + "]") in text:
        level += 1
    open_delim = "[" + "=" * level + "["
    close = "]" + "=" * level + "]"
    return f"{open_delim}{text}{close}"


def build_script(mock: str, payload: str, asserts: str) -> str:
    mock = mock.rstrip()
    if mock.endswith("return Mock"):
        mock = mock[: -len("return Mock")].rstrip()
    # Los asserts acaban en "return ...": se envuelven en una funcion.
    asserts = "local function __asserts()\n" + asserts.rstrip() + "\nend"
    return "\n".join([
        "--[[ harness Luau real generado por tools/luau_check.py ]]",
        mock,
        "",
        "Mock.setLuauMode(true)",
        "local __PAYLOAD = " + long_bracket(payload),
        "",
        "local ok, err = pcall(Mock.runSource, __PAYLOAD)",
        "if not ok then",
        '	print("PAYLOAD ERROR: " .. tostring(err))',
        "	os.exit(1)",
        "end",
        "",
        asserts,
        "local __passed, __failed, __details = __asserts()",
        'for line in tostring(__details or ""):gmatch("[^\\n]+") do',
        '	if line:match("%S") then print("FAIL  " .. line) end',
        "end",
        'print(string.format("%d passed, %d failed", tonumber(__passed) or 0, tonumber(__failed) or 0))',
        "if (tonumber(__failed) or 0) > 0 then os.exit(1) end",
        "",
    ])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", default=str(ROOT / "dist" / "milonarie_tycoon.lua"))
    parser.add_argument("--luau", default=LUAU)
    args = parser.parse_args()

    if not pathlib.Path(args.luau).exists():
        print(f"no encuentro el binario luau en {args.luau}")
        return 2

    target = pathlib.Path(args.target)
    if not target.is_absolute():
        target = ROOT / target

    mock = (ROOT / "tools" / "roblox_mock.lua").read_text(encoding="utf-8")
    payload = target.read_text(encoding="utf-8")
    asserts = (ROOT / "tools" / "full_assert.lua").read_text(encoding="utf-8")

    script = build_script(mock, payload, asserts)
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as handle:
        handle.write(script)
        script_path = handle.name

    proc = subprocess.run([args.luau, script_path], capture_output=True, text=True, cwd=ROOT)
    out = (proc.stdout + proc.stderr).strip()
    if out:
        print(out)
    print(f"luau {target.name}: exit {proc.returncode}")
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
