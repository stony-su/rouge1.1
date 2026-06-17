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
--     zaps, phantom blink, the cannon's falloff splash, aegis wall setup),
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
    signature = 'aegis', sig = {reflect_dmg = 20},
    blurb = 'The pit is closed: balls bounce off a bottom wall forever.',
    sig_blurb = 'parries bullets back; touching the paddle wipes a ball',
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
    id = 'tesla', name = 'Tesla', price = 4500, color_key = 'blue',
    size = 1.0, move = 1.0, ball = 0.8, charge = 0.8, aim = 0.9, dmg = 1.4,
    xp = 1.0, combo = 1.1, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'wizard', 'wizard', 'wizard', 'wizard'},
    signature = 'tesla', sig = {zap_dmg = 7, zap_width = 12, zap_cd = 0.25},
    blurb = 'Paddle bounces arc lightning between ALL live balls.',
    sig_blurb = 'damage scales with ball count',
  },
  terrorist = {
    id = 'terrorist', name = 'Terrorist', price = 6500, color_key = 'red',
    size = 1.0, move = 1.0, ball = 1.1, charge = 1.0, aim = 1.0, dmg = 1.6,
    xp = 1.0, combo = 1.0, hp = 3, hp_mode = 'hearts', xp_mode = 'flat',
    start_balls = {'bomber', 'bomber', 'bomber', 'bomber'},
    -- blast_radius: the detonation AoE (also the arm range — a ball blows on E
    -- when an enemy sits inside its blast reach). blast_mult: the blast's payoff
    -- (the build's whole damage). Both the radius and the damage SCALE with the
    -- run level (blast_*_per_level) so the blast keeps pace late-game; radius is
    -- capped at blast_radius_max. other_dmg_mult: every NON-blast damage source
    -- is gutted to this.
    signature = 'terrorist',
    sig = {blast_radius = 78, blast_radius_per_level = 0.05, blast_radius_max = 150,
           blast_mult = 5.0, blast_dmg_per_level = 0.18, other_dmg_mult = 0.2},
    blurb = 'Press E to detonate balls near blocks — the blast is your real damage.',
    sig_blurb = 'spent balls are gone; level-ups auto-arm a new random ball',
  },
  cannon = {
    id = 'cannon', name = 'Cannon', price = 7500, color_key = 'orange',
    size = 0.9, move = 1.0, ball = 0.6, charge = 1.7, aim = 0.9, dmg = 1.5,
    xp = 1.0, combo = 1.1, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'cannoneer', 'cannoneer'},
    -- launch_at is vestigial now (every paddle hit mortars — no threshold);
    -- impacts = z-axis crashes per hop. charge scales hop height + splash size.
    signature = 'cannon', sig = {launch_at = 1.5, impacts = 4},
    blurb = 'Every paddle hit mortars the ball out of the screen to crash down in splashes.',
    sig_blurb = 'juggling builds the charge (bigger crashes); a pit drop resets it',
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
  self.aegis_wall       = nil
  self.twin_fx          = nil

  if sigid == 'aegis' then
    -- Close the pit. A separate field from floor_wall so the floor powerup's
    -- wave-end teardown in advance_wave never removes it.
    local thick = 6
    self.aegis_wall = self:spawn_wall((self.x1 + self.x2)/2, self.y2 + thick/2 + 2,
                                      self.x2 - self.x1 + thick, thick)
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
    AllyCritter{group = self.main, x = x, y = y, color = color,
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
          o:take_damage(dmg, blue[0])
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
function BallPit:do_splash_falloff(x, y, radius, dmg_max, color)
  spawn_burst(self.effects, x, y, color, 12, 80, 170)
  for _, o in ipairs(self.main.objects) do
    if not o.dead and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) and o.take_damage then
      local d = math.max(0, math.distance(x, y, o.x, o.y) - (o.r_outer or 0))
      if d <= radius then
        local k = math.clamp(1 - d/radius, 0.25, 1)
        if d < 8 then k = k*1.5 end
        o:take_damage(dmg_max*k, color)
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
        o:take_damage(dmg*k, color)
      end
    end
  end
  if     element == 'burn' then self:burn_area(x, y, radius, dmg*0.35, 3)
  elseif element == 'slow' then self:slow_in_area(x, y, radius, 0.5, 3) end
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
  self:do_splash_falloff(x, y, radius, dmg, color)
  if element then
    for _, o in ipairs(self.main.objects) do
      if o:is(Brick) and not o.dead and math.distance(x, y, o.x, o.y) <= radius then
        if     element == 'burn' and o.apply_burn then o:apply_burn(dmg*0.22, 2.5)
        elseif element == 'slow' and o.apply_slow then o:apply_slow(0.5, 2.0) end
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
            local dmg = (sig.nova_dmg or 26)*(1 + 0.5*(lvl - 1))*((self.run_mods.dmg) or 1)
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


-- ----- The post-death paddle shop -----
--
-- The existing game_over flag doubles as "shop open": trigger_game_over banks
-- the wallet + selects the equipped card, BallPit:update routes input here
-- while game_over is set, and the draw_game_over override below renders the
-- shop instead of the old plain overlay. R still restarts (with whatever
-- paddle is equipped).

local SHOP_COLS   = 4
local CARD_W      = 104
local CARD_H      = 78
local CARD_GAP_X  = 112
local CARD_GAP_Y  = 88
local GRID_TOP    = 150

function BallPit:shop_card_pos(i)
  local total = #PADDLES.order
  local rows  = math.ceil(total/SHOP_COLS)
  local row   = math.ceil(i/SHOP_COLS)
  local col   = i - (row - 1)*SHOP_COLS
  -- The last row may be short (13 cards -> 4/4/4/1); centre whatever it holds.
  local in_row = (row < rows) and SHOP_COLS or (total - (rows - 1)*SHOP_COLS)
  local cx = gw/2 + (col - (in_row + 1)/2)*CARD_GAP_X
  local cy = GRID_TOP + (row - 1)*CARD_GAP_Y
  return cx, cy
end


function BallPit:shop_card_under_mouse()
  for i = 1, #PADDLES.order do
    local cx, cy = self:shop_card_pos(i)
    if mouse.x >= cx - CARD_W/2 and mouse.x <= cx + CARD_W/2
    and mouse.y >= cy - CARD_H/2 and mouse.y <= cy + CARD_H/2 then
      return i
    end
  end
  return nil
end


function BallPit:update_shop(dt)
  PADDLES.ensure_state()
  self.shop_selected = self.shop_selected or 1

  -- Mouse: hover selects, click buys/equips.
  local hovered = self:shop_card_under_mouse()
  if hovered then
    if hovered ~= self.shop_selected then
      self.shop_selected = hovered
      ui_switch1:play{volume = 0.25}
    end
    if input.click.pressed then
      self:shop_activate(self.shop_selected)
      return
    end
  end

  -- Keyboard: arrows move within a row, W/S jump rows, Enter buys/equips.
  local n = #PADDLES.order
  if input.aim_left.pressed then
    self.shop_selected = math.max(1, self.shop_selected - 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.aim_right.pressed then
    self.shop_selected = math.min(n, self.shop_selected + 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.move_up.pressed then
    self.shop_selected = math.max(1, self.shop_selected - SHOP_COLS)
    ui_switch1:play{volume = 0.3}
  end
  if input.move_down.pressed then
    self.shop_selected = math.min(n, self.shop_selected + SHOP_COLS)
    ui_switch1:play{volume = 0.3}
  end
  if input.confirm.pressed then
    self:shop_activate(self.shop_selected)
  end
end


-- Buy (if affordable) or equip (if owned) the i-th paddle card.
function BallPit:shop_activate(i)
  PADDLES.ensure_state()
  local id  = PADDLES.order[i]
  local def = PADDLES.get(id)
  if not id then return end

  if state.paddles_owned[id] then
    if state.selected_paddle ~= id then
      state.selected_paddle = id
      system.save_state()
      confirm1:play{volume = 0.4}
    end
  elseif state.wallet >= def.price then
    state.wallet = state.wallet - def.price
    state.paddles_owned[id] = true
    state.selected_paddle = id
    system.save_state()
    confirm1:play{volume = 0.45, pitch = 1.1}
    level_up1:play{volume = 0.3, pitch = 1.05}
    self.shop_bought_i = i
    self.shop_bought_t = love.timer.getTime()
  else
    -- Can't afford it: buzz + flash the wallet readout red for a beat.
    hit1:play{volume = 0.3, pitch = 0.7}
    self.shop_denied_t = love.timer.getTime()
  end
end


-- Replaces the original plain game-over overlay (this file is required after
-- ballpit.lua, so this definition wins).
function BallPit:draw_game_over()
  PADDLES.ensure_state()
  local now = love.timer.getTime()

  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0, 0, 0, 0.78))
  graphics.print_centered('GAME OVER', fat_font, gw/2, 26, 0, 1.1, 1.1, 0, 0, red[0])
  graphics.print_centered('Wave ' .. self.wave .. '   Score ' .. self.score ..
                          '   Kills ' .. (self.run_kills or 0),
                          pixul_font, gw/2, 48, 0, 1, 1, 0, 0, fg[0])

  local denied = self.shop_denied_t and (now - self.shop_denied_t) < 0.35
  local wcol   = denied and red[0] or yellow[0]
  graphics.print_centered('BLOCKS  ' .. math.floor(state.wallet or 0),
                          fat_font, gw/2, 72, 0, 0.9, 0.9, 0, 0, wcol)
  graphics.print_centered('hover + click (or arrows + enter) to buy / equip   —   R to restart',
                          pixul_font, gw/2, 94, 0, 0.9, 0.9, 0, 0, fg_alt[0])

  for i, id in ipairs(PADDLES.order) do
    local def = PADDLES.get(id)
    local cx, cy = self:shop_card_pos(i)
    local selected = (i == self.shop_selected)
    local owned    = state.paddles_owned[id] == true
    local equipped = (state.selected_paddle == id)
    local col      = _G[def.color_key][0]

    local border = fg_transparent_weak
    if equipped then border = yellow[0]
    elseif owned then border = green[0] end
    graphics.rectangle(cx, cy, CARD_W, CARD_H, 4, 4, bg[-1])
    graphics.rectangle(cx, cy, CARD_W, CARD_H, 4, 4,
                       selected and fg[0] or border, selected and 2 or 1)

    -- Just-bought celebration: an expanding ring around the card.
    if self.shop_bought_i == i and self.shop_bought_t and (now - self.shop_bought_t) < 0.5 then
      local k = (now - self.shop_bought_t)/0.5
      graphics.rectangle(cx, cy, CARD_W + 24*k, CARD_H + 24*k, 6, 6,
                         Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.7*(1 - k)), 2)
    end

    -- Paddle glyph. Width tracks the Size stat so the cards preview the
    -- hitbox; the Pinball Lobber draws its two tilted flippers instead.
    local gy = cy - 18
    if def.signature == 'flippers' then
      for side = -1, 1, 2 do
        graphics.push(cx + side*9, gy, side*0.3)
          graphics.rectangle(cx + side*9, gy, 13, 4, 1, 1, col)
        graphics.pop()
      end
    elseif def.signature == 'twincast' then
      -- Twin Cast preview: two orbiting twins joined by a fusion bond.
      local sp = 11
      graphics.line(cx - sp, gy, cx + sp, gy, Color(col.r, col.g, col.b, 0.6), 1)
      graphics.circle(cx - sp, gy, 3, col)
      graphics.circle(cx + sp, gy, 3, col)
      graphics.circle(cx, gy, 2.5, fg[0])
    else
      local gw_card = math.clamp(26*def.size, 14, 38)
      graphics.rectangle(cx, gy, gw_card, 5, 2, 2, col)
      graphics.rectangle(cx, gy - 2.5, gw_card, 1, nil, nil, fg[5])
    end

    graphics.print_centered(def.name, pixul_font, cx, cy + 2, 0, 0.9, 0.9, 0, 0, fg[0])

    if equipped then
      graphics.print_centered('EQUIPPED', pixul_font, cx, cy + 18, 0, 1, 1, 0, 0, yellow[0])
    elseif owned then
      graphics.print_centered('OWNED', pixul_font, cx, cy + 18, 0, 1, 1, 0, 0, green[0])
    else
      local afford = (state.wallet or 0) >= def.price
      local pcol = afford and fg[0] or Color(red[0].r, red[0].g, red[0].b, 0.7)
      graphics.print_centered(def.price .. ' BLOCKS', pixul_font, cx, cy + 18, 0, 1, 1, 0, 0, pcol)
    end

    if equipped or owned then
      graphics.print_centered(equipped and 'press R to play' or 'click to equip',
                              pixul_font, cx, cy + 30, 0, 0.8, 0.8, 0, 0, fg_alt[0])
    end
  end

  -- Detail panel for the selected card.
  local sel = PADDLES.get(PADDLES.order[self.shop_selected or 1])
  local py = 478
  graphics.rectangle(gw/2, py + 56, gw - 40, 118, 4, 4, bg[-1])
  graphics.rectangle(gw/2, py + 56, gw - 40, 118, 4, 4, fg_transparent_weak, 1)
  graphics.print_centered(sel.name, fat_font, gw/2, py + 14, 0, 0.8, 0.8, 0, 0, _G[sel.color_key][0])
  graphics.print_centered(sel.blurb, pixul_font, gw/2, py + 34, 0, 0.9, 0.9, 0, 0, fg[0])
  graphics.print_centered(sel.sig_blurb, pixul_font, gw/2, py + 48, 0, 0.9, 0.9, 0, 0, fg_alt[0])

  local hp_s = (sel.hp_mode == 'bar') and 'BAR' or tostring(sel.hp)
  local xp_s = (sel.xp_mode == 'flat') and 'FLAT' or string.format('%.1f', sel.xp)
  graphics.print_centered(string.format(
      'SIZE %.1f  MOVE %.1f  BALL %.1f  CHARGE %.1f  AIM %.1f',
      sel.size, sel.move, sel.ball, sel.charge, sel.aim),
    pixul_font, gw/2, py + 68, 0, 0.85, 0.85, 0, 0, fg[0])
  graphics.print_centered(string.format(
      'DMG %.1f  XP %s  COMBO %.1f  HP %s',
      sel.dmg, xp_s, sel.combo, hp_s),
    pixul_font, gw/2, py + 82, 0, 0.85, 0.85, 0, 0, fg[0])

  local starts = {}
  for _, c in ipairs(sel.start_balls) do starts[#starts + 1] = c end
  graphics.print_centered('starts with: ' .. table.concat(starts, ', ') ..
                          (sel.signature == 'twincast' and ' (mirrored)' or ''),
                          pixul_font, gw/2, py + 96, 0, 0.85, 0.85, 0, 0, fg_alt[0])
end
