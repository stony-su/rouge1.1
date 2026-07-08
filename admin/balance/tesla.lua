-- ==========================================================================
-- BALL PIT X — DAMAGE MASTER FILE — Tesla paddle
-- ==========================================================================
-- This file is the single source of truth for every damage number in the
-- game WHILE THE Tesla PADDLE IS EQUIPPED. Each paddle has its own copy
-- (balance/<paddle>.lua), so tuning this file never affects other paddles.
--
--   * It is re-read from disk at the start of every run: edit a number,
--     press R in-game, and the new value is live. No game restart needed.
--   * Every key is optional — delete a line (or break the file) and the
--     game falls back to its built-in value for it (a warning is printed
--     to the --console window).
--   * NUMBERS ONLY. Structure (which behavior a hero uses, skins, colors)
--     stays in code.
--
-- Sections: loadout (this paddle's stat multipliers) -> signature (this
-- paddle's power) -> globals -> combo -> on_bounce -> dots -> effects ->
-- enemies -> heroes (all 20 balls).
-- ==========================================================================

return {

  -- Run-wide stat multipliers for this paddle (1.0 = baseline). dmg scales
  -- ALL ball damage; ball = ball speed; charge = paddle-bounce speed ramp;
  -- combo = combo point gain; hp = starting hearts.
  loadout = {
    dmg = 1.4, size = 1.0, move = 1.0, ball = 0.8, charge = 0.8, aim = 0.9,
    xp = 1.0, combo = 1.1, hp = 4,
  },

  -- Persistent conduction web: paddle -> ball -> ball arcs damage every
  -- brick a segment passes near, on a steady pulse.
  signature = {
    zap_dmg   = 7,      -- damage per pulse per brick (x loadout dmg)
    zap_width = 12,     -- how near a brick must be to a web segment
    zap_cd    = 0.25,   -- seconds between pulses
  },

  -- ======================================================================
  -- GLOBAL DAMAGE MULTIPLIERS
  -- ======================================================================
  globals = {
    -- Per-level damage growth for every ball: +40% of base per level
    -- (applied at spawn AND on each level-up in ballpit.lua).
    level_dmg_growth      = 0.4,

    -- Charge-on-paddle: damage bonus at a FULL charge (0.5 = up to 1.5x).
    charge_dmg_bonus_max  = 0.5,

    -- Pinball flippers: each flip multiplies the ball's charge damage by
    -- flipper_charge_step, capped at flipper_charge_cap (paddle.lua).
    flipper_charge_step   = 1.12,
    flipper_charge_cap    = 1.5,

    -- Ranged pace tuning: ranged auto-attacks (arrow/crossbow/knife/
    -- spellblade/random-shot/volcano) fire ranged_cd_mult slower than their
    -- listed cd, and their damage carries ranged_dmg_mult (mortar shells and
    -- volcano eruptions read it directly).
    ranged_cd_mult        = 4.0,
    ranged_dmg_mult       = 2.5,

    -- Per-shot damage multiplier on every arrow / knife / bolt / turret shot
    -- (this is the old 3.5 x ranged_dmg_mult, flattened into one knob).
    projectile_dmg_mult   = 8.75,

    -- Spellblade shard multiplier (fires ~10x/sec and pierces everything, so
    -- it is deliberately much lower than projectile_dmg_mult).
    spellblade_dmg_mult   = 1.5,

    -- Crit multiplier on shots flagged as crits (random-shot heroes).
    crit_dmg_mult         = 2.0,

    -- Scout chain-knife: speed/damage multiplier gained on every chain hop
    -- (damage ramp only applies at level 3).
    chain_hop_speed_mult  = 1.25,
    chain_hop_dmg_mult    = 1.25,
  },

  -- ======================================================================
  -- COMBO METER (rank multiplier applies to ALL ball-contact damage)
  -- ======================================================================
  combo = {
    -- Rank ladder, low -> high. threshold = points needed, mult = the damage
    -- multiplier while at that rank. Labels/colors stay in ballpit.lua.
    ranks = {
      {threshold =    0, mult = 1.0},   -- D
      {threshold =   50, mult = 1.2},   -- C
      {threshold =  150, mult = 1.5},   -- B
      {threshold =  300, mult = 1.9},   -- A
      {threshold =  500, mult = 2.4},   -- S
      {threshold =  750, mult = 3.0},   -- SS
      {threshold = 1100, mult = 3.5},   -- SSS
      {threshold = 1500, mult = 4.0},   -- FRENZY
    },

    -- Per-ball bounce chain: +bounce_dmg_step damage per consecutive bounce
    -- without being caught/dropped, counted up to bounce_cap bounces.
    bounce_dmg_step   = 0.08,
    bounce_cap        = 15,

    -- Point economy (how fast ranks climb / fall).
    base_points       = 10,    -- per brick bounce
    variety_bonus     = 5,     -- + when hitting a different variant than last
    streak_bonus_cap  = 10,    -- + min(streak, cap) per bounce
    miss_frac         = 0.25,  -- fraction of current points lost per pit drop
    miss_min          = 100,   -- ...but never less than that many points
    idle_grace        = 2,     -- seconds without a bounce before decay
    idle_decay_frac   = 0.08,  -- fraction of current points bled per idle second
    idle_decay_min    = 6,     -- ...with this floor so low bars still reach zero
  },

  -- ======================================================================
  -- ON-BOUNCE ABILITIES (wizard / pyromancer / frost / splash triggers)
  -- ======================================================================
  on_bounce = {
    -- Wizard: chain lightning fired on brick bounce.
    chain_dmg_mult      = 0.7,   -- x current damage per bolt
    chain_links_base    = 3,     -- links = base + ball level

    -- Pyromancer: ignites an area on bounce. NOTE: bricks that catch fire
    -- always burn at dots.burn_max_hp_frac (the dps below only matters for
    -- the Boss, which uses the passed dps directly).
    burn_radius         = 32,
    burn_dps_mult       = 2.5,
    burn_duration       = 2.5,

    -- 'slow' on-bounce trigger (chill burst).
    slow_radius         = 32,
    slow_factor         = 0.5,   -- speed multiplier applied to bricks
    slow_duration       = 2.0,

    -- 'big_splash' on-bounce trigger.
    big_splash_radius   = 64,
    big_splash_dmg_mult = 1.1,

    -- 'flagellant_pulse' on-bounce trigger (no cooldown, every bounce).
    flagellant_radius   = 36,
    flagellant_dmg_mult = 0.45,
  },

  -- ======================================================================
  -- DAMAGE OVER TIME (status channels on bricks)
  -- ======================================================================
  dots = {
    -- Burn/scorch: a burning brick loses this fraction of its MAX HP per
    -- second, forever (0.2 = guaranteed dead in at most 5s).
    burn_max_hp_frac    = 0.2,

    -- Fire-trail powerup: burn applied on every ball contact while active.
    -- (Brick burn strength is burn_max_hp_frac; this dps only hits the Boss.)
    fire_trail_dps_mult = 0.4,
    fire_trail_duration = 2.0,

    -- Hive infestation rot.
    infest_rot_frac      = 0.16,  -- fraction of max HP eaten per second at potency 1
    infest_spread_cd     = 1.3,   -- seconds between creeps to a neighbour
    infest_spread_radius = 26,    -- how far the rot can creep
    infest_spread_decay  = 0.7,   -- potency multiplier per hop
    infest_min_spread    = 0.4,   -- potency floor below which it stops creeping
  },

  -- ======================================================================
  -- ABILITY / EFFECT INTERNALS (multipliers inside effect entities)
  -- ======================================================================
  effects = {
    -- Swordsman cleave: total damage = dmg x (1 + per_target_bonus x targets
    -- hit), all x lvl3_mult at level 3. Same shape for the barbarian slam.
    cleave_per_target_bonus  = 0.15,
    cleave_lvl3_mult         = 2.0,
    hexslam_per_target_bonus = 0.15,
    hexslam_lvl3_mult        = 2.0,

    -- Cleric consecrated ground: the spinning outer blades hit for
    -- slice_mult x the ground's dps per touch (the inner AoE tick is the
    -- cleric's holy_mult stat).
    consecrate_slice_mult    = 0.6,

    -- Cryomancer frost aura at level 3: damage/slow-factor multipliers.
    frost_lvl3_dmg_mult      = 1.6,
    frost_lvl3_slow_mult     = 0.7,   -- <1 = a HARDER slow

    -- Bomber level-3 aftershock (second blast a beat after the first).
    reactor_aftershock_dmg_mult    = 0.55,
    reactor_aftershock_radius_mult = 0.7,

    -- Cannoneer level-3 bombardment cluster (also the cannonball's).
    mortar_cluster_dmg_mult    = 0.5,
    mortar_cluster_radius_mult = 0.7,

    -- Vulcanist volcano: eruption cadence (interval seconds x count blasts).
    volcano_interval      = 1.0,
    volcano_count         = 4,
    volcano_interval_lvl3 = 0.5,
    volcano_count_lvl3    = 8,
  },

  -- ======================================================================
  -- ENEMY-SOURCED DAMAGE TO BRICKS
  -- ======================================================================
  enemies = {
    -- Volatile brick variant: on death it chain-damages neighbours within
    -- volatile_death_radius for volatile_death_frac of its own max HP.
    volatile_death_frac   = 0.4,
    volatile_death_radius = 28,
  },

  -- ======================================================================
  -- HEROES — the full numeric stat block for all 20 draftable balls.
  -- Any NUMBER here overrides ball_hero.lua's HERO_STATS for THIS paddle
  -- only. Strings (behavior/skin/color) stay in code. dmg feeds contact
  -- damage AND every ability that scales off current damage. cd values are
  -- the BASE cooldown (ranged shooters additionally take ranged_cd_mult).
  -- ======================================================================
  heroes = {
    -- projectile shooter: arrow at nearest brick in range
    vagrant     = {dmg = 8,  cd = 0.5,  range = 96,  speed = 220, r = 6, base_speed = 160},
    -- crossbow bolt: infinite pierce, level 3 wall-ricochet
    archer      = {dmg = 10, cd = 2.0,  range = 160, speed = 260, r = 5.5, base_speed = 175},
    -- chain knife: leaps brick to brick (chain = hops)
    scout       = {dmg = 6,  cd = 2.0,  range = 64,  speed = 240, chain = 3, r = 5.5, base_speed = 180},
    -- constant spiral blade stream (spellblade_dmg_mult applies per shard)
    spellblade  = {dmg = 7,  cd = 0.1,  range = 9999, speed = 200, orbit_vr = 6, r = 6, base_speed = 160},
    -- cleave square (area = visual side; hit square is 1.5x)
    swordsman   = {dmg = 14, cd = 3.0,  range = 48,  area = 96,  r = 6.5, base_speed = 150},
    -- hexagon hammer slam (big cleave)
    barbarian   = {dmg = 16, cd = 5.0,  range = 96,  area = 110, r = 7, base_speed = 140},
    -- consecrated ground: heals player, damages bricks at holy_mult x dmg/sec
    cleric      = {dmg = 4,  cd = 7,    ground_rs = 64, ground_duration = 6, heal_interval = 2.0, holy_mult = 0.6, blade_mult = 1.5, r = 6, base_speed = 145},
    -- pandemonium hex: dead hexed bricks burst into knife_mult x dmg knives
    jester      = {dmg = 8,  cd = 6,    range = 96, curse_radius = 128, curse_targets = 6, curse_duration = 6, knife_mult = 2.5, knife_speed = 250, r = 6, base_speed = 190},
    -- roaming void pool: dps_mult x dmg per second, shoot_mult at level 3
    witch       = {dmg = 6,  cd = 4,    pool_rs = 44, tick = 0.25, dps_mult = 0.7, dur_min = 11, dur_max = 15, shoot_mult = 2.5, r = 6, base_speed = 140},
    -- proximity mine: blast_mult x dmg over bomb_radius
    bomber      = {dmg = 10, cd = 7,    bomb_radius = 60, fuse = 8, trigger_radius = 16, count = 1, blast_mult = 2.0, r = 6.5, base_speed = 125},
    -- deployable turret: turret_mult x dmg per shot, burst_count per volley
    engineer    = {dmg = 8,  cd = 8,    lifetime = 16, turret_cd = 3.0, burst_count = 3, burst_gap = 0.12, turret_range = 256, turret_mult = 2.0, shot_speed = 220, lvl3_count = 2, r = 6, base_speed = 150},
    -- gravity well: pulls swarms; level 3 expire burst = dmg_mult x dmg
    psykino     = {dmg = 8,  cd = 5,    range = 140, well_rs = 64, well_dur = 2.0, pull = 4, dmg_mult = 4.0, r = 6, base_speed = 150},
    -- initiated chain lightning: full dmg first hit, x hop_falloff per link
    stormweaver = {dmg = 7,  cd = 1.3,  range = 122, links = 2, chain_radius = 64, hop_falloff = 0.55, zigzag = 7.0, bounce_scramble = 0.7, r = 6, base_speed = 150},
    -- locust drizzle: each locust gnaws for locust_dmg x dmg
    infestor    = {dmg = 5,  cd = 0.13, range = 150, locust_dmg = 1.25, locust_speed = 155, dart = 0.32, r = 6, base_speed = 165},
    -- die roll: N laser strikes at payout_mult x dmg each
    gambler     = {dmg = 8,  cd = 2,    range = 360, payout_mult = 3.0, r = 6.5, base_speed = 170},
    -- volcano: eruptions at dmg x ranged_dmg_mult over `area` square
    vulcanist   = {dmg = 14, cd = 12,   area = 360, volcano_rs = 24, r = 6, base_speed = 150},
    -- artillery mortar: blast_mult x dmg splash, bombard clusters at level 3
    cannoneer   = {dmg = 16, cd = 1.0,  range = 240, blast_radius = 50, blast_mult = 1.0, bombard = 2, shell_delay = 0.8, r = 6.5, base_speed = 132},
    -- on-bounce chain lightning (see on_bounce.chain_*)
    wizard      = {dmg = 7,  bounce_cd = 0.3, r = 5.5, base_speed = 170},
    -- following frost aura: dps_mult x dmg per tick + slow
    cryomancer  = {dmg = 6,  area_rs = 58, tick = 0.5, dps_mult = 0.8, slow_factor = 0.5, slow_duration = 1.5, r = 6, base_speed = 135},
    -- on-bounce burn area (see on_bounce.burn_*)
    pyromancer  = {dmg = 8,  bounce_cd = 0.4, r = 6, base_speed = 160},
  },

  -- Aim-line sight: predicted launch-path length in px. Total length =
  -- path_base + path_per_level*(level - 1); the trace bounces off walls
  -- AND enemy blocks (see BallPit:draw_aim_trajectory).
  -- Tesla: a scientific instrument — the longest, farthest-reaching sight.
  aim = {
    path_base      = 220,
    path_per_level = 22,
  },
}
