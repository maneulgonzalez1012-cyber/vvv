# Aero :: Milonarie Tycoon

Exploit en Lua para ejecutar dentro del juego con cualquier executor (Synapse, KRNL, Fluxus...).
El nucleo no depende de saber los nombres de los remotes: **captura la forma real de los
argumentos que el juego manda, y los reproduce**.

## Como funciona

1. **Spy** — hook de `__index` sobre `game` intercepta `FireServer` / `InvokeServer`.
   Cada llamada queda registrada con su path y sus argumentos reales.
2. **Auto-bind** — el path se clasifica por nombre (`collect` / `buy` / `rebirth`) y se
   liga a la accion correspondiente. Si falla, se liga a mano en la tab TARGET.
3. **Replay** — el farm dispara el remote ligado con los args capturados. Con
   `Inflar cantidad` reescribe el argumento numerico para intentar forzar el pago.
4. **Fallback fisico** — si el juego cobra por ProximityPrompt o tocando partes de
   dinero, el modo `physical` camina al objetivo y/o dispara el prompt
   (`fireproximityprompt` -> `fireclickdetector` -> caminar encima).

## Uso

1. Abre el juego, entra a un server.
2. Pega `dist/milonarie_tycoon.lua` en el executor.
3. `RightShift` abre/cierra el menu.
4. Tab **FARM**: activa `Autofarm`, elige modo (`hybrid` / `remote` / `physical`).
5. Si el remote aparece sin ligar: haz **una vez** la accion real en el juego (cobrar,
   comprar, renacer) para que el spy capture los args, y luego `Auto-bind` (o el boton
   `C` / `B` / `R` de cada remote en la tab TARGET).

Tabs: `FARM` (farm, intervalos, inflate), `MOVE` (speed, fly, noclip, infinite jump,
anti-AFK, TP), `TARGET` (remotes capturados y bindings), `CONFIG` (save/load JSON).

## Build

```
python3 build.py            # src/ -> dist/milonarie_tycoon.lua
python3 build.py --check    # + syntax check de cada modulo y del dist
```

Test sin Roblox (mock de la API en `tools/roblox_mock.lua`):

```
.venv/bin/python tools/mock_run.py                 # Lua 5.5
.venv/bin/python tools/mock_run.py --runtime lua51 # Lua 5.1
```

Carga el script entero contra el mock, construye la UI y ejercita
captura -> auto-bind -> replay con override de argumento (15 asserts).

## Ofuscado (Prometheus)

```
.venv/bin/python tools/prometheus_build.py --preset Medium --verify
```

Clona `prometheus-lua/Prometheus` en `~/.cache/prometheus-lua/`, ofusca `dist/milonarie_tycoon.lua`
y deja el payload en `release/`. Con `--verify` comprueba que el payload ofuscado sigue pasando
las 15 asserts del mock en Lua 5.1 y Lua 5.5.

Variantes: `--preset Strong`, `--drop-step Vmify` (version ligera sin VM).
Detalles y tabla de tamaños: `release/README.md`.

## Hotkeys

| Tecla | Accion |
|---|---|
| `RightShift` | abrir/cerrar el menu |
| `W A S D` + `Space` / `LeftControl` | fly (mientras este activo) |

## Ajustes

Todo esta en `src/config.lua`: patrones de clasificacion de remotes, intervalos,
radio de busqueda, cantidad a inflar (`argIndex` / `value` / `cap`), velocidades.

## Pendiente del target

No se pudo confirmar el place exacto de "Milonarie Tycoon" desde fuera, asi que el
script aprende solo. Si el auto-bind no pilla el remote correcto, hay dos formas:

- ligar a mano en la tab TARGET (botones `C` / `B` / `R`), o
- pegar el path real del remote (ej. `ReplicatedStorage.MoneyService.Claim`) en
  `src/config.lua` para dejarlo fijo.

El `argIndex` de `Inflar cantidad` depende de que argumento lleva la cantidad en el
remote del juego: si el remote recibe `(amount)`, es `1`; si recibe `(id, amount)`, es `2`.
