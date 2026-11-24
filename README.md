# vvv
vanta creation

## Aero / Roblox

`aero_roblox.lua` — ESP, aimbot, triggerbot, radar y fly en Luau. Menú INSERT con pestañas ESP / AIMBOT / MISC / CONFIG.
`loadstring.lua` — loadstring para el executor.

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

### Uso

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/6922546f-vvv/aero_roblox.lua", true))()
```

INSERT = menú · RMB = aimbot mantenido · T = triggerbot · F = fly · WASD + Q/E (o espacio/ctrl) = mover · CONFIG guarda/carga `aero_roblox_config.json`. Todo apagado al cargar.
