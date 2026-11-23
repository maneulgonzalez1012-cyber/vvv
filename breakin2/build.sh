#!/usr/bin/env bash
# build.sh — bundle, gate, obfuscate, verify.
#
# The dist/ artifacts are committed, so this only needs to run when the source
# changes. It wants a toolchain that is not vendored here:
#
#   PROMETHEUS  path to a Prometheus checkout (its cli.lua)
#   LUA         a Lua 5.4 binary to run that cli
#   LUAU        the Luau CLI (luau-lang/luau, target Luau.Repl.CLI)
#   LUAJIT      a LuaJIT 2.1 binary
#
# Example (the toolchain used for the committed build):
#   PROMETHEUS=/tmp/Prometheus-master/cli.lua \
#   LUA=/tmp/lua_bin LUAU=/tmp/luau-master/build/luau \
#   LUAJIT=/tmp/LuaJIT-2.1/src/luajit ./build.sh
set -euo pipefail

cd "$(dirname "$0")"

PROMETHEUS="${PROMETHEUS:-/tmp/Prometheus-master/cli.lua}"
LUA="${LUA:-/tmp/lua_bin}"
LUAU="${LUAU:-/tmp/luau-master/build/luau}"
LUAJIT="${LUAJIT:-/tmp/LuaJIT-2.1/src/luajit}"

step() { printf '\n== %s\n' "$*"; }

step "bundle"
python3 build/pack.py

step "analyze (nonstrict, our own code only)"
"$LUAU" build/out/gate.luau >/dev/null
"$LUAU" build/out/gate.luau | tail -3
mkdir -p build/out
# lint: unknown globals are expected (Roblox API), everything else is not
if command -v luau-analyze >/dev/null 2>&1; then ANALYZE=luau-analyze
else ANALYZE="$(dirname "$LUAU")/luau-analyze"; fi
"$ANALYZE" --mode=nonstrict dist/breakin2.lua 2>&1 \
    | grep -v "Unknown global" > build/out/lint.txt || true
if [ -s build/out/lint.txt ]; then
    echo "lint findings:"; cat build/out/lint.txt
fi

step "obfuscate (Prometheus, Medium variant)"
"$LUA" "$PROMETHEUS" --config build/prometheus.medium.lua --LuaU --nocolors \
    --out dist/breakin2.obf.lua dist/breakin2.lua

step "verify: obfuscated output runs"
python3 build/verify.py
"$LUAJIT" build/out/verify_luajit.lua
"$LUAU" build/out/verify_luau.luau

step "summary"
python3 - <<'PY'
import hashlib, os
for name in ("dist/breakin2.lua", "dist/breakin2.obf.lua"):
    data = open(name, "rb").read()
    print("%-24s %8d bytes  sha256=%s" % (
        name, len(data), hashlib.sha256(data).hexdigest()[:32]))
PY
