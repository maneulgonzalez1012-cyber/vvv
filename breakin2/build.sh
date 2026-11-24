#!/usr/bin/env bash
# build.sh — bundle, gate, obfuscate each part, assemble, verify.
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

step "gate: load every module, fire every menu callback, item flows"
"$LUAU" build/out/gate.luau

step "lint"
mkdir -p build/out
if command -v luau-analyze >/dev/null 2>&1; then ANALYZE=luau-analyze
else ANALYZE="$(dirname "$LUAU")/luau-analyze"; fi
"$ANALYZE" --mode=nonstrict dist/breakin2.lua 2>&1 \
    | grep -v "Unknown global" > build/out/lint.txt || true
if [ -s build/out/lint.txt ]; then
    echo "lint findings:"; cat build/out/lint.txt
fi

step "obfuscate each part (Prometheus, Medium variant)"
mkdir -p build/out/obf
rm -f build/out/obf/*.lua
for part in build/out/parts/p*.lua; do
    name="$(basename "$part")"
    "$LUA" "$PROMETHEUS" --config build/prometheus.medium.lua --LuaU --nocolors \
        --out "build/out/obf/$name" "$part" >/dev/null
    printf '  %s  %8d -> %8d bytes\n' "$name" "$(wc -c < "$part")" "$(wc -c < "build/out/obf/$name")"
done

step "assemble"
python3 build/assemble.py

step "verify: the assembled file runs under LuaJIT and Luau"
python3 build/verify.py
"$LUAJIT" build/out/verify_luajit.lua
"$LUAU" build/out/verify_luau.luau

step "summary"
python3 - <<'PY'
import hashlib
for name in ("dist/breakin2.lua", "dist/breakin2_v2.obf.lua"):
    data = open(name, "rb").read()
    print("%-24s %8d bytes  sha256=%s" % (
        name, len(data), hashlib.sha256(data).hexdigest()[:32]))
PY
