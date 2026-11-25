# Vanta

ESP + hitbox expander para Roblox. Código abierto, sin ofuscación, sin key system.

```
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/main/loader.lua"))()
```

Menú con **RightShift**. Todo arranca apagado.

## Archivos

| archivo | qué es |
|---|---|
| `loader.lua` | el loadstring que jala `Vanta.lua` del repo y lo ejecuta. Desinstala la instancia anterior si ya había una cargada |
| `Vanta.lua` | el cheat completo: ESP por Drawing + hitbox expander + menú |

## Features

**ESP**
- caja 3D → 2D: bounding box del modelo, 8 esquinas al viewport, hull en pantalla
- barra de vida (rojo → verde según HP)
- nombre (DisplayName)
- distancia en studs
- team check (compara el objeto `Team`, no `TeamColor`)
- distancia máxima configurable

**Hitbox expander**
- escala 1x–10x, aplica a 20 partes (R15) o a las 6 de R6
- opción "root part only" para no tocar cabeza/extremidades
- guarda el `Size` original y restaura al apagar, al recargar config o en `unload()`
- re-aplica cada 0.5 s para sobrevivir respawns

**Menú**
- tabs por sección, arrastrable desde el título
- toggles y sliders por click o drag
- CONFIG: guarda/carga `Vanta/config.json` en la carpeta del executor

## Límites reales

- El hitbox se agranda **solo en tu cliente**. Las partes las posee el otro jugador. Funciona en juegos cuya detección de golpes corre en el cliente (la mayoría de los "combat" simples); no hace nada en shooters con validación estricta del servidor.
- El ESP necesita la API `Drawing`. Executors sin `Drawing` abortan al arrancar con un error claro en consola.
- Requiere `loadstring` habilitado (lo da el executor, no Roblox).

## Anti-cheat

Roblox corre **Hyperion (Byfron)** en el cliente de Windows. Los executors que funcionan lo hacen bypasseando ese proceso, y eso está en la mira constante de Roblox: la detección es sobre tu cuenta, no sobre el script. Un script externo como este no cambia ese riesgo, solo lo usa.

## Verificado

Compila con el compilador de Luau (`luau-compile`). Probado con un harness que emula Roblox: ESP proyecta y dibuja, toggles responden al click, sliders al drag, hitbox aplica y restaura, `unload()` limpia todo. No se probó en el cliente de Roblox en vivo.
