# vvv
vanta creation

## Aero / Roblox

`aero_roblox.lua` — ESP, aimbot, triggerbot, radar y fly en Luau. Menú INSERT con pestañas ESP / AIMBOT / MISC / CONFIG.
`loadstring.lua` — **el corto**: loadstring de una línea con link acortado, para pegar en el executor.
`loader.lua` — stage 2: baja el payload desde la URL y lo ejecuta con validación.
`shorten.sh` — regenera los links cortos.

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

### "El corto": loadstring con link acortado

En la jerga de los script hubs, "el corto" es el loadstring de una sola línea cuya
URL está **acortada** (`is.gd`, `tinyurl`, `v.gd`): en vez de pegar los ~120 caracteres
de `raw.githubusercontent.com/owner/repo/rama/archivo.lua`, pegas ~20. No cambia el
código, cambia el enlace: el acortador responde un 3xx y `game:HttpGet` sigue la
redirección hasta el `.lua`. Los generadores de loadstring hacen exactamente eso:
`loadstring(game:HttpGet("https://..."))()` con la URL que les pases [1](https://github.com/CommunityPokeOrg/roblox-loadstring-generator).
`is.gd` y `tinyurl.com` son redirecciones 3xx planas, sin página HTML de por medio [2](https://www.flyn.to/blog/short-link-referrer-behavior).

Reglas que salen de la investigación (y de probar los links, no de suponer):

- El acortador **tiene que devolver un 3xx sin cuerpo HTML**. Si mete un interstitial
  de anuncios/cuenta atrás, `HttpGet` recibe HTML y `loadstring` falla al compilar.
  Linkvertise/LootLabs son el caso clásico de "el loadstring no funciona" [3](https://www.reddit.com/r/robloxhackers/comments/1eon4q2/got_banned_from_linkvertise/).
- `tinyurl.com/api-create.php` es un endpoint **deprecado**: los links creados ahí
  muestran una pantalla de preview/anuncio antes de redirigir, y no se pueden editar
  ni borrar [4](https://tinyurl.com/blog/why-my-tinyurl-link-show-ad-preview-screen-before-redirecting/).
  Verificado: `https://tinyurl.com/238ak693` (creado sin alias por ese endpoint) cae
  en `tinyurl.com/preview/deprecated/...`. El link con alias `aero-vvv` redirige
  directo al `.lua`; aun así, `is.gd` es el primario.
- `is.gd/create.php?format=simple&url=...&shorturl=<alias>` no pide API key, admite
  alias de 5-30 caracteres y devuelve el link en texto plano [5](https://is.gd/apishorteningreference.php) [6](https://api-catalog-tau.vercel.app/compare/url-shortener-api).
- Un 301 lo cachea el cliente y no vuelve a preguntar al acortador; si el destino se
  edita, los que ya lo visitaron siguen yendo al viejo [7](https://dev.to/somnath_khadanga_2e5c2364/five-bugs-hiding-in-a-url-shortener-and-the-fix-for-each-3852).
  Por eso el link congelado por SHA existe como alias separado (`aeropin`), no se
  "actualiza" el `aerovvv`.

Links creados y verificados (redirección al `.lua` correcto, comprobada con query
strings de cache-bust encima):

| Alias | Destino |
|---|---|
| `https://is.gd/aerovvv` | payload en la rama (auto-update) |
| `https://is.gd/aeroldr` | `loader.lua` estructurado |
| `https://is.gd/aeropin` | payload congelado en `5bb6154` |
| `https://is.gd/wmQUvu` | payload, alias aleatorio de respaldo |
| `https://tinyurl.com/aero-vvv` | payload en la rama |

Para regenerar: `./shorten.sh [SHA]`. Si un alias ya está ocupado, la API da error;
cambia el nombre. El link corto añade un tercero en la cadena: si el acortador cae o
cambia el destino, el loadstring deja de funcionar (o ejecuta otra cosa).

### Uso

```lua
loadstring(game:HttpGet("https://is.gd/aerovvv", true))()
```

Si el acortador no responde, la URL cruda:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/6922546f-vvv/loader.lua", true))()
```

INSERT = menú · RMB = aimbot mantenido · T = triggerbot · F = fly · WASD + Q/E (o espacio/ctrl) = mover · CONFIG guarda/carga `aero_roblox_config.json`. Todo apagado al cargar.
