# breaker — Break In 2

A Rayfield **Gen2** menu for *Break In 2* (Cracky4), built from small modules,
tested without a game client, and shipped obfuscated with Prometheus.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/maneulgonzalez1012-cyber/vvv/arena/3fa3ee03-vvv/breakin2/dist/breakin2_v3.obf.lua"))()
```

The published file is `dist/breakin2_v3.obf.lua`; the readable bundle it is
built from is `dist/breakin2.lua`. The filename changes between releases on
purpose — a cached old file at the same URL is indistinguishable from a fix
that did not work. The **Home** tab prints the build id; if it does not say
`2026.11.23-d`, you are still running an old chunk.

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
| **Diagnóstico** | which modules loaded, which failed and why, the remote table, a one-click Energy sweep |

## Architecture: one tab, one file, one failure

The menu used to be a single 800-line `build()`: one bad callback and the rest
of the tab went with it, one failing `require` and the whole chunk died. It is
now a shell plus a folder:

```
src/ui/menu.lua           the window, the HUD loop, and every pcall
src/ui/tabs/home.lua      one file per tab, each returns Tab.build(ctx)
src/ui/tabs/…            training items npcs twado combat move world
                         enemies roles safety diagnostics
```

`Menu.build()` creates the window, loads the modules through a `require` that
swallows a dead module into a stub, then builds each tab inside its own `pcall`:

- a module that throws on load becomes a stub that answers `false, "<name> no
  cargo"` — tabs that mention it still build and their other buttons work;
- a tab that throws loses its own card, and the reason is listed in
  **Diagnóstico**;
- every callback is wrapped where the widget is created, so an error inside one
  button cannot escape into Rayfield's event loop — it is counted, notified and
  written to the log instead.

Loading never aborts the script either: if Rayfield itself fails to load, the
menu reports it and `getgenv().breaker.run("features/items", "obtain", …)` still
drives every feature from the console. `getgenv().breaker` also exposes
`unload()`, `errors`, `net` and `loops()`.

The build proves the isolation instead of claiming it: the gate injects a module
that crashes on load and a tab that crashes on build, and asserts that the other
tabs still come up (`fault injection: crashing module contained`,
`isolation: 1 pestaña rota, 2 siguen construyendo`).

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
./build.sh          # pack, gate, analyze, obfuscate per part, assemble, verify
./build.sh --fast   # everything except obfuscation (source-level check)
```

The toolchain is not vendored; point the build at it:

| Variable | Default | What it is |
| --- | --- | --- |
| `LUAU_BIN` | `/tmp/x_luau/build/luau` | Luau CLI (`Luau.Repl.CLI`) — runs the gate |
| `LUAU_ANALYZE_BIN` | `/tmp/x_luau/build/luau-analyze` | Luau analyzer |
| `LUAJIT_BIN` | `/tmp/x_lj/src/luajit` | LuaJIT 2.1 — runs Prometheus and the 5.1 check |
| `PROMETHEUS_DIR` | `/tmp/x_prom` | Prometheus checkout (its `cli.lua`) |
| `PROMETHEUS_CONFIG` | `build/prometheus.medium.lua` | Medium, minus `NumbersToExpressions` |

Six steps, none optional:

1. **pack** — `build/pack.py` bundles `src/` into `dist/breakin2.lua` (one
   chunk, a module table) and splits the same modules into parts of ~22 KB. It
   also refuses the build for three classes of mistake: a `require` that names a
   file that does not exist, a tab calling `Items.something` that the module
   never defined, and any Luau-only syntax (`+=`, `..=`, `continue`) that the
   Lua 5.1 obfuscation target cannot parse.
2. **gate** — the whole tree runs under the Luau CLI against a Roblox stub, and
   then: every module is loaded in isolation, every tab is built, **every
   callback is fired**, the catalogue is checked entry by entry, and the
   features that were reported broken are exercised end to end — the heal must
   move the health bar +25 without putting a tool in the backpack, the
   semi-godmode hook must block a `-50` Energy call, weapons must arrive through
   the vending route, Twado must read what he wants and feed it.
3. **analyze** — `luau-analyze` over every source file; only `Unknown global`
   findings are tolerated, because those are the executor and Roblox globals.
4. **obfuscate** — each part through Prometheus with
   `build/prometheus.medium.lua`. Parts are small because Cff flattens a chunk
   into one function and LuaJIT caps a function at 65536 constants; the whole
   bundle in one chunk would not parse.
5. **assemble** — `build/assemble.py` embeds the parts into
   `dist/breakin2_v3.obf.lua`, one file, self-contained.
6. **verify** — `build/verify.py` runs the **shipped bytes** under LuaJIT and
   Luau against the same stub, and asserts outcomes rather than an exit code:
   the bundle loads, `main` reaches the end, no module failed, at least 100 UI
   elements were created and no callback threw.

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

Bugs this round caught, all of them silent in game:

- **curar a todos** called `Items.heal_all()`, which did not exist. A button
  wired to a function nobody wrote only fails when a player clicks it, so the
  packer now audits every `Module.method` a tab calls against the module;
- `dist/` shipped a 9 MB bundle because stock Medium's `NumbersToExpressions`
  inflates every numeric literal; the config that already excluded it was lost
  with the tree and is restored;
- the assembled bundle would not parse at all: Prometheus emits `...` at the top
  level of its VM entry, so the per-part wrappers have to accept varargs;
- `..=` and `+=` are Luau-only, and the obfuscation target is Lua 5.1 — the
  enemy-list line and the fly vector were both silently unshippable;
- if Rayfield failed to download, `ui/rayfield.lua` called `error()` and took
  the entire script with it, features included.
