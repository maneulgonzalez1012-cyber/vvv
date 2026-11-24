#!/usr/bin/env python3
"""Aero :: Milonarie Tycoon :: ofuscado con Prometheus.

Reutiliza o clona Prometheus (prometheus-lua/Prometheus), ofusca el payload con
un preset y opcionalmente verifica que el resultado sigue corriendo contra el
mock de Roblox.

    .venv/bin/python tools/prometheus_build.py --preset Medium --verify

Prometheus necesita Lua 5.1 (o LuaJIT). Se usa lupa.lua51 si esta instalada;
si no, se busca un binario luajit/lua5.1 en el PATH.
"""
import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Presets propios: pipeline de steps completo (no heredado de Prometheus).
# Compact: sin Vmify, sin HoistVmStrings y sin NumbersToExpressions, asi el
# payload baja de 700 KB a ~84 KB. Ese tamano entra de sobra en el tope de
# respuesta que ponen algunos executors (~100 KB) y evita el "string too long
# in loadstring" de los que cortan fuentes grandes.
COMPACT_STEPS = [
    "EncryptStrings:HoistVmStrings=false",
    "AntiTamper:UseDebug=false",
    "ConstantArray:Threshold=1;StringsOnly=true",
    "WrapInFunction",
]

# Base de Prometheus de la que se heredan los ajustes globales (seed, target, nombres).
LOCAL_PRESETS = {
    "Compact": {"base": "Medium", "steps": COMPACT_STEPS},
}
CACHE = pathlib.Path(os.environ.get("PROMETHEUS_CACHE", pathlib.Path.home() / ".cache" / "prometheus-lua"))
REPO_URL = "https://github.com/prometheus-lua/Prometheus.git"

# Serializa el preset a un fichero de config (Lua) para poder fijar seed y target.
DUMP_LUA = """
local src = {src}
package.path = src .. "/src/?.lua;" .. src .. "/?.lua;" .. package.path
local Presets = require("presets")

local function dump(v, indent)
	local t = type(v)
	if t == "string" then
		return string.format("%q", v)
	end
	if t == "number" or t == "boolean" then
		return tostring(v)
	end
	if t ~= "table" then
		return "nil"
	end
	if next(v) == nil then
		return "{{}}"
	end
	local isArray, count = true, 0
	for k in pairs(v) do
		if type(k) ~= "number" then
			isArray = false
			break
		end
		count = count + 1
	end
	local parts = {{}}
	if isArray and count == #v then
		for _, item in ipairs(v) do
			parts[#parts + 1] = indent .. "\\t" .. dump(item, indent .. "\\t")
		end
		return "{{\\n" .. table.concat(parts, ",\\n") .. ",\\n" .. indent .. "}}"
	end
	local keys = {{}}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do
		parts[#parts + 1] = indent .. "\\t[" .. dump(k, indent) .. "] = " .. dump(v[k], indent .. "\\t")
	end
	return "{{\\n" .. table.concat(parts, ",\\n") .. "\\n" .. indent .. "}}"
end

local config = {{}}
for k, v in pairs(Presets[{preset}]) do
	config[k] = v
end
local customSteps = {{ {steps} }}
if #customSteps > 0 then
	local steps = {{}}
	for _, entry in ipairs(customSteps) do
		local name, settings = entry:match("^([^:]+):?(.*)$")
		local step = {{ Name = name, Settings = {{}} }}
		if settings and settings ~= "" then
			for pair in settings:gmatch("[^;]+") do
				local key, value = pair:match("^%s*([%w_]+)%s*=%s*(%S+)%s*$")
				if key then
					if value == "true" then
						step.Settings[key] = true
					elseif value == "false" then
						step.Settings[key] = false
					elseif tonumber(value) then
						step.Settings[key] = tonumber(value)
					else
						step.Settings[key] = value
					end
				end
			end
		end
		steps[#steps + 1] = step
	end
	config.Steps = steps
end

local drops = {{ {drops} }}
if #drops > 0 and config.Steps then
	local kept = {{}}
	for _, step in ipairs(config.Steps) do
		local keep = true
		for _, d in ipairs(drops) do
			if step.Name == d then keep = false end
		end
		if keep then kept[#kept + 1] = step end
	end
	config.Steps = kept
end
config.Seed = {seed}
config.LuaVersion = "{target}"
config.PrettyPrint = false
local handle = assert(io.open({out}, "wb"))
handle:write("return " .. dump(config, "") .. "\\n")
handle:close()
"""


def lua_quote(value) -> str:
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def ensure_prometheus(explicit: str | None) -> pathlib.Path:
    if explicit:
        path = pathlib.Path(explicit).expanduser().resolve()
        if not (path / "src" / "prometheus.lua").is_file():
            raise SystemExit(f"no parece Prometheus: {path}")
        return path
    dest = CACHE / "Prometheus"
    if not (dest / "src" / "prometheus.lua").is_file():
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            shutil.rmtree(dest)
        print(f"clonando Prometheus en {dest} ...")
        subprocess.run(["git", "clone", "--depth", "1", REPO_URL, str(dest)], check=True)
    return dest


def lua51_runtime():
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError:
        return None
    return LuaRuntime(unpack_returned_tuples=True)


def run_lua51(code: str) -> str:
    lua = lua51_runtime()
    if lua is not None:
        lines: list[str] = []
        lua.globals()["print"] = lambda *a: lines.append(" ".join(str(x) for x in a))
        lua.execute(code)
        return "\n".join(lines)

    for exe in ("luajit", "lua5.1", "lua51"):
        binary = shutil.which(exe)
        if binary:
            proc = subprocess.run([binary, "-e", code], capture_output=True, text=True)
            if proc.returncode != 0:
                raise SystemExit("prometheus fallo:\n" + proc.stdout + proc.stderr)
            return proc.stdout
    raise SystemExit("necesita Lua 5.1/LuaJIT: pip install lupa (lupa.lua51) o ponlo en el PATH")


def write_preset_config(source_dir: pathlib.Path, preset: str, seed: int, target: str,
                        drops: list[str] | None = None, steps: list[str] | None = None) -> pathlib.Path:
    handle = tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8")
    handle.close()
    code = DUMP_LUA.format(
        src=lua_quote(source_dir),
        preset=lua_quote(preset),
        seed=seed,
        target=target,
        out=lua_quote(handle.name),
        drops=", ".join('"%s"' % d for d in (drops or [])),
        steps=", ".join('"%s"' % d for d in (steps or [])),
    )
    run_lua51(code)
    return pathlib.Path(handle.name)


def run_cli(source_dir: pathlib.Path, cli_args: list[str]) -> str:
    """Ejecuta el CLI oficial de Prometheus (cli.lua) con los argumentos dados."""
    previous = pathlib.Path.cwd()
    try:
        os.chdir(source_dir)
        lua = lua51_runtime()
        if lua is None:
            return run_lua51(" ".join([str(source_dir / "cli.lua")] + cli_args))
        lines: list[str] = []
        lua.globals()["print"] = lambda *a: lines.append(" ".join(str(x) for x in a))
        lua.globals()["arg"] = lua.table_from(cli_args)
        lua.execute(f'dofile("{source_dir / "cli.lua"}")')
        return "\n".join(lines)
    finally:
        os.chdir(previous)


def verify(target: pathlib.Path) -> int:
    """Corre el payload ofuscado contra el mock de Roblox."""
    runtimes = []
    try:
        from lupa.lua51 import LuaRuntime as L51
        runtimes.append(("lua51", L51))
    except ImportError:
        pass
    try:
        from lupa.lua55 import LuaRuntime as L55
        runtimes.append(("lua55", L55))
    except ImportError:
        pass
    if not runtimes:
        print("verify: lupa no instalado, se omite")
        return 0

    failures = 0
    for name, runtime in runtimes:
        lua = runtime(unpack_returned_tuples=True)
        try:
            lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text(encoding="utf-8"))
            lua.execute(target.read_text(encoding="utf-8"))
        except Exception as exc:  # lupa.LuaError
            print(f"verify {name}: CARGA FALLIDA -> {exc}")
            failures += 1
            continue
        try:
            results = lua.execute((ROOT / "tools" / "mock_assert.lua").read_text(encoding="utf-8"))
        except Exception as exc:  # lupa.LuaError
            print(f"verify {name}: ASSERTS FALLARON -> {exc}")
            failures += 1
            continue
        for failed in results["failures"]:
            print(f"verify {name}: FAIL {failed}")
        print(f"verify {name}: {results['passed']} passed, {results['failed']} failed")
        failures += int(results["failed"])
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--prometheus", help="ruta a un checkout de Prometheus")
    parser.add_argument("--preset", default="Medium",
                        choices=["Minify", "Weak", "Cff", "Vmify", "Medium", "Strong", "Compact"],
                        help="Compact es un pipeline propio (ver COMPACT_STEPS) basedo en Medium.")
    parser.add_argument("--lua-target", default="LuaU", choices=["Lua51", "LuaU"])
    parser.add_argument("--seed", type=int, default=1337)
    parser.add_argument("--in", dest="input", default=str(ROOT / "dist" / "milonarie_tycoon.lua"))
    parser.add_argument("--out", dest="output", default=str(ROOT / "release" / "milonarie_tycoon_obfuscated.lua"))
    parser.add_argument("--drop-step", action="append", default=[],
                        help="quita un step del preset (ej: Vmify). Repetible.")
    parser.add_argument("--steps", default="",
                        help="lista de steps separada por comas; ignora el preset. "
                             "Settings por step: 'Nombre:Clave=valor;Clave2=valor2' "
                             "(ej: AntiTamper:UseDebug=false)")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    source_dir = ensure_prometheus(args.prometheus)
    target = pathlib.Path(args.output).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    input_file = pathlib.Path(args.input).resolve()

    preset = args.preset
    base_preset = preset
    custom_steps = [s.strip() for s in args.steps.split(",") if s.strip()]
    if preset in LOCAL_PRESETS:
        base_preset = LOCAL_PRESETS[preset]["base"]
        if not custom_steps:
            custom_steps = list(LOCAL_PRESETS[preset]["steps"])
    if custom_steps and args.drop_step:
        dropped = set(args.drop_step)
        custom_steps = [s for s in custom_steps if s.split(":")[0] not in dropped]
    config_path = write_preset_config(source_dir, base_preset, args.seed, args.lua_target,
                                      args.drop_step, custom_steps)
    cli_args = ["--config", str(config_path), "--out", str(target), "--nocolors", str(input_file)]
    print(run_cli(source_dir, cli_args).strip())

    if args.verify:
        bad = verify(target)
        if bad:
            print("verify: FALLO")
            return 1
        print("verify: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
