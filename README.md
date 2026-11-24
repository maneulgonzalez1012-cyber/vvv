# vvv

vanta creation

## Layout

```
roblox/milonarie_tycoon/     exploit para Roblox (Lua, single-file para executor)
  src/                       modulos editables (config, util, remotes, farm, move, ui, main)
  dist/milonarie_tycoon.lua  build pegable (python3 build.py)
  release/                   artefactos de distribucion: payload ofuscado, loader, landing
  tools/                     mock de Roblox, asserts, build con Prometheus
  build.py                   concatena src/ -> dist/ y hace syntax check
```

Build + check:

```
python3 roblox/milonarie_tycoon/build.py --check
.venv/bin/python roblox/milonarie_tycoon/tools/mock_run.py
.venv/bin/python roblox/milonarie_tycoon/tools/prometheus_build.py --preset Medium --verify
```

Detalles del exploit, uso y limits: `roblox/milonarie_tycoon/README.md`.
Ofuscado, loader y landing: `roblox/milonarie_tycoon/release/README.md`.
