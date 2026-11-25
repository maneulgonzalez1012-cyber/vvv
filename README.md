# Astral

ESP + hitbox expander para Roblox. Código abierto, sin ofuscación, sin key system.
UI: **Rayfield Gen 2**.

```
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/refs/heads/arena/b9dbd63d-vvv/loader.lua"))()
```

El menú es el de Rayfield: pill colapsado arriba a la izquierda, la tecla se cambia en su
pestaña de Settings. Todo arranca apagado.

> El loader vive en esta branch, no en `main`. Si pegas la URL con `/main/` vas a recibir
> un 404 y `loadstring(nil)` truena — ese era el "no carga".

## Archivos

| archivo | qué es |
|---|---|
| `loader.lua` | el loadstring: baja `Astral.lua` del repo, lo compila, llama `unload` de la instancia anterior si había una, y lo corre |
| `Astral.lua` | el cheat completo: ESP + hitbox + ventana de Rayfield |

## Features

**ESP**
- caja: bounding box del modelo → 8 esquinas al viewport → hull en pantalla (no se estira cuando el personaje gira)
- barra de vida rojo → verde
- nombre (DisplayName)
- distancia en studs
- team check por el objeto `Team` (no `TeamColor`, que es blanco en juegos sin equipos)
- distancia máxima con slider
- color de caja con color picker

**Hitbox expander**
- 1x–10x sobre 20 parts (R15) o las 6 de R6
- opción "root part only"
- guarda el `Size` original y lo restaura al apagar, al recargar config y en `unload()`
- re-aplica cada 0.5 s para sobrevivir respawns

**Render**
- usa `Drawing` si el executor lo tiene
- si no, cae a un `ScreenGui` con `Frame` + `UIStroke` y `TextLabel` — mismo código, mismo resultado
- sin ninguno de los dos, aborta con un `warn` claro en vez de morir a medias

**Config**
- Rayfield guarda y restaura solo: toggles, sliders, color y la posición de la ventana
- se escribe en `Astral/Astral.json` en la carpeta del executor
- botones Save / Load / Reset hitboxes en la pestaña Config

## Límites reales

- El hitbox cambia **solo en tu cliente**: las parts las posee el otro jugador. Funciona donde
  el hit detection corre del lado del cliente; no hace nada en shooters validados por servidor.
- ESP necesita `Drawing` o acceso a `PlayerGui`/`CoreGui`. Con cualquiera de los dos funciona.
- La UI necesita `loadstring` y `game:HttpGet` (los da el executor, no Roblox).

## Anti-cheat

Roblox corre **Hyperion (Byfron)** en Windows. Los executors que funcionan lo bypassean, y eso
está permanentemente en la mira de Roblox: el riesgo es sobre tu cuenta, no sobre el script.

## Verificado

- `luau-compile` limpio en `loader.lua` y `Astral.lua`
- probado con un harness que emula Roblox + un stub de la API de Rayfield Gen 2: la ventana se
  crea con las 3 tabs, 8 toggles, 2 sliders, 1 color picker y 3 botones; prender ESP dibuja
  caja/vida/nombre/distancia, apagarlo los esconde, el slider de distancia filtra, el de escala
  aplica y restaura el `Size`, y `unload()` no deja objetos ni conexiones
- probado en los dos renderers (Drawing y ScreenGui)
- no lo corrí en el cliente real de Roblox, eso solo lo compruebas tú
