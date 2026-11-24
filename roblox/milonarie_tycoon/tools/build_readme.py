#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: rellena el README de la raiz con la linea de paste.

    .venv/bin/python tools/build_readme.py
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
README = REPO / "README.md"
RELEASE_README = ROOT / "release" / "README.md"
PASTE = ROOT / "release" / "paste_line.txt"


def fill(path: pathlib.Path, paste: str) -> bool:
    text = path.read_text(encoding="utf-8")
    if "__PASTE_LINE__" not in text:
        print(f"{path.name}: no tiene el marcador __PASTE_LINE__")
        return False
    path.write_text(text.replace("__PASTE_LINE__", paste), encoding="utf-8")
    print(f"{path.name}: linea de paste de {len(paste)} bytes")
    return True


def main() -> int:
    paste = PASTE.read_text(encoding="utf-8").strip()
    ok = fill(README, paste)
    if RELEASE_README.exists():
        ok = fill(RELEASE_README, paste) and ok
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main())
