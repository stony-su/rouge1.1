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

Most files are byte-identical between the two copies (modulo line endings), so the same Edit
`old_string`/`new_string` works in both. Verify a pair with:

```bash
diff <(tr -d '\r' < admin/FILE) <(tr -d '\r' < BlockBreakoutGame/FILE)
```

**Exceptions:**
- `ballpit.lua` **differs** between builds — `admin/ballpit.lua` has terminal hooks and extra
  comments; function bodies are equivalent but NOT byte-identical and line numbers differ
  (admin is ~+350 lines offset). **Find anchors per-file before editing**; don't trust line numbers.
- `powerup.lua` should stay byte-identical between the two builds.

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
