# Astral

ESP + hitbox expander + aim para Roblox. Código abierto, sin ofuscación, sin key system.
UI: **Rayfield Gen 2**.

```
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/loader.lua"))()
```

Si algo no responde, la pestaña **Misc → Status** dice qué está viendo el script en ese
segundo: renderer, jugadores, cajas de ESP, partes infladas y si hay cámara.

## Loader

`loader.lua` es una sola línea de uso, y si falla dice exactamente por qué:

- timeout de 20 s sobre `HttpGet` (que en varios executors se cuelga sin devolver nunca)
- distingue error de red, respuesta vacía, tabla en vez de texto, 404 en texto plano y
  HTML de error — cada uno con su mensaje
- si la fuente principal de raw.githubusercontent falla, prueba jsDelivr y luego `main`
- apaga la instancia anterior **solo cuando la nueva ya arrancó**: si el fetch o el arranque
  revientan, la que estaba corriendo sigue viva

## Render

**ScreenGui, no Drawing.** `Drawing` no existe o no pinta nada en varios executors,
sobre todo en móvil — antes el ESP intentaba usarla y se quedaba en blanco. Ahora todo se
dibuja con `Frame` + `UIStroke` + `TextLabel`, que funcionan en cualquier executor y en
cualquier plataforma. El gui va a `gethui()` → `CoreGui` → `PlayerGui`, en ese orden.

## Estructura

Proyecto modular en `src/`; `Astral.lua` es el build de una pieza que carga el loader.

```
src/
  init.luau              estado, módulos, loop, unload
  shared/
    config.luau          nombres, rangos, defaults, versión
    mathx.luau           proyección de caja, clamp, lerp de color
    players.luau         objetivo válido, huesos, cache de jugadores por frame
    renderer.luau        ScreenGui
  modules/
    esp.luau             pool por jugador: caja, relleno, vida, nombre, distancia, tracer
    hitbox.luau          expansor por eje con hooks y restore
    hitdebug.luau        cajas de alambre sobre las partes infladas
    aim.luau             FOV + giro de cámara suavizado
    radar.luau           2D XZ relativo a la cámara
    diag.luau            el renglón de Status
  ui/window.luau         ventana de Rayfield + flags
Astral.lua               build (esto carga el loader)
loader.lua               fetch + compile + reemplazo de instancia
build.py                 src/ -> Astral.lua
```

Rebuild: `python3 build.py` (reescribe cada `require(script.…)` a un lookup en tabla).

## Hitbox

- **escala independiente por eje** (X / Y / Z) y botón `Uniformes` para copiar X a Y y Z
- **alcance por modo**: `all`, `torso`, `head`, `root`
- el `Size` base se captura **una vez por parte** y nunca se sobreescribe; cambiar la escala
  compone sobre el original, no sobre lo ya inflado
- al cambiar de modo o escala, las partes de la config anterior se restauran antes de
  aplicar la nueva — cambiar de `all` a `head` no deja los brazos gigantes
- **hooks por personaje** en vez de barrido por timer: `ChildAdded` mete las partes que
  llegan después, `Humanoid.Died` restaura en el acto, `AncestryChanged` suelta el char
  cuando sale del workspace
- `Debug boxes` dibuja un alambre sobre cada parte inflada: si no aparece nada, el problema
  es el juego (validación en servidor) o el personaje, no el script

Sigue siendo local: las partes las posee el otro cliente.

## ESP

- caja desde las 8 esquinas del bounding box → hull en pantalla (no se estira al girar)
- relleno, barra de vida rojo→verde, nombre, distancia, tracer
- team check por el objeto `Team` (no `TeamColor`, que es blanco sin equipos)
- distancia máxima y tres color pickers

## Aim

Mantén click derecho. Elige el hueso más cercano al centro dentro del FOV (convertido a
píxeles con el `FieldOfView` real), gira la cámara con suavizado exponencial independiente
del framerate, wall check opcional de un raycast, y dibuja el círculo del FOV.

## Config

Rayfield guarda y restaura solo (toggles, sliders, dropdowns, colores, posición de la
ventana) en `Astral/Astral.json`.

## Límites reales

- El hitbox solo cambia el tamaño en tu cliente: sirve donde el hit detection corre del
  lado del cliente.
- El aim escribe `Camera.CFrame` desde `RenderStepped`; los scripts de cámara de Roblox
  también escriben cada frame, así que con `smooth` bajo el pulso se nota.

## Anti-cheat

Roblox corre **Hyperion (Byfron)** en Windows. La detección cae sobre la cuenta, no sobre el
script.

## Verificado

`luau-compile` limpio en los 12 módulos, en `Astral.lua` y en `loader.lua`. Harness con
Roblox emulado (instancias, señales, parentesco, `Humanoid.Died`, `ChildAdded`) y stub de
Rayfield Gen 2, en 8 escenarios: arranque y UI, ESP con filtros, hitbox por eje y por modo
con restore en muerte/respawn/salida/unload, debug de hitbox, radar, status, aim con y sin
bind, y doble carga. En cliente real no lo corrí.
