# vvv
vanta creation

## Aero / Roblox

`aero_roblox.lua` — ESP, aimbot, triggerbot, radar y fly en Luau. Menú INSERT con pestañas ESP / AIMBOT / MISC / CONFIG.
`loadstring.lua` — loadstring **de URL**, una línea para pegar en el executor.
`loader.lua` — stage 2: baja el payload desde la URL y lo ejecuta con validación.

### Investigación: el fly de Infinite Yield

"infiny field" = **Infinite Yield FE** (EdgeIY/infiniteyield, MIT), no el juego Track & Field: Infinite.
Fuente: `source` del repo oficial, `sFLY()` (líneas 7108-7216) y `mobilefly()` (7239-7307),
bajado con `api.github.com/repos/EdgeIY/infiniteyield/contents/source`.

- `BodyVelocity` + `BodyGyro` sobre `HumanoidRootPart`.
- `MaxForce` / `MaxTorque` = `Vector3.new(9e9, 9e9, 9e9)`. No es `math.huge`: IY usa 9e9 a propósito para que el solver de física no se desestabilice.
- `BG.P = 9e4`, `BG.D = 50`, `BG.CFrame = camera.CFrame` en cada frame → la velocidad siempre es relativa a la cámara.
- `Humanoid.PlatformStand = true` mientras vuela, `false` al apagar; sin eso el Humanoid pelea con el `BodyVelocity`.
- Velocidad = `iyflyspeed * 50` (default 50). Q/E suben/bajan. Aquí `cfg.misc.flySpeed` ya es studs/s, así que `60` equivale a `;flyspeed 1.2`.
- Re-armado en respawn: `HumanoidRootPart` y `Humanoid` son instancias nuevas, hay que recrear BV/BG y soltar el `PlatformStand` del Humanoid viejo.

Loader oficial de IY, para referencia:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()
```

### Estructura del loadstring (investigación)

Un loadstring de URL no es solo `loadstring(game:HttpGet(url))()`. La cadena que sobrevive
a un executor real, a un 404 y a un CDN cacheado tiene seis etapas:

| # | Etapa | Qué resuelve |
|---|---|---|
| 1 | config | owner/repo/rama/SHA, archivo, reintentos, marker, chunk name en un solo bloque |
| 2 | env + guard | `getgenv()` → `getfenv(0)` → `_G`; flag `AERO_LOADED` evita dos GUI, `AERO_FORCE_RELOAD` permite recargar |
| 3 | `game.Loaded:Wait()` | ejecutar antes de que exista `Players.LocalPlayer` rompe todo |
| 4 | fetch | `game:HttpGet(url, true)` (`true` = `noCache`, mismo significado que `HttpService:GetAsync(url, nocache)`), con fallback `request` / `http_request` / `syn.request` / `http.request` / `fluxus.request` y reintentos con backoff |
| 5 | validate + compile | longitud mínima y marker para no ejecutar una página HTML de error; `loadstring(src, "=AeroRoblox")` dentro de `pcall` para que un error de sintaxis sea un mensaje y no un executor muerto |
| 6 | run + report | `xpcall` con `debug.traceback`, y `warn`/`print` con el resultado |

Detalles que importan:

- El segundo argumento de `HttpGet` es `noCache`, pero no todos los executors lo
  implementan igual — hay uno que lo invierte a `cache`. Por eso `loader.lua` añade
  además `?t=<os.time()>_<random>` a la URL en modo rama. Verificado: GitHub raw sirve
  el archivo con query string.
- `usePin = false` sigue la rama (auto-update); `usePin = true` congela en `CFG.sha`.
  Para congelar: `git rev-parse HEAD` y poner ese SHA en `CFG.sha`.
- El payload también tiene guard: si lo pegas dos veces, la segunda ejecución sale
  con `return` antes de crear la GUI.

Fuentes:

- `HttpService:GetAsync(url, nocache)` — https://robloxapi.github.io/ref/class/HttpService.html
- `HttpGet` arg 2 = `noCache`, y el bug de executors que lo invierten — https://github.com/sUNC-Utilities/docs/issues/264
- cadena de fallback y guard `IY_LOADED` + `game.Loaded:Wait()` — https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source
- fallback `request` con `StatusCode`/`Body` — https://github.com/dissering/roblox-executor-mcp
- `pcall(loadstring, src)` y `loadstring(src, chunkName)` — https://posvirtual.fapam.edu.br/fapam-news/roblox-loadstring-scripts-the-ultimate-guide-1764805242

### Uso

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/6922546f-vvv/loader.lua", true))()
```

INSERT = menú · RMB = aimbot mantenido · T = triggerbot · F = fly · WASD + Q/E (o espacio/ctrl) = mover · CONFIG guarda/carga `aero_roblox_config.json`. Todo apagado al cargar.
