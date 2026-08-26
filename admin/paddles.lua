-- Paddle loadouts + the post-death unlock shop.
--
-- PADDLES is the data table for the 13 run-start loadouts (see PADDLES.md):
-- each entry holds the stat multipliers the run reads in reset_run, the
-- starting ball list, and a `signature` id the gameplay code switches on.
-- This file also owns:
--   * the persistent meta-state (state.wallet / paddles_owned / selected) —
--     the engine auto-loads `state` at boot and saves it on quit; we save
--     explicitly on death and on every shop transaction too,
--   * the arena-side signature helpers (mitosis clones, hive maggots, tesla
--     zaps, phantom blink, the cannon's falloff splash, aegis brace reset),
--   * the shop screen that replaces the plain game-over overlay. The shop is
--     also the paddle-select screen: click an unlocked paddle to equip it.
--
-- Required from main.lua AFTER every other game module so the BallPit methods
-- defined here (including the draw_game_over override) land on the final
-- class. Colors are stored as palette KEY strings and resolved at draw time —
-- shared_init hasn't run yet when this file is required.

PADDLES = {}

-- Terrorist's flat level cost. The normal curve is 5/7/10/14/19/27/37/51/...;
-- a flat 14 is slower for the first few levels and dramatically faster from
-- ~level 6 on — "slow opener, out-level hard late".
PADDLES.XP_FLAT = 14

-- Positional unlock pricing: the Nth paddle you BUY costs the Nth entry
-- here, regardless of WHICH paddle it is — unlock in any order you like
-- (boomerang first, then cannon, then pinball...), each successive unlock
-- just costs more. The per-def `price` fields below are no longer read.
PADDLES.PRICE_LADDER = {100, 250, 500, 750, 1000, 1500, 2500, 3000, 4000, 5000}

-- Cost of the player's next unlock: count the PAID paddles already owned
-- (the free Standard doesn't count) and index the ladder. Past the ladder's
-- end (can't happen — it covers every paid paddle) the last entry repeats.
function PADDLES.next_price()
  PADDLES.ensure_state()
  local owned = 0
  for id in pairs(state.paddles_owned or {}) do
    if id ~= 'standard' then owned = owned + 1 end
  end
  return PADDLES.PRICE_LADDER[math.min(owned + 1, #PADDLES.PRICE_LADDER)]
end

PADDLES.order = {
  'standard', 'pinball', 'aegis', 'mitosis', 'hive', 'vampire', 'boomerang',
  'twincast', 'tesla', 'terrorist', 'cannon',
}

PADDLES.defs = {
  standard = {
    id = 'standard', name = 'Standard', price = 0, color_key = 'fg',
    size = 1.0, move = 1.0, ball = 1.0, charge = 1.0, aim = 1.0, dmg = 1.0,
    xp = 1.0, combo = 1.0, hp = 5, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'vagrant', 'swordsman'},
    signature = 'none', sig = {},
    blurb = 'The baseline. Balanced, no signature power.',
    sig_blurb = 'flat reflective paddle, 5 hearts',
  },
  pinball = {
    id = 'pinball', name = 'Pinball Lobber', price = 100, color_key = 'orange',
    size = 0.5, move = 1.1, ball = 0.7, charge = 1.4, aim = 1.5, dmg = 1.3,
    xp = 1.0, combo = 1.4, hp = 5, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'scout', 'scout'},
    signature = 'flippers',
    -- Real-table physics: balls fall under gravity and roll off the bats; a
    -- flip lobs them back up. ball/restitution kept low + gravity gentle so
    -- balls stay slow and easy to flip; launch_speed is the modest pop.
    sig = {
      flip_window = 0.16, gap = 14,
      flipper_len = 34, flipper_thick = 5, rest_tilt = 0.30, flip_up = 0.62,
      -- Floaty + slow between flips (low gravity = high hang-time arc), but a
      -- flip is a real launch: launch_speed is the "100%" unit and flip_launch
      -- scales it 2x (+200%) out by the pivot up to 4x (+400%) at the inner
      -- tip. speed_cap is the hard ceiling. First-pass; expect to retune.
      launch_speed = 150, gravity = 170, speed_cap = 620, restitution = 0.12,
    },
    blurb = 'Two long flippers with a central drain - balls fall, you flip them back up.',
    sig_blurb = 'tap left/right to flip; gravity does the rest',
  },
  aegis = {
    id = 'aegis', name = 'Aegis', price = 250, color_key = 'blue2',
    size = 1.4, move = 0.6, ball = 0.7, charge = 0.2, aim = 0.5, dmg = 0.7,
    xp = 0.9, combo = 0.6, hp = 7, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'cleric', 'cleric'},
    signature = 'aegis', sig = {
      reflect_dmg = 60, parry_window = 0.6, parry_lockout = 2.5,
      parry_hits = 4, parry_dmg_mult = 2.5, parry_speed_mult = 1.6,
      parry_combo = 25,
      -- Bulwark meter -> Greater Aegis (see paddles.lua helpers).
      bulwark_max = 5, bulwark_bullet = 1, bulwark_ball = 2,
      bulwark_decay = 0.1, bulwark_grace = 4,
      greater_window_mult = 2.0, greater_reflect_mult = 2.0,
      greater_hits_mult = 2.0, greater_heal = 2, greater_dr = 0.5,
      greater_nova_dmg = 40, greater_nova_radius = 120,
    },
    blurb = 'A shield that answers: raise it at the right moment to parry balls and bullets.',
    sig_blurb = 'E/click raises the shield; parries bank bulwark - a full meter turns the next raise gold',
  },
  mitosis = {
    id = 'mitosis', name = 'Mitosis', price = 500, color_key = 'green',
    size = 1.0, move = 1.0, ball = 1.0, charge = 0.9, aim = 1.0, dmg = 0.5,
    xp = 1.4, combo = 1.3, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'vagrant'},
    signature = 'mitosis', sig = {clone_life = 4.5, clone_cap = 10, clone_renew_mult = 0.75},
    blurb = 'Every kill makes a ball divide in two like a splitting cell.',
    sig_blurb = 'one daughter decays - bounce it off the paddle to feed it; lost types regrow',
  },
  hive = {
    id = 'hive', name = 'Hive', price = 750, color_key = 'orange',
    size = 1.0, move = 1.0, ball = 0.8, charge = 0.7, aim = 0.8, dmg = 1.0,
    xp = 1.6, combo = 0.9, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'infestor', 'infestor', 'infestor'},
    signature = 'hive',
    sig = {contact_zero = true, maggot_cap = 24, maggot_dmg_mult = 0.8, maggot_speed = 140,
           maggot_life = 7},
    blurb = 'Balls deal NO damage - maggots infest bricks with a spreading rot.',
    sig_blurb = 'one bite blackens a brick; the plague creeps to its neighbours',
  },
  vampire = {
    id = 'vampire', name = 'Vampire', price = 1000, color_key = 'red',
    size = 0.9, move = 1.2, ball = 1.3, charge = 1.2, aim = 1.1, dmg = 1.5,
    xp = 1.0, combo = 1.2, hp = 5, hp_mode = 'bar', xp_mode = 'scale',
    start_balls = {'barbarian', 'barbarian'},
    signature = 'vampire', sig = {drain = 2.0, heal_per_kill = 3},
    blurb = 'HP drains constantly; killing blocks restores it.',
    sig_blurb = 'stop killing and you die',
  },
  boomerang = {
    id = 'boomerang', name = 'Boomerang', price = 1500, color_key = 'yellow',
    size = 1.0, move = 1.0, ball = 1.2, charge = 0.6, aim = 1.3, dmg = 1.4,
    xp = 1.0, combo = 0.7, hp = 5, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'swordsman', 'swordsman'},
    signature = 'boomerang', sig = {turn_rate = 5},
    blurb = 'Balls curl back to the paddle after any wall hit.',
    sig_blurb = 'double-pass lanes, always recoverable',
  },
  twincast = {
    id = 'twincast', name = 'Twin Cast', price = 2500, color_key = 'blue',
    size = 1.0, move = 0.9, ball = 1.0, charge = 1.0, aim = 0.9, dmg = 1.6,
    xp = 0.5, combo = 1.1, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'spellblade', 'swordsman'},
    -- Binary Fusion: each hero is a bonded PAIR that orbits a shared core,
    -- charging as they swirl; at full charge the twins FUSE into one super-ball
    -- that detonates a nova supercast, then split and recharge. fuse_time =
    -- seconds of both-twins-in-play to fill; fuse_window = how long they stay
    -- fused; split_cd = beat after a split before charge resumes; nova_* = the
    -- blast (dmg scales with pair level); orbit_pull = how hard the spin tightens
    -- with charge. cd_mult keeps the between-nova pair snappy (a dialled-back
    -- echo of the old "double cast" feel).
    signature = 'twincast',
    sig = {cd_mult = 0.75, fuse_time = 8, fuse_window = 0.42, split_cd = 0.6,
           nova_radius = 80, nova_dmg = 26, orbit_pull = 2.4, fuse_converge = 0.2,
           beam_dmg = 5, beam_width = 7, beam_cd = 0.2,
           nova_spread_ref = 80, nova_spread_min = 0.7, nova_spread_max = 2.0,
           nova_spread_dmg = 0.6},
    blurb = 'Bonded twins burn a live tether between them, then FUSE into a nova.',
    sig_blurb = 'the tether cuts whatever it crosses; the wider the twins when they draw in, the bigger the nova',
  },
  tesla = {
    id = 'tesla', name = 'Tesla', price = 3000, color_key = 'blue',
    size = 1.0, move = 1.0, ball = 0.8, charge = 0.8, aim = 0.9, dmg = 1.4,
    xp = 1.0, combo = 1.1, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'wizard', 'wizard', 'wizard', 'wizard'},
    signature = 'tesla', sig = {zap_dmg = 7, zap_width = 12, zap_cd = 0.25},
    blurb = 'Paddle bounces arc lightning between ALL live balls.',
    sig_blurb = 'damage scales with ball count',
  },
  terrorist = {
    id = 'terrorist', name = 'Terrorist', price = 4000, color_key = 'red',
    size = 1.0, move = 1.0, ball = 1.1, charge = 1.0, aim = 1.0, dmg = 1.6,
    xp = 1.0, combo = 1.0, hp = 3, hp_mode = 'hearts', xp_mode = 'flat',
    start_balls = {'bomber', 'bomber', 'bomber', 'bomber'},
    -- blast_radius: the detonation AoE (also the arm range — a ball blows on E
    -- when an enemy sits inside its blast reach). blast_mult: the blast's payoff
    -- (the build's whole damage). Both the radius and the damage SCALE with the
    -- run level (blast_*_per_level) so the blast keeps pace late-game; radius is
    -- capped at blast_radius_max. other_dmg_mult: every NON-blast damage source
    -- is gutted to this. passive_xp_pct: passive XP gain as a percentage of the
    -- current level's XP requirement per second (~15.38% = 6.5 seconds per level).
    signature = 'terrorist',
    sig = {blast_radius = 78, blast_radius_per_level = 0.05, blast_radius_max = 150,
           blast_mult = 5.0, blast_dmg_per_level = 0.18, other_dmg_mult = 0.2,
           passive_xp_pct = 0.1538},
    blurb = 'Press E to detonate balls near blocks - the blast is your real damage.',
    sig_blurb = 'spent balls are gone; level-ups auto-arm a new random ball',
  },
  cannon = {
    id = 'cannon', name = 'Cannon', price = 5000, color_key = 'orange',
    size = 0.9, move = 1.0, ball = 0.6, charge = 1.7, aim = 0.9, dmg = 1.5,
    xp = 1.0, combo = 1.1, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'cannoneer', 'cannoneer'},
    -- The hop is driven by PADDLE STRIKES (Paddle:on_ball_bounce -> start_hop):
    -- height/air-time/splash scale with how hard the paddle was charging forward
    -- into the ball. While airborne the ball flies OVER bricks/critters/boss
    -- (nothing on the ground can deflect it) and each landing rebounds smaller
    -- until the hop settles flat on its own. Physics/decay tunables live in
    -- ball_hero.lua (HOP_* constants). other_dmg_mult: every ability/projectile/
    -- pet damage source is damped to this so the damage lives in BOUNCES —
    -- brick-contact hits and the hop-landing splash keep full strength.
    signature = 'cannon', sig = {other_dmg_mult = 0.35},
    blurb = 'Strike balls with the paddle to launch HOPS that crash down in splashes.',
    sig_blurb = 'pull back, then charge forward into the ball for bigger hops',
  },
}


function PADDLES.get(id)
  return PADDLES.defs[id] or PADDLES.defs.standard
end


-- Fill in / repair the persistent meta-state. Idempotent; called from
-- reset_run and every shop handler (NOT at require time — the engine only
-- loads `state` inside engine_run, after all modules are required).
function PADDLES.ensure_state()
  if not state then state = {} end
  if type(state.wallet) ~= 'number' then state.wallet = 0 end
  if type(state.paddles_owned) ~= 'table' then state.paddles_owned = {} end
  state.paddles_owned.standard = true
  if type(state.selected_paddle) ~= 'string'
  or not PADDLES.defs[state.selected_paddle]
  or not state.paddles_owned[state.selected_paddle] then
    state.selected_paddle = 'standard'
  end
end


-- ----- HP routing (hearts vs the Vampire bar) -----
--
-- All player damage/heal flows through these two so the Vampire's 0-100 bar
-- and the normal heart counter share one code path. 1 heart = 20 bar units.

function BallPit:damage_player(hearts)
  -- Phased (the wide powerup): the paddle is intangible for the buff's
  -- duration. Every damage channel routes through here, so this one early-out
  -- covers swarm breaches, critter contact and enemy fire alike. Deliberately
  -- NOT applied to the Vampire signature's self-drain (ballpit.lua), which is
  -- that loadout's own running cost rather than damage taken.
  if self.paddle and self.paddle.phased then return end
  local amount = hearts or 1
  -- Greater Aegis: while the gold dome is up the player takes greater_dr of
  -- all damage. This is what HALF-hearts exist for — a 1-dmg bullet through
  -- the dome costs half a heart (see draw_steel_hearts).
  if self.paddle and self.paddle.greater then
    amount = amount*((self.run_mods and self.run_mods.sig and self.run_mods.sig.greater_dr) or 0.5)
  end
  if self.run_mods and self.run_mods.hp_mode == 'bar' then amount = amount*20 end
  self.player_hp = self.player_hp - amount
end


-- Returns how much was actually healed (0 when already full).
function BallPit:heal_hearts(hearts)
  local amount = hearts or 1
  if self.run_mods and self.run_mods.hp_mode == 'bar' then amount = amount*20 end
  local prev = self.player_hp
  self.player_hp = math.min(self.player_hp_max, self.player_hp + amount)
  return self.player_hp - prev
end


-- ----- Signature setup + arena-side signature helpers -----

-- One-time per-run signature state. Called at the end of reset_run, after the
-- paddle + starting heroes exist.
function BallPit:setup_signature()
  local sigid = self.run_mods and self.run_mods.signature

  self.tesla_cd         = false
  self.phantom_anchor   = nil
  self.phantom_cd_ready = true
  self.twin_fx          = nil

  if sigid == 'aegis' then
    -- Perfect Parry: the state (brace_t window / brace_lock_t recharge)
    -- lives on the paddle — ticked in Paddle:update, raised by E/click via
    -- BallPit:update. The pit is OPEN (the old bottom wall is gone); missed
    -- balls recall like any other loadout. The BULWARK meter banks parries
    -- toward a Greater Aegis raise (bulwark_add / aegis_tick below).
    self.paddle.brace_t      = 0
    self.paddle.brace_lock_t = 0
    self.paddle.greater      = false
    self.bulwark             = 0
    self.bulwark_idle_t      = 0
  elseif sigid == 'mitosis' then
    -- Regrow: a drafted hero type with zero live balls comes back on its own,
    -- so the player never permanently loses a variant.
    self.t:every(1, function()
      if self.game_over or self.upgrade_pending then return end
      for character in pairs(self.seen_characters or {}) do
        local alive = false
        for _, h in ipairs(self.heroes) do
          if h and not h.dead and h.character == character then alive = true; break end
        end
        if not alive then self:add_hero(character) end
      end
    end, nil, nil, 'mitosis_regrow')
  elseif sigid == 'tesla' then
    -- Persistent conduction web: spawn the always-on visual now; tesla_tick
    -- keeps it alive and fires the steady damage pulses (see BallPit:update).
    self.tesla_t   = 0
    self.tesla_web = TeslaWeb{group = self.effects}
  elseif sigid == 'glacier' then
    -- Ice rink: glacier_tick lays slick patches over the run (see BallPit:update).
    self.slick_t = SLICK_SPAWN_CD
  elseif sigid == 'twincast' then
    -- Binary Fusion: one FX entity draws every bonded pair's bond/charge/core
    -- each frame (it reads arena.twin_pairs, which add_hero filled in before this
    -- ran). twincast_tick drives the charge -> fuse -> split cycle.
    self.twin_fx = TwinFusionFX{group = self.effects}
  elseif sigid == 'terrorist' then
    -- Munitions never run fully dry: detonations CONSUME balls (they don't
    -- re-form), so if every ball has been spent, arm a fresh random one after a
    -- short beat. New balls otherwise come from the auto-drafted level-ups
    -- (see BallPit:terror_auto_levelup). This only fires at exactly zero balls,
    -- so it never resurrects a specific spent ball — it just stops a hard-lock.
    self.t:every(2.5, function()
      if self.game_over or self.upgrade_pending then return end
      for _, h in ipairs(self.heroes) do if h and not h.dead then return end end
      self:add_hero(hero_pool[random:int(1, #hero_pool)])
    end, nil, nil, 'terror_regrow')
  end
end


-- ----- Aegis bulwark meter + Greater Aegis + steel hearts -----

-- Parries bank pips (bullet = bulwark_bullet, ball = bulwark_ball, capped at
-- bulwark_max). A FULL meter turns the next raise into a GREATER AEGIS (see
-- Paddle:start_brace): gold dome, doubled window/payloads, balls turn
-- bullets, half damage taken, +greater_heal hearts, ends in a nova. Gains
-- pause while the gold dome itself is up (no self-feeding). The meter is
-- drawn as the shield face's meander ticks (Paddle:draw_aegis_paddle).
function BallPit:bulwark_add(pips)
  if not (self.run_mods and self.run_mods.signature == 'aegis') then return end
  if self.paddle and self.paddle.greater then return end
  local sigt = self.run_mods.sig or {}
  local max  = sigt.bulwark_max or 5
  local prev = self.bulwark or 0
  self.bulwark        = math.min(max, prev + (pips or 1))
  self.bulwark_idle_t = 0
  if prev < max and self.bulwark >= max then
    -- Bank full: one clear chime — the next raise goes gold.
    level_up1:play{volume = 0.3, pitch = 1.4}
  end
end


-- Idle bleed: a banked meter slowly drains after bulwark_grace seconds
-- without a parry, so a full dome can't sit in the pocket all wave.
function BallPit:aegis_tick(dt)
  if not (self.run_mods and self.run_mods.signature == 'aegis') then return end
  local sigt = self.run_mods.sig or {}
  self.bulwark_idle_t = (self.bulwark_idle_t or 0) + dt
  if (self.bulwark or 0) > 0 and self.bulwark_idle_t > (sigt.bulwark_grace or 4) then
    self.bulwark = math.max(0, self.bulwark - (sigt.bulwark_decay or 0.1)*dt)
  end
end


-- Greater Aegis finale: the gold dome collapses outward as a nova — a
-- falloff blast centered just above the paddle that clears the space the
-- shield was holding. Fired from the Paddle brace tick the frame the
-- empowered window closes.
function BallPit:aegis_greater_nova()
  local sigt   = (self.run_mods and self.run_mods.sig) or {}
  local gold   = Color(1, 0.85, 0.35, 1)
  local px, py = self.paddle.x, self.paddle.y - 10
  local radius = sigt.greater_nova_radius or 120
  self:do_splash_falloff(px, py, radius, sigt.greater_nova_dmg or 40, gold, 'aegis')
  TelegraphRing{group = self.effects, x = px, y = py, radius = radius*0.6,
                color = gold, duration = 0.35}
  spawn_burst(self.effects, px, py - 8, gold, 12, 120, 240)
  explosion1:play{volume = 0.4, pitch = 1.1}
  camera:shake(4, 0.25, 80)
end


-- Aegis HP readout: forged STEEL hearts instead of the flat red squares,
-- with the half-heart granularity the Greater dome's 0.5x damage creates.
-- Each heart is two lobes + a convex tip triangle (polygon fills convex
-- shapes only), drawn as left/right halves so a half heart is literally the
-- left half lit. Idle: a tiny out-of-phase breathing pulse per heart and a
-- specular glint that sweeps each heart every few seconds. Same 10px stride
-- as the plain hearts so the XP bar layout is untouched.
function BallPit:draw_steel_hearts()
  local t = love.timer.getTime()
  for i = 1, self.player_hp_max do
    local cx   = self.x1 + 8 + (i - 1)*10
    local cy   = self.y1 - 8
    local fill = math.clamp(self.player_hp - (i - 1), 0, 1)
    local s    = 1 + 0.06*math.sin(t*2.2 + i*0.9)
    local function half_heart(side, color)
      graphics.circle(cx + side*1.5*s, cy - 1.2*s, 1.7*s, color)
      graphics.polygon({cx, cy - 0.6*s, cx + side*3.1*s, cy - 0.6*s, cx, cy + 3.4*s}, color)
    end
    -- Empty socket underneath, then light the halves the fill covers.
    half_heart(-1, bg[2]); half_heart(1, bg[2])
    local steel = Color(0.66, 0.71, 0.80, 1)
    if fill >= 0.5   then half_heart(-1, steel) end
    if fill >= 0.999 then half_heart( 1, steel) end
    if fill >= 0.5 then
      -- Forged look: top-left catch-light + a shaded tip.
      graphics.circle(cx - 1.6*s, cy - 1.9*s, 0.6*s, Color(0.95, 0.97, 1, 0.9))
      -- Sweeping glimmer: a bright fleck crosses the heart every few seconds,
      -- staggered per heart so the row ripples instead of strobing.
      local u = (t + i*0.25) % 3.5
      if u < 0.45 then
        local p  = u/0.45
        local gx = cx - 2.2*s + p*4.4*s
        graphics.line(gx - 0.8, cy + 1.6*s, gx + 0.8, cy - 2.6*s,
                      Color(1, 1, 1, 0.7*math.sin(p*math.pi)), 1)
      end
    end
  end
end


-- ----- Themed HP hearts (one glyph style per paddle) -----
--
-- Every loadout renders its own life glyph in the HUD strip. The Vampire's
-- blood bar and the Aegis steel halves live elsewhere; everything here is a
-- binary full/empty glyph on the same 10px stride as the original red
-- squares, so the XP bar layout is untouched. Each style is
-- fn(cx, cy, lit, i, t, max) — kept to a handful of primitives each.

-- Shared classic heart silhouette: two lobes + a convex tip triangle.
local function heart_glyph(cx, cy, s, color)
  graphics.circle(cx - 1.5*s, cy - 1.2*s, 1.7*s, color)
  graphics.circle(cx + 1.5*s, cy - 1.2*s, 1.7*s, color)
  graphics.polygon({cx - 3.1*s, cy - 0.6*s, cx + 3.1*s, cy - 0.6*s, cx, cy + 3.4*s}, color)
end

-- One side of the classic heart (for the split-in-two death animation).
local function heart_half(cx, cy, side, s, color)
  graphics.circle(cx + side*1.5*s, cy - 1.2*s, 1.7*s, color)
  graphics.polygon({cx, cy - 0.6*s, cx + side*3.1*s, cy - 0.6*s, cx, cy + 3.4*s}, color)
end

local HEART_STYLES = {
  -- Standard: the classic red heart, with an honest heartbeat thump.
  none = function(cx, cy, lit, i, t)
    if not lit then heart_glyph(cx, cy, 1, bg[2]) return end
    local s = 1 + 0.10*(math.max(0, math.sin(t*2.4 + i*0.3)))^8
    heart_glyph(cx, cy, s, red[0])
    graphics.circle(cx - 1.4*s, cy - 1.7*s, 0.55*s, Color(1, 0.8, 0.8, 0.9))
  end,

  -- Pinball Lobber: cabinet marquee bulbs with a chase light running the row.
  flippers = function(cx, cy, lit, i, t, max)
    graphics.circle(cx, cy, 3.4, Color(0.62, 0.65, 0.72, 1), 1)
    if not lit then graphics.circle(cx, cy, 2.4, bg[2]) return end
    local hot = (math.floor(t*6) % math.max(max, 1)) == (i - 1)
    graphics.circle(cx, cy, 2.4, hot and Color(1, 0.75, 0.30, 1) or Color(0.85, 0.45, 0.12, 1))
    if hot then graphics.circle(cx, cy, 4.2, Color(1, 0.70, 0.25, 0.25)) end
    graphics.circle(cx - 0.9, cy - 0.9, 0.7, Color(1, 1, 0.85, hot and 1 or 0.7))
  end,

  -- Mitosis: a living cell — membrane, drifting nucleus, orbiting organelle.
  mitosis = function(cx, cy, lit, i, t)
    if not lit then graphics.circle(cx, cy, 3.0, bg[2], 1) return end
    local wob = t*1.7 + i*1.1
    graphics.circle(cx, cy, 3.2 + 0.25*math.sin(wob*1.3), Color(0.45, 0.85, 0.50, 0.30))
    graphics.circle(cx, cy, 3.2, green[0], 1)
    graphics.circle(cx + 0.9*math.cos(wob), cy + 0.9*math.sin(wob*0.8), 1.3, green[0])
    graphics.circle(cx + 2.2*math.cos(-wob*0.6), cy + 2.2*math.sin(-wob*0.6), 0.5,
                    Color(0.80, 1, 0.80, 0.8))
  end,

  -- Hive: honeycomb — full cells hold capped amber honey, lost ones run dry.
  hive = function(cx, cy, lit, i, t)
    local pts = {}
    for v = 0, 5 do
      local a = math.pi/6 + v*math.pi/3
      pts[#pts + 1] = cx + 3.4*math.cos(a)
      pts[#pts + 1] = cy + 3.4*math.sin(a)
    end
    if not lit then graphics.polygon(pts, bg[2], 1) return end
    graphics.polygon(pts, Color(0.95, 0.72, 0.20, 1))
    graphics.polygon(pts, Color(0.55, 0.38, 0.08, 1), 1)
    local g = 0.5 + 0.5*math.sin(t*2 + i*0.7)
    graphics.circle(cx - 1.0, cy - 1.1, 0.7, Color(1, 0.95, 0.70, 0.4 + 0.4*g))
  end,

  -- Boomerang: a carved wooden chevron, rocking gently as if just caught.
  boomerang = function(cx, cy, lit, i, t)
    local rock = lit and 0.28*math.sin(t*2.1 + i*0.8) or 0
    local wood = lit and Color(0.78, 0.56, 0.28, 1) or bg[2]
    graphics.push(cx, cy, math.pi/4 + rock)
      graphics.rectangle(cx - 1.4, cy, 3.6, 1.6, 0.8, 0.8, wood)
      graphics.rectangle(cx, cy - 1.4, 1.6, 3.6, 0.8, 0.8, wood)
    graphics.pop()
    if lit then graphics.circle(cx - 0.5, cy - 0.5, 0.5, Color(0.95, 0.85, 0.60, 0.8)) end
  end,

  -- Twin Cast: a bonded pair of motes orbiting a shared spark.
  twincast = function(cx, cy, lit, i, t)
    if not lit then
      graphics.circle(cx - 1.5, cy, 0.9, bg[2])
      graphics.circle(cx + 1.5, cy, 0.9, bg[2])
      return
    end
    local a = t*2.6 + i*0.9
    local ox, oy = 2.0*math.cos(a), 1.1*math.sin(a)
    graphics.line(cx + ox, cy + oy, cx - ox, cy - oy, Color(0.72, 0.55, 1, 0.35), 1)
    graphics.circle(cx + ox, cy + oy, 1.4, Color(0.72, 0.55, 1, 1))
    graphics.circle(cx - ox, cy - oy, 1.4, Color(0.55, 0.75, 1, 1))
    graphics.circle(cx, cy, 0.6, Color(1, 1, 1, 0.6 + 0.4*math.sin(t*7 + i)))
  end,

  -- Tesla: a charged capacitor cell — a spark sputters between the terminals.
  tesla = function(cx, cy, lit, i, t)
    graphics.rectangle(cx, cy + 0.6, 6.4, 4.6, 1, 1, lit and Color(0.16, 0.22, 0.30, 1) or bg[2])
    graphics.rectangle(cx - 1.8, cy - 2.0, 1.2, 1.6, nil, nil, Color(0.62, 0.65, 0.72, 1))
    graphics.rectangle(cx + 1.8, cy - 2.0, 1.2, 1.6, nil, nil, Color(0.62, 0.65, 0.72, 1))
    if not lit then return end
    local f = math.sin(t*13 + i*2.7)
    if f > 0.1 then
      graphics.polyline(Color(0.55, 0.85, 1, 0.35 + 0.6*f), 1,
        cx - 1.8, cy - 1.4, cx - 0.5, cy - 2.2 + f, cx + 0.6, cy - 1.0 - f, cx + 1.8, cy - 1.4)
    end
    graphics.circle(cx, cy + 0.8, 1.1, Color(0.55, 0.85, 1, 0.5 + 0.3*math.abs(f)))
  end,

  -- Terrorist: a pocket bomb, fuse spark sputtering while the life is yours.
  terrorist = function(cx, cy, lit, i, t)
    if not lit then graphics.circle(cx, cy + 0.6, 2.8, bg[2], 1) return end
    graphics.circle(cx, cy + 0.6, 2.8, Color(0.24, 0.24, 0.28, 1))
    graphics.circle(cx - 1.0, cy - 0.3, 0.8, Color(0.50, 0.50, 0.58, 0.8))
    graphics.line(cx + 1.2, cy - 1.4, cx + 2.2, cy - 2.6, Color(0.75, 0.60, 0.40, 1), 1)
    local sp = 0.5 + 0.5*math.sin(t*11 + i*1.9)
    graphics.circle(cx + 2.3, cy - 2.7, 0.7 + 0.5*sp, Color(1, 0.80, 0.30, 0.5 + 0.5*sp))
    graphics.circle(cx + 2.3, cy - 2.7, 0.35, Color(1, 1, 0.90, 0.9))
  end,

  -- Cannon: stacked iron shot — a slow glint rolls over what's left.
  cannon = function(cx, cy, lit, i, t)
    if not lit then graphics.circle(cx, cy, 2.9, bg[2], 1) return end
    graphics.circle(cx, cy, 2.9, Color(0.30, 0.32, 0.38, 1))
    graphics.circle(cx - 1.0, cy - 1.0, 1.0, Color(0.55, 0.58, 0.66, 0.9))
    local u = (t*0.7 + i*0.31) % 3
    if u < 0.5 then
      local p = u/0.5
      graphics.circle(cx - 1.8 + p*3.6, cy - 0.6, 0.5, Color(1, 1, 1, 0.6*math.sin(p*math.pi)))
    end
  end,
}

-- One lit glyph of a given loadout's life icon, for menus that want to SHOW
-- the hull rather than track it (the shop's HULL row). The HUD's own dispatch
-- is below and stays separate, because it has live HP to honour: Aegis in
-- particular renders half hearts there, which needs a fill fraction. Here it
-- gets the whole forged heart.
local function life_glyph(sig, cx, cy, i, t, max)
  if sig == 'aegis' then
    local steel = Color(0.66, 0.71, 0.80, 1)
    local s = 1 + 0.06*math.sin(t*2.2 + i*0.9)
    heart_half(cx, cy, -1, s, steel)
    heart_half(cx, cy,  1, s, steel)
    graphics.circle(cx - 1.6*s, cy - 1.9*s, 0.6*s, Color(0.95, 0.97, 1, 0.9))
    return
  end
  local draw = HEART_STYLES[sig] or HEART_STYLES.none
  draw(cx, cy, true, i, t, max or 5)
end


-- HUD entry point (draw_hud): dispatch to this paddle's glyph, defaulting to
-- the classic heart. Aegis routes to its half-heart steel renderer above;
-- the Vampire never reaches here (hp_mode 'bar' draws the blood bar).
function BallPit:draw_themed_hearts()
  local sig = (self.run_mods and self.run_mods.signature) or 'none'
  if sig == 'aegis' then return self:draw_steel_hearts() end
  local draw = HEART_STYLES[sig] or HEART_STYLES.none
  local t = love.timer.getTime()
  for i = 1, self.player_hp_max do
    draw(self.x1 + 8 + (i - 1)*10, self.y1 - 8, self.player_hp >= i - 0.5, i, t, self.player_hp_max)
  end
end


-- Mitosis: a brick kill makes a live "cell" (hero ball) DIVIDE — a daughter
-- cell grows out of it at its position, the two diverge, and one of the pair
-- (chosen at random) is the non-viable daughter that decays and dies. The cell
-- lifecycle/visuals live on BallHero (begin_mitosis_grow / begin_mitosis_decay
-- / draw_mitosis_cell / mitosis_die); regrow covers a fully-lost variant.
-- Deferred a frame — on_brick_killed can fire inside a Box2D contact callback
-- and body creation there would crash (same reason Brick:die defers its XpOrb).
function BallPit:mitosis_on_kill()
  local sig = (self.run_mods and self.run_mods.sig) or {}
  self.t:after(0, function()
    if self.game_over or not (self.main and self.main.world) then return end
    local clones, live = 0, {}
    for _, h in ipairs(self.heroes) do
      if h and not h.dead then
        if h.is_clone then clones = clones + 1
        else live[#live + 1] = h end
      end
    end
    if clones >= (sig.clone_cap or 10) or #live == 0 then return end
    -- Only a cell that's actually in play can divide (not caught/serving).
    local pool = {}
    for _, h in ipairs(live) do
      if not (h.stuck or h.returning or h.serving or h.mortar) then pool[#pool + 1] = h end
    end
    if #pool == 0 then return end
    local src = pool[random:int(1, #pool)]

    -- Grow a daughter cell OUT of the source at its position (no teleport-in).
    local bud = self:add_hero(src.character, {clone = true})
    bud.is_clone        = true
    bud.mitosis_spawned = true   -- skip the default launch-from-paddle
    bud.level           = src.level
    bud.dmg             = src.dmg
    if bud.body then bud.body:setActive(true) end
    bud:set_position(src.x, src.y)
    bud:begin_mitosis_grow()

    -- The two cells split apart along a random axis (equal, opposite pushes).
    local ang = random:float(0, 2*math.pi)
    local sp  = (src.base_speed or 120)*(src.speed_mult or 1)
    src:set_velocity(math.cos(ang)*sp, math.sin(ang)*sp)
    bud:set_velocity(-math.cos(ang)*sp, -math.sin(ang)*sp)
    src.spring:pull(0.4)

    -- One of the pair is the non-viable daughter that decays + dies; the other
    -- stays as the persistent cell. Which is which is chosen at random.
    local decayer, survivor
    if random:bool(50) then decayer, survivor = bud, src
    else                    decayer, survivor = src, bud end
    survivor.is_clone      = false
    survivor.mitosis_clone = nil
    survivor.mitosis_decay_t = nil
    decayer:begin_mitosis_decay(sig.clone_life or 2.5)

    -- Division flourish at the split point.
    spawn_burst(self.effects, src.x, src.y, src.color, 5, 30, 70)
    TelegraphRing{group = self.effects, x = src.x, y = src.y,
                  radius = (src.r_size or 6)*2.4, color = src.color, duration = 0.3}
  end)
end


-- Hive: spawn one maggot at the ball. Carries the hero's element (burn/slow)
-- if it has one. Deferred for the same world-locked reason as above.
function BallPit:hive_spawn_maggot(ball)
  local sig = (self.run_mods and self.run_mods.sig) or {}
  local live = 0
  for _, o in ipairs(self.main.objects) do
    if not o.dead and o:is(AllyCritter) then live = live + 1 end
  end
  if live >= (sig.maggot_cap or 24) then return end

  local x, y   = ball.x, ball.y
  local color  = ball.color
  local dmg    = ball:current_dmg()*(sig.maggot_dmg_mult or 0.8)
  -- Reach. A maggot vented on a PADDLE bounce starts at the bottom of the pit
  -- and has the whole arena (~600px) to cross; speed x life has to cover that
  -- or the bug dies in open air. seek makes it steer at the nearest brick
  -- instead of flying its launch heading (AllyCritter:steer).
  local life   = sig.maggot_life or 7
  local effect = nil
  local ob = ball.stats and ball.stats.on_bounce
  if ob == 'burn' then effect = 'burn' elseif ob == 'slow' then effect = 'slow' end

  self.t:after(0, function()
    if not (self.main and self.main.world) then return end
    AllyCritter{group = self.main, x = x, y = y, color = color, source = 'maggot',
                speed = sig.maggot_speed or 140, dmg = dmg, effect = effect, infest = true,
                seek = true, lifetime = life}
  end)
  if random:bool(30) then critter1:play{volume = 0.2, pitch = random:float(0.95, 1.1)} end
end


-- Distance from point p to segment a-b. Used by the Tesla arcs.
local function point_segment_distance(px, py, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local len2 = dx*dx + dy*dy
  if len2 < 0.0001 then return math.distance(px, py, ax, ay) end
  local t = math.clamp(((px - ax)*dx + (py - ay)*dy)/len2, 0, 1)
  return math.distance(px, py, ax + t*dx, ay + t*dy)
end


-- Tesla "Chain Conduction": a PERSISTENT lightning web. The paddle is the
-- generator; current runs paddle -> ball -> ball through every live ball and
-- damages any brick a segment passes near, on a steady tick (no bounce needed),
-- so damage scales with ball count + spreading the balls out. The crackling web
-- itself is drawn every frame by the TeslaWeb effect below.

-- Ordered conduction path: the paddle (generator) then every live ball.
function BallPit:tesla_web_points()
  local pts = {{x = self.paddle.x, y = self.paddle.y}}
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and not h.stuck and not h.returning and not h.mortar then
      pts[#pts + 1] = {x = h.x, y = h.y}
    end
  end
  return pts
end


-- One damage pulse: every brick within zap_width of a web segment takes a tick
-- (once per pulse). Driven by tesla_tick on a steady cadence; take_damage's own
-- flash is the per-brick hit feedback.
function BallPit:tesla_pulse()
  local sig   = (self.run_mods and self.run_mods.sig) or {}
  local pts   = self:tesla_web_points()
  if #pts < 2 then return end
  local dmg   = (sig.zap_dmg or 7)*((self.run_mods and self.run_mods.dmg) or 1)
  local width = sig.zap_width or 12
  local zapped, hit = {}, false
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    for _, o in ipairs(self.main.objects) do
      if o:is(Brick) and not o.dead and not zapped[o.id] then
        if point_segment_distance(o.x, o.y, a.x, a.y, b.x, b.y) <= width then
          zapped[o.id] = true
          o:take_damage(dmg, blue[0], nil, 'tesla')
          hit = true
        end
      end
    end
  end
  if hit and thunder1 then thunder1:play{volume = 0.10, pitch = random:float(1.15, 1.35)} end
end


-- Per-frame driver (called unconditionally from BallPit:update). On a Tesla run
-- it keeps the web effect alive and fires a damage pulse every zap_cd seconds.
function BallPit:tesla_tick(dt)
  if not (self.run_mods and self.run_mods.signature == 'tesla') then return end
  if not (self.tesla_web and not self.tesla_web.dead) then
    self.tesla_web = TeslaWeb{group = self.effects}
  end
  local sig = self.run_mods.sig or {}
  self.tesla_t = (self.tesla_t or 0) + dt
  if self.tesla_t >= (sig.zap_cd or 0.25) then
    self.tesla_t = 0
    self:tesla_pulse()
  end
end


-- A jagged lightning bolt between two points, drawn as a few segments that
-- crackle/jitter over time. Two passes: a soft wide glow + a bright thin core.
local function draw_tesla_bolt(x1, y1, x2, y2, t, seed)
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx*dx + dy*dy)
  if len < 1 then return end
  local nx, ny = -dy/len, dx/len
  local segs = math.clamp(math.floor(len/14) + 2, 3, 7)
  local glow = Color(0.30, 0.62, 1.0, 0.5)
  local core = Color(0.85, 0.95, 1.0, 0.95)
  local px, py = x1, y1
  for i = 1, segs do
    local f  = i/segs
    local off = (i < segs) and math.sin(t*32 + seed*2.7 + i*1.9)*math.min(7, len*0.10) or 0
    local qx = x1 + dx*f + nx*off
    local qy = y1 + dy*f + ny*off
    graphics.line(px, py, qx, qy, glow, 3)
    graphics.line(px, py, qx, qy, core, 1)
    px, py = qx, qy
  end
end


-- The always-on conduction web. Lives in arena.effects (so it shakes + layers
-- with the rest of the juice) and re-reads the live conduction path every frame
-- from BallPit:tesla_web_points, so it tracks the balls as they fly.
TeslaWeb = Object:extend()
TeslaWeb:implement(GameObject)

function TeslaWeb:init(args)
  self:init_game_object(args)
end

function TeslaWeb:update(dt)
  self:update_game_object(dt)
end

function TeslaWeb:draw()
  local arena = main.current
  if not (arena and arena.tesla_web_points) then return end
  local pts = arena:tesla_web_points()
  if #pts < 2 then return end
  local t = love.timer.getTime()
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    draw_tesla_bolt(a.x, a.y, b.x, b.y, t, i)            -- primary filament
    draw_tesla_bolt(a.x, a.y, b.x, b.y, t*1.3 + 10, i + 5) -- a second, offset filament for body
  end
  -- Node terminals: a soft pulsing halo + bright core on the generator + balls.
  for i, p in ipairs(pts) do
    local pulse = 0.5 + 0.5*math.sin(t*9 + i*1.3)
    graphics.circle(p.x, p.y, 3.5 + pulse*1.6, Color(0.4, 0.7, 1.0, 0.22))
    graphics.circle(p.x, p.y, 1.6, Color(0.9, 0.97, 1.0, 0.9))
  end
end


-- Glacier "Ice Rink": the paddle lays slick ice patches out on the rink that
-- ricochet pucks off-centre, adding chaotic glide angles (which feed the
-- glide-charge heat-up). Tuning: how often a patch drops, how many co-exist,
-- their radius and lifetime.
local SLICK_SPAWN_CD = 3.5
local SLICK_CAP      = 4
local SLICK_RS       = 18
local SLICK_LIFE     = 9


-- A slick ice patch on the rink. While alive it acts like a frictionless
-- bumper: a puck that skates into it is flung back OUT from the patch centre
-- with a small kick (per-ball cooldown so it doesn't buzz). Lives in the floor
-- group so it draws UNDER the balls + paddle, like ice on the ground.
SlickPatch = Object:extend()
SlickPatch:implement(GameObject)

function SlickPatch:init(args)
  self:init_game_object(args)
  self.rs       = self.rs or SLICK_RS
  self.max_life = self.duration or SLICK_LIFE
  self.life     = self.max_life
  self.spin     = random:float(0, 2*math.pi)
  self.hit_cd   = {}
end

function SlickPatch:update(dt)
  self:update_game_object(dt)
  self.life = self.life - dt
  if self.life <= 0 then self.dead = true; return end
  self.spin = self.spin + dt*0.6
  local arena = main.current
  if not arena then return end
  for _, h in ipairs(arena.heroes) do
    if h and not h.dead and h.body and not h.stuck and not h.returning then
      local cd = self.hit_cd[h.id] or 0
      if cd > 0 then
        self.hit_cd[h.id] = cd - dt
      else
        local d = math.distance(self.x, self.y, h.x, h.y)
        if d < self.rs and d > 0.5 then
          -- ricochet: redirect the puck straight out from the patch + a kick
          local vx, vy = h:get_velocity()
          local sp = math.max(40, math.sqrt(vx*vx + vy*vy))*1.08
          h:set_velocity((h.x - self.x)/d*sp, (h.y - self.y)/d*sp)
          h.spring:pull(0.25)
          self.hit_cd[h.id] = 0.5
          spawn_burst(arena.effects, h.x, h.y, Color(0.7, 0.9, 1.0, 0.9), 4, 50, 120)
          if frost1 then frost1:play{volume = 0.18, pitch = random:float(1.0, 1.2)} end
        end
      end
    end
  end
end

function SlickPatch:draw()
  local fade = math.min(math.clamp(self.life/0.8, 0, 1), math.clamp((self.max_life - self.life)/0.4, 0, 1))
  graphics.circle(self.x, self.y, self.rs, Color(0.45, 0.72, 0.95, 0.12*fade))      -- slick fill
  graphics.circle(self.x, self.y, self.rs, Color(0.72, 0.90, 1.0, 0.42*fade), 1)    -- frosted rim
  for i = 0, 2 do                                                                   -- shimmer streaks
    local a = self.spin + i*2.1
    graphics.line(self.x + math.cos(a)*self.rs*0.3, self.y + math.sin(a)*self.rs*0.3,
                  self.x + math.cos(a)*self.rs*0.82, self.y + math.sin(a)*self.rs*0.82,
                  Color(0.88, 0.96, 1.0, 0.28*fade), 1)
  end
end


-- Per-frame driver (called unconditionally from BallPit:update). On a Glacier
-- run it lays a fresh slick patch onto the rink every SLICK_SPAWN_CD seconds,
-- capped at SLICK_CAP, somewhere in the field where pucks actually glide.
function BallPit:glacier_tick(dt)
  if not (self.run_mods and self.run_mods.signature == 'glacier') then return end
  self.slick_t = (self.slick_t or 0) - dt
  if self.slick_t > 0 then return end
  self.slick_t = SLICK_SPAWN_CD
  local n = 0
  for _, o in ipairs(self.floor.objects) do
    if o:is(SlickPatch) and not o.dead then n = n + 1 end
  end
  if n >= SLICK_CAP then return end
  local line_y = (self.breach_line_y and self:breach_line_y()) or (self.y1 + (self.y2 - self.y1)*0.5)
  local px = random:float(self.x1 + 26, self.x2 - 26)
  local py = random:float(self.y1 + 40, line_y - 24)
  SlickPatch{group = self.floor, x = px, y = py, rs = SLICK_RS, duration = SLICK_LIFE}
  if frost1 then frost1:play{volume = 0.12, pitch = random:float(0.85, 0.98)} end
end


-- Phantom: first press drops a ghost-paddle anchor, second press teleports
-- the paddle back to it (consuming the ghost). Dropping a new anchor is
-- gated by a short cooldown; the return blink is always free.
function BallPit:phantom_blink()
  local p = self.paddle
  if not p then return end
  if self.phantom_anchor and not self.phantom_anchor.dead then
    spawn_burst(self.effects, p.x, p.y, purple[0], 8, 70, 150)
    local ax, ay = self.phantom_anchor.x, self.phantom_anchor.y
    p:set_position(ax, ay)
    self.phantom_anchor.dead = true
    self.phantom_anchor = nil
    spawn_burst(self.effects, ax, ay, purple[0], 10, 80, 160)
    buff1:play{volume = 0.35, pitch = 1.3}
  elseif self.phantom_cd_ready then
    local sig = (self.run_mods and self.run_mods.sig) or {}
    self.phantom_cd_ready = false
    self.t:after(sig.blink_cd or 2.5, function() self.phantom_cd_ready = true end, 'phantom_cd')
    self.phantom_anchor = GhostPaddle{group = self.main, x = p.x, y = p.y,
                                      w = p.w, h = p.h, aim_mult = p.aim_mult}
    TelegraphRing{group = self.effects, x = p.x, y = p.y, radius = 20,
                  color = purple[0], duration = 0.3}
    pop1:play{volume = 0.3, pitch = 0.85}
  end
end


-- Cannon: splash with damage falloff from the impact centre. Unlike
-- do_splash this also hits the Boss and critters (the mortar is the Cannon's
-- whole offense — it has to be able to fight the boss). Direct hits
-- (centre within 8px) get a 1.5x bonus.
function BallPit:do_splash_falloff(x, y, radius, dmg_max, color, source)
  spawn_burst(self.effects, x, y, color, 12, 80, 170)
  for _, o in ipairs(self.main.objects) do
    if not o.dead and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) and o.take_damage then
      local d = math.max(0, math.distance(x, y, o.x, o.y) - (o.r_outer or 0))
      if d <= radius then
        local k = math.clamp(1 - d/radius, 0.25, 1)
        if d < 8 then k = k*1.5 end
        o:take_damage(dmg_max*k, color, nil, source)
      end
    end
  end
  TelegraphRing{group = self.effects, x = x, y = y, radius = radius, color = color, duration = 0.25}
  camera:shake(math.clamp(radius/10, 2, 7), 0.2, 90)
end


-- Terrorist: the manual detonation blast — the whole offense of the build.
-- Like the Cannon splash it hits bricks, critters AND the boss with distance
-- falloff (a near-direct hit lands a bonus), carries the ball's element onto
-- the bricks, and throws a big TerrorBlast flash. Damage lives here; the
-- consuming of the spent ball happens in BallHero:terror_detonate.
function BallPit:terror_blast(x, y, radius, dmg, color, element)
  for _, o in ipairs(self.main.objects) do
    if not o.dead and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) and o.take_damage then
      local d = math.max(0, math.distance(x, y, o.x, o.y) - (o.r_outer or 0))
      if d <= radius then
        local k = math.clamp(1 - d/radius, 0.3, 1)
        if d < 10 then k = k*1.5 end                 -- near-direct hit bonus
        o:take_damage(dmg*k, color, nil, 'detonate')
      end
    end
  end
  if     element == 'burn' then self:burn_area(x, y, radius, dmg*BAL('signature.element_burn_dps_mult', 0.35), BAL('signature.element_burn_duration', 3))
  elseif element == 'slow' then self:slow_in_area(x, y, radius, BAL('signature.element_slow_factor', 0.5), BAL('signature.element_slow_duration', 3)) end
  TerrorBlast{group = self.effects, x = x, y = y, radius = radius, color = color}
  camera:shake(math.clamp(radius/8, 3, 8), 0.25, 110)
  if explosion1 then explosion1:play{volume = 0.5, pitch = random:float(0.85, 1.0)} end
end


-- ----- Twin Cast (Binary Fusion) signature -----
--
-- Each drafted hero arrives as a bonded PAIR (the mirror spawn in add_hero).
-- The two twins share a fusion bond that charges while both are in play; as it
-- fills, a gentle orbit pull spirals them together until they FUSE into one
-- super-ball that detonates a nova supercast, then split apart and recharge.
-- One TwinFusionFX entity draws every pair's bond/charge/core each frame (it
-- reads arena.twin_pairs, like the Tesla web reads its conduction path).

-- Link a freshly-spawned twin pair and register it for twincast_tick.
function BallPit:twincast_register_pair(a, b)
  if not (a and b) then return end
  a.twin, b.twin = b, a
  local pair = {
    a = a, b = b, charge = 0, state = 'charging', timer = 0, flash = 0,
    winding = random:bool(50) and 1 or -1,
    color   = a.color,
    element = a.stats and a.stats.on_bounce,
    fx_x = a.x, fx_y = a.y,
  }
  a.twin_pair, b.twin_pair = pair, pair
  self.twin_pairs = self.twin_pairs or {}
  self.twin_pairs[#self.twin_pairs + 1] = pair
end


-- Steer one twin's velocity toward a tangential orbit around the pair's
-- barycenter (mx,my), biased inward as charge rises so the pair spirals
-- together. Magnitude is preserved (normalize_speed keeps the speed), so this
-- only curves the path — the balls still bounce, attack and ramp normally.
function BallPit:twincast_orbit(ball, mx, my, charge, winding, pull, dt)
  if not ball.body then return end
  local dx, dy = ball.x - mx, ball.y - my
  local dist = math.sqrt(dx*dx + dy*dy)
  if dist < 1 then return end
  local rx, ry = dx/dist, dy/dist
  local tx, ty = -ry*winding, rx*winding          -- tangential (orbit direction)
  local inb = 0.12 + 0.7*charge                   -- inward spiral grows with charge
  local dirx, diry = tx - rx*inb, ty - ry*inb
  local dl = math.sqrt(dirx*dirx + diry*diry)
  if dl < 0.0001 then return end
  dirx, diry = dirx/dl, diry/dl
  local vx, vy = ball:get_velocity()
  local sp = math.sqrt(vx*vx + vy*vy)
  if sp < 1 then sp = (ball.base_speed or 120)*(ball.speed_mult or 1) end
  local k = math.min(0.9, (0.25 + charge*pull)*dt)
  local nx, ny = (vx/sp)*(1 - k) + dirx*k, (vy/sp)*(1 - k) + diry*k
  local nl = math.sqrt(nx*nx + ny*ny)
  if nl < 0.0001 then return end
  ball:set_velocity(nx/nl*sp, ny/nl*sp)
end


-- The fusion nova: a heavy AoE supercast at the fuse point. Reuses the Cannon's
-- falloff splash (hits bricks, critters AND the boss), layers on the twins'
-- element if they carry one, and throws the TwinNova shockwave + a big boom.
function BallPit:twincast_fuse_blast(x, y, radius, dmg, color, element)
  self:do_splash_falloff(x, y, radius, dmg, color, 'fusion')
  if element then
    for _, o in ipairs(self.main.objects) do
      if o:is(Brick) and not o.dead and math.distance(x, y, o.x, o.y) <= radius then
        if     element == 'burn' and o.apply_burn then o:apply_burn(dmg*BAL('signature.nova_burn_dps_mult', 0.22), BAL('signature.nova_burn_duration', 2.5))
        elseif element == 'slow' and o.apply_slow then o:apply_slow(BAL('signature.nova_slow_factor', 0.5), BAL('signature.nova_slow_duration', 2.0)) end
      end
    end
  end
  TwinNova{group = self.effects, x = x, y = y, radius = radius, color = color}
  camera:shake(5, 0.25, 100)
  if explosion1 then explosion1:play{volume = 0.42, pitch = random:float(0.95, 1.08)} end
  if force1     then force1:play{volume = 0.30, pitch = 1.25} end
end


-- One damage pulse along every live tether. Anything sitting on the line
-- between two charging twins takes a tick -- once per pulse per enemy, so a
-- brick straddling two pairs' tethers is still only bitten once by each.
--
-- Deliberately NOT contact-driven: the bond is drawn continuously, so tying the
-- damage to a cadence is what makes the visual honest. Pairs in the 'fused'
-- state are skipped because they draw no bond at all, and the line naturally
-- stops mattering as a pair spirals in -- a wide pair sweeps a long cutting
-- edge, a tight one sweeps almost nothing.
function BallPit:twincast_beam_pulse()
  local sig   = (self.run_mods and self.run_mods.sig) or {}
  local dmg   = (sig.beam_dmg or 5)*((self.run_mods and self.run_mods.dmg) or 1)
  local width = sig.beam_width or 7
  for _, pr in ipairs(self.twin_pairs or {}) do
    local a, b = pr.a, pr.b
    if a and b and not a.dead and not b.dead and pr.state ~= 'fused' then
      local burned = {}
      for _, o in ipairs(self.main.objects) do
        if not o.dead and not burned[o.id] and o.take_damage
           and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
          if point_segment_distance(o.x, o.y, a.x, a.y, b.x, b.y) <= width then
            burned[o.id] = true
            o:take_damage(dmg, pr.color or blue[0], nil, 'tether')
          end
        end
      end
    end
  end
end


-- Tangential speed of the final approach spiral, in px/sec. Held roughly
-- constant as the radius closes, so the pair never outruns a live ball on its
-- way into the fuse (a hero ball tops out near 385px/s at FRENZY).
local TWIN_APPROACH_SPIN = 190

-- Per-frame driver (called unconditionally from BallPit:update). Advances every
-- bonded pair's charge -> fuse -> split cycle. No-op off a Twin Cast run.
function BallPit:twincast_tick(dt)
  if not (self.run_mods and self.run_mods.signature == 'twincast') then return end
  if self.game_over or self.upgrade_pending then return end
  local sig         = self.run_mods.sig or {}
  local fuse_time   = sig.fuse_time   or 8
  local fuse_window = sig.fuse_window or 0.42
  local split_cd    = sig.split_cd    or 0.6
  local pull        = sig.orbit_pull  or 2.4
  local converge    = sig.fuse_converge or 0.2

  -- The tether between a charging pair is LIVE: it cuts whatever it crosses, on
  -- a steady cadence rather than on contact (same shape as the Tesla web). It
  -- is the reason to keep the twins apart and swinging -- and it fades out on
  -- its own as they spiral in, because a nearly-fused pair spans nothing.
  self.twin_beam_t = (self.twin_beam_t or 0) + dt
  if self.twin_beam_t >= (sig.beam_cd or 0.2) then
    self.twin_beam_t = 0
    self:twincast_beam_pulse()
  end

  for _, pr in ipairs(self.twin_pairs or {}) do
    local a, b = pr.a, pr.b
    if a and b and not a.dead and not b.dead and a.body and b.body then
      if pr.flash > 0 then pr.flash = math.max(0, pr.flash - dt*3) end

      if pr.state == 'charging' then
        local in_play = not (a.stuck or a.returning or a.serving or a.mortar
                          or  b.stuck or b.returning or b.serving or b.mortar)
        if in_play then
          pr.charge = math.min(1, pr.charge + dt/fuse_time)
          local mx, my = (a.x + b.x)/2, (a.y + b.y)/2

          -- FINAL APPROACH. twincast_orbit only bends each twin's heading --
          -- normalize_speed puts the magnitude straight back every frame -- so
          -- steering alone can leave the pair half the arena apart at the
          -- instant the meter fills, and the fuse then reads as both balls
          -- blinking out and reappearing in the middle. Over the last
          -- `converge` fraction of the charge the pair is instead flown on a
          -- scripted spiral: the radius closes to nothing and the spin winds
          -- up as it does (a skater pulling their arms in), so the twins ARRIVE
          -- at the fuse point under visible motion and r is already 0 by the
          -- time the blast fires. The centre is frozen when the approach begins
          -- so the nova lands where the spiral has been telegraphing it.
          if converge > 0 and pr.charge >= 1 - converge then
            if not pr.conv_r then
              pr.conv_r = (math.distance(a.x, a.y, mx, my) + math.distance(b.x, b.y, mx, my))/2
              pr.conv_a = math.atan2(a.y - my, a.x - mx)
              pr.conv_x, pr.conv_y = mx, my
              a.spring:pull(0.25);  b.spring:pull(0.25)
            end
            local f = math.clamp((pr.charge - (1 - converge))/converge, 0, 1)
            local r = pr.conv_r*(1 - f*f*(3 - 2*f))       -- smoothstep closure
            -- Spin at a fixed LINEAR speed, not a fixed angular one: the twins
            -- whip up as the radius closes (the skater pulling their arms in)
            -- while their actual travel stays ball-paced instead of blurring.
            -- The cap stops r -> 0 dividing out into a strobe.
            pr.conv_a = pr.conv_a
                      + pr.winding*math.min(14, TWIN_APPROACH_SPIN/math.max(r, 4))*dt
            local ca, sa = math.cos(pr.conv_a), math.sin(pr.conv_a)
            a:set_position(pr.conv_x + ca*r, pr.conv_y + sa*r)
            b:set_position(pr.conv_x - ca*r, pr.conv_y - sa*r)
            mx, my = pr.conv_x, pr.conv_y
          else
            -- How far apart the pair is flying. Sampled only while they are
            -- still free -- once the approach takes over, the scripted radius
            -- is collapsing to zero and would overwrite this with nothing --
            -- so it holds the separation they COMMITTED to the fuse at, which
            -- is what sizes the nova below. Sampling here rather than inside
            -- the approach also keeps it honest when fuse_converge is 0 and
            -- there is no approach at all.
            pr.spread = (math.distance(a.x, a.y, mx, my) + math.distance(b.x, b.y, mx, my))/2
            self:twincast_orbit(a, mx, my, pr.charge, pr.winding, pull, dt)
            self:twincast_orbit(b, mx, my, pr.charge, pr.winding, pull, dt)
          end

          if pr.charge >= 1 then
            pr.state, pr.timer = 'fused', fuse_window
            pr.fuse_window = fuse_window
            pr.fx_x, pr.fx_y = mx, my
            pr.conv_r = nil
            a:set_position(mx, my);  b:set_position(mx, my)
            a:set_velocity(0, 0);    b:set_velocity(0, 0)
            a.spring:pull(0.6);      b.spring:pull(0.6)
            local lvl = a.level or 1
            -- Spread bonus: the wider the twins were when the approach began,
            -- the bigger the blast. Radius takes the multiplier straight;
            -- damage takes a dampened share of it (nova_spread_dmg), because
            -- radius already squares into area and a full double on both would
            -- make a wide fuse worth roughly four tight ones.
            local sp_mult = math.clamp((pr.spread or 0)/(sig.nova_spread_ref or 80),
                                       sig.nova_spread_min or 0.7,
                                       sig.nova_spread_max or 2.0)
            local dmg_mult = 1 + (sp_mult - 1)*(sig.nova_spread_dmg or 0.6)
            local dmg = (sig.nova_dmg or 26)*(1 + BAL('signature.nova_level_growth', 0.5)*(lvl - 1))
                        *((self.run_mods.dmg) or 1)*dmg_mult
            self:twincast_fuse_blast(mx, my, (sig.nova_radius or 80)*sp_mult, dmg,
                                     pr.color or blue[0], pr.element)
          end
        else
          -- Caught / serving mid-approach: drop the captured spiral so it is
          -- re-measured from wherever the pair actually is when play resumes.
          pr.conv_r = nil
        end

      elseif pr.state == 'fused' then
        pr.timer = pr.timer - dt
        a:set_position(pr.fx_x, pr.fx_y);  b:set_position(pr.fx_x, pr.fx_y)
        a:set_velocity(0, 0);              b:set_velocity(0, 0)
        if pr.timer <= 0 then
          pr.state, pr.timer = 'split', split_cd
          pr.charge, pr.flash = 0, 1
          local ang = random:float(0, 2*math.pi)
          local sp  = (a.base_speed or 120)*1.25
          a:set_velocity(math.cos(ang)*sp,  math.sin(ang)*sp)
          b:set_velocity(-math.cos(ang)*sp, -math.sin(ang)*sp)
          a.spring:pull(0.5);  b.spring:pull(0.5)
          spawn_burst(self.effects, pr.fx_x, pr.fx_y, pr.color or blue[0], 14, 90, 190)
          if pop1 then pop1:play{volume = 0.3, pitch = 1.3} end
        end

      elseif pr.state == 'split' then
        pr.timer = pr.timer - dt
        if pr.timer <= 0 then pr.state, pr.charge = 'charging', 0 end
      end
    end
  end
end


-- A twisting twin-strand bond drawn between the two balls; brightens + fattens
-- as the pair charges, pinched to a point at each ball.
local function draw_fusion_bond(ax, ay, bx, by, charge, col, t)
  local dx, dy = bx - ax, by - ay
  local len = math.sqrt(dx*dx + dy*dy)
  if len < 1 then return end
  local nx, ny = -dy/len, dx/len
  local amp  = 3 + 6*charge
  local al   = 0.22 + 0.55*charge
  local segs = 16
  for strand = 0, 1 do
    local px, py
    for i = 0, segs do
      local f   = i/segs
      local env = math.sin(math.pi*f)                       -- pinch at both ends
      local off = math.sin(f*math.pi*3 + t*6 + strand*math.pi)*amp*env
      local x, y = ax + dx*f + nx*off, ay + dy*f + ny*off
      if i > 0 then graphics.line(px, py, x, y, Color(col.r, col.g, col.b, al), 1.4 + charge) end
      px, py = x, y
    end
  end
end


-- One always-on entity drawing every pair's fusion visuals (bond, charge ring,
-- orbit motes, and the fused core), reading arena.twin_pairs each frame. Lives
-- in arena.effects so it shakes + layers over the balls.
TwinFusionFX = Object:extend()
TwinFusionFX:implement(GameObject)

function TwinFusionFX:init(args) self:init_game_object(args) end
function TwinFusionFX:update(dt) self:update_game_object(dt) end

function TwinFusionFX:draw()
  local arena = main.current
  if not (arena and arena.twin_pairs) then return end
  local t = love.timer.getTime()
  for _, pr in ipairs(arena.twin_pairs) do
    local a, b = pr.a, pr.b
    if a and b and not a.dead and not b.dead then
      local col = pr.color or blue[0]
      if pr.state == 'fused' then
        local p     = math.clamp((pr.timer or 0)/(pr.fuse_window or 0.42), 0, 1)
        local pulse = 0.7 + 0.3*math.sin(t*30)
        local R     = (a.r_size or 6)*(2.1 + 0.9*p)*pulse
        for i = 0, 5 do
          local ang = t*8 + i*math.pi/3
          graphics.line(pr.fx_x, pr.fx_y, pr.fx_x + math.cos(ang)*R*2.1,
                        pr.fx_y + math.sin(ang)*R*2.1, Color(col.r, col.g, col.b, 0.4), 2)
        end
        graphics.circle(pr.fx_x, pr.fx_y, R*1.7,  Color(col.r, col.g, col.b, 0.16))
        graphics.circle(pr.fx_x, pr.fx_y, R,      Color(col.r, col.g, col.b, 0.85))
        graphics.circle(pr.fx_x, pr.fx_y, R*0.55, Color(1, 1, 1, 0.92))
      else
        local ch = pr.charge or 0
        draw_fusion_bond(a.x, a.y, b.x, b.y, ch, col, t)
        local mx, my = (a.x + b.x)/2, (a.y + b.y)/2
        local cr = 2 + 5*ch
        graphics.circle(mx, my, cr + 2, Color(col.r, col.g, col.b, 0.25*ch))
        graphics.circle(mx, my, cr,     Color(1, 1, 1, 0.35 + 0.5*ch))
        local sa = -math.pi/2
        graphics.arc('open', mx, my, 9 + 3*ch, sa, sa + ch*2*math.pi,
                     Color(col.r, col.g, col.b, 0.85), 2)
        for i = 0, 2 do
          local ang = t*3 + i*2.094
          local orb = 7 + 4*ch
          graphics.circle(mx + math.cos(ang)*orb, my + math.sin(ang)*orb,
                          1.2 + ch, Color(col.r, col.g, col.b, 0.5*ch))
        end
      end
      if pr.flash and pr.flash > 0 then
        graphics.circle(pr.fx_x, pr.fx_y, (a.r_size or 6)*2*(2 - pr.flash),
                        Color(1, 1, 1, 0.45*pr.flash), 2)
      end
    end
  end
end


-- The fusion nova shockwave: an expanding ring + radial spokes in the twins'
-- colour. Pure juice — the damage is dealt immediately in twincast_fuse_blast.
TwinNova = Object:extend()
TwinNova:implement(GameObject)

function TwinNova:init(args)
  self:init_game_object(args)
  self.radius = self.radius or 78
  self.life, self.max = 0.5, 0.5
  self.spin = random:float(0, 2*math.pi)
end

function TwinNova:update(dt)
  self:update_game_object(dt)
  self.life = self.life - dt
  self.spin = self.spin + dt*4
  if self.life <= 0 then self.dead = true end
end

function TwinNova:draw()
  local k   = 1 - self.life/self.max
  local r   = self.radius*(0.25 + 0.95*k)
  local al  = 1 - k
  local col = self.color or blue[0]
  graphics.circle(self.x, self.y, r*0.85, Color(col.r, col.g, col.b, 0.10*al))
  graphics.circle(self.x, self.y, r,      Color(col.r, col.g, col.b, 0.70*al), 3)
  graphics.circle(self.x, self.y, r*0.7,  Color(1, 1, 1, 0.45*al), 1.5)
  for i = 0, 7 do
    local ang = self.spin + i*math.pi/4
    graphics.line(self.x + math.cos(ang)*r*0.4,  self.y + math.sin(ang)*r*0.4,
                  self.x + math.cos(ang)*r*1.05, self.y + math.sin(ang)*r*1.05,
                  Color(col.r, col.g, col.b, 0.5*al), 2)
  end
end


-- ----- The post-death screens: run report + paddle shop -----
--
-- The game_over flag routes BallPit:update into update_shop and draw into the
-- draw_game_over override below, which now hosts TWO screens picked by
-- self.go_screen (set to 'over' by trigger_game_over):
--   'over'  the run report -- headline, stats panel, RESTART / SHOP buttons.
--   'shop'  the paddle shop -- card grid + detail panel, BACK returns to the
--           report. Cards render the loadout's REAL paddle body via
--           Paddle.draw_preview. R still restarts from either screen.

-- ===========================================================================
-- THE SHOP: an arcade pinball cabinet
-- ===========================================================================
-- The shop is not an overlay on the dead arena any more -- it is its own
-- opaque PAGE, dressed as the backglass of a pinball machine: a bulb-lit
-- marquee, an electro-mechanical credit reel, chrome ball-guide rails,
-- pop-bumper nav buttons, drop-target buttons and a pair of idling flippers.
--
-- Page layout (canvas is 480 x 656):
--     12.. 74   marquee + chase lights
--     84..112   credit reel  |  EXIT drop target
--    128..340   paddle CAROUSEL (focus card + neighbours) + position lamps
--    352..560   spec panel: stat RADAR (left) + loadout copy (right)
--    570..608   BUY / EQUIP drop target
--    612..656   flippers + control hints
local SHOP_MARQUEE_CY = 44
local SHOP_MARQUEE_W  = 404
local SHOP_MARQUEE_H  = 58
local SHOP_CREDIT_CY  = 98
local CARO_CY         = 232
local CARO_W          = 176   -- focus card size; neighbours are scaled down
local CARO_H          = 148
local CARO_STEP       = 142   -- x distance between adjacent carousel slots
local CARO_SIDE_S     = 0.66  -- scale of the immediate neighbours
local SHOP_PANEL_CY   = 456
local SHOP_PANEL_W    = 440
local SHOP_PANEL_H    = 208
local SHOP_ACT_CY     = 586   -- BUY / EQUIP drop target
local RADAR_CX        = 116
local RADAR_CY        = 486
local RADAR_R         = 46
local RADAR_ICON_OUT  = 13    -- how far past the rim the axis symbols sit

-- Run-report buttons + the shop's BACK button.
local GO_BUTTONS = {
  {id = 'restart', label = 'RESTART RUN'},
  {id = 'shop',    label = 'PADDLE SHOP'},
}
-- Sized and spaced as cab_target drop tabs, the same hardware the shop's EXIT
-- and BUY buttons are made of.
local GO_BTN_W, GO_BTN_H = 260, 36

local function go_button_pos(i)
  return gw/2, 490 + (i - 1)*58
end

-- The EXIT drop target shares the credit-reel row: the marquee owns the whole
-- top strip now, so a top-left button would sit inside it.
local function shop_back_rect()
  -- Left edge flush with the marquee's, so EXIT reads as hanging off the
  -- corner of the PADDLE EXCHANGE sign instead of floating out past it.
  local w, h = 76, 24
  return gw/2 - SHOP_MARQUEE_W/2 + w/2, SHOP_CREDIT_CY, w, h
end

local function draw_menu_button(bx, by, w, h, label, selected)
  graphics.rectangle(bx, by, w, h, 4, 4, selected and bg[1] or bg[-1])
  graphics.rectangle(bx, by, w, h, 4, 4, selected and yellow[0] or fg_transparent_weak, selected and 2 or 1)
  graphics.print_centered(label, pixul_font, bx, by - 1, 0, 1, 1, 0, 0, selected and yellow[0] or fg[0])
end

-- ---------------------------------------------------------------------------
-- Cabinet hardware. Every one of these is a real part off a pinball machine,
-- so the whole screen reads as playfield furniture rather than as a menu.
-- ---------------------------------------------------------------------------

-- A marquee bulb. Lit bulbs get a hot core and a halo; dark ones are a socket.
local function cab_bulb(x, y, lit, col)
  if lit then
    graphics.circle(x, y, 3.6, Color(col.r, col.g, col.b, 0.26))
    graphics.circle(x, y, 1.9, col)
    graphics.circle(x - 0.5, y - 0.6, 0.7, Color(1, 1, 1, 0.9))
  else
    graphics.circle(x, y, 1.8, Color(0, 0, 0, 0.5))
    graphics.circle(x, y, 1.8, Color(col.r, col.g, col.b, 0.22), 1)
  end
end


-- Brushed-metal panel: dark face, a bright hairline along the top edge (the
-- light in an arcade always comes from the marquee above), thin bezel.
local function cab_panel(cx, cy, w, h, r, face, edge)
  graphics.rectangle(cx, cy, w, h, r, r, face or bg[-1])
  graphics.rectangle(cx, cy - h/2 + 2, w - 8, 1, nil, nil, Color(1, 1, 1, 0.09))
  graphics.rectangle(cx, cy, w, h, r, r, edge or Color(1, 1, 1, 0.15), 1)
end


-- Chrome ball guide: the twin rails that shepherd a ball across a playfield,
-- with a post at each end.
local function cab_rail(x1, x2, y, col)
  graphics.line(x1, y,     x2, y,     Color(1, 1, 1, 0.20), 1)
  graphics.line(x1, y + 2, x2, y + 2, Color(col.r, col.g, col.b, 0.28), 1)
  graphics.circle(x1, y + 1, 2.4, Color(1, 1, 1, 0.22))
  graphics.circle(x2, y + 1, 2.4, Color(1, 1, 1, 0.22))
end


-- Pop bumper. Doubles as the carousel's prev/next button: `dir` (-1/1) draws
-- the chevron, `hot` lights the lamp when the mouse is over it.
local function cab_bumper(cx, cy, r, col, t, dir, hot)
  local p = 0.5 + 0.5*math.sin(t*2.4 + cx*0.05)
  local lamp = hot and 1 or (0.35 + 0.25*p)
  graphics.circle(cx, cy, r,        Color(col.r, col.g, col.b, 0.10 + 0.14*lamp))
  graphics.circle(cx, cy, r,        Color(col.r, col.g, col.b, 0.30 + 0.5*lamp), hot and 2 or 1)
  graphics.circle(cx, cy, r*0.66,   Color(col.r, col.g, col.b, 0.22 + 0.3*lamp), 1)
  if dir then
    local s = r*0.34
    -- Apex leads, flat back edge trails, so the left bumper's arrow points
    -- LEFT and the right one points RIGHT (dir is -1 left / +1 right).
    graphics.polygon({cx - dir*s, cy - s, cx - dir*s, cy + s, cx + dir*s*0.7, cy},
                     hot and Color(1, 1, 1, 1) or Color(col.r, col.g, col.b, 0.85))
  else
    graphics.circle(cx, cy, r*0.26, Color(col.r, col.g, col.b, 0.4 + 0.5*lamp))
  end
end


-- A DROP TARGET: the standing plastic tab you knock down with the ball. Every
-- button on this page is one, so the UI is all playfield hardware.
local function cab_target(cx, cy, w, h, label, col, hot, dim)
  local face = hot and Color(col.r*0.30, col.g*0.30, col.b*0.30, 1) or bg[-1]
  graphics.rectangle(cx, cy, w, h, 3, 3, face)
  -- Lit strip across the top of the tab -- the target's own lamp.
  graphics.rectangle(cx, cy - h/2 + 4, w - 12, 2, 1, 1,
                     Color(col.r, col.g, col.b, hot and 0.95 or 0.30))
  graphics.rectangle(cx, cy, w, h, 3, 3,
                     hot and col or Color(col.r, col.g, col.b, 0.42), hot and 2 or 1)
  -- Mounting screws either side, like the real plastic.
  graphics.circle(cx - w/2 + 5, cy + h/2 - 4, 1, Color(1, 1, 1, 0.18))
  graphics.circle(cx + w/2 - 5, cy + h/2 - 4, 1, Color(1, 1, 1, 0.18))
  local tcol = dim and fg_alt[0] or (hot and Color(1, 1, 1, 1) or fg[0])
  -- Native scale (see shared.lua): print_centered lifts by font.h/2 = 6.5 and
  -- the ink is 9 tall, so cy + 2 puts the ink's centre on the tab's centre.
  -- The widest label ('INSERT 5000 BLOCKS' = 163px) still clears the 260px tab.
  graphics.print_centered(label, pixul_mono_font, cx, cy + 2, 0, 1, 1, 0, 0, tcol)
end


-- Electro-mechanical score reel: fixed-width digit windows with a seam across
-- the middle, the way a cabinet actually shows credits.
local function cab_reel(cx, cy, value, digits, col)
  local dw, dh, gap = 16, 24, 3
  local total = digits*dw + (digits - 1)*gap
  local s = string.format('%0' .. digits .. 'd',
                          math.min(math.max(math.floor(value or 0), 0), 10^digits - 1))
  for i = 1, digits do
    local x = cx - total/2 + dw/2 + (i - 1)*(dw + gap)
    graphics.rectangle(x, cy, dw, dh, 2, 2, Color(0, 0, 0, 0.8))
    graphics.rectangle(x, cy, dw, dh, 2, 2, Color(1, 1, 1, 0.13), 1)
    -- fat_font ink runs y-17s .. y+2s through print_centered, so cy + 7.5s is
    -- the draw y that actually centres a digit in its window; at the old cy - 1
    -- every digit hung ~7px out of the top of its own reel.
    graphics.print_centered(s:sub(i, i), fat_font, x, cy + 7.9, 0, 1.05, 1.05, 0, 0, col)
    graphics.rectangle(x, cy, dw - 2, 0.6, nil, nil, Color(0, 0, 0, 0.55))   -- reel seam
  end
end


-- (cab_flipper lived here: the idling flipper bats that used to sit along the
-- bottom of both pages. Both pages dropped them, so it went with them.)


-- Greedy word wrap against a pixel width, for the loadout copy.
local function wrap_text(text, font, scale, max_w)
  local lines, line = {}, nil
  for word in tostring(text or ''):gmatch('%S+') do
    local try = line and (line .. ' ' .. word) or word
    if (not line) or font:get_text_width(try)*scale <= max_w then
      line = try
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line then lines[#lines + 1] = line end
  return lines
end


-- ---------------------------------------------------------------------------
-- STAT RADAR
-- ---------------------------------------------------------------------------
-- The eight loadout multipliers, in radar order (clockwise from the top). The
-- paddle-feel stats occupy the left half and the ball/offence stats the right,
-- so two loadouts are comparable at a glance by which side of the web bulges.
-- `icon` picks the glyph; `label` is what the hover tooltip says.
local STAT_AXES = {
  {key = 'size',   icon = 'size',   label = 'PADDLE SIZE'},
  {key = 'ball',   icon = 'ball',   label = 'BALL SPEED'},
  {key = 'dmg',    icon = 'dmg',    label = 'DAMAGE'},
  {key = 'combo',  icon = 'combo',  label = 'COMBO GAIN'},
  {key = 'xp',     icon = 'xp',     label = 'XP GAIN'},
  {key = 'charge', icon = 'charge', label = 'CHARGE RATE'},
  {key = 'aim',    icon = 'aim',    label = 'AIM CONTROL'},
  {key = 'move',   icon = 'move',   label = 'MOVE SPEED'},
}

-- Every multiplier in PADDLES.defs lives in 0.2 .. 1.7, so one shared scale
-- keeps all eight axes comparable. The floor stops a crippled stat (Aegis
-- charge 0.2) from collapsing to a point, and 1.0 -- the Standard baseline --
-- lands just past half radius, so "better than default" reads as "outside the
-- dashed ring".
local function stat_norm(v)
  return math.clamp(((v or 1) - 0.2)/1.5, 0.08, 1)
end


-- Tiny 7px pictograms for the radar rim. All built from convex primitives
-- (graphics.polygon fills convex only), so bolts and stars are unions of
-- triangles rather than single concave outlines.
local function draw_stat_icon(kind, x, y, s, col)
  if kind == 'size' then            -- a paddle bar with expand arrows
    graphics.rectangle(x, y, 1.5*s, 0.6*s, 0.3, 0.3, col)
    graphics.polygon({x - 1.7*s, y, x - 0.9*s, y - 0.8*s, x - 0.9*s, y + 0.8*s}, col)
    graphics.polygon({x + 1.7*s, y, x + 0.9*s, y - 0.8*s, x + 0.9*s, y + 0.8*s}, col)

  elseif kind == 'move' then        -- double chevron
    graphics.polygon({x - 1.5*s, y - 1.1*s, x - 0.3*s, y, x - 1.5*s, y + 1.1*s}, col)
    graphics.polygon({x + 0.1*s, y - 1.1*s, x + 1.3*s, y, x + 0.1*s, y + 1.1*s}, col)

  elseif kind == 'ball' then        -- ball with a speed trail
    graphics.circle(x + 0.5*s, y, 0.9*s, col)
    graphics.circle(x - 0.7*s, y, 0.45*s, Color(col.r, col.g, col.b, 0.65))
    graphics.circle(x - 1.5*s, y, 0.3*s,  Color(col.r, col.g, col.b, 0.35))

  elseif kind == 'charge' then      -- lightning bolt, as two triangles
    graphics.polygon({x + 0.2*s, y - 1.6*s, x - 1.1*s, y + 0.2*s, x + 0.35*s, y - 0.1*s}, col)
    graphics.polygon({x + 1.1*s, y - 0.2*s, x - 0.2*s, y + 1.6*s, x - 0.35*s, y + 0.1*s}, col)

  elseif kind == 'aim' then         -- crosshair
    graphics.circle(x, y, 1.2*s, col, 1)
    graphics.circle(x, y, 0.32*s, col)
    graphics.rectangle(x, y - 1.7*s, 0.5, 0.8*s, nil, nil, col)
    graphics.rectangle(x, y + 1.7*s, 0.5, 0.8*s, nil, nil, col)
    graphics.rectangle(x - 1.7*s, y, 0.8*s, 0.5, nil, nil, col)
    graphics.rectangle(x + 1.7*s, y, 0.8*s, 0.5, nil, nil, col)

  elseif kind == 'dmg' then         -- impact starburst (four spikes)
    for i = 0, 3 do
      local a = i*math.pi/2 + math.pi/4
      local ca, sa = math.cos(a), math.sin(a)
      graphics.polygon({x + ca*1.7*s, y + sa*1.7*s,
                        x - sa*0.55*s, y + ca*0.55*s,
                        x + sa*0.55*s, y - ca*0.55*s}, col)
    end
    graphics.circle(x, y, 0.5*s, col)

  elseif kind == 'combo' then       -- flame
    graphics.polygon({x, y - 1.7*s, x + 1.0*s, y + 0.5*s, x - 1.0*s, y + 0.5*s}, col)
    graphics.circle(x, y + 0.55*s, 0.85*s, col)
    graphics.circle(x, y + 0.75*s, 0.38*s, Color(1, 1, 1, 0.55))

  elseif kind == 'xp' then          -- gem
    graphics.polygon({x, y - 1.6*s, x + 1.1*s, y, x, y + 1.6*s, x - 1.1*s, y}, col)
    graphics.polygon({x, y - 1.6*s, x + 1.1*s, y, x - 0.2*s, y - 0.1*s}, Color(1, 1, 1, 0.35))
  end
end


-- Screen position of radar axis `i`. Shared by the painter and the hit test so
-- the tooltip can never drift off its symbol.
local function radar_axis_pos(i, out)
  local a = -math.pi/2 + (i - 1)*(2*math.pi/#STAT_AXES)
  local r = RADAR_R + (out or 0)
  return RADAR_CX + math.cos(a)*r, RADAR_CY + math.sin(a)*r
end


-- Which axis symbol the mouse is on, or nil.
function BallPit:shop_radar_hover()
  for i = 1, #STAT_AXES do
    local ix, iy = radar_axis_pos(i, RADAR_ICON_OUT)
    if math.distance(mouse.x, mouse.y, ix, iy) <= 9 then return i end
  end
  return nil
end


-- The spider web itself. `hovered` lights one axis; the caller draws the
-- tooltip afterwards so it floats above everything.
function BallPit:draw_stat_radar(def, col, hovered)
  local n = #STAT_AXES

  -- Web: concentric rings + a spoke per axis.
  for _, f in ipairs{0.34, 0.67, 1.0} do
    local pts = {}
    for i = 1, n do
      local x, y = radar_axis_pos(i, 0)
      pts[#pts + 1] = RADAR_CX + (x - RADAR_CX)*f
      pts[#pts + 1] = RADAR_CY + (y - RADAR_CY)*f
    end
    pts[#pts + 1], pts[#pts + 2] = pts[1], pts[2]
    graphics.polyline(Color(1, 1, 1, f == 1 and 0.20 or 0.08), 1, pts)
  end
  for i = 1, n do
    local x, y = radar_axis_pos(i, 0)
    graphics.line(RADAR_CX, RADAR_CY, x, y, Color(1, 1, 1, 0.10), 1)
  end

  -- Baseline ring at 1.0x: anything outside it beats the Standard paddle.
  local base = stat_norm(1.0)
  local bpts = {}
  for i = 1, n do
    local x, y = radar_axis_pos(i, 0)
    bpts[#bpts + 1] = RADAR_CX + (x - RADAR_CX)*base
    bpts[#bpts + 1] = RADAR_CY + (y - RADAR_CY)*base
  end
  bpts[#bpts + 1], bpts[#bpts + 2] = bpts[1], bpts[2]
  graphics.polyline(Color(fg_alt[0].r, fg_alt[0].g, fg_alt[0].b, 0.35), 1, bpts)

  -- The loadout's profile. Filled as a fan of triangles from the centre so a
  -- concave web (e.g. Aegis: huge size, no charge) still fills correctly.
  local vx, vy = {}, {}
  for i = 1, n do
    local x, y = radar_axis_pos(i, 0)
    local f = stat_norm(def[STAT_AXES[i].key])
    vx[i] = RADAR_CX + (x - RADAR_CX)*f
    vy[i] = RADAR_CY + (y - RADAR_CY)*f
  end
  for i = 1, n do
    local j = (i % n) + 1
    graphics.polygon({RADAR_CX, RADAR_CY, vx[i], vy[i], vx[j], vy[j]},
                     Color(col.r, col.g, col.b, 0.28))
  end
  local opts = {}
  for i = 1, n do opts[#opts + 1] = vx[i]; opts[#opts + 1] = vy[i] end
  opts[#opts + 1], opts[#opts + 2] = vx[1], vy[1]
  graphics.polyline(col, 1.5, opts)
  for i = 1, n do graphics.circle(vx[i], vy[i], 1.7, col) end

  -- Axis symbols on the rim, each in its own little lamp socket.
  for i = 1, n do
    local ix, iy = radar_axis_pos(i, RADAR_ICON_OUT)
    local hot = (i == hovered)
    graphics.circle(ix, iy, 7.5, hot and Color(col.r, col.g, col.b, 0.35) or Color(0, 0, 0, 0.5))
    graphics.circle(ix, iy, 7.5, hot and col or Color(1, 1, 1, 0.16), 1)
    draw_stat_icon(STAT_AXES[i].icon, ix, iy, 2.6,
                   hot and Color(1, 1, 1, 1) or Color(fg[0].r, fg[0].g, fg[0].b, 0.85))
  end
end


-- Hover tooltip for one axis symbol: what the stat IS, plus this loadout's
-- actual multiplier and how it compares to the 1.0 baseline. Drawn last.
function BallPit:draw_stat_tooltip(i, def)
  local ax  = STAT_AXES[i]
  local v   = def[ax.key] or 1
  local val = string.format('%.2fx', v)
  if ax.key == 'xp' and def.xp_mode == 'flat' then val = 'FLAT CURVE' end
  local txt = ax.label .. '   ' .. val

  local w = pixul_mono_font:get_text_width(txt) + 16
  local h = 18
  local ix, iy = radar_axis_pos(i, RADAR_ICON_OUT)
  local tx = math.clamp(ix, w/2 + 4, gw - w/2 - 4)
  local ty = iy - 16
  if ty - h/2 < SHOP_PANEL_CY - SHOP_PANEL_H/2 then ty = iy + 16 end

  graphics.rectangle(tx, ty, w, h, 3, 3, Color(0, 0, 0, 0.92))
  graphics.rectangle(tx, ty, w, h, 3, 3, Color(1, 1, 1, 0.3), 1)
  -- Colour the value by whether it beats the baseline.
  local vcol = fg[0]
  if v > 1.001 then vcol = green[0] elseif v < 0.999 then vcol = red[0] end
  -- print (not print_centered) puts the ink at y .. y+9, so y = ty - 4.5
  -- centres it in the 18px box.
  local lw = pixul_mono_font:get_text_width(ax.label)
  graphics.print(ax.label, pixul_mono_font, tx - w/2 + 8, ty - 4.5, 0, 1, 1, 0, 0, fg[0])
  graphics.print(val, pixul_mono_font, tx - w/2 + 8 + lw + 8, ty - 4.5, 0, 1, 1, 0, 0, vcol)
end


-- ---------------------------------------------------------------------------
-- CAROUSEL
-- ---------------------------------------------------------------------------

-- Where a card sits, given its signed distance in slots from the focus.
-- `d` is fractional (it comes off the animated scroll), so cards glide and
-- shrink continuously rather than snapping between slots.
local function caro_slot(d)
  local ad = math.min(math.abs(d), 2.4)
  local s  = 1 - (1 - CARO_SIDE_S)*math.min(ad, 1)
  if ad > 1 then s = s*(1 - 0.20*(ad - 1)) end
  return gw/2 + d*CARO_STEP, s, math.clamp(1 - 0.40*ad, 0.10, 1)
end


-- Carousel nav bumpers.
local function caro_arrow_pos(dir)
  return (dir < 0) and 26 or (gw - 26), CARO_CY
end


-- Topmost card under the mouse (nearest the focus wins, matching draw order).
function BallPit:shop_caro_hit()
  local scroll = self.shop_scroll or 1
  local best, bestd
  for i = 1, #PADDLES.order do
    local d = i - scroll
    if math.abs(d) <= 2.4 then
      local x, s = caro_slot(d)
      if math.abs(mouse.x - x) <= CARO_W*s/2 and math.abs(mouse.y - CARO_CY) <= CARO_H*s/2 then
        if not bestd or math.abs(d) < bestd then best, bestd = i, math.abs(d) end
      end
    end
  end
  return best
end


-- ----- Equip flourishes: one per loadout -----
--
-- Equipping used to be one confirm beep for all eleven paddles. Each loadout
-- now plays its OWN half-second animation over the focused card, built from
-- the verb that loadout is actually about -- so the moment you pick it, the
-- shop shows you what you just signed up for. Signature-keyed, exactly like
-- HEART_STYLES, and every one of them stays inside the card: no screen
-- flashes, no full-page wipes.
--
-- fn(cx, cy, w, h, p, col) -- p runs 0..1 across EQUIP_FX_TIME, col is the
-- loadout's palette colour.
local EQUIP_FX_TIME = 0.55

local EQUIP_FX = {
  -- Standard: no trick, just the tile locking shut. A bracket closes from
  -- both edges while a specular wipe crosses the face.
  none = function(cx, cy, w, h, p, col)
    local k = 1 - (1 - p)^3
    for _, s in ipairs{-1, 1} do
      local bx = cx + s*(w*0.5*(1 - k) + 6)
      graphics.line(bx, cy - h/2 + 8, bx, cy + h/2 - 8, Color(1, 1, 1, 0.7*(1 - p)), 2)
    end
    local wx = cx - w/2 + w*k
    graphics.line(wx, cy - h/2 + 4, wx, cy + h/2 - 4, Color(1, 1, 1, 0.4*(1 - p)), 3)
    graphics.rectangle(cx, cy, w*k, h*k, 5, 5, Color(col.r, col.g, col.b, 0.4*(1 - p)), 2)
  end,

  -- Pinball Lobber: both flippers kick, and the ball they launched leaves
  -- through the top of the card.
  flippers = function(cx, cy, w, h, p, col)
    local kick = math.sin(math.min(1, p*2.2)*math.pi)
    local by   = cy + h/2 - 16
    for _, s in ipairs{-1, 1} do
      local fx = cx + s*(w/2 - 26)
      graphics.push(fx, by, s*(0.55 - 1.0*kick))
        graphics.rectangle(fx + s*13, by, 30, 7, 3, 3, Color(1, 1, 1, 0.8*(1 - p*0.5)))
      graphics.pop()
    end
    local t  = p*p
    local ly = by - 12 - t*(h - 34)
    graphics.circle(cx, ly, 4.5, Color(col.r, col.g, col.b, 1 - t))
    graphics.circle(cx - 1.4, ly - 1.4, 1.6, Color(1, 1, 1, 0.85*(1 - t)))
  end,

  -- Aegis: the shield plate drops into place and rings once.
  aegis = function(cx, cy, w, h, p, col)
    local gold = Color(1, 0.85, 0.35, 1)
    local drop = (p < 0.4) and (1 - p/0.4)^2 or 0
    local sy   = cy - drop*(h/2 + 30)
    local pts  = {}
    for v = 0, 5 do
      local a = -math.pi/2 + v*math.pi/3
      pts[#pts + 1] = cx + 26*math.cos(a)
      pts[#pts + 1] = sy + 30*math.sin(a)
    end
    graphics.polygon(pts, Color(gold.r, gold.g, gold.b, 0.20*(1 - p)))
    graphics.polygon(pts, Color(gold.r, gold.g, gold.b, 1 - p), 2)
    if p >= 0.4 then
      local k = (p - 0.4)/0.6
      graphics.circle(cx, cy, 26 + k*64, Color(gold.r, gold.g, gold.b, 0.5*(1 - k)), 2)
    end
  end,

  -- Mitosis: the cell divides, and the daughter is already fading.
  mitosis = function(cx, cy, w, h, p, col)
    local d = (1 - (1 - p)^2)*30
    graphics.circle(cx - d, cy, 16, Color(col.r, col.g, col.b, 0.22*(1 - p)))
    graphics.circle(cx - d, cy, 16, Color(col.r, col.g, col.b, 1 - p), 2)
    graphics.circle(cx - d, cy, 4, Color(1, 1, 1, 0.6*(1 - p)))
    graphics.circle(cx + d, cy, 16 - 8*p, Color(col.r, col.g, col.b, 0.75*(1 - p)), 2)
  end,

  -- Hive: the comb builds outward, centre cell first.
  hive = function(cx, cy, w, h, p, col)
    local amber = Color(0.95, 0.72, 0.20, 1)
    for cell = 0, 6 do
      local k = math.clamp((p - (cell == 0 and 0 or 0.06*cell))/0.35, 0, 1)
      if k > 0 then
        local ca = cell*math.pi/3
        local cr = (cell == 0) and 0 or 23
        local hx, hy = cx + cr*math.cos(ca), cy + cr*math.sin(ca)
        local pts = {}
        for v = 0, 5 do
          local a = math.pi/6 + v*math.pi/3
          pts[#pts + 1] = hx + 12*k*math.cos(a)
          pts[#pts + 1] = hy + 12*k*math.sin(a)
        end
        graphics.polygon(pts, Color(amber.r, amber.g, amber.b, 0.55*k*(1 - p)))
        graphics.polygon(pts, Color(0.55, 0.38, 0.08, 0.9*k*(1 - p)), 1)
      end
    end
  end,

  -- Vampire: the card fills with blood, then drains back out of it.
  vampire = function(cx, cy, w, h, p, col)
    local fill = math.sin(math.min(1, p*1.5)*math.pi)
    local bh   = (h - 14)*fill
    if bh > 1 then
      graphics.rectangle(cx, cy + h/2 - 7 - bh/2, w - 14, bh, 3, 3,
                         Color(0.55, 0.03, 0.06, 0.5))
      graphics.line(cx - (w - 14)/2, cy + h/2 - 7 - bh,
                    cx + (w - 14)/2, cy + h/2 - 7 - bh,
                    Color(0.85, 0.10, 0.16, 0.8*(1 - p)), 1)
    end
    for i = 1, 4 do
      local dx = cx - w/4 + (i - 1)*w/6
      local dy = cy - h/2 + 10 + ((p*2.0 + i*0.23) % 1)*(h - 26)
      graphics.circle(dx, dy, 2.2, Color(0.78, 0.06, 0.12, 0.85*(1 - p)))
    end
  end,

  -- Boomerang: it flies out, arcs, and comes back to the hand.
  boomerang = function(cx, cy, w, h, p, col)
    local wood = Color(0.78, 0.56, 0.28, 1 - p*0.35)
    local hx   = cx - w/2 + 20
    local bx   = hx + math.sin(p*math.pi)*(w - 40)
    local by   = cy - math.sin(p*math.pi)*26
    graphics.line(hx, cy, bx, by, Color(0.78, 0.56, 0.28, 0.22*(1 - p)), 1)
    graphics.push(bx, by, p*16)
      graphics.rectangle(bx - 5, by, 13, 5, 2, 2, wood)
      graphics.rectangle(bx, by - 5, 5, 13, 2, 2, wood)
    graphics.pop()
  end,

  -- Twin Cast: the pair spirals in and fuses.
  twincast = function(cx, cy, w, h, p, col)
    local r = 4 + (1 - p)^1.5*44
    local a = p*7
    local ox, oy = r*math.cos(a), r*math.sin(a)*0.7
    graphics.line(cx + ox, cy + oy, cx - ox, cy - oy, Color(1, 1, 1, 0.22*(1 - p)), 1)
    graphics.circle(cx + ox, cy + oy, 5 - 2*p, Color(0.72, 0.55, 1, 1))
    graphics.circle(cx - ox, cy - oy, 5 - 2*p, Color(0.55, 0.75, 1, 1))
    if p > 0.78 then
      local k = (p - 0.78)/0.22
      graphics.circle(cx, cy, 6 + k*42, Color(1, 1, 1, 0.45*(1 - k)), 2)
    end
  end,

  -- Tesla: three bolts crack between the terminals, settling as they die.
  tesla = function(cx, cy, w, h, p, col)
    local x0, x1 = cx - w/2 + 18, cx + w/2 - 18
    for _, s in ipairs{-1, 1} do
      graphics.rectangle(cx + s*(w/2 - 18), cy, 6, 14, 1, 1,
                         Color(0.62, 0.65, 0.72, 1 - p))
    end
    for b = 1, 3 do
      local pts, n = {}, 8
      for i = 0, n do
        local u  = i/n
        local jy = (i == 0 or i == n) and 0
                   or math.sin(b*2.7 + u*13 + p*26)*(9 + 5*b)*(1 - p)
        pts[#pts + 1] = x0 + (x1 - x0)*u
        pts[#pts + 1] = cy + jy
      end
      graphics.polyline(Color(0.55, 0.85, 1, (1 - p)*((b == 1) and 0.95 or 0.35)),
                        (b == 1) and 2 or 1, unpack(pts))
    end
  end,

  -- Terrorist: the fuse runs the card's edge, then the charge goes off.
  terrorist = function(cx, cy, w, h, p, col)
    local x0, y0 = cx - w/2 + 8, cy - h/2 + 8
    local pw, ph = w - 16, h - 16
    local d = math.min(1, p/0.7)*2*(pw + ph)
    local sx, sy
    if     d < pw        then sx, sy = x0 + d, y0
    elseif d < pw + ph   then sx, sy = x0 + pw, y0 + (d - pw)
    elseif d < 2*pw + ph then sx, sy = x0 + pw - (d - pw - ph), y0 + ph
    else                      sx, sy = x0, y0 + ph - (d - 2*pw - ph) end
    graphics.rectangle(cx, cy, pw, ph, 3, 3, Color(0.75, 0.60, 0.40, 0.30*(1 - p)), 1)
    graphics.circle(sx, sy, 3, Color(1, 0.80, 0.30, 1))
    graphics.circle(sx, sy, 1.4, Color(1, 1, 0.90, 1))
    if p > 0.7 then
      local k = (p - 0.7)/0.3
      graphics.circle(cx, cy, k*46, Color(1, 0.55, 0.15, 0.55*(1 - k)), 2)
      graphics.circle(cx, cy, k*30, Color(1, 0.80, 0.30, 0.40*(1 - k)), 2)
    end
  end,

  -- Cannon: the shot drops in and lands hard enough to throw a ring.
  cannon = function(cx, cy, w, h, p, col)
    local land, fy = 0.55, cy + 20
    local by = (p < land) and (cy - h/2 - 12 + (p/land)^2*(h/2 + 32)) or fy
    if p >= land then
      local k = (p - land)/(1 - land)
      graphics.circle(cx, fy, 10 + k*44, Color(1, 1, 1, 0.30*(1 - k)), 2)
      graphics.line(cx - 26 - k*22, fy, cx + 26 + k*22, fy,
                    Color(col.r, col.g, col.b, 0.45*(1 - k)), 1)
    end
    graphics.circle(cx, by, 9, Color(0.30, 0.32, 0.38, 1))
    graphics.circle(cx - 3, by - 3, 3, Color(0.55, 0.58, 0.66, 0.9))
  end,
}

-- Each loadout also gets its own confirm sound. Resolved by NAME at play time:
-- the sound globals are built in main.lua, which may load after this file, so
-- capturing the objects in the table above would capture nils.
local EQUIP_SFX = {
  none      = {'confirm1',   0.40, 1.00},
  flippers  = {'mine1',      0.45, 1.20},
  aegis     = {'mine1',      0.50, 0.70},
  mitosis   = {'spawn1',     0.45, 1.30},
  hive      = {'spawn1',     0.40, 0.90},
  vampire   = {'hit1',       0.40, 0.55},
  boomerang = {'ui_switch1', 0.50, 1.25},
  twincast  = {'level_up1',  0.35, 1.30},
  tesla     = {'level_up1',  0.35, 1.55},
  terrorist = {'hit1',       0.45, 0.85},
  cannon    = {'mine1',      0.55, 0.50},
}

local function play_equip_sfx(sig)
  local e   = EQUIP_SFX[sig] or EQUIP_SFX.none
  local snd = _G[e[1]]
  if snd then snd:play{volume = e[2], pitch = e[3]} end
end


-- One carousel card: a backglass tile carrying the loadout's REAL paddle body
-- (Paddle.draw_preview), its name and its ownership state.
function BallPit:draw_shop_card(i, id, def, x, s, alpha, focused, now)
  local w, h = CARO_W*s, CARO_H*s
  local col  = _G[def.color_key][0]
  local owned    = state.paddles_owned[id] == true
  local equipped = (state.selected_paddle == id)

  local edge = Color(1, 1, 1, 0.16*alpha)
  if equipped   then edge = Color(yellow[0].r, yellow[0].g, yellow[0].b, alpha)
  elseif owned  then edge = Color(green[0].r,  green[0].g,  green[0].b,  alpha) end

  -- Focused card gets a colour wash + a breathing lamp glow behind it.
  if focused then
    local p = 0.5 + 0.5*math.sin(now*3)
    graphics.rectangle(x, CARO_CY, w + 12, h + 12, 8, 8,
                       Color(col.r, col.g, col.b, 0.07 + 0.05*p))
  end
  graphics.rectangle(x, CARO_CY, w, h, 5, 5, Color(bg[-1].r, bg[-1].g, bg[-1].b, alpha))
  graphics.rectangle(x, CARO_CY - h/2 + 2, w - 10, 1, nil, nil, Color(1, 1, 1, 0.10*alpha))
  graphics.rectangle(x, CARO_CY, w, h, 5, 5, edge, focused and 2 or 1)

  -- Just-bought celebration: a ring popping off the card.
  if self.shop_bought_i == i and self.shop_bought_t and (now - self.shop_bought_t) < 0.55 then
    local k = (now - self.shop_bought_t)/0.55
    graphics.rectangle(x, CARO_CY, w + 34*k, h + 34*k, 8, 8,
                       Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.8*(1 - k)), 2)
  end

  -- The paddle itself, on a lit "playfield" strip so it looks mounted.
  local py = CARO_CY - 22*s
  graphics.rectangle(x, py + 12*s, w - 22*s, 1, nil, nil, Color(col.r, col.g, col.b, 0.30*alpha))
  -- Scaled with the card so a neighbour's paddle shrinks with its tile
  -- (draw_preview always paints at true in-game width).
  graphics.push(x, py, 0, s, s)
  Paddle.draw_preview(id, def, x, py)
  graphics.pop()

  -- The title now scales WITH the card. It used to be drawn at a flat 0.9 on
  -- shrunken neighbours, so the longest names hung over their tile's edges.
  -- 0.8 keeps the widest ('Pinball Lobber', 159px) inside the 176px focus card.
  local ns = 0.8*(focused and 1 or s)
  graphics.print_centered(def.name, fat_font, x, CARO_CY + 22*s, 0, ns, ns, 0, 0,
                          Color(fg[0].r, fg[0].g, fg[0].b, alpha))

  -- Ownership line. Locked cards wear the NEXT unlock's positional price.
  -- Drawn at the card's own scale (so 1.0 on the focus card, where the brush
  -- lands on the pixel grid it was cut for). 'EQUIPPED' is 73px inside a 176px
  -- focus tile, and the ink bottom sits 11px clear of the tile's edge.
  local ly = CARO_CY + h/2 - 14*s
  if equipped then
    graphics.print_centered('EQUIPPED', pixul_mono_font, x, ly, 0, s, s, 0, 0,
                            Color(yellow[0].r, yellow[0].g, yellow[0].b, alpha))
  elseif owned then
    graphics.print_centered('OWNED', pixul_mono_font, x, ly, 0, s, s, 0, 0,
                            Color(green[0].r, green[0].g, green[0].b, alpha))
  else
    local price  = PADDLES.next_price()
    local afford = (state.wallet or 0) >= price
    local pc = afford and yellow[0] or red[0]
    -- A padlock, then the price, so a locked card reads as locked at any scale.
    -- The lock backs off to -22 and the price to +4: at native width a 4-digit
    -- price is 37px wide and would otherwise sit on the shackle.
    graphics.rectangle(x - 22*s, ly, 6*s, 5*s, 1, 1, Color(pc.r, pc.g, pc.b, alpha))
    graphics.arc('open', x - 22*s, ly - 2.5*s, 2.6*s, math.pi, 2*math.pi,
                 Color(pc.r, pc.g, pc.b, alpha), 1)
    graphics.print_centered(tostring(price), pixul_mono_font, x + 4*s, ly,
                            0, s, s, 0, 0, Color(pc.r, pc.g, pc.b, alpha))
  end
end


-- ---------------------------------------------------------------------------
-- UPDATE
-- ---------------------------------------------------------------------------

function BallPit:update_shop(dt)
  PADDLES.ensure_state()
  self.go_screen     = self.go_screen or 'over'
  self.shop_selected = self.shop_selected or 1
  self.shop_scroll   = self.shop_scroll or self.shop_selected

  -- A transition is running: the page underneath is mid-move and is about to
  -- be swapped, so taking input now would stack a second switch on the first.
  if self.gate then return end

  -- Run report screen: RESTART / SHOP buttons (mouse hover + click, or
  -- up/down + enter).
  if self.go_screen == 'over' then
    self.go_selected = self.go_selected or 1
    local hovered = nil
    for i = 1, #GO_BUTTONS do
      local bx, by = go_button_pos(i)
      if math.abs(mouse.x - bx) <= GO_BTN_W/2 and math.abs(mouse.y - by) <= GO_BTN_H/2 then hovered = i end
    end
    if hovered and hovered ~= self.go_selected then
      self.go_selected = hovered
      ui_switch1:play{volume = 0.25}
    end
    if input.move_up.pressed or input.aim_left.pressed then
      self.go_selected = math.max(1, self.go_selected - 1)
      ui_switch1:play{volume = 0.3}
    end
    if input.move_down.pressed or input.aim_right.pressed then
      self.go_selected = math.min(#GO_BUTTONS, self.go_selected + 1)
      ui_switch1:play{volume = 0.3}
    end
    if (hovered and input.click.pressed) or input.confirm.pressed then
      -- Both routes go through the gate, which owns the sound, the screen
      -- swap and (for a restart) the reset itself.
      self:begin_page_gate(GO_BUTTONS[self.go_selected].id == 'restart'
                           and 'restart' or 'shop')
    end
    return
  end

  -- ---- shop page ----
  local n = #PADDLES.order

  -- The carousel glides toward the selection instead of cutting to it.
  self.shop_scroll = math.lerp_dt(0.0002, dt, self.shop_scroll, self.shop_selected)
  if math.abs(self.shop_scroll - self.shop_selected) < 0.001 then
    self.shop_scroll = self.shop_selected
  end

  local function step(d)
    local nx = math.clamp(self.shop_selected + d, 1, n)
    if nx ~= self.shop_selected then
      self.shop_selected = nx
      ui_switch1:play{volume = 0.3}
    end
  end

  -- EXIT drop target (top-left) returns to the run report. Eat the click so it
  -- can't also land on whatever is underneath.
  local ex, ey, ew, eh = shop_back_rect()
  if input.click.pressed
  and math.abs(mouse.x - ex) <= ew/2 and math.abs(mouse.y - ey) <= eh/2 then
    self:begin_page_gate('over')
    input.click.pressed = false
    return
  end

  -- Nav bumpers.
  if input.click.pressed then
    for _, dir in ipairs{-1, 1} do
      local ax, ay = caro_arrow_pos(dir)
      if math.distance(mouse.x, mouse.y, ax, ay) <= 20 then
        step(dir)
        input.click.pressed = false
        return
      end
    end
  end

  -- BUY / EQUIP drop target.
  if input.click.pressed
  and math.abs(mouse.x - gw/2) <= 130 and math.abs(mouse.y - SHOP_ACT_CY) <= 18 then
    self:shop_activate(self.shop_selected)
    input.click.pressed = false
    return
  end

  -- Cards: clicking a neighbour scrolls to it, clicking the focus buys/equips.
  local hit = self:shop_caro_hit()
  if hit and input.click.pressed then
    if hit == self.shop_selected then
      self:shop_activate(self.shop_selected)
    else
      self.shop_selected = hit
      ui_switch1:play{volume = 0.3}
    end
    input.click.pressed = false
    return
  end

  -- Keyboard: left/right (or A/D) spin the carousel, Enter buys/equips.
  if input.aim_left.pressed  or input.move_left.pressed  then step(-1) end
  if input.aim_right.pressed or input.move_right.pressed then step(1)  end
  if input.confirm.pressed then self:shop_activate(self.shop_selected) end
end


-- Buy (if affordable) or equip (if owned) the i-th paddle.
function BallPit:shop_activate(i)
  PADDLES.ensure_state()
  local id = PADDLES.order[i]
  if not id then return end

  local sig = PADDLES.get(id).signature or 'none'

  if state.paddles_owned[id] then
    if state.selected_paddle ~= id then
      state.selected_paddle = id
      system.save_state()
      -- This loadout's own confirm + its own animation over the card.
      play_equip_sfx(sig)
      self.shop_equip_i = i
      self.shop_equip_t = love.timer.getTime()
    end
  elseif state.wallet >= PADDLES.next_price() then
    state.wallet = state.wallet - PADDLES.next_price()
    state.paddles_owned[id] = true
    state.selected_paddle = id
    system.save_state()
    -- A purchase equips too, so it gets the buy chime AND the equip flourish.
    confirm1:play{volume = 0.45, pitch = 1.1}
    play_equip_sfx(sig)
    self.shop_bought_i = i
    self.shop_bought_t = love.timer.getTime()
    self.shop_equip_i  = i
    self.shop_equip_t  = self.shop_bought_t
  else
    -- Can't afford it. A pinball machine has a word for this.
    hit1:play{volume = 0.3, pitch = 0.7}
    self.shop_denied_t = love.timer.getTime()
  end
end


-- ---------------------------------------------------------------------------
-- PAGE TRANSITIONS
-- ---------------------------------------------------------------------------
-- One mechanism serves all three moves, because the cabinet already has the
-- part for it: a ball GATE. A pair of steel shutters slams shut across the
-- screen, everything that has to change happens in the single frame while
-- they are closed, and then they part again.
--
-- Underneath, the page you are leaving slides the way you are travelling and
-- the page you arrive at comes in from the opposite edge, so "deeper into the
-- machine" and "back out of it" read as opposite moves instead of the same cut
-- played twice:
--
--   'shop'     report -> shop    travelling DOWN into the cabinet
--   'over'     shop   -> report  travelling back UP
--   'restart'  either -> a fresh run: the page is launched out and the
--              shutters part onto live play
local GATE_CLOSE = 0.24
local GATE_OPEN  = 0.30
local GATE_SLIDE = 54     -- how far a page travels while it is covered


-- Start a transition. Ignored if one is already running, so a mashed key can't
-- stack two switches (or fire reset_run twice).
function BallPit:begin_page_gate(kind)
  if self.gate then return end
  self.gate = {kind = kind, phase = 'close', t = 0}
  mine1:play{volume = 0.5, pitch = 0.8}
end


-- Drive the gate. Called from BallPit:update every frame, NOT from update_shop:
-- a 'restart' has to keep animating after game_over has already been cleared
-- and the shop's update has stopped running.
function BallPit:tick_page_gate(dt)
  local g = self.gate
  if not g then return end
  g.t = g.t + dt

  if g.phase == 'close' then
    if g.t < GATE_CLOSE then return end
    -- Fully covered. This is the only frame anything is allowed to change.
    -- The open phase restarts its clock at zero rather than carrying the
    -- overshoot: carrying it meant the shutters had already parted by up to a
    -- frame's worth (~16% of the screen) on the very frame the page swapped,
    -- so you could catch the swap through the gap.
    g.phase, g.t = 'open', 0
    if g.kind == 'restart' then
      self:reset_run()
      spawn1:play{volume = 0.45}
    else
      self.go_screen = g.kind
      if g.kind == 'shop' then
        -- Open the carousel already focused on what is equipped.
        PADDLES.ensure_state()
        for i, pid in ipairs(PADDLES.order) do
          if pid == state.selected_paddle then self.shop_selected = i end
        end
        self.shop_scroll = self.shop_selected
      end
      confirm1:play{volume = 0.28, pitch = (g.kind == 'shop') and 1.1 or 0.9}
    end
    camera:shake(2, 0.14, 90)
  elseif g.t >= GATE_OPEN then
    self.gate = nil
  end
end


-- How far the shutters have travelled: 0 wide open, 1 fully closed.
function BallPit:page_gate_cover()
  local g = self.gate
  if not g then return 0 end
  if g.phase == 'close' then
    local p = math.clamp(g.t/GATE_CLOSE, 0, 1)
    return p*p                     -- accelerates into the slam
  end
  return (1 - math.clamp(g.t/GATE_OPEN, 0, 1))^3   -- springs apart, eases to rest
end


-- Vertical offset for whichever page is on screen. The slide is always smaller
-- than what the shutters have already hidden (54*p^2 against the 328*p each
-- shutter covers), so a travelling page can never show a bare edge.
function BallPit:page_slide()
  local g = self.gate
  if not g then return 0 end
  local down = (g.kind == 'over')          -- coming back out travels down-screen
  if g.phase == 'close' then
    local p = math.clamp(g.t/GATE_CLOSE, 0, 1)
    return (down and 1 or -1)*GATE_SLIDE*p*p
  end
  local p = math.clamp(g.t/GATE_OPEN, 0, 1)
  return (down and -1 or 1)*GATE_SLIDE*(1 - p)^3
end


-- The shutters themselves, drawn over EVERYTHING -- including live play, which
-- is what a restart parts them onto.
function BallPit:draw_page_gate()
  local c = self:page_gate_cover()
  if c <= 0.001 then return end
  local half = gh/2
  local d    = half*c                      -- how far each shutter has come in
  local now  = love.timer.getTime()

  -- One steel panel per side. `edge` is its leading lip, `dir` which way the
  -- lip faces, so the same code draws both.
  local function shutter(cy, edge, dir)
    graphics.rectangle(gw/2, cy, gw, half, nil, nil, bg[-2])
    graphics.rectangle(gw/2, cy, gw - 26, half - 18, 4, 4, Color(1, 1, 1, 0.03))
    for x = 26, gw - 26, 34 do
      graphics.circle(x, edge - dir*9, 1.6, Color(1, 1, 1, 0.10))   -- rivet row
    end
    graphics.rectangle(gw/2, edge - dir*1.5, gw, 3, nil, nil, Color(1, 1, 1, 0.13))
    graphics.rectangle(gw/2, edge + dir*4,   gw, 8, nil, nil, Color(0, 0, 0, 0.35))
  end
  shutter(d - half/2,      d,      1)
  shutter(gh - d + half/2, gh - d, -1)

  -- Nearly shut: a seam lamp strip along the join, coloured by where you are
  -- headed. Deliberately a thin strip and not a screen flash.
  if c > 0.86 then
    local k   = (c - 0.86)/0.14
    local col = (self.gate.kind == 'restart') and green[0]
             or ((self.gate.kind == 'shop') and yellow[0] or fg_alt[0])
    graphics.rectangle(gw/2, half, gw, 2, nil, nil, Color(col.r, col.g, col.b, 0.5*k))
    for i = 0, 13 do
      graphics.circle(18 + i*34, half, 2.2,
                      Color(col.r, col.g, col.b,
                            0.45*k*(0.4 + 0.6*math.abs(math.sin(now*6 + i)))))
    end
  end
end


-- ---------------------------------------------------------------------------
-- DRAW
-- ---------------------------------------------------------------------------

-- Replaces the original plain game-over overlay (this file is required after
-- ballpit.lua, so this definition wins). Routes between the run report and
-- the paddle shop.
function BallPit:draw_game_over()
  PADDLES.ensure_state()
  -- Whichever page is up rides the transition offset; the shutters (drawn
  -- later, in BallPit:draw) hide the edge it exposes.
  local dy = self:page_slide()
  if dy ~= 0 then graphics.push(0, 0, 0, 1, 1); graphics.translate(0, dy) end
  if self.go_screen == 'shop' then
    self:draw_shop_screen()
  else
    self:draw_game_over_screen()
  end
  if dy ~= 0 then graphics.pop() end
end


-- The run report. Same cabinet as the shop -- solid page, bezel, header board,
-- reel, drop targets, flippers -- so moving between the two feels like one
-- machine changing what it is showing. It is arranged as a machine that has
-- just ENDED a game rather than one attracting play, which is what keeps it
-- from being the shop with different words: the header board is dark with a
-- single lamp still walking its frame, the reel is front and centre and counts
-- the final SCORE instead of credits, the stats read as playfield inserts down
-- one panel, and the only lit things left are the two drop targets.
function BallPit:draw_game_over_screen()
  local now  = love.timer.getTime()
  local pdef = self.paddle_def or PADDLES.get(state.selected_paddle)
  local pcol = _G[pdef.color_key][0]

  -- ---- 1. the page ----
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, bg[0])
  -- Same backboard sheen as the shop, drifting the other way and dimmer.
  for i = -6, 20 do
    local x = i*36 - (now*5 % 36)
    graphics.line(x, 0, x - 90, gh, Color(1, 1, 1, 0.010), 6)
  end
  -- Powered-down vignette: nested rims, so the cabinet reads as dark at the
  -- edges with only the board and the targets alight.
  for i = 1, 5 do
    graphics.rectangle(gw/2, gh/2, gw - i*4, gh - i*4, 8, 8, Color(0, 0, 0, 0.10), 3)
  end
  graphics.rectangle(gw/2, gh/2, gw - 12, gh - 12, 8, 8, Color(1, 1, 1, 0.05), 2)
  graphics.rectangle(gw/2, gh/2, gw - 18, gh - 18, 6, 6, Color(0, 0, 0, 0.35), 1)

  -- ---- 2. dead header board ----
  -- Same footprint as the shop's marquee so the two pages line up through a
  -- transition, but unlit: one lamp still crawls the frame, the way a real
  -- cabinet idles between games.
  cab_panel(gw/2, SHOP_MARQUEE_CY, SHOP_MARQUEE_W, SHOP_MARQUEE_H, 6,
            bg[-1], Color(red[0].r, red[0].g, red[0].b, 0.35))
  local mx0, mx1 = gw/2 - SHOP_MARQUEE_W/2, gw/2 + SHOP_MARQUEE_W/2
  local my0, my1 = SHOP_MARQUEE_CY - SHOP_MARQUEE_H/2, SHOP_MARQUEE_CY + SHOP_MARQUEE_H/2
  local ring = {}
  for x = mx0 + 10, mx1 - 10,  21 do ring[#ring + 1] = {x, my0 + 6} end
  for y = my0 + 20, my1 - 20,  18 do ring[#ring + 1] = {mx1 - 8, y} end
  for x = mx1 - 10, mx0 + 10, -21 do ring[#ring + 1] = {x, my1 - 6} end
  for y = my1 - 20, my0 + 20, -18 do ring[#ring + 1] = {mx0 + 8, y} end
  local walker = math.floor(now*9) % #ring + 1
  for i, p in ipairs(ring) do cab_bulb(p[1], p[2], i == walker, red[0]) end

  local pulse = 0.5 + 0.5*math.sin(now*1.6)
  graphics.print_centered('GAME OVER', fat_font, gw/2, SHOP_MARQUEE_CY + 11, 0, 1.45, 1.45,
                          0, 0, Color(red[0].r, red[0].g*(0.55 + 0.3*pulse),
                                      red[0].b*(0.55 + 0.3*pulse), 1))

  -- ---- 3. final score on the reel ----
  graphics.print_centered('FINAL SCORE', pixul_mono_font, gw/2, 96, 0, 1, 1, 0, 0, fg_alt[0])
  cab_reel(gw/2, 122, self.score or 0, 7, red[0])
  graphics.print_centered('the swarm broke through on wave ' .. self.wave,
                          pixul_mono_font, gw/2, 152, 0, 1, 1, 0, 0, fg_alt[0])
  cab_rail(24, gw - 24, 172, red[0])

  -- ---- 4. scoreboard ----
  -- Height is the five rows plus the two footer lines, not a round number:
  -- sized any taller and the panel ends in a band of dead space.
  local pw, ph, pcy = 340, 214, 300
  cab_panel(gw/2, pcy, pw, ph, 6, bg[-1], Color(red[0].r, red[0].g, red[0].b, 0.28))
  local px0 = gw/2 - pw/2
  local rt  = self.run_time or 0
  local rows = {
    {'WAVE REACHED',  tostring(self.wave)},
    {'SCORE',         tostring(self.score)},
    {'BLOCKS BROKEN', tostring(self.run_kills or 0)},
    {'HERO LEVEL',    tostring(self.level or 1)},
    {'TIME ON TABLE', string.format('%d:%02d', math.floor(rt/60), math.floor(rt % 60))},
  }
  local ry = pcy - ph/2 + 22
  for _, r in ipairs(rows) do
    -- Each row is a playfield insert: lamp, label, dotted lane, value.
    graphics.circle(px0 + 16, ry + 3, 2.2, Color(red[0].r, red[0].g, red[0].b, 0.55))
    graphics.print(r[1], pixul_mono_font, px0 + 26, ry, 0, 1, 1, 0, 0, fg_alt[0])
    local vw  = pixul_mono_font:get_text_width(r[2])
    local lx0 = px0 + 30 + pixul_mono_font:get_text_width(r[1])
    graphics.print(r[2], pixul_mono_font, px0 + pw - 18 - vw, ry, 0, 1, 1, 0, 0, fg[0])
    graphics.dashed_line(lx0, ry + 6, px0 + pw - 22 - vw, ry + 6, 2, 3, Color(1, 1, 1, 0.10), 1)
    ry = ry + 26
  end

  -- Footer: what the run banked (literally the shop's currency) and what you
  -- ran it with, so the SHOP target below has an obvious reason to exist.
  graphics.line(px0 + 14, ry + 2, px0 + pw - 14, ry + 2, Color(1, 1, 1, 0.12), 1)
  local earned = '+' .. (self.run_kills or 0) .. ' BLOCKS'
  local ew     = pixul_mono_font:get_text_width(earned)
  graphics.print('BANKED', pixul_mono_font, px0 + 26, ry + 14, 0, 1, 1, 0, 0, fg_alt[0])
  graphics.print(earned, pixul_mono_font, px0 + pw - 18 - ew, ry + 14, 0, 1, 1, 0, 0, yellow[0])

  graphics.print('YOU RAN', pixul_mono_font, px0 + 26, ry + 36, 0, 1, 1, 0, 0, fg_alt[0])
  Paddle.draw_preview(pdef.id, pdef, px0 + 140, ry + 40)
  local nw = fat_font:get_text_width(pdef.name)*0.62
  graphics.print(pdef.name, fat_font, px0 + pw - 18 - nw, ry + 28, 0, 0.62, 0.62, 0, 0, pcol)

  cab_rail(24, gw - 24, 452, red[0])

  -- ---- 5. drop targets ----
  -- Same hardware as the shop's EXIT / BUY tabs, so the two pages share one
  -- interaction language even though they share no layout.
  for i, b in ipairs(GO_BUTTONS) do
    local bx, by = go_button_pos(i)
    local hot = math.abs(mouse.x - bx) <= GO_BTN_W/2
            and math.abs(mouse.y - by) <= GO_BTN_H/2
    cab_target(bx, by, GO_BTN_W, GO_BTN_H, b.label,
               (i == 1) and green[0] or yellow[0],
               hot or (self.go_selected or 1) == i)
  end

  -- The page ends on the drop targets. The idling flippers and the control
  -- hint that used to sit under them are gone (they read as clutter once the
  -- targets were the obvious thing to press), so the bottom strip is left as
  -- bare playfield -- matching the shop, which lost the same pair.
end


-- The shop page. Opaque, full-bleed, and dressed as a pinball cabinet.
function BallPit:draw_shop_screen()
  local now    = love.timer.getTime()
  local sel_id = PADDLES.order[self.shop_selected or 1]
  local sel    = PADDLES.get(sel_id)
  local scol   = _G[sel.color_key][0]
  local owned    = state.paddles_owned[sel_id] == true
  local equipped = (state.selected_paddle == sel_id)
  local price    = PADDLES.next_price()
  local afford   = (state.wallet or 0) >= price
  local denied   = self.shop_denied_t and (now - self.shop_denied_t) < 0.6

  -- ---- 1. the page itself: SOLID, not an overlay ----
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, bg[0])
  -- Cabinet backboard: a slow diagonal sheen plus faint playfield lamp inserts,
  -- so the solid fill still has some depth to it.
  for i = -6, 20 do
    local x = i*36 + (now*7 % 36)
    graphics.line(x, 0, x - 90, gh, Color(1, 1, 1, 0.012), 6)
  end
  graphics.rectangle(gw/2, gh/2, gw - 12, gh - 12, 8, 8, Color(1, 1, 1, 0.06), 2)
  graphics.rectangle(gw/2, gh/2, gw - 18, gh - 18, 6, 6, Color(0, 0, 0, 0.35), 1)

  -- ---- 2. marquee ----
  cab_panel(gw/2, SHOP_MARQUEE_CY, SHOP_MARQUEE_W, SHOP_MARQUEE_H, 6,
            bg[-1], Color(scol.r, scol.g, scol.b, 0.5))
  local chase = math.floor(now*7)
  local mx0, mx1 = gw/2 - SHOP_MARQUEE_W/2, gw/2 + SHOP_MARQUEE_W/2
  local my0, my1 = SHOP_MARQUEE_CY - SHOP_MARQUEE_H/2, SHOP_MARQUEE_CY + SHOP_MARQUEE_H/2
  local b = 0
  for x = mx0 + 10, mx1 - 10, 21 do
    cab_bulb(x, my0 + 6, (b + chase) % 3 == 0, yellow[0])
    cab_bulb(x, my1 - 6, (b + chase + 1) % 3 == 0, yellow[0])
    b = b + 1
  end
  for y = my0 + 20, my1 - 20, 18 do
    cab_bulb(mx0 + 8, y, (b + chase) % 3 == 0, yellow[0]); b = b + 1
    cab_bulb(mx1 - 8, y, (b + chase) % 3 == 0, yellow[0])
  end
  -- fat_font ink runs y-17s .. y+2s through print_centered, so the draw y that
  -- puts the ink's CENTRE on the marquee's centre line is cy + 7.5s. At the old
  -- cy - 6 the top of the lettering ran straight through the upper bulb row.
  graphics.print_centered('PADDLE EXCHANGE', fat_font, gw/2, SHOP_MARQUEE_CY + 11,
                          0, 1.45, 1.45, 0, 0, yellow[0])


  -- ---- 3. credit reel + EXIT ----
  local ex, ey, ew, eh = shop_back_rect()
  local exit_hot = math.abs(mouse.x - ex) <= ew/2 and math.abs(mouse.y - ey) <= eh/2
  cab_target(ex, ey, ew, eh, 'EXIT', red[0], exit_hot)

  -- Right up against the reel (its first digit window starts at x = 330) so the
  -- label reads as belonging to the number instead of floating away from it:
  -- at native width 'CREDITS' is 64px, so its last ink column lands on 324.
  graphics.print('CREDITS', pixul_mono_font, 262, SHOP_CREDIT_CY - 6, 0, 1, 1, 0, 0, fg_alt[0])
  cab_reel(376, SHOP_CREDIT_CY, state.wallet or 0, 5, denied and red[0] or yellow[0])
  if denied then
    -- Every pinball machine's way of saying no.
    graphics.print_centered('TILT', fat_font, 168, SHOP_CREDIT_CY, 0, 1.2, 1.2, 0, 0,
                            Color(red[0].r, red[0].g, red[0].b, 0.5 + 0.5*math.sin(now*26)))
  end

  -- ---- 4. carousel ----
  cab_rail(24, gw - 24, 136, scol)
  cab_rail(24, gw - 24, 318, scol)

  local scroll = self.shop_scroll or 1
  local order  = {}
  for i = 1, #PADDLES.order do
    local d = i - scroll
    if math.abs(d) <= 2.4 then order[#order + 1] = {i = i, d = d} end
  end
  -- Farthest first so the focus card lands on top.
  table.sort(order, function(p, q) return math.abs(p.d) > math.abs(q.d) end)
  for _, e in ipairs(order) do
    local x, s, a = caro_slot(e.d)
    local id = PADDLES.order[e.i]
    self:draw_shop_card(e.i, id, PADDLES.get(id), x, s, a, e.i == self.shop_selected, now)
  end

  -- This loadout's equip flourish, over the card it belongs to. Scroll away
  -- mid-animation and it simply stops -- it is a confirmation of THIS card.
  if self.shop_equip_t then
    local ep = (now - self.shop_equip_t)/EQUIP_FX_TIME
    if ep >= 1 then
      self.shop_equip_t = nil
    elseif self.shop_equip_i == self.shop_selected then
      local fx = EQUIP_FX[sel.signature or 'none'] or EQUIP_FX.none
      fx(gw/2, CARO_CY, CARO_W, CARO_H, ep, scol)
    end
  end

  -- Nav bumpers, dimmed at the ends of the rack.
  for _, dir in ipairs{-1, 1} do
    local ax, ay = caro_arrow_pos(dir)
    local live = (dir < 0) and (self.shop_selected > 1)
                            or (self.shop_selected < #PADDLES.order)
    local hot  = live and math.distance(mouse.x, mouse.y, ax, ay) <= 20
    cab_bumper(ax, ay, 17, live and scol or bg[2], now, dir, hot)
  end

  -- Position lamps: one insert per loadout, lit through the current pick.
  local n  = #PADDLES.order
  local lw = (n - 1)*14
  for i = 1, n do
    local lx = gw/2 - lw/2 + (i - 1)*14
    local on = (i == self.shop_selected)
    graphics.circle(lx, 334, on and 3.4 or 2, on and scol or Color(1, 1, 1, 0.18))
    if on then graphics.circle(lx, 334, 5.6, Color(scol.r, scol.g, scol.b, 0.28)) end
  end

  -- ---- 5. spec panel ----
  cab_panel(gw/2, SHOP_PANEL_CY, SHOP_PANEL_W, SHOP_PANEL_H, 6,
            bg[-1], Color(scol.r, scol.g, scol.b, 0.35))
  local px0 = gw/2 - SHOP_PANEL_W/2

  graphics.print(sel.name, fat_font, px0 + 16, 364, 0, 0.95, 0.95, 0, 0, scol)
  local chip, ccol = nil, fg[0]
  if equipped then chip, ccol = 'EQUIPPED', yellow[0]
  elseif owned then chip, ccol = 'OWNED', green[0]
  else chip, ccol = 'LOCKED', afford and yellow[0] or red[0] end
  -- 'EQUIPPED' is 73px at native width, so the chip is 87 wide and still sits
  -- 16px inside the panel. Ink is 9 tall in a 15px chip: y = 372 centres it.
  local chw = pixul_mono_font:get_text_width(chip) + 14
  graphics.rectangle(px0 + SHOP_PANEL_W - 16 - chw/2, 370, chw, 15, 3, 3,
                     Color(ccol.r, ccol.g, ccol.b, 0.18))
  graphics.rectangle(px0 + SHOP_PANEL_W - 16 - chw/2, 370, chw, 15, 3, 3,
                     Color(ccol.r, ccol.g, ccol.b, 0.7), 1)
  graphics.print_centered(chip, pixul_mono_font, px0 + SHOP_PANEL_W - 16 - chw/2, 372,
                          0, 1, 1, 0, 0, ccol)

  -- Two lines for the longest blurb even at native width; at this pitch line
  -- 2's ink ends at 409, clear of the rule at 414.
  local by = 388
  for _, line in ipairs(wrap_text(sel.blurb, pixul_mono_font, 1, SHOP_PANEL_W - 34)) do
    graphics.print(line, pixul_mono_font, px0 + 16, by, 0, 1, 1, 0, 0, fg[0])
    by = by + 12
  end
  graphics.line(px0 + 14, 414, px0 + SHOP_PANEL_W - 14, 414, Color(1, 1, 1, 0.12), 1)

  local hovered = self:shop_radar_hover()
  self:draw_stat_radar(sel, scol, hovered)

  -- Right column: signature, hull, starting balls.
  --
  -- FLOWED, not pinned. At native width the longest signature line (Aegis)
  -- wraps to four rather than three, which used to drive it straight through
  -- the HULL label below. Each block is now placed under the measured bottom
  -- of the one above it, with the old fixed positions as the floor -- so the
  -- short loadouts look exactly as they did and the long one still fits (its
  -- worst case ends 7px inside the panel).
  local tx = 198
  local LP = 11                                   -- line pitch (9px ink + 2)
  graphics.print('SIGNATURE', pixul_mono_font, tx, 422, 0, 1, 1, 0, 0, fg_alt[0])
  local sy, sn = 434, 0
  for _, line in ipairs(wrap_text(sel.sig_blurb, pixul_mono_font, 1, 246)) do
    graphics.print(line, pixul_mono_font, tx, sy + sn*LP, 0, 1, 1, 0, 0, fg[0])
    sn = sn + 1
  end

  local hully = math.max(474, sy + (sn - 1)*LP + 9 + 6)
  graphics.print('HULL', pixul_mono_font, tx, hully, 0, 1, 1, 0, 0, fg_alt[0])
  if sel.hp_mode == 'bar' then
    -- The Vampire runs a draining blood bar instead of discrete hearts.
    graphics.rectangle(tx + 66, hully + 4, 62, 7, 3, 3, Color(0, 0, 0, 0.6))
    graphics.rectangle(tx + 66, hully + 4, 60, 5, 2, 2, Color(0.55, 0.03, 0.06, 1))
    graphics.print('DRAINS', pixul_mono_font, tx + 104, hully, 0, 1, 1, 0, 0, red[0])
  else
    -- The loadout's OWN life glyph, the one the HUD will draw all run (bulbs,
    -- cells, honeycomb, capacitors...), not a generic red heart.
    local sig = sel.signature or 'none'
    local now2 = love.timer.getTime()
    for i = 1, (sel.hp or 5) do
      life_glyph(sig, tx + 42 + (i - 1)*12, hully + 4.5, i, now2, sel.hp or 5)
    end
  end

  graphics.print('STARTS WITH', pixul_mono_font, tx, hully + 22, 0, 1, 1, 0, 0, fg_alt[0])
  -- Collapse repeats into 'bomber x4'. Tesla and Terrorist both open with four
  -- of the same hero, and four separate rows ran off the bottom of the panel.
  local seen, uniq = {}, {}
  for _, c in ipairs(sel.start_balls) do
    if seen[c] then uniq[seen[c]].n = uniq[seen[c]].n + 1
    else uniq[#uniq + 1] = {c = c, n = 1}; seen[c] = #uniq end
  end
  local hy = hully + 36
  for _, e in ipairs(uniq) do
    local hc = (character_colors and character_colors[e.c]) or fg[0]
    graphics.circle(tx + 5, hy + 4, 3.5, hc)
    graphics.circle(tx + 4, hy + 3, 1.2, fg[5])
    graphics.print(e.n > 1 and (e.c .. ' x' .. e.n) or e.c, pixul_mono_font,
                   tx + 14, hy, 0, 1, 1, 0, 0, fg[0])
    hy = hy + 13
  end
  if sel.signature == 'twincast' then
    graphics.print('(mirrored pair)', pixul_mono_font, tx + 14, hy, 0, 1, 1, 0, 0, fg_alt[0])
  end

  -- ---- 6. action drop target ----
  local act_hot = math.abs(mouse.x - gw/2) <= 130 and math.abs(mouse.y - SHOP_ACT_CY) <= 18
  local label, acol, dim
  if equipped then
    label, acol, dim = 'EQUIPPED', green[0], true
  elseif owned then
    label, acol = 'EQUIP', yellow[0]
  else
    label, acol = 'INSERT ' .. price .. ' BLOCKS', afford and yellow[0] or red[0]
  end
  cab_target(gw/2, SHOP_ACT_CY, 260, 36, label, acol, act_hot and not dim, dim)

  -- ---- 7. tooltip, above everything ----
  -- (The idling flippers, the drain ball and the control-hint line that used
  -- to fill the strip below the BUY target are gone; the page ends on the
  -- target, and the run report ends the same way.)
  if hovered then self:draw_stat_tooltip(hovered, sel) end
end
