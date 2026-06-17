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
| **Pinball Lobber** | 0.5 | 1.1 | 0.7 | 1.4 | 1.5 | 1.3 | 1.0 | 1.4 | 5♥ | Scout | 2 |
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
| **Cannon** | 0.9 | 1.0 | 0.6 | 1.7 | 0.9 | 1.5 | 1.0 | 1.1 | 4♥ | Cannoneer | 2 |

**✦ notes:** Hive deals **0 contact damage** (the critters are the damage).
Twin Cast Count 4 = 2 hero types **mirrored**. Terrorist XP **FLAT** = every
level costs the same fixed XP (no scaling curve).

---

## What each paddle (block) does

### Standard — *the baseline*
Flat reflective paddle, 5 hearts, all stats 1.0. The reference everything else is
measured against. Balanced; no signature power.

### Pinball Lobber — *real-table physics / timing*
Two long **flippers with a central drain gap**, played like a real pinball table.
Balls obey **gravity** (Ball 0.7 + a low speed cap → slow, easy to track), **roll
off the bats instead of bouncing** (low restitution), and **drain down the centre
gap** if you don't act. Tap left/right to **flip a bat** and lob the resting ball
back up into the swarm with a gentle pop + a per-flip **damage ramp** (Dmg 1.3,
Charge 1.4, Combo 1.4) — boost, not raw speed, so the ball stays catchable.
- **No catch/aim/charge:** a drained ball isn't recalled-and-stuck; it's **dropped
  back in from above the flippers**, and you have to knock it up again.
- **Downside:** the centre gap is an open drain with no safety net (Size 0.5); a
  missed flip means re-serving from scratch.
- **Hook:** `BallHero:pinball_update` (gravity + cap, replaces normalize_speed) +
  `pinball_serve` (drop-in respawn); `Paddle:build_flipper_rig` (two long resting
  bats on one kinematic body) + `Paddle:flip_launch` (tap → upward impulse to
  nearby balls). Ball/flipper restitution low; side walls damped in `reset_run`.

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

### Twin Cast — *binary fusion / burst rhythm*
Every drafted hero is **mirrored into a bonded pair** that **orbits a shared
core**, charging as it swirls. At full charge the twins **FUSE** into one
super-ball that detonates a **nova supercast** — a heavy falloff AoE (hits
bricks, critters AND the boss) carrying the pair's element — then **split apart
and recharge**. Strongest right after a fusion, weakest mid-charge (Dmg 1.6,
Count 4). A twisting tether + charge ring telegraph the build-up; cooldowns are
still mildly cut (`cd_mult 0.75`) so the between-nova pair stays snappy.
- **Downside:** **XP 0.5×** (much slower draft); the nova is on a ~8s active-play
  timer, so the burst is paid for with uptime, not screen clutter.
- **Hook:** `add_hero` spawns + bonds each pair (`twincast_register_pair`);
  `twincast_tick` runs the orbit → charge → fuse → split state machine and fires
  `twincast_fuse_blast` (reusing the Cannon's `do_splash_falloff`); `TwinFusionFX`
  + `TwinNova` draw the bond, charge ring, fused core and shockwave. All in
  `paddles.lua` (+ the `twincast_tick` call and pair registration in `ballpit.lua`).

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

### Cannon — *artillery / Z-axis mortar*
The ball **charges automatically every time it returns to the paddle** after its
attack reaches the furthest wall — the same bounce-return loop the paddle already
uses to ramp speed, no holding needed. A charged ball **fires up into the third
dimension** (out of the screen) and falls back down onto the playfield, crashing
into blocks from above. Depth is sold with a **ground shadow** + **ball scale** +
real gravity on its Z height: the higher the ball rises, the further its shadow
separates beneath it and the larger the ball draws. The **higher the charge, the
faster it bounces up and down** (more crashes per second) and the **bigger the
splash** each landing covers. A **direct hit** (impact centred on a block) deals
heavy damage, with **falloff the further a block sits from the impact centre** —
an AoE that rewards precise drops (Charge 1.7, Dmg 1.5).
- **Downside:** almost no horizontal arena coverage (Ball 0.6) — you hit where it
  lands, not everywhere; weak until the charge ramps over several returns, and
  **dropping the ball into the pit resets its charge**; 4 hearts.
- **Hook:** reuse the existing paddle-bounce charge — each time the ball returns
  to the paddle after reaching the far wall, bump its charge (like `speed_mult`),
  automatically. Give the ball a `z` height + `z_vel` (draw it at `(x, y - z)`
  scaled by z, with a shadow ellipse at ground `(x, y)`) and gravity on z; when
  `z <= 0`, call `do_splash(x, y, radius, dmg, color)` scaling damage by distance
  from the impact centre (the falloff). Charge sets BOTH the up/down bounce
  velocity and the splash radius.

---

## Implementation notes
- These would live in a `PADDLES` data table (one entry per paddle, the stat
  columns above as fields + a `signature` flag the run reads in `reset_run`).
- The stat multipliers feed existing systems: Ball/Charge → `BallHero` speed +
  `speed_mult_step`; Aim → the `±π/3` term in `Paddle:on_ball_bounce`; XP →
  `gain_xp` / `xp_to_next`; Combo → the `COMBO_*` gain/penalty; Size/Move →
  `Paddle:init`/`update`; HP → `reset_run`.
- **Z-axis system (Cannon only):** add a fake `z` height + `z_vel` to the ball, draw it at `(x, y - z)` scaled by height with a ground-shadow ellipse at `(x, y)`, and splash on `z <= 0` — the one paddle that needs out-of-plane rendering; every other paddle is pure 2D.
- DUAL-BUILD: any actual gameplay implementation must go into BOTH
  `BlockBreakoutGame/` and `admin/` (see MEMORY / GAME_CODE_SUMMARY.txt).
- This is a design doc only — nothing here is wired up yet.
