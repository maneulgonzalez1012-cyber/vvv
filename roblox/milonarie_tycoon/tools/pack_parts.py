#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: trocea un payload en partes descargables.

Algunos executors recortan el body de la respuesta HTTP. Si el payload llega
truncado, no compila y el loader no puede hacer nada. Con este troceado el
loader puede reintentar por partes y concatenar.

Escribe en <out-dir>/:
    <name>.part0, <name>.part1, ...   trozos del fuente
    <name>.manifest                   "total=N\\nsize=B\\n"

    .venv/bin/python tools/pack_parts.py \
        --in release/milonarie_tycoon_obfuscated_compact.lua \
        --out-dir release/parts \
        --name milonarie_tycoon_obfuscated_compact \
        --chunk 65536
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--in", dest="source", required=True)
    parser.add_argument("--out-dir", dest="out_dir", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--chunk", type=int, default=65536)
    args = parser.parse_args()

    source = pathlib.Path(args.source)
    if not source.is_absolute():
        source = ROOT / source
    if not source.is_file():
        print(f"no encuentro {source}")
        return 2

    out_dir = pathlib.Path(args.out_dir)
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    data = source.read_bytes()
    chunk = max(1024, args.chunk)
    parts = [data[i:i + chunk] for i in range(0, len(data), chunk)] or [b""]

    # Se limpian las partes viejas del mismo nombre para no dejar restos.
    for stale in out_dir.glob(f"{args.name}.part*"):
        stale.unlink()

    for index, blob in enumerate(parts):
        path = out_dir / f"{args.name}.part{index}"
        path.write_bytes(blob)

    manifest = out_dir / f"{args.name}.manifest"
    manifest.write_text(f"total={len(parts)}\nsize={len(data)}\n", encoding="utf-8")

    print(f"{source.name}: {len(data)} bytes -> {len(parts)} partes de <= {chunk} en {out_dir}")
    print(f"manifest: {manifest.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
