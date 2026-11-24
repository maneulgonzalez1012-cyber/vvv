# breaker — Break In 2

A Rayfield **Gen2** menu for *Break In 2* (Cracky4), built from small modules,
tested without a game client, and shipped obfuscated with Prometheus.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/3fa3ee03-vvv/breakin2/dist/breakin2_v2.obf.lua"))()
```

The published file is `dist/breakin2_v2.obf.lua`; the readable bundle it is
built from is `dist/breakin2.lua`. The filename changes between releases on
purpose — a cached old file at the same URL is indistinguishable from a fix
that did not work. The **Home** tab prints the build id; if it does not say
`2026.11.23-c`, you are still running an old chunk.

## What it does

Every tab starts **off**. Nothing fires a remote until you flip a switch, and
the two global escapes are on the Safety tab.

| Tab | What's in it |
| --- | --- |
| **Home** | where you are (base / lobby / private), enemy count, resolved remote count, rescan button, panic button |
| **Training** | Strength/Speed loop through `RainbowWhatStat`, per-stat interval, jitter, stop-at-N-pips, one-shot bursts |
| **Items** | 29 objects in four dropdowns, every one reporting whether it actually arrived; stack x10, all weapons at once, survival kit, backpack readout, **+HP out of nothing and semi godmode** |
| **NPCs** | Uncle Pete's key, Louise for Detective Beans, clear the fallen-tree roadblock, teleports |
| **Twado** | read what he wants from either UI, feed him, or leave a **watcher** running that checks every 2 s and feeds by itself |
| **Combat** | throttled `HitBadguy` loop, damage/hits/range, skip boss, single bursts, client-side freeze |
| **Move** | WalkSpeed, JumpPower, noclip, BodyVelocity fly — all local, no remotes |
| **World** | brightness / no fog, anti-mud, anti-wind, cash pickup, cash loop |
| **Enemies** | `Highlight` per enemy plus a distance/HP list |
| **Roles** | free kid roles (`OutsideRole`) in the lobby only, role pads |
| **Safety** | kill switch, dry-run, remote table, reset counters |

## Items

Two remotes hand out objects, and the split is not "food vs weapons":

| Route | Call | Objects |
| --- | --- | --- |
| give | `GiveTool:FireServer(name)` | Apple, Cookie, Chips, Pizza, Lollipop, Bloxy Cola, Expired Bloxy Cola, Bottle, MedKit, Key, GoldKey, Louise, Phone, Book, Ladder, Battery |
| food | `Vending:FireServer(3, name, "Food", playerName, 1)` | RainbowPizza, RainbowPizzaBox |
| weapon | `Vending:FireServer(3, name, "Weapons", …)` — 4 variants, see below | Crowbar1/2/3, Bat, Wrench, Pitchfork, Hammer, Broom |
| gold_armor | `Vending:FireServer(3, "Armor2", "Armor", ...)` | the golden armour |
| auto | give, then food | GoldenApple, GoldPizza — sources disagree, so both are tried |

Every button waits for the tool to appear in the character or backpack and
reports what happened: `obtenido (give)` or `no llego: give fired, nothing
arrived`. That check exists because firing a remote is not the same as being
given the object — the server refuses quietly when the level gate, the
location or the money is wrong, and a button that claims success teaches
nothing.

Names were verified against two working scripts, not invented: `GiveTool` wants
the tool name with no spaces (`BloxyCola`, `GoldenApple`, `MedKit`, `GoldKey`),
and the drinks are `BloxyCola` / `ExpiredBloxyCola`, not the in-game display
names.

### Weapons, and why they were the broken half

Every public script fires `Vending(3, name, "Weapons", X, 1)` but `X` differs
in each one — the player's name, the `LocalPlayer` object, or nothing — and one
of the popular hubs is labelled *"the only thing that's lacking in this script
is the weapons"*. Picking one spelling and hoping is how a weapon button ends up
doing nothing, so the four shapes are tried in order and **the one that produced
a tool is cached**:

| Variant | Arguments |
| --- | --- |
| `name` | `3, "Crowbar3", "Weapons", playerName, 1` |
| `player` | `3, "Crowbar3", "Weapons", LocalPlayer, 1` |
| `no-count` | `3, "Crowbar3", "Weapons", playerName` |
| `bare` | `3, "Crowbar3", "Weapons"` |

The first weapon costs a few extra calls; every later one is a single fire.
*Qué variante de Vending funcionó* in the Items tab shows which one is live, and
the build gate confirms all nine weapon entries end up in the backpack.

## Energy: +HP out of nothing, and semi godmode

`Energy` **is** the health bar in Break In 2: 200 max, 0 is instant death. What
the working scripts show is that the heal is not the food:

| Call | Effect |
| --- | --- |
| `Energy:FireServer(25, "Pizza")` | the shape every BI2 script uses, +25 |
| `Energy:FireServer(75, "GoldPizza")` / `(999, "GoldenApple")` | the bigger tiers |
| `Energy:FireServer(999999)` | **this one is from Break In 1**, where the remote lives in `ReplicatedStorage.RemoteEvents` — not evidence for BI2 |
| `Energy:FireServer(-amount, false, false)` | **subtracts** — this is how damage is applied |

An earlier build assumed the bare-amount shape worked in BI2 because a search
result showed one. It does not follow: that script also calls `HealPlayer` and
`Energy("Cat")`, neither of which exists in BI2. So the heal is now sent the way
BI2's own scripts send it — amount **and** the matching food name — and then the
Humanoid is read, because the client mirrors server health. The shape that moved
the bar is cached; if none does, **por qué no sube (diagnóstico)** sweeps five
shapes and prints what each one did, so the answer comes from the game instead of
from a guess. There is also *sumar esa cantidad* (5–200) and
*llenar la barra*, which reads `MaxHealth` and sends the missing difference once.

**Semi godmode** is a second mechanism, and it is the one the public scripts
use: boss attacks apply their damage *through this same remote* with a negative
amount, so `__namecall` is hooked and a negative is clamped to `0`. That needs
`hookmetamethod` / `getrawmetatable`, so the feature reports honestly:

- supported executor → the hook goes in, the status shows
  `hook activo | negativos bloqueados: N`;
- unsupported → it says so and still runs the periodic top-up;
- minion hits are applied server-side, which no client hook can stop — the
  top-up covers those, one heal per 0.6 s under the floor you pick.

*Quitar el hook* restores the original `__namecall`.

## Twado

What he wants is exposed in two places, and older scripts read only one, which
is why the button did nothing until the phone was open:

- `PlayerGui.Phone…DogInfo.TwadoWants.Text`
- `PlayerGui.Assets.Note.Note.Note` → children named `Circle<Item>` whose
  `Visible` flag marks the wanted food

Both are read on every check. The watcher polls every 2 s (a once-a-minute
event in game, not a combat loop), reads first and only then feeds — the wrong
food costs 10 energy. Three failed attempts and it stops and says so instead of
cycling through his whole diet. There is also a *forzar comida* button for when
the UI is blank and you already know what he wants.

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
- **Hand-triggered actions wait their turn.** `Net.fire` drops a call that
  arrives inside the remote's throttle window, which is right for a loop but
  wrong for a button. Items, NPC steps and training use `Net.fire_wait`, which
  sleeps out the remaining gap. The old x10 was losing half its calls to that
  gate.
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
4. The bundle is split into 4 parts of ~25 KB and each is obfuscated with
   `build/prometheus.medium.lua`. Prometheus's Cff pass flattens a chunk into
   one function and LuaJIT caps a function at 65536 constants; the whole bundle
   in one chunk produced ~70k constants and the obfuscated file would not even
   parse. Parts stay a third under the limit.
5. `build/assemble.py` embeds the obfuscated parts into `dist/breakin2.obf.lua`,
   which is still the single file you publish.
6. `build/verify.py` produces two runners for that assembled file — one for
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

## Bugs this build caught

Recorded because each one was silent in game, and each is now covered by the
gate:

- items never arrived: the tool name was sent with the display spelling, and
  the vending route was only used for weapons;
- weapons: the fourth vending argument was a guess, so it is now probed and
  cached;
- the semi-godmode cooldown compared against `0` as if it were a timestamp, so
  the first heal could never fire;
- x10 fired ten times and delivered about five — call spacing equalled the
  throttle window, so half were rejected;
- `Items.equip` reparented a tool that did not exist yet, because `await`'s
  return value was discarded;
- noclip and fly added a new connection on every enable, so on/off/on left two
  loops fighting over the character;
- "skip boss" matched the model's name against `Boss`, which never matched:
  boss minions live in a folder called `BadGuysBoss` and the brutes arrive as
  `BadGuyBrute`;
- the role pad button touched every unnamed `Part` in the workspace, hazards
  included;
- the enemy highlight only ever parented to `CoreGui`, which most executors
  protect.
