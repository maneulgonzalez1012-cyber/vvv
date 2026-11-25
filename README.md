# Astral

ESP + hitbox expander + aim para Roblox. Código abierto, sin ofuscación, sin key system.
UI: **Rayfield Gen 2**.

```
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/loader.lua"))()
```

El menú es el de Rayfield: pill colapsado, la tecla se cambia en su pestaña de Settings.
Todo arranca apagado.

> El loader vive en esta branch, no en `main`. Una URL con `/main/` devuelve 404 y
> `loadstring` recibe nil — el loader ahora detecta ese caso y te lo dice en vez de
> morir con un error seco.

## Estructura

El repo guarda el proyecto **modular** en `src/`; `Astral.lua` es un build generado.

```
src/
  init.luau              entry point: estado, módulos, loop, unload
  shared/
    config.luau          nombres, rangos de sliders, defaults, versión
    mathx.luau           proyección de caja, clamp, lerp de color
    players.luau         quién es objetivo válido + resolución de huesos
    renderer.luau        Drawing o ScreenGui, mismo contrato
  modules/
    esp.luau             pool de objetos por jugador, caja/vida/nombre/distancia/tracer
    hitbox.luau          expansión de Size con original guardado y throttling
    aim.luau             selección por FOV + giro de cámara con suavizado exponencial
    radar.luau           2D XZ relativo a la cámara, esquina superior derecha
  ui/
    window.luau          ventana de Rayfield + tabla de flags
Astral.lua               build de una pieza (esto es lo que carga el loader)
loader.lua               fetch + compile + reemplazo de instancia
build.py                 src/ -> Astral.lua
```

Rebuild:

```
python3 build.py
```

`build.py` reescribe cada `require(script.…)` a un lookup en una tabla de módulos, así
el archivo final no necesita ModuleScripts ni acceso al disco en runtime.

## Features

**ESP**
- caja desde las 8 esquinas del bounding box → hull en pantalla (no se estira al girar)
- relleno, barra de vida rojo→verde, nombre, distancia
- tracer desde el borde inferior
- team check por el objeto `Team` (no `TeamColor`, que es blanco sin equipos)
- slider de distancia máxima y tres color pickers

**Hitbox**
- 1x–10x sobre las partes del cuerpo (R15 completo, R6 reducido)
- opción root-only
- `Size` original guardado una vez y restaurado al apagar, al recargar config y en unload
- re-aplicado cada 0.5 s, con techo de jugadores por pase

**Aim**
- mantén click derecho; elige el hueso más cercano al centro dentro del FOV
- FOV en grados convertido a píxeles con el `FieldOfView` real de la cámara
- suavizado exponencial independiente del framerate, dt clampado
- wall check opcional con un solo raycast, filtrado contra tu personaje y el objetivo
- círculo de FOV dibujado en pantalla

**Radar**
- 250 studs de radio, gira con la vista (proyección sobre forward/right de la cámara)

**Config**
- Rayfield guarda y restaura solo: toggles, sliders, dropdowns, colores y posición
- `Astral/Astral.json` en la carpeta del executor
- botones Save / Load / Restore hitboxes / Unload

## Límites reales

- El hitbox cambia **solo en tu cliente**: las partes las posee el otro jugador. Funciona
  donde el hit detection corre del lado del cliente, no en shooters validados por servidor.
- El aim escribe `Camera.CFrame` desde `RenderStepped`; los scripts de cámara de Roblox
  también escriben cada frame, así que con `smooth` bajo el pulso se nota.
- ESP usa `Drawing` si existe; si no, cae a un `ScreenGui` en `CoreGui`/`PlayerGui`.

## Anti-cheat

Roblox corre **Hyperion (Byfron)** en Windows. Los executors que funcionan lo bypassean, y
eso está permanentemente en la mira de Roblox: el riesgo es sobre tu cuenta, no sobre el script.

## Verificado

- `luau-compile` limpio en los 10 módulos, en `Astral.lua` y en `loader.lua`
- harness que emula Roblox + un stub de la API de Rayfield Gen 2, en 8 escenarios:
  arranque y elementos de UI, ESP con team check y distancia, hitbox aplicando y
  restaurando en dos escalas, radar, aim (FOV, bind, wall check, dt gigante),
  doble carga, config restaurada sin callbacks, fallos de arranque y backend ScreenGui
- no lo corrí en el cliente real de Roblox; eso solo lo compruebas tú
