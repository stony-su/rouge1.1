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
  'twincast', 'phantom', 'tesla', 'glacier', 'terrorist', 'cannon',
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
    blurb = 'Every kill splits off a short-lived clone ball.',
    sig_blurb = 'lost hero types regrow on their own',
  },
  hive = {
    id = 'hive', name = 'Hive', price = 750, color_key = 'orange',
    size = 1.0, move = 1.0, ball = 0.8, charge = 0.7, aim = 0.8, dmg = 1.0,
    xp = 1.6, combo = 0.9, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'infestor', 'infestor', 'infestor'},
    signature = 'hive',
    sig = {contact_zero = true, maggot_cap = 24, maggot_dmg_mult = 0.8, maggot_speed = 85},
    blurb = 'Balls deal NO contact damage — every bounce spawns critters.',
    sig_blurb = 'damage is volume, not impact',
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
    signature = 'twincast', sig = {cd_mult = 0.5},
    blurb = 'Every hero arrives mirrored as a pair, abilities fire 2x as fast.',
    sig_blurb = 'XP crawls at half speed to pay for it',
  },
  phantom = {
    id = 'phantom', name = 'Phantom', price = 3500, color_key = 'purple',
    size = 0.8, move = 1.0, ball = 1.0, charge = 1.0, aim = 1.0, dmg = 1.0,
    xp = 1.0, combo = 1.0, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'assassin', 'assassin'},
    signature = 'phantom', sig = {blink_cd = 2.5},
    blurb = 'E drops a ghost paddle anchor; E again teleports back to it.',
    sig_blurb = 'the ghost still bounces balls',
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
  glacier = {
    id = 'glacier', name = 'Glacier', price = 5500, color_key = 'blue',
    size = 1.0, move = 0.8, ball = 1.5, charge = 1.3, aim = 0.6, dmg = 1.1,
    xp = 1.0, combo = 1.2, hp = 5, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'cryomancer', 'cryomancer'},
    signature = 'glacier', sig = {ice = true},
    blurb = 'Pucks on ice: long gliding paths, every hit chills the block.',
    sig_blurb = 'the paddle itself slides too',
  },
  terrorist = {
    id = 'terrorist', name = 'Terrorist', price = 6500, color_key = 'red',
    size = 1.0, move = 1.0, ball = 1.1, charge = 1.0, aim = 1.0, dmg = 1.6,
    xp = 1.0, combo = 1.0, hp = 3, hp_mode = 'hearts', xp_mode = 'flat',
    start_balls = {'bomber', 'bomber', 'bomber'},
    signature = 'terrorist', sig = {fuse = 6, blast_radius = 56, blast_mult = 2.2},
    blurb = 'Balls self-detonate with their own element, then re-form.',
    sig_blurb = 'every level costs the same flat XP',
  },
  cannon = {
    id = 'cannon', name = 'Cannon', price = 7500, color_key = 'orange',
    size = 0.9, move = 1.0, ball = 0.6, charge = 1.7, aim = 0.9, dmg = 1.5,
    xp = 1.0, combo = 1.1, hp = 4, hp_mode = 'hearts', xp_mode = 'scale',
    start_balls = {'cannoneer', 'cannoneer'},
    signature = 'cannon', sig = {launch_at = 1.5, impacts = 4},
    blurb = 'Charged balls mortar out of the screen and crash down in splashes.',
    sig_blurb = 'dropping a ball into the pit resets its charge',
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
  end
end


-- Mitosis: a brick kill splits off a temporary clone of a random live hero.
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
    local src = live[random:int(1, #live)]
    local c = self:add_hero(src.character, {clone = true})
    c.is_clone = true
    c.level    = src.level
    c.dmg      = src.dmg
    self.t:after(sig.clone_life or 2.5, function()
      if c and not c.dead then
        if c.body then c.body:setActive(false) end
        c.dead = true
      end
      for i = #self.heroes, 1, -1 do
        if self.heroes[i] and self.heroes[i].dead then table.remove(self.heroes, i) end
      end
    end)
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
                speed = sig.maggot_speed or 85, dmg = dmg, effect = effect}
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


-- Tesla: arc lightning paddle -> ball -> ball ..., damaging every brick the
-- arcs pass near. Throttled by a short arena-side cooldown so a multi-ball
-- bounce burst doesn't fire it many times in one frame.
function BallPit:tesla_zap(ball)
  if self.tesla_cd then return end
  local sig = (self.run_mods and self.run_mods.sig) or {}
  self.tesla_cd = true
  self.t:after(sig.zap_cd or 0.25, function() self.tesla_cd = false end, 'tesla_cd')

  local pts = {{x = self.paddle.x, y = self.paddle.y}}
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and not h.stuck and not h.returning and not h.mortar then
      pts[#pts + 1] = {x = h.x, y = h.y}
    end
  end
  if #pts < 2 then return end

  local dmg    = (sig.zap_dmg or 7)*(self.run_mods.dmg or 1)
  local width  = sig.zap_width or 12
  local zapped = {}
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    arena_zap_line(self, a.x, a.y, b.x, b.y, blue[0])
    for _, o in ipairs(self.main.objects) do
      if o:is(Brick) and not o.dead and not zapped[o.id] then
        if point_segment_distance(o.x, o.y, a.x, a.y, b.x, b.y) <= width then
          zapped[o.id] = true
          o:take_damage(dmg, blue[0])
        end
      end
    end
  end
  if next(zapped) and thunder1 then
    thunder1:play{volume = 0.12, pitch = random:float(1.15, 1.35)}
  end
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
