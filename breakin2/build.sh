#!/usr/bin/env bash
# build.sh — pack -> gate -> analyze -> obfuscate (per part) -> assemble -> verify
#
# Nothing here is optional. A red step stops the build, because the only thing
# worse than no artifact is an artifact that half works.
#
#   ./build.sh              full build + verification
#   ./build.sh --fast       skip obfuscation (readable bundle + gate only)
#
# Tool locations can be overridden:
#   LUAJIT_BIN, LUAU_BIN, LUAU_ANALYZE_BIN, PROMETHEUS_DIR (folder with cli.lua)
set -euo pipefail

cd "$(dirname "$0")"

LUAJIT_BIN="${LUAJIT_BIN:-/tmp/x_lj/src/luajit}"
LUAU_BIN="${LUAU_BIN:-/tmp/x_luau/build/luau}"
LUAU_ANALYZE_BIN="${LUAU_ANALYZE_BIN:-/tmp/x_luau/build/luau-analyze}"
PROMETHEUS_DIR="${PROMETHEUS_DIR:-/tmp/x_prom}"
PROMETHEUS_CONFIG="${PROMETHEUS_CONFIG:-build/prometheus.medium.lua}"

FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1

step() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

for bin in "$LUAJIT_BIN" "$LUAU_BIN" "$LUAU_ANALYZE_BIN"; do
    [[ -x "$bin" ]] || fail "missing tool: $bin"
done

rm -rf build/out build/out/parts
mkdir -p build/out/parts dist

# ── 1. pack ────────────────────────────────────────────────────────────────
step "1/6 pack"
python3 build/pack.py

# ── 2. gate ────────────────────────────────────────────────────────────────
step "2/6 gate (load every module, build every tab, fire every callback)"
"$LUAU_BIN" build/out/gate.luau | tee build/out/gate.log
grep -q "GATE OK" build/out/gate.log || fail "gate failed"
grep -q "callbacks fired=.* failed=0" build/out/gate.log || fail "a callback threw"
grep -q "fault injection: crashing module contained" build/out/gate.log || fail "module isolation broken"

# ── 3. analyze ─────────────────────────────────────────────────────────────
step "3/6 analyze (luau-analyze: syntax, unused locals, unknown API)"
# Unknown globals are the executor's (hookmetamethod, gethui, ...) and `require`
# is the bundler's, so those two classes are expected; anything else is a bug.
ANALYZE_LOG=build/out/analyze.log
"$LUAU_ANALYZE_BIN" --formatter=gnu $(find src -name '*.lua' | sort) \
    > "$ANALYZE_LOG" 2>&1 || true
if grep -Ev "Unknown global|Unknown require|Unknown type|unknown global" "$ANALYZE_LOG" | grep -q ":"; then
    grep -Ev "Unknown global|Unknown require|Unknown type|unknown global" "$ANALYZE_LOG"
    fail "analyzer reported problems"
fi
printf 'analyze clean (%s issues, all executor globals)\n' "$(wc -l < "$ANALYZE_LOG")"

# ── 4. obfuscate, one part at a time ───────────────────────────────────────
if [[ "$FAST" == "1" ]]; then
    step "4/6 obfuscate (skipped: --fast)"
else
    step "4/6 obfuscate (Prometheus Medium via $PROMETHEUS_CONFIG, per part)"
    [[ -f "$PROMETHEUS_DIR/cli.lua" ]] || fail "missing Prometheus at $PROMETHEUS_DIR"
    for part in build/out/parts/p*.lua; do
        out="${part%.lua}.obf.lua"
        "$LUAJIT_BIN" "$PROMETHEUS_DIR/cli.lua" --config "$PROMETHEUS_CONFIG" \
            --Lua51 --nocolors --out "$out" "$part" \
            > "build/out/$(basename "${part%.lua}").obf.log" 2>&1 \
            || { tail -20 "build/out/$(basename "${part%.lua}").obf.log"; fail "obfuscation failed: $part"; }
        printf '  %-28s %8d -> %8d bytes\n' "$(basename "$part")" "$(stat -c%s "$part")" "$(stat -c%s "$out")"
    done
fi

# ── 5. assemble ────────────────────────────────────────────────────────────
if [[ "$FAST" == "1" ]]; then
    step "5/6 assemble (skipped: --fast)"
else
    step "5/6 assemble"
    python3 build/assemble.py
fi

# ── 6. verify ──────────────────────────────────────────────────────────────
step "6/6 verify (luajit + luau, run the shipped bytes)"
LUAJIT_BIN="$LUAJIT_BIN" LUAU_BIN="$LUAU_BIN" python3 build/verify.py

step "dist"
ls -l dist

if [[ "$FAST" == "0" ]]; then
    step "loadstring"
    url="https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/3fa3ee03-vvv/breakin2/dist/breakin2_v3.obf.lua"
    printf 'loadstring(game:HttpGet("%s"))()\n' "$url"
fi
