# Release :: Milonarie Tycoon

Artefactos listos para distribuir. El payload va ofuscado con **Prometheus**
(`prometheus-lua/Prometheus`), target `LuaU`, seed fija (1337) para builds reproducibles.

## Linea de paste

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/loader.lua"))()
```

`loader.lua` vive en la raiz del repo (`/loader.lua`): pantalla de carga al estilo VANTA,
baja el payload y lo ejecuta. Menu con `RightShift`.

## Artefactos

| Fichero | Que es | Tamano | Carga+run (mock, Lua 5.5) |
|---|---|---|---|
| `milonarie_tycoon_obfuscated.lua` | preset **Medium**: Vmify + EncryptStrings + AntiTamper + ConstantArray + Cff + NumbersToExpressions | 4.2 MB | 152 ms |
| `milonarie_tycoon_obfuscated_strong.lua` | preset **Strong**: Medium + Cff completo + numbers mutados | 4.5 MB | 170 ms |
| `milonarie_tycoon_obfuscated_light.lua` | preset **Medium sin Vmify** (CFF + strings + antitamper) | 675 KB | 64 ms |
| `landing.html` | landing de una pagina con boton de copiar la linea de paste y el loader | 6 KB | - |

Recomendado: **light** para el loader (rapido de descargar y de cargar, proteccion suficiente
para un exploit de juego); **medium/strong** si vendes el script o quieres que reversing sea caro.

## Como se generaron

```
python3 build.py                                        # src/ -> dist/milonarie_tycoon.lua
python3 tools/prometheus_build.py --preset Medium --verify
python3 tools/prometheus_build.py --preset Strong --out release/milonarie_tycoon_obfuscated_strong.lua --verify
python3 tools/prometheus_build.py --preset Medium --drop-step Vmify --out release/milonarie_tycoon_obfuscated_light.lua --verify
```

`--verify` corre el payload ofuscado contra el mock de Roblox (`tools/roblox_mock.lua`) en
Lua 5.1 y Lua 5.5 y ejecuta las 15 asserts de `tools/mock_assert.lua`: construccion del menu,
lectura del cash, captura de remote, auto-bind y replay con override de cantidad.

`tools/loader_run.py` prueba la cadena entera: linea de paste -> `game:HttpGet(loader.lua)`
-> loader -> payload ofuscado -> menu montado (HTTP stubbeado con los ficheros locales).

## Hosting

Las URLs apuntan a este repo en la rama `arena/5e9deb5f-vvv`:

```
https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/loader.lua
https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/5e9deb5f-vvv/roblox/milonarie_tycoon/release/milonarie_tycoon_obfuscated_light.lua
```

Cámbialas en `loader.lua` y en `landing.html` si hosteas en otro sitio.

Ojo: `raw.githubusercontent.com` solo sirve repos publicos de forma anonima (este lo es). Con repo
privado usa tu propio host (pastebin, gist, workers) y actualiza `PAYLOAD_URL`.

Ademas, `game:HttpGet` en Roblox solo funciona con dominios en la allowlist del juego; por eso
el loader intenta primero `request` / `http_request` (natives del executor, sin restriccion) y
solo despues cae a `game:HttpGet`.
