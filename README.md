# vvv

vanta creation

## VANTA | Milonarie Tycoon

Linea de paste (autonoma, no depende de `game:HttpGet`):

```lua
loadstring((function()local u="https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/loader.lua";local function b(r,e)if type(r)=="string"and #r>0 then return r end;if type(r)=="table" then local x=r.Body or r.body;if type(x)=="string"and #x>0 then return x end end;if type(e)=="string"and #e>0 then return e end;return nil end;local c={};if type(request)=="function" then c[#c+1]=request end;if type(http_request)=="function" then c[#c+1]=http_request end;if type(syn)=="table" and type(syn.request)=="function" then c[#c+1]=syn.request end;if type(http)=="table" and type(http.request)=="function" then c[#c+1]=http.request end;local s;for _,f in ipairs(c) do local ok,x=pcall(f,{Url=u,Method="GET"});if ok then s=b(x) end;if not s then local o,y=pcall(f,u);if o then s=b(y) end end;if s then break end end;if not s then local ok,x=pcall(function() return game:HttpGet(u) end);if ok then s=b(x) end end;if not s then error("[VANTA] no se pudo descargar el loader") end;return s end)())()
```

> Athena (y otros executors) lanzan `HttpGet is not a valid member of DataModel`
> al indexar `game.HttpGet`. Por eso la linea prueba `request`, `http_request`,
> `syn.request` y `http.request` con sus distintas firmas, y deja
> `game:HttpGet` como ultimo recurso.

## Layout

```
loader.lua                       loader de distribucion (GUI VANTA -> payload)
bootstrap.lua                    bootstrap publico autonomo (pegado a mano)
roblox/milonarie_tycoon/         exploit para Roblox (Lua, single-file para executor)
  src/                           modulos editables (config, util, remotes, farm, move, ui, main)
  dist/milonarie_tycoon.lua      build pegable (python3 build.py)
  release/                       payloads ofuscados, partes, landing, docs
  tools/                         mock de Roblox, asserts, build con Prometheus
  build.py                       concatena src/ -> dist/ y hace syntax check
```

## Build + check

```
python3 roblox/milonarie_tycoon/build.py --check
.venv/bin/python roblox/milonarie_tycoon/tools/full_run.py
.venv/bin/python roblox/milonarie_tycoon/tools/luau_check.py
.venv/bin/python roblox/milonarie_tycoon/tools/loader_run.py
.venv/bin/python roblox/milonarie_tycoon/tools/bootstrap_run.py
.venv/bin/python roblox/milonarie_tycoon/tools/e2e_athena.py --download
.venv/bin/python roblox/milonarie_tycoon/tools/prometheus_build.py --preset Compact --verify
```

Detalles del exploit, uso y limits: `roblox/milonarie_tycoon/README.md`.
Ofuscado, loader y landing: `roblox/milonarie_tycoon/release/README.md`.
