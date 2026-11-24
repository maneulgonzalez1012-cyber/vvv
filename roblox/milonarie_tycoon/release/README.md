# Release :: Milonarie Tycoon

Artefactos listos para distribuir. El payload va ofuscado con **Prometheus**
(`prometheus-lua/Prometheus`), target `LuaU`, seed fija (1337) para builds reproducibles.

## Linea de paste

```lua
loadstring((function()local u="https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/loader.lua";local function b(r,e)if type(r)=="string"and #r>0 then return r end;if type(r)=="table" then local x=r.Body or r.body;if type(x)=="string"and #x>0 then return x end end;if type(e)=="string"and #e>0 then return e end;return nil end;local c={};if type(request)=="function" then c[#c+1]=request end;if type(http_request)=="function" then c[#c+1]=http_request end;if type(syn)=="table" and type(syn.request)=="function" then c[#c+1]=syn.request end;if type(http)=="table" and type(http.request)=="function" then c[#c+1]=http.request end;local s;for _,f in ipairs(c) do local ok,x=pcall(f,{Url=u,Method="GET"});if ok then s=b(x) end;if not s then local o,y=pcall(f,u);if o then s=b(y) end end;if s then break end end;if not s then local ok,x=pcall(function() return game:HttpGet(u) end);if ok then s=b(x) end end;if not s then error("[VANTA] no se pudo descargar el loader") end;return s end)())()
```

La linea es **autonoma**: no usa `game:HttpGet` como via principal porque Athena
(y otros executors) lanzan `HttpGet is not a valid member of DataModel` al
indexarlo. Prueba en este orden:

1. `request({Url=,Method=})` -> string | `{Body=,StatusCode=}` | `(body, ok, code)`
2. `http_request(url)` -> string | `{Body=}` | `(body, ok, code)`
3. `syn.request({Url=,Method=})` -> string | `(body, ok, code)`
4. `http.request({Url=,Method=})` -> string | `{Body=}` | `(body, code, msg, headers)`
5. `game:HttpGet(url)` -> ultimo recurso

La linea baja `loader.lua` (GUI VANTA + payload con respaldo por partes) y lo ejecuta.
El menu se abre con `RightShift`.

## Artefactos

| Fichero | Que es | Tamano | Carga+run (mock, Lua 5.5) |
|---|---|---|---|
| `milonarie_tycoon_obfuscated_compact.lua` | preset **Compact**: strings cifrados + constant array + antitamper, sin Vmify | 84 KB | 60 ms |
| `milonarie_tycoon_obfuscated_light.lua` | preset **Medium sin Vmify** (CFF + strings + antitamper) | 675 KB | 64 ms |
| `milonarie_tycoon_obfuscated.lua` | preset **Medium**: Vmify + EncryptStrings + AntiTamper + ConstantArray + Cff + NumbersToExpressions | 4.2 MB | 152 ms |
| `milonarie_tycoon_obfuscated_strong.lua` | preset **Strong**: Medium + Cff completo + numbers mutados | 4.5 MB | 170 ms |
| `parts/` | payload Compact troceado + manifest (respaldo si el executor recorta el body) | 2 partes | - |
| `paste_line.txt` | la linea de paste en texto plano | 1 KB | - |
| `landing.html` | landing de una pagina con boton de copiar la linea de paste y el loader | 10 KB | - |

**Por defecto: Compact.** Los 84 KB entran de sobra en el tope de respuesta que
ponen algunos executors (~100 KB) y evitan el `string too long in loadstring`
de los que cortan fuentes grandes. Si vendes el script y quieres que reversing
sea caro, usa `medium` o `strong` y cambia `PAYLOAD_URL` en el loader.

## Como se generaron

```
python3 build.py                                        # src/ -> dist/milonarie_tycoon.lua
python3 tools/prometheus_build.py --preset Compact --out release/milonarie_tycoon_obfuscated_compact.lua
python3 tools/pack_parts.py --in release/milonarie_tycoon_obfuscated_compact.lua \
        --out-dir release/parts --name milonarie_tycoon_obfuscated_compact --chunk 65536
python3 tools/prometheus_build.py --preset Medium --out release/milonarie_tycoon_obfuscated.lua
python3 tools/prometheus_build.py --preset Strong --out release/milonarie_tycoon_obfuscated_strong.lua
python3 tools/prometheus_build.py --preset Medium --drop-step Vmify --out release/milonarie_tycoon_obfuscated_light.lua
python3 tools/build_loader.py --check                    # loader.lua + bootstrap.lua + linea de paste
python3 tools/build_landing.py                           # landing con la linea real
python3 tools/build_readme.py                            # README de la raiz
```

`loader.lua` y `bootstrap.lua` se **generan** desde una fuente unica
(`tools/http_client.lua` + `tools/build_loader.py`) para que el cliente HTTP
nunca diverja entre los dos.

## Verificacion

```
.venv/bin/python tools/full_run.py                       # 24 checks, Lua 5.5 (mock)
.venv/bin/python tools/full_run.py --strict              # idem con env capado
.venv/bin/python tools/luau_check.py                     # Luau real 0.748
.venv/bin/python tools/loader_run.py                     # loader completo -> menu montado
.venv/bin/python tools/bootstrap_run.py                  # 12 perfiles de executor x 2 bootstrap
```

`tools/bootstrap_run.py` es el que importa para el "no carga": simula cada
firma de HTTP que usan los executors, incluido el caso Athena **sin**
`game:HttpGet`, y comprueba que el payload se descarga y el menu se monta.
Tambien prueba el respaldo por partes cuando el body llega recortado.

## Hosting

Las URLs apuntan a este repo en la rama `arena/5e9deb5f-vvv`:

```
https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/loader.lua
https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/roblox/milonarie_tycoon/release/milonarie_tycoon_obfuscated_compact.lua
https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/roblox/milonarie_tycoon/release/parts/milonarie_tycoon_obfuscated_compact.manifest
```

Cámbialas en `tools/build_loader.py` si hosteas en otro sitio.

Ojo: `raw.githubusercontent.com` solo sirve repos publicos de forma anonima (este lo es). Con repo
privado usa tu propio host (pastebin, gist, workers) y regenera con `tools/build_loader.py`.

Ademas, `game:HttpGet` en Roblox solo funciona con dominios en la allowlist del juego; por eso
el loader prueba primero las APIs del executor y solo despues cae a `game:HttpGet`.
