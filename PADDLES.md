# BALL PIT X — Paddle Loadouts (design spec)

Run-start **loadouts**: picking a paddle reconfigures the whole run. Each one
rewrites a core verb, so stats are balanced by tradeoffs, not flat power.

> All numbers are **× the Standard baseline** unless noted, and are a FIRST-PASS
> design pass — untested, expect to retune after playtesting. Baseline =
> Width 36px, Move 220, ball speed/charge/aim/dmg/XP/combo = 1.0, HP = 5 hearts,
> start with 2 balls.

---

## Stat columns — what each one means

| Stat | Meaning |
|---|---|
| **Size** | Paddle hitbox width (base 36px). Big = easy ball catches + bullet blocking, but clumsy precise aiming. Small = nimble but drops balls / lets bullets through. |
| **Move** | Paddle lateral movement speed (base 220). |
| **Ball** | Starting ball **base speed** (per-hero ~140–200). Faster = more hits/sec but harder to track and catch. |
| **Charge** | How fast a ball's `speed_mult` ramps **per paddle bounce** (base ×1.07, up to a cap). The "reward for juggling" stat — high Charge makes chains escalate damage fast. SEPARATE from Ball. |
| **Aim** | Width of the reflection arc you steer via edge-offset hits (base ±60°). Wider = easier to redirect but looser; narrower = precise but demanding. |
| **Dmg** | Ball contact + ability damage multiplier. |
| **XP** | XP gain rate / leveling pace. `FLAT` = no scaling curve (every level costs the same). |
| **Combo** | Combo-point **gain AND loss** rate — how fast the ULTRAKILL meter builds and how hard it bleeds on a drop. |
| **HP** | Player health (base 5 hearts). `BAR` = a continuously draining health bar instead of discrete hearts. |
| **Start Ball** | The hero type you begin the run with. |
| **Count** | How many balls you start with. |

---

## Stat table (× baseline)

| Paddle | Size | Move | Ball | Charge | Aim | Dmg | XP | Combo | HP | Start Ball | Count |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Standard** | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 5♥ | Vagrant | 2 |
| **Pinball Lobber** | 0.5 | 1.1 | 1.4 | 1.8 | 1.5 | 1.2 | 1.0 | 1.4 | 5♥ | Scout | 2 |
| **Aegis** | 1.4 | 0.6 | 0.7 | 0.2 | 0.5 | 0.7 | 0.9 | 0.6 | 7♥ | Cleric | 2 |
| **Mitosis** | 1.0 | 1.0 | 1.0 | 0.9 | 1.0 | 0.5 | 1.4 | 1.3 | 4♥ | Vagrant | 1 |
| **Hive** | 1.0 | 1.0 | 0.8 | 0.7 | 0.8 | 0 ✦ | 1.6 | 0.9 | 4♥ | Infestor | 3 |
| **Vampire** | 0.9 | 1.2 | 1.3 | 1.2 | 1.1 | 1.5 | 1.0 | 1.2 | BAR | Barbarian | 2 |
| **Boomerang** | 1.0 | 1.0 | 1.2 | 0.6 | 1.3 | 1.4 | 1.0 | 0.7 | 5♥ | Swordsman | 2 |
| **Twin Cast** | 1.0 | 0.9 | 1.0 | 1.0 | 0.9 | 1.6 | 0.5 | 1.1 | 4♥ | Spellblade | 4 ✦ |
| **Phantom** | 0.8 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 1.0 | 4♥ | Assassin | 2 +blink |
| **Tesla** | 1.0 | 1.0 | 0.8 | 0.8 | 0.9 | 1.4 | 1.0 | 1.1 | 4♥ | Wizard | 4 |
| **Glacier** | 1.0 | 0.8 | 1.5 | 1.3 | 0.6 | 1.1 | 1.0 | 1.2 | 5♥ | Cryomancer | 2 |
| **Terrorist** | 1.0 | 1.0 | 1.1 | 1.0 | 1.0 | 1.6 | FLAT ✦ | 1.0 | 3♥ | Bomber | 3 |

**✦ notes:** Hive deals **0 contact damage** (the critters are the damage).
Twin Cast Count 4 = 2 hero types **mirrored**. Terrorist XP **FLAT** = every
level costs the same fixed XP (no scaling curve).

---

## What each paddle (block) does

### Standard — *the baseline*
Flat reflective paddle, 5 hearts, all stats 1.0. The reference everything else is
measured against. Balanced; no signature power.

### Pinball Lobber — *aggro / aiming*
Two angled **flippers with a central drain gap** (like a real pinball table). Tap
left/right to flip a side and **lob a ball upward with force + spin**. Hits hard
and keeps balls upstairs in the swarm (Charge 1.8, Combo 1.4).
- **Downside:** the center gap means balls can drain straight down the middle —
  no safety net (Size 0.5).
- **Hook:** rewrite `Paddle:update` movement + `on_ball_bounce` into flipper
  impulses; two fixtures with a gap between them.

### Aegis — *defensive / grind*
Spawns a **bottom wall** (the pit is closed): balls auto-bounce off it instead of
recalling, so they **never charge speed via paddle bounces** (Charge 0.2, hence
low Ball/Dmg). The paddle **reflects enemy bullets** back as damage and **hurts
any ball that touches it** — you want balls on the bottom wall, not on you. Tanky
at 7 hearts.
- **Downside:** no speed/charge ramp = low scaling damage; slow defensive grind.
- **Hook:** `reset_run` adds a bottom wall + disables `BallHero:start_return`;
  bullet-reflect in the paddle collision callback.

### Mitosis — *snowball / swarm*
Each brick kill spawns a **temporary clone ball (2.5s life)**. If any hero variant
has **zero balls live, it auto-regrows**, so you never permanently lose a hero.
Clean clears snowball into a screen full of balls (XP 1.4, Combo 1.3).
- **Downside:** clones hit soft (Dmg 0.5/ball) and clutter the screen; bursty,
  inconsistent uptime. Starts with just 1 ball.
- **Hook:** `BallPit:on_brick_killed` → spawn a temp `BallHero` with
  `t:after(2.5, …dead)`; plus a missing-variant regrow check.

### Hive — *critter swarm / DoT*
Balls deal **0 contact damage**; instead every bounce/hit **spawns mini critters
(maggots)** that inherit the hero's ability and swarm bricks. Damage is volume,
not impact (XP 1.6 from many small kills).
- **Downside:** very weak single-target (suffers vs tanks and the boss); slow
  ramp-up.
- **Hook:** `BallHero:on_brick_hit` dmg → 0; spawn `AllyCritter` carrying the
  hero's behavior on each bounce.

### Vampire — *high-risk aggro*
HP becomes a **continuously draining bar** instead of hearts; **killing bricks
restores HP** (lifesteal). It's a race — stop killing and you die (Dmg 1.5,
Move 1.2 to keep the pressure on).
- **Downside:** idle = death; a bad spawn lull can spiral you out.
- **Hook:** `reset_run` HP as a float + drain in `update`; heal in
  `on_brick_killed`; rewrite the `draw_hud` HP readout to a bar.

### Boomerang — *control / lanes*
Balls **return to the paddle after hitting any wall**, dealing damage on the way
back (double-pass lanes). Always recoverable, very controlled (Dmg 1.4, Aim 1.3).
- **Downside:** low screen coverage and few wild wall-chains (Charge 0.6,
  Combo 0.7) — you only hit where you aim.
- **Hook:** in the ball's wall-collision callback, set velocity back toward the
  paddle and flag a damaging return state.

### Twin Cast — *ability spam*
Every drafted hero is **mirrored into two balls**, and abilities fire at **double
frequency** (halved cooldowns). Raw ability-spam build (Dmg 1.6, Count 4).
- **Downside:** **XP 0.5×** (much slower draft) and heavy screen clutter balance
  the power.
- **Hook:** `add_hero` spawns 2; halve `cd` in `setup_continuous_attack`.

### Phantom — *mobility / skill*
Press **E** to drop a **ghost paddle anchor** at your current spot (it still
bounces balls); press **E again** to **teleport back** to it. A blink for dodging
bullet patterns then snapping back to catch. Near-baseline stats — the power is
the blink.
- **Downside:** purely defensive utility (no offense bonus), blink cooldown, and
  a badly-placed anchor punishes you (Size 0.8, 4 hearts).
- **Hook:** bind `'e'` in `main.lua`; ghost-paddle object + teleport in
  `Paddle:update`.

### Tesla — *chain / go-wide synergy*
Every paddle bounce arcs **chain lightning between all live balls**, zapping
bricks the arcs cross. Each ball is weak alone (Ball 0.8) but a crowd is lethal —
damage **scales with ball count** (starts with 4), so it loves Mitosis/Twin-Cast
support.
- **Downside:** near-useless down to one ball; low individual ball speed/charge.
- **Hook:** on ball→paddle bounce, run `do_chain_lightning` across
  `self.heroes`.

### Glacier — *pucks on ice*
Balls behave like **pucks on ice**: friction/damping ≈ 0 with high restitution, so
they **keep momentum and glide long, curving paths** covering huge ground — but
are hard to steer (Aim 0.6) and the paddle itself slides (Move 0.8). Every brick
hit chills/slows it (Ball 1.5 glide).
- **Downside:** low control; pucks go where the physics sends them, not where you
  want them.
- **Hook:** ball `set_friction(0)` / `set_damping(~0)` + high restitution;
  `apply_slow` on `BallHero:on_brick_hit`.

### Terrorist — *glass bomber*
**No XP scaling** — every level costs the same flat XP (slow start, but you
out-level hard in the late game). Balls **self-detonate on a timer** for an AoE
blast that **applies that ball's own effect** (a Pyromancer ball → burn blast, a
Cryomancer ball → freeze blast), then re-form at the paddle. Glass cannon at 3
hearts (Dmg 1.6).
- **Downside:** fragile; timing-dependent; the flat XP curve is a slow opener.
- **Hook:** pin `xp_to_next` to a constant; per-ball `t:after(fuse)` →
  `do_splash` + apply the ball's effect + respawn at the paddle.

---

## Implementation notes
- These would live in a `PADDLES` data table (one entry per paddle, the stat
  columns above as fields + a `signature` flag the run reads in `reset_run`).
- The stat multipliers feed existing systems: Ball/Charge → `BallHero` speed +
  `speed_mult_step`; Aim → the `±π/3` term in `Paddle:on_ball_bounce`; XP →
  `gain_xp` / `xp_to_next`; Combo → the `COMBO_*` gain/penalty; Size/Move →
  `Paddle:init`/`update`; HP → `reset_run`.
- DUAL-BUILD: any actual gameplay implementation must go into BOTH
  `BlockBreakoutGame/` and `admin/` (see MEMORY / GAME_CODE_SUMMARY.txt).
- This is a design doc only — nothing here is wired up yet.
