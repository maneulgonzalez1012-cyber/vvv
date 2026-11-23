# breaker — Break In 2

A Rayfield **Gen2** menu for *Break In 2* (Cracky4), built from small modules,
tested without a game client, and shipped obfuscated with Prometheus.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/3fa3ee03-vvv/breakin2/dist/breakin2.obf.lua"))()
```

The published file is `dist/breakin2.obf.lua`; the readable bundle it is built
from is `dist/breakin2.lua`.

## What it does

Every tab starts **off**. Nothing fires a remote until you flip a switch, and
the two global escapes are on the Safety tab.

| Tab | What's in it |
| --- | --- |
| **Home** | where you are (base / lobby / private), enemy count, resolved remote count, rescan button, panic button |
| **Training** | Strength/Speed loop through `RainbowWhatStat`, per-stat interval, jitter, stop-at-N-pips, one-shot bursts |
| **Items** | food via `GiveTool`, weapons and armour via `Vending`, stack x10, heal self, heal everyone |
| **NPCs** | Uncle Pete's key, Louise for Detective Beans, feed Twado (reads which food the GUI is asking for), clear the fallen-tree roadblock, teleports |
| **Combat** | throttled `HitBadguy` loop, damage/hits/range, skip boss, single bursts, client-side freeze |
| **Move** | WalkSpeed, JumpPower, noclip, BodyVelocity fly — all local, no remotes |
| **World** | brightness / no fog, anti-mud, anti-wind, cash pickup, cash loop |
| **Enemies** | `Highlight` per enemy plus a distance/HP list |
| **Roles** | free kid roles (`OutsideRole`) in the lobby only, role pads |
| **Safety** | kill switch, dry-run, remote table, reset counters |

## Remote knowledge

Names and argument shapes came from scripts that were working against the live
game, not from guesses:

- `Events.RainbowWhatStat:FireServer("Strength" | "Speed")`
- `Events.HitBadguy:FireServer(enemyModel, damage, hits)`
- `Events.GiveTool:FireServer("GoldenApple")` — no spaces in tool names
- `Events.Vending:FireServer(3, "Crowbar3", "Weapons", playerName, 1)`
- `Events.HealTheNoobs:FireServer()` with a Golden Apple equipped
- `Events.Energy:FireServer(25, "Pizza")`
- `Events.KeyEvent:FireServer()`, `Events.LouiseGive:FireServer(2)`
- `Events.CatFed:FireServer(itemName)`, `Events.RoadMissionEvent:FireServer(1, part, 5)`
- `ReplicatedStorage.RemoteEvents.OutsideRole:FireServer("Phone" | "Book", true, false)`

Damage is kept at golden-crowbar tier (64.8) rather than a fantasy number,
because the server clamps against its own weapon table — a huge value just gets
clamped, or gets the shot dropped.

## Design rules

- **One gate for every remote.** `core/net.lua` owns the kill switch, dry-run,
  per-remote throttle and the missing-remote report. A feature cannot fire
  around it.
- **Loops are cancellable.** `U.loop(name, …)` invalidates the previous token,
  so flipping a toggle twice cannot leave two loops running.
- **Reversible.** Mud and wind are `CanTouch = false`, brightness keeps a
  pristine snapshot of the six Lighting fields it touches, freeze unanchors
  everything on the way out. Nothing deletes a mission object.
- **Discovery, not assumption.** Folders are looked up by name with a deep
  fallback; if a folder is gone the feature says so instead of erroring.
- **Lobby-only features check the place.** Roles refuse to run on the base.

## Build

```bash
PROMETHEUS=~/Prometheus/cli.lua LUA=lua5.4 \
LUAU=~/luau/luau LUAJIT=~/luajit/src/luajit ./build.sh
```

What the script does:

1. `build/pack.py` bundles `src/` into `dist/breakin2.lua` — one chunk, a module
   table, `require("core/net")` resolved in-process. It also emits
   `build/out/gate.luau`, the whole tree with a Roblox stub.
2. The gate runs under the Luau CLI: every module loads, `main` runs, then
   **every menu callback is fired** (toggles on and off, sliders at two values,
   dropdowns with each option). A callback that errors fails the build.
3. `luau-analyze --mode=nonstrict` over the bundle; only `Unknown global`
   findings are tolerated, since those are the Roblox and executor API.
4. Prometheus with `build/prometheus.medium.lua`.
5. `build/verify.py` produces two runners for the obfuscated chunk — one for
   LuaJIT (Lua 5.1, i.e. what executors run) and one for Luau (what Roblox
   runs) — and both must print `VERIFY OK`.

### Why not stock `--preset Medium`

Stock Medium ends with `NumbersToExpressions`. Its output failed to *load* in
LuaJIT and Luau — it died inside Prometheus's own generated runtime before the
first user statement, in both the full build and a six-line test. Every other
Medium step is kept (Vmify, EncryptStrings, AntiTamper, ConstantArray,
WrapInFunction, Cff), which is why `build/prometheus.medium.lua` exists and why
the verify step is part of the build rather than an afterthought.

Obfuscation is not the same as undetectable: this is an external menu, and the
server still sees every remote that the toggles fire.
