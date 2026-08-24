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
    blurb = 'Two long flippers with a central drain — balls fall, you flip them back up.',
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
    sig_blurb = 'E/click raises the shield; parries bank bulwark — a full meter turns the next raise gold',
  },
  mitosis = {
    id = 'mitosis', name = 'Mitosis', price = 500, color_key = 'green',
    size = 1.0, move = 1.0, ball = 1.0, charge = 0.9, aim = 1.0, dmg = 0.5,
    xp = 1.4, combo = 1.3, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'vagrant'},
    signature = 'mitosis', sig = {clone_life = 2.5, clone_cap = 10},
    blurb = 'Every kill makes a ball divide in two like a splitting cell.',
    sig_blurb = 'one daughter cell decays away; lost types regrow',
  },
  hive = {
    id = 'hive', name = 'Hive', price = 750, color_key = 'orange',
    size = 1.0, move = 1.0, ball = 0.8, charge = 0.7, aim = 0.8, dmg = 1.0,
    xp = 1.6, combo = 0.9, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'infestor', 'infestor', 'infestor'},
    signature = 'hive',
    sig = {contact_zero = true, maggot_cap = 24, maggot_dmg_mult = 0.8, maggot_speed = 85},
    blurb = 'Balls deal NO damage — maggots infest bricks with a spreading rot.',
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
           nova_radius = 80, nova_dmg = 26, orbit_pull = 2.4},
    blurb = 'Bonded twins orbit and FUSE into a nova supercast, then split.',
    sig_blurb = 'charge the binary; strongest right after a fusion',
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
    blurb = 'Press E to detonate balls near blocks — the blast is your real damage.',
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
  local effect = nil
  local ob = ball.stats and ball.stats.on_bounce
  if ob == 'burn' then effect = 'burn' elseif ob == 'slow' then effect = 'slow' end

  self.t:after(0, function()
    if not (self.main and self.main.world) then return end
    AllyCritter{group = self.main, x = x, y = y, color = color, source = 'maggot',
                speed = sig.maggot_speed or 85, dmg = dmg, effect = effect, infest = true}
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
          self:twincast_orbit(a, mx, my, pr.charge, pr.winding, pull, dt)
          self:twincast_orbit(b, mx, my, pr.charge, pr.winding, pull, dt)
          if pr.charge >= 1 then
            pr.state, pr.timer = 'fused', fuse_window
            pr.fuse_window = fuse_window
            pr.fx_x, pr.fx_y = mx, my
            a:set_position(mx, my);  b:set_position(mx, my)
            a:set_velocity(0, 0);    b:set_velocity(0, 0)
            a.spring:pull(0.6);      b.spring:pull(0.6)
            local lvl = a.level or 1
            local dmg = (sig.nova_dmg or 26)*(1 + BAL('signature.nova_level_growth', 0.5)*(lvl - 1))*((self.run_mods.dmg) or 1)
            self:twincast_fuse_blast(mx, my, sig.nova_radius or 80, dmg, pr.color or blue[0], pr.element)
          end
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
  {id = 'restart', label = 'RESTART'},
  {id = 'shop',    label = 'SHOP'},
}
local GO_BTN_W, GO_BTN_H = 160, 26

local function go_button_pos(i)
  return gw/2, gh/2 + 84 + (i - 1)*36
end

-- The EXIT drop target shares the credit-reel row: the marquee owns the whole
-- top strip now, so a top-left button would sit inside it.
local function shop_back_rect()
  return 50, SHOP_CREDIT_CY, 76, 24
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
    graphics.polygon({cx + dir*s, cy - s, cx + dir*s, cy + s, cx - dir*s*0.7, cy},
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
  graphics.print_centered(label, pixul_font, cx, cy + 1, 0, 1, 1, 0, 0, tcol)
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
    graphics.print_centered(s:sub(i, i), fat_font, x, cy - 1, 0, 1.05, 1.05, 0, 0, col)
    graphics.rectangle(x, cy, dw - 2, 0.6, nil, nil, Color(0, 0, 0, 0.55))   -- reel seam
  end
end


-- A flipper bat, pivoting at (px, py). side = -1 left / 1 right. Idles with an
-- occasional demo kick so the cabinet never looks dead.
local function cab_flipper(px, py, side, len, col, t)
  local kick = math.max(0, math.sin(t*1.1 + (side > 0 and 2.1 or 0)))^14
  local rest = 0.40 - kick*0.78
  local ang  = (side < 0) and rest or (math.pi - rest)
  local tx, ty = px + math.cos(ang)*len, py + math.sin(ang)*len
  local nx, ny = -math.sin(ang), math.cos(ang)
  graphics.polygon({px + nx*5,   py + ny*5,   px - nx*5,   py - ny*5,
                    tx - nx*2.6, ty - ny*2.6, tx + nx*2.6, ty + ny*2.6}, col)
  graphics.circle(px, py, 5, col)
  graphics.circle(tx, ty, 2.6, col)
  graphics.circle(px, py, 1.8, Color(0, 0, 0, 0.5))
end


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

  local w = pixul_font:get_text_width(txt)*0.9 + 16
  local h = 16
  local ix, iy = radar_axis_pos(i, RADAR_ICON_OUT)
  local tx = math.clamp(ix, w/2 + 4, gw - w/2 - 4)
  local ty = iy - 16
  if ty - h/2 < SHOP_PANEL_CY - SHOP_PANEL_H/2 then ty = iy + 16 end

  graphics.rectangle(tx, ty, w, h, 3, 3, Color(0, 0, 0, 0.92))
  graphics.rectangle(tx, ty, w, h, 3, 3, Color(1, 1, 1, 0.3), 1)
  -- Colour the value by whether it beats the baseline.
  local vcol = fg[0]
  if v > 1.001 then vcol = green[0] elseif v < 0.999 then vcol = red[0] end
  local lw = pixul_font:get_text_width(ax.label)*0.9
  graphics.print(ax.label, pixul_font, tx - w/2 + 8, ty - 5, 0, 0.9, 0.9, 0, 0, fg[0])
  graphics.print(val, pixul_font, tx - w/2 + 8 + lw + 8, ty - 5, 0, 0.9, 0.9, 0, 0, vcol)
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

  graphics.print_centered(def.name, focused and fat_font or pixul_font,
                          x, CARO_CY + 22*s, 0, focused and 0.85 or 0.9,
                          focused and 0.85 or 0.9, 0, 0,
                          Color(fg[0].r, fg[0].g, fg[0].b, alpha))

  -- Ownership line. Locked cards wear the NEXT unlock's positional price.
  local ly = CARO_CY + h/2 - 14*s
  if equipped then
    graphics.print_centered('EQUIPPED', pixul_font, x, ly, 0, s, s, 0, 0,
                            Color(yellow[0].r, yellow[0].g, yellow[0].b, alpha))
  elseif owned then
    graphics.print_centered('OWNED', pixul_font, x, ly, 0, s, s, 0, 0,
                            Color(green[0].r, green[0].g, green[0].b, alpha))
  else
    local price  = PADDLES.next_price()
    local afford = (state.wallet or 0) >= price
    local pc = afford and yellow[0] or red[0]
    -- A padlock, then the price, so a locked card reads as locked at any scale.
    graphics.rectangle(x - 20*s, ly, 6*s, 5*s, 1, 1, Color(pc.r, pc.g, pc.b, alpha))
    graphics.arc('open', x - 20*s, ly - 2.5*s, 2.6*s, math.pi, 2*math.pi,
                 Color(pc.r, pc.g, pc.b, alpha), 1)
    graphics.print_centered(tostring(price), pixul_font, x + 2*s, ly, 0, s, s, 0, 0,
                            Color(pc.r, pc.g, pc.b, alpha))
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
      local id = GO_BUTTONS[self.go_selected].id
      if id == 'restart' then
        confirm1:play{volume = 0.4}
        self:reset_run()
      else
        self.go_screen = 'shop'
        -- Open the carousel already focused on what you have equipped.
        for i, pid in ipairs(PADDLES.order) do
          if pid == state.selected_paddle then self.shop_selected = i end
        end
        self.shop_scroll = self.shop_selected
        ui_switch1:play{volume = 0.35}
      end
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
    self.go_screen = 'over'
    ui_switch1:play{volume = 0.3}
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

  if state.paddles_owned[id] then
    if state.selected_paddle ~= id then
      state.selected_paddle = id
      system.save_state()
      confirm1:play{volume = 0.4}
    end
  elseif state.wallet >= PADDLES.next_price() then
    state.wallet = state.wallet - PADDLES.next_price()
    state.paddles_owned[id] = true
    state.selected_paddle = id
    system.save_state()
    confirm1:play{volume = 0.45, pitch = 1.1}
    level_up1:play{volume = 0.3, pitch = 1.05}
    self.shop_bought_i = i
    self.shop_bought_t = love.timer.getTime()
  else
    -- Can't afford it. A pinball machine has a word for this.
    hit1:play{volume = 0.3, pitch = 0.7}
    self.shop_denied_t = love.timer.getTime()
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
  if self.go_screen == 'shop' then
    self:draw_shop_screen()
  else
    self:draw_game_over_screen()
  end
end


-- The run report: dark backdrop, ember-pulsing headline, a stats panel for
-- the run that just ended, and the RESTART / SHOP buttons.
function BallPit:draw_game_over_screen()
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0, 0, 0, 0.82))

  -- Headline with a slow ember pulse, over a thin accent rule.
  local now   = love.timer.getTime()
  local pulse = 0.5 + 0.5*math.sin(now*1.6)
  graphics.print_centered('GAME OVER', fat_font, gw/2, gh/2 - 150, 0, 1.5, 1.5, 0, 0,
                          Color(red[0].r, red[0].g*(0.6 + 0.3*pulse), red[0].b*(0.6 + 0.3*pulse), 1))
  graphics.rectangle(gw/2, gh/2 - 126, 200, 1, nil, nil, Color(red[0].r, red[0].g, red[0].b, 0.5))
  graphics.print_centered('the swarm broke through on wave ' .. self.wave,
                          pixul_font, gw/2, gh/2 - 112, 0, 0.95, 0.95, 0, 0, fg_alt[0])

  -- Run report panel: label column left, value column right.
  local pw, ph   = 260, 132
  local pcx, pcy = gw/2, gh/2 - 20
  cab_panel(pcx, pcy, pw, ph, 4)
  local rt   = self.run_time or 0
  local rows = {
    {'WAVE',          tostring(self.wave)},
    {'SCORE',         tostring(self.score)},
    {'KILLS',         tostring(self.run_kills or 0)},
    {'LEVEL',         tostring(self.level or 1)},
    {'TIME',          string.format('%d:%02d', math.floor(rt/60), math.floor(rt % 60))},
    {'BLOCKS EARNED', '+' .. (self.run_kills or 0)},
  }
  local ry = pcy - ph/2 + 14
  for i, r in ipairs(rows) do
    local vcol = (i == #rows) and yellow[0] or fg[0]
    graphics.print(r[1], pixul_font, pcx - pw/2 + 14, ry - 4, 0, 1, 1, 0, 0, fg_alt[0])
    local vw = pixul_font:get_text_width(r[2])
    graphics.print(r[2], pixul_font, pcx + pw/2 - 14 - vw, ry - 4, 0, 1, 1, 0, 0, vcol)
    ry = ry + 19
  end

  for i, b in ipairs(GO_BUTTONS) do
    local bx, by = go_button_pos(i)
    draw_menu_button(bx, by, GO_BTN_W, GO_BTN_H, b.label, (self.go_selected or 1) == i)
  end
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
  graphics.print_centered('PADDLE EXCHANGE', fat_font, gw/2, SHOP_MARQUEE_CY - 6,
                          0, 1.45, 1.45, 0, 0, yellow[0])
  graphics.print_centered('select your loadout', pixul_font, gw/2, SHOP_MARQUEE_CY + 16,
                          0, 0.9, 0.9, 0, 0, fg_alt[0])

  -- ---- 3. credit reel + EXIT ----
  local ex, ey, ew, eh = shop_back_rect()
  local exit_hot = math.abs(mouse.x - ex) <= ew/2 and math.abs(mouse.y - ey) <= eh/2
  cab_target(ex, ey, ew, eh, 'EXIT', red[0], exit_hot)

  graphics.print('CREDITS', pixul_font, 246, SHOP_CREDIT_CY - 6, 0, 0.85, 0.85, 0, 0, fg_alt[0])
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
  local chw = pixul_font:get_text_width(chip)*0.9 + 14
  graphics.rectangle(px0 + SHOP_PANEL_W - 16 - chw/2, 370, chw, 15, 3, 3,
                     Color(ccol.r, ccol.g, ccol.b, 0.18))
  graphics.rectangle(px0 + SHOP_PANEL_W - 16 - chw/2, 370, chw, 15, 3, 3,
                     Color(ccol.r, ccol.g, ccol.b, 0.7), 1)
  graphics.print_centered(chip, pixul_font, px0 + SHOP_PANEL_W - 16 - chw/2, 369,
                          0, 0.9, 0.9, 0, 0, ccol)

  local by = 390
  for _, line in ipairs(wrap_text(sel.blurb, pixul_font, 0.88, SHOP_PANEL_W - 34)) do
    graphics.print(line, pixul_font, px0 + 16, by, 0, 0.88, 0.88, 0, 0, fg[0])
    by = by + 12
  end
  graphics.line(px0 + 14, 414, px0 + SHOP_PANEL_W - 14, 414, Color(1, 1, 1, 0.12), 1)

  local hovered = self:shop_radar_hover()
  self:draw_stat_radar(sel, scol, hovered)

  -- Right column: signature, hull, starting balls.
  local tx = 198
  graphics.print('SIGNATURE', pixul_font, tx, 428, 0, 0.8, 0.8, 0, 0, fg_alt[0])
  local sy = 442
  for _, line in ipairs(wrap_text(sel.sig_blurb, pixul_font, 0.88, 250)) do
    graphics.print(line, pixul_font, tx, sy, 0, 0.88, 0.88, 0, 0, fg[0])
    sy = sy + 12
  end

  graphics.print('HULL', pixul_font, tx, 478, 0, 0.8, 0.8, 0, 0, fg_alt[0])
  if sel.hp_mode == 'bar' then
    -- The Vampire runs a draining blood bar instead of discrete hearts.
    graphics.rectangle(tx + 66, 482, 62, 7, 3, 3, Color(0, 0, 0, 0.6))
    graphics.rectangle(tx + 66, 482, 60, 5, 2, 2, Color(0.55, 0.03, 0.06, 1))
    graphics.print('DRAINS', pixul_font, tx + 102, 476, 0, 0.75, 0.75, 0, 0, red[0])
  else
    for i = 1, (sel.hp or 5) do
      heart_glyph(tx + 38 + (i - 1)*13, 482, 1.5, red[0])
    end
  end

  graphics.print('STARTS WITH', pixul_font, tx, 502, 0, 0.8, 0.8, 0, 0, fg_alt[0])
  local hy = 518
  for _, c in ipairs(sel.start_balls) do
    local hc = (character_colors and character_colors[c]) or fg[0]
    graphics.circle(tx + 5, hy + 3, 3.5, hc)
    graphics.circle(tx + 4, hy + 2, 1.2, fg[5])
    graphics.print(c, pixul_font, tx + 14, hy, 0, 0.88, 0.88, 0, 0, fg[0])
    hy = hy + 13
  end
  if sel.signature == 'twincast' then
    graphics.print('(mirrored pair)', pixul_font, tx + 14, hy, 0, 0.8, 0.8, 0, 0, fg_alt[0])
  end

  -- ---- 6. action drop target ----
  local act_hot = math.abs(mouse.x - gw/2) <= 130 and math.abs(mouse.y - SHOP_ACT_CY) <= 18
  local label, acol, dim
  if equipped then
    label, acol, dim = 'EQUIPPED', green[0], true
  elseif owned then
    label, acol = 'PRESS START TO EQUIP', yellow[0]
  else
    label, acol = 'INSERT ' .. price .. ' BLOCKS', afford and yellow[0] or red[0]
  end
  cab_target(gw/2, SHOP_ACT_CY, 260, 36, label, acol, act_hot and not dim, dim)

  -- ---- 7. flippers + hints ----
  graphics.print_centered('<  >  SELECT      ENTER  START      R  RESTART RUN',
                          pixul_font, gw/2, 616, 0, 0.8, 0.8, 0, 0, fg_alt[0])
  cab_flipper(140, 638, -1, 44, Color(1, 1, 1, 0.28), now)
  cab_flipper(340, 638,  1, 44, Color(1, 1, 1, 0.28), now)
  graphics.circle(240, 642, 4, Color(1, 1, 1, 0.35))
  graphics.circle(238.5, 640.5, 1.4, Color(1, 1, 1, 0.7))

  -- ---- 8. tooltip, above everything ----
  if hovered then self:draw_stat_tooltip(hovered, sel) end
end
