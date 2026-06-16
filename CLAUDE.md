# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Ball Pit X** — a LÖVE2D (Love2D 11.3, Lua) roguelike that fuses Arkanoid/Breakout with a
vampire-survivors swarm loop and an ULTRAKILL-style combo meter. You control a paddle; your
"heroes" are bouncing balls (SNKRX archetypes) that auto-attack; enemy "bricks" drift down in
swarms and breach the paddle for HP damage.

There is **no build step, no test suite, and no linter**. The game runs directly under LÖVE.

## Running the game

```bat
BlockBreakoutGame\run.bat   :: launches LÖVE with --console on the bundled engine\love\love.exe
```

`admin\run.bat` does the same for the admin/playtest build.

**You cannot run or test the game in this environment** — there is no Lua interpreter here and
LÖVE opens a GUI window. Every gameplay/UI edit is therefore **UNTESTED** until the user runs
`run.bat`. Always say so, and ask the user to playtest.

## CRITICAL: dual-build sync

There are **two parallel copies** of the game. Every gameplay change must be applied to **both**:

- `BlockBreakoutGame/` — uses **LF** line endings.
- `admin/` — uses **CRLF** line endings; this is the **PLAYTEST build**. It additionally has
  `admin/terminal.lua`, a debug console that can spawn powerups / force state.

Many files are *near*-identical between the two copies (modulo line endings), so the same Edit
`old_string`/`new_string` usually works in both — but several diverge in small ways, so **find
anchors per-file and verify each pair** (don't assume a clean whole-file diff):

```bash
diff <(tr -d '\r' < admin/FILE) <(tr -d '\r' < BlockBreakoutGame/FILE)
```

**Known divergences (verified — more files differ than just `ballpit.lua`):**
- `ballpit.lua` differs most — `admin/` has terminal hooks, godmode (`if not arena.god` around
  HP loss), boss-trace methods, and **`sdt` (scaled dt) in the main update loop** (shipping uses
  `dt`). Bodies are equivalent but line numbers are offset (admin ~+350 lines).
- `ball_hero.lua` — `admin/` draws level pips in `BallHero:draw`.
- `effects.lua` — admin/shipping diverge around the water-wave block, `spawn_bounce_sparks`
  placement, and a `WallArrow` comment dash. `brick.lua` — minor comment/note differences.
- `powerup.lua` / `projectile.lua` should stay byte-identical between the two builds.

The function bodies you actually edit are almost always identical across builds, so the same
anchor works — the divergences are in *other* parts of the file. Proven workflow: edit
`BlockBreakoutGame/` first, apply the same `old_string`/`new_string` to `admin/`, then
LF-normalized `diff` each pair and confirm only the known divergences above remain.

`assets_from_SNKRX/` is the original SNKRX source kept as **reference material** — it is not part
of the running game; do not edit it to change gameplay.

## Authoritative deep references (read these first)

- **`GAME_CODE_SUMMARY.txt`** — the canonical, regularly-updated deep-dive on every subsystem
  (engine facilities, boot flow, every game file, the collision matrix, and a "where to tune X"
  index). Read it before any non-trivial change; keep it current when architecture shifts.
- **`PADDLES.md`** — design spec for the run-start paddle "loadouts" feature (13 paddles, each
  rewriting a core verb via stat multipliers + a signature power).

## Architecture (big picture)

```
conf.lua    -> love.conf: 720x984 window, identity "BallPitX"
main.lua    -> entry: requires modules in order, binds input (WASD move, arrows aim,
               space launch, enter confirm, m1 click, r restart), loads SFX/music,
               creates Main() + BallPit, runs engine_run{ game 480x656, window 720x984 }
shared.lua  -> global palette, fonts, canvases, hero color table, the 20-hero draft pool
               (trimmed from the 57 SNKRX archetypes; every paddle's start_balls must stay in it);
               shared_draw composites background + main (stencil) + drop-shadow canvases
engine/     -> a327ex/SNKRX-style framework (Object, GameObject, Physics=Box2D wrapper,
               State, Group, Trigger timers, input, graphics, Color, etc.). Rarely edited.
```

- **`ballpit.lua`** is the orchestrator: one large `BallPit` State (~2400+ lines) owning the
  physics world, wave/swarm spawning, combo system, XP/level/draft, powerup + level-orb pity
  timers, breach/damage, and all draw/HUD/overlay code. The collision matrix is set in
  `BallPit:reset_run` (e.g. ball:ball OFF, xp collides with nothing, powerups collide only with
  walls — catch/deflect are proximity box-checks in code, not Box2D contacts).
- **Players:** `paddle.lua` (kinematic paddle, edge-offset reflection, dodge band) and
  `ball_hero.lua` (`HERO_STATS` for the 20-ball roster; behavior families + per-bounce abilities;
  stuck/launch/magnet-recall ball flow).
- **Enemies:** `brick.lua` (one swarm cell; `VARIANTS` table + `cast_*` behaviors),
  `swarm.lua` (a springy 2D chunk of bricks that owns its bricks' positions and breach test),
  `enemies.lua` (critters, bullet-hell `EnemyProjectile`, ally pets, and the wave-10 `Boss`).
- **Pickups / shots / juice:** `xp_orb.lua`, `powerup.lua` (tier-1 instant-catch vs tier-2
  deflect-to-arm kinds), `projectile.lua` (hero shots), `effects.lua` (pure-juice entities).

Game flow: `reset_run` → waves spawn swarms on a timer; balls auto-attack; brick kills drop XP →
levels → 3-card draft; powerups/level-orb on pity timers; combo points gate a damage multiplier;
breaches cost player HP (5). Wave 10 = boss (3 phases); waves 11+ are the hardest tier. Endless
after the boss; no save/meta-progression yet.

### Coordinate gotchas (Love2D is y-DOWN)

- Canvas is fixed `gw=480 x gh=656`, scaled up to the window.
- `graphics.push(x,y,r)` rotates around a point; `graphics.triangle` points RIGHT at angle 0
  (push by `-math.pi/2` to point it UP).
- Arena: left/right/top walls are solid (frictionless, restitution 1); the **bottom is open** —
  missed balls fall into the pit and magnet-recall to the paddle.

### Where to tune things

| Knob | Location |
|---|---|
| Palette / hero colors / draft pool | `shared.lua` (`shared_init`) |
| Per-wave difficulty / enemy mix | `ballpit.lua` `wave_config()` |
| Combo ranks + point tunables | `ballpit.lua` `COMBO_RANKS` / `COMBO_*` |
| Pity timers (powerup / level-up) | `ballpit.lua` `reset_run` |
| Hero stats & behaviors | `ball_hero.lua` `HERO_STATS` |
| Brick variant stats / sizes | `brick.lua` `VARIANTS`, `BRICK_W/H`, `CELL_W/H` |
| Swarm shapes / density | `swarm.lua` `SHAPES`, `generate_cells` |
| Boss HP / phases / attacks | `enemies.lua` `Boss` |
| Powerup kinds + feel | `powerup.lua` `Powerup.KINDS`, init / deflect |
| Paddle size / dodge band / bounce angle | `paddle.lua` |

(See `GAME_CODE_SUMMARY.txt` §10 for the full index.)

## Adding or redesigning a hero (ball)

A hero = a `HERO_STATS` entry + a `BEHAVIORS` attack + an optional custom `skin`, almost all in
**`ball_hero.lua`**. (Mirror every edit into `admin/` — see dual-build sync.) This is the recipe
the assassin / spellblade / barbarian / cleric reworks all followed.

### Where the SNKRX source is

The original 57 SNKRX archetypes live in **`assets_from_SNKRX/`** — reference ONLY, never wired
into the running game; don't edit it to change gameplay. Attacks are in
**`assets_from_SNKRX/player.lua`**:
- Per-character attack *setup* is one big `if/elseif self.character == '<name>' then …` chain
  (starts ~line 24). Read the hero's `attack_sensor = Circle(x, y, R)` → your `range`, the
  `t:cooldown(delay, …)` / `t:every(delay, …)` → your `cd`, and the attack body.
- `Player:shoot(r, mods)` (~line 1791) is the shared projectile spawner (where crit / damage
  multipliers are applied).
- Projectile *motion* and *on-hit* are further down — search the same `self.character == '<name>'`
  (e.g. spellblade's spiral `orbit_r/orbit_vr` ~2013/2116/2132; assassin's bleed `apply_dot` ~2356).

Porting = translate that hero's sensor / cd / attack into a Ball Pit `BEHAVIORS.<name>`. Adapt
freely: SNKRX heals/buffs allied *units*, but Ball Pit has no ally HP — so e.g. the cleric heals
the *player* instead. Cite the SNKRX `player.lua` line in a comment when you port one.

### The edit points in `ball_hero.lua`

1. **`HERO_STATS.<name>`** (top of file) — the stat block: `r`, `base_speed`, `dmg`,
   `color` (a palette key like `'green'`), `behavior` (keys into `BEHAVIORS`), optional
   `skin = '<name>'`, plus behavior-specific params (`cd`, `range`, `pierce`, `speed`, …). The
   character key must also be in `shared.lua`'s draft pool to be draftable.
2. **`BEHAVIORS.<name>`** (the dispatch table, ~line 422) — the attack, run once at ball-init by
   `setup_continuous_attack()`. Two timer shapes:
   - `self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function() … end, 0, nil, 'attack')`
     — fires when an enemy is within `range`.
   - `self.t:every(s.cd, function() … end, 0, nil, 'attack')` — flat timer, no enemy gate (heal /
     zone / constant-stream attacks).
   Always guard `if self.stuck or self.returning then return end`; tag `'attack'` (or `'heal'`).
3. **A `do_<name>` / `shoot_<name>` method** for anything non-trivial. If it references
   `PROJECTILE_DMG_MULT` (= `3.5 * RANGED_DMG_MULT`, the per-shot damage buff) it MUST be defined
   *below* that `local` (~line 850) — the `BEHAVIORS` handlers sit above it, so they call the method
   rather than the bare local.
4. **`RANGED_BEHAVIORS`** (~line 26) — add the behavior key ONLY if it should take the global pace
   tuning (ranged attacks fire 4× slower but hit 2.5× harder). Omit it to keep a custom cadence
   (e.g. a constant stream) and apply the multiplier yourself.
5. **Custom skin** (optional look) — set `skin = '<name>'`, then add four pieces, each next to the
   existing `crescent` / `shuriken` / `shadow` / `lifebloom` examples:
   - **init** in `BallHero:init` (just before `self:set_as_circle`): seed animation state + any
     aftertrail sampler (`self.t:every(dt, function() SomeMote{group = main.current.effects, …} end)`).
   - **update** in `BallHero:update` (before `if self.stuck`): advance spin / pulse, decay a
     cast-flash timer.
   - **draw dispatch**: `elseif self.stats.skin == '<name>' then self:draw_<name>(s)` in `BallHero:draw`.
   - **`BallHero:draw_<name>(s)`** (before `draw_charge`): draw the body; `s` is the spring scale.

### Where the attack itself lives, by type

- **Projectiles** (arrows / knives / blades) → `projectile.lua`: flags in `Projectile:init`, motion
  in `:update`, hit logic in `:on_hit_brick`. Spawn via
  `main.current:fire_projectile_at_nearest(self, opts)` OR build `Projectile{…}` directly **inside
  `arena.t:after(0, function() … end)`** — the Box2D world is locked during collision callbacks.
  `pierce` / `crit` / `bleed` / `orbit_vr` are flags read here.
- **Melee / area / zones** (cleave, slam, consecrated ground) → an effect entity in `effects.lua`
  that runs its own hit test + damage in `:init`/`:update` (see `CleaveArea`, `HexSlamArea`,
  `ConsecratedGround`).
- **Status on enemies** (burn, bleed, slow, curse) → `brick.lua`: fields in init, a tick in
  `Brick:update`, an `apply_<x>` method. (`apply_burn` = burn-to-death scorch; `apply_bleed` = a
  scaled, expiring DoT — separate channels.) Non-brick enemies expose no-op `apply_*`, so guard
  `if brick.apply_<x>`.
- **Pure juice** (trails / auras / bursts) → effect entities in `effects.lua`
  (`X = Object:extend(); X:implement(GameObject)` + init/update/draw), spawned into `arena.effects`
  — or **`arena.floor`** for on-ground things that must sit UNDER the paddle/balls (the floor group
  is drawn before `main`; added for the cleric heal sigil).

### Drawing notes (LÖVE 11)

- Use `self:current_dmg()` for ALL damage — it folds in charge bonus, ally buffs and the loadout
  Dmg stat.
- Palette globals from `shared.lua`: `green[0]`, `red[0]`, `blue[0]`, `bg[-2]`, `fg[5]`, …;
  `Color(r,g,b,a)` (0–1 floats) for custom colors.
- `graphics.circle / rectangle / line / polygon / polyline / arc`. **`graphics.polygon` fills
  CONVEX polygons only** — build concave shapes (curled flower petals, crescents) from a strip of
  convex quads.
- `graphics.push(x, y, r, sx, sy)` rotates+scales around a point; a non-uniform scale + a circle
  draws an ellipse.
- Enemy lists: iterate `arena.main.objects`, filter `o:is(Brick) / o:is(EnemyCritter) / o:is(Boss)`,
  range via `math.distance`. Useful arena helpers: `get_nearest_brick_within`,
  `get_random_brick_within`, `has_brick_within`, `get_bricks_within`, `breach_line_y` (the red
  defense line — paddle side below, enemy side above), `heal_hearts(n)`, `arena.paddle`.

## Current work in progress

`BlockBreakoutGame/paddles.lua` is a new, uncommitted partial implementation of the `PADDLES.md`
loadout spec (the `PADDLES` data table, persistent meta-state/wallet, signature helpers, and a
shop screen that replaces the game-over overlay). It is **not yet wired in** — `main.lua` does not
`require 'paddles'` and there is no matching `admin/paddles.lua`. When this feature lands, it must
be added to the require chain (after the other game modules) and mirrored into `admin/`.

## Conventions / gotchas

- The user edits files concurrently and a linter touches them, so **line numbers shift**. Re-grep
  for anchors before editing; don't trust cached line numbers.
- `engine/sound.lua` is a stub; audio goes through `engine/external/ripple.lua` (sfx/music tags).
- Git: branch off `main` before committing; **commit/push only when asked**; end commit messages
  with the `Co-Authored-By` trailer.
</content>
</invoke>
