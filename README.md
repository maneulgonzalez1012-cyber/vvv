# vvv

vanta creation

## VANTA | Milonarie Tycoon

Linea de paste (la del loader con pantalla de carga):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/loader.lua"))()
```

## Layout

```
loader.lua                       loader de distribucion (pantalla de carga -> payload)
roblox/milonarie_tycoon/         exploit para Roblox (Lua, single-file para executor)
  src/                           modulos editables (config, util, remotes, farm, move, ui, main)
  dist/milonarie_tycoon.lua      build pegable (python3 build.py)
  release/                       payload ofuscado, landing, docs
  tools/                         mock de Roblox, asserts, build con Prometheus
  build.py                       concatena src/ -> dist/ y hace syntax check
```

Build + check:

```
python3 roblox/milonarie_tycoon/build.py --check
.venv/bin/python roblox/milonarie_tycoon/tools/mock_run.py
.venv/bin/python roblox/milonarie_tycoon/tools/loader_run.py
.venv/bin/python roblox/milonarie_tycoon/tools/prometheus_build.py --preset Medium --verify
```

Detalles del exploit, uso y limits: `roblox/milonarie_tycoon/README.md`.
Ofuscado, loader y landing: `roblox/milonarie_tycoon/release/README.md`.
