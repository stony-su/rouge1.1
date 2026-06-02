-- Brick: one cell of a Row formation.
--
-- Bodies are kinematic — the row sets each brick's position every frame.
-- Balls still bounce off them normally (Box2D handles kinematic-vs-dynamic).
-- When a ball hits a brick, the brick tells its row to apply a small
-- knockback impulse to the whole formation; individual bricks never drift.
--
-- Variants are ported from SNKRX-master/enemies.lua. The "boss" Seeker
-- subtypes (forcer/swarmer/randomizer) and the regular-Seeker flag variants
-- (tank/headbutter/shooter/spawner/exploder/speed_booster) live in the same
-- table here.

Brick = Object:extend()
Brick:implement(GameObject)
Brick:implement(Physics)


local BRICK_W, BRICK_H = 18, 10
-- Grid spacing must match BallPit's CELL_W/CELL_H so multi-cell bricks line
-- up with the swarm planner's grid and adjacent cells of the same brick
-- inherit the 4px gap that lives between separate 1×1 bricks.
local CELL_W, CELL_H = 22, 14
local DEFAULT_SHAPE = {{0, 0}}


-- All variants share size so they slot cleanly into a row. Behaviors are
-- driven by the `behavior` key + the corresponding branch in
-- Brick:setup_behavior. Stats are tuned for our pacing, not SNKRX's.
local VARIANTS = {
  seeker        = {hp = 30,  xp = 1, color = 'red',     dmg = 1, behavior = nil},
  speed_booster = {hp = 45,  xp = 2, color = 'green',   dmg = 1, behavior = 'speed_booster'},
  exploder      = {hp = 35,  xp = 2, color = 'blue',    dmg = 1, behavior = 'exploder'},
  headbutter    = {hp = 55,  xp = 3, color = 'orange',  dmg = 2, behavior = 'headbutter'},
  tank          = {hp = 120, xp = 4, color = 'yellow',  dmg = 2, behavior = nil},
  shooter       = {hp = 45,  xp = 3, color = 'fg',      dmg = 1, behavior = 'shooter'},
  spawner       = {hp = 60,  xp = 3, color = 'purple',  dmg = 2, behavior = 'spawner'},
  swarmer       = {hp = 90,  xp = 5, color = 'purple',  dmg = 2, behavior = 'swarmer'},
  forcer        = {hp = 80,  xp = 4, color = 'yellow2', dmg = 2, behavior = 'forcer'},
  randomizer    = {hp = 70,  xp = 4, color = 'blue2',   dmg = 2, behavior = 'randomizer'},
  -- Ranged variants. These lean into the bullet-hell fantasy: aimed shots,
  -- spread fans, rotating spirals, quick bursts and arcing homing lobs.
  sniper        = {hp = 50,  xp = 3, color = 'red',     dmg = 2, behavior = 'sniper'},
  spreader      = {hp = 55,  xp = 3, color = 'blue2',   dmg = 1, behavior = 'spreader'},
  spiraler      = {hp = 70,  xp = 4, color = 'purple',  dmg = 1, behavior = 'spiraler'},
  burster       = {hp = 50,  xp = 3, color = 'orange',  dmg = 1, behavior = 'burster'},
  arc_lobber    = {hp = 65,  xp = 4, color = 'yellow',  dmg = 2, behavior = 'arc_lobber'},
}

function Brick.variants() return VARIANTS end


function Brick:init(args)
  self:init_game_object(args)
  self.variant_name = self.variant or 'seeker'
  local v = VARIANTS[self.variant_name]

  -- Shape: list of {cx, cy} cell offsets in grid units. Single-cell bricks
  -- default to {{0,0}}; multi-cell shapes (rect 2x2, L, T, etc.) come from
  -- the swarm generator. self.x/self.y end up at the centroid of the shape
  -- so the brick balances on its visual centre rather than the top-left
  -- cell.
  self.shape_cells = self.shape_cells or DEFAULT_SHAPE
  local sum_cx, sum_cy = 0, 0
  local min_cx, max_cx = 1/0, -1/0
  local min_cy, max_cy = 1/0, -1/0
  for _, c in ipairs(self.shape_cells) do
    sum_cx = sum_cx + c[1]; sum_cy = sum_cy + c[2]
    if c[1] < min_cx then min_cx = c[1] end
    if c[1] > max_cx then max_cx = c[1] end
    if c[2] < min_cy then min_cy = c[2] end
    if c[2] > max_cy then max_cy = c[2] end
  end
  local n_cells = #self.shape_cells
  self.shape_cx, self.shape_cy   = sum_cx/n_cells, sum_cy/n_cells
  self.cell_min_cx, self.cell_max_cx = min_cx, max_cx
  self.cell_min_cy, self.cell_max_cy = min_cy, max_cy
  self.cols, self.rows = max_cx - min_cx + 1, max_cy - min_cy + 1

  -- Bounding-box extent in pixels. One cell is BRICK_W/H wide; each extra
  -- cell along an axis adds CELL_W/H (cell-to-cell spacing, which preserves
  -- the 4px between-cell visual gap).
  self.w = BRICK_W + (self.cols - 1) * CELL_W
  self.h = BRICK_H + (self.rows - 1) * CELL_H

  -- HP and XP scale linearly with cell count — bigger bricks are tougher and
  -- more rewarding in proportion to the area they cover.
  self.cell_count = n_cells
  self.max_hp     = v.hp * (1 + 0.2*(main.current.wave or 1)) * n_cells
  self.hp         = self.max_hp
  self.xp_value   = v.xp * n_cells
  self.color      = _G[v.color][0]
  self.player_dmg = v.dmg
  self.behavior   = v.behavior

  self.slow_factor = 1
  self.slow_timer  = 0
  self.burn_timer  = 0
  self.burn_dps    = 0

  -- One kinematic body, one BRICK_W×BRICK_H fixture per cell. The fixture
  -- userdata all point at the same brick id, so collision callbacks route to
  -- a single on_ball_contact regardless of which cell the ball touched.
  -- Tetris-shape bricks have accurate concave collision this way instead of
  -- a fake bounding-box hit on empty interior cells.
  self:setup_multi_cell_body('kinematic', 'brick')
  self:set_fixed_rotation(true)
  self:set_restitution(1)
  self:set_friction(0)
  self.hfx:add('hit', 1)

  self:setup_behavior()
end


function Brick:setup_multi_cell_body(body_type, tag)
  if not self.group then error('Brick must have a group for the Physics mixin to function') end
  self.tag  = tag
  self.body = love.physics.newBody(self.group.world, self.x, self.y, body_type)

  local fixtures = {}
  for _, c in ipairs(self.shape_cells) do
    local lx = (c[1] - self.shape_cx) * CELL_W
    local ly = (c[2] - self.shape_cy) * CELL_H
    local box = love.physics.newRectangleShape(lx, ly, BRICK_W, BRICK_H)
    local fixture = love.physics.newFixture(self.body, box)
    fixture:setUserData(self.id)
    fixture:setCategory(self.group.collision_tags[tag].category)
    fixture:setMask(unpack(self.group.collision_tags[tag].masks))
    table.insert(fixtures, fixture)
  end

  -- Physics:destroy iterates self.fixtures THEN destroys self.fixture, so we
  -- keep them disjoint: singular = first cell, plural = the rest. Otherwise
  -- the first fixture would be destroyed twice and crash.
  self.fixture = fixtures[1]
  if #fixtures > 1 then
    self.fixtures = {}
    for i = 2, #fixtures do table.insert(self.fixtures, fixtures[i]) end
  end
  return self
end


-- World-space y of the bottom edge of this brick's lowest cell. Used by the
-- swarm breach check, which has to know how far the brick *actually* extends
-- — not just its body center, which is the shape centroid.
function Brick:bottom_y()
  return self.y + (self.cell_max_cy - self.shape_cy) * CELL_H + BRICK_H/2
end


-- Variant-specific timer hooks. Triggered periodically while the brick lives.
function Brick:setup_behavior()
  local b = self.behavior
  if not b then return end

  if b == 'speed_booster' then
    self.t:every({5, 7}, function() self:cast_speed_boost() end, 0, nil, 'behavior')

  elseif b == 'headbutter' then
    self.t:every({4, 6}, function() self:cast_headbutt() end, 0, nil, 'behavior')

  elseif b == 'shooter' then
    self.t:every({4, 6}, function() self:cast_shoot() end, 0, nil, 'behavior')

  elseif b == 'spawner' then
    self.t:every({6, 8}, function() self:cast_spawn_critter() end, 0, nil, 'behavior')

  elseif b == 'forcer' then
    self.t:every({5, 8}, function() self:cast_force_push() end, 0, nil, 'behavior')

  elseif b == 'sniper' then
    self.t:every({3.5, 5}, function() self:cast_sniper() end, 0, nil, 'behavior')

  elseif b == 'spreader' then
    self.t:every({4.5, 6.5}, function() self:cast_spread() end, 0, nil, 'behavior')

  elseif b == 'spiraler' then
    self.t:every({5, 7}, function() self:cast_spiral() end, 0, nil, 'behavior')

  elseif b == 'burster' then
    self.t:every({5, 7}, function() self:cast_burst() end, 0, nil, 'behavior')

  elseif b == 'arc_lobber' then
    self.t:every({4, 6}, function() self:cast_arc_lob() end, 0, nil, 'behavior')

  elseif b == 'randomizer' then
    self.t:every({4, 6}, function()
      local pick = random:table{'speed_boost', 'shoot', 'spawn', 'force', 'sniper', 'spread', 'spiral', 'burst'}
      if     pick == 'speed_boost' then self:cast_speed_boost()
      elseif pick == 'shoot'       then self:cast_shoot()
      elseif pick == 'spawn'       then self:cast_spawn_critter()
      elseif pick == 'force'       then self:cast_force_push()
      elseif pick == 'sniper'      then self:cast_sniper()
      elseif pick == 'spread'      then self:cast_spread()
      elseif pick == 'spiral'      then self:cast_spiral()
      elseif pick == 'burst'       then self:cast_burst() end
    end, 0, nil, 'behavior')
  end
  -- exploder and swarmer trigger on death, not on timer.
end


-- Brief boost to the whole formation's drift speed.
function Brick:cast_speed_boost()
  if self.dead then return end
  TelegraphRing{group = main.current.effects, x = self.x, y = self.y, radius = 12, color = green[0], duration = 0.2}
  for _, row in ipairs(main.current.swarms.objects) do
    if not row.dead then
      row._base_drift = row._base_drift or row.drift_speed
      row.drift_speed = row._base_drift*2
    end
  end
  main.current.t:after(2, function()
    for _, row in ipairs(main.current.swarms.objects) do
      if row._base_drift then row.drift_speed = row._base_drift end
    end
  end)
end


-- Charge forward in formation — row gets a small downward kick.
function Brick:cast_headbutt()
  if self.dead or not self.swarm then return end
  TelegraphRing{group = main.current.effects, x = self.x, y = self.y, radius = 8, color = orange[0], duration = 0.15}
  self.swarm:apply_knockback(40, math.pi/2)
end


-- Fire a slow projectile downward at the paddle's current x.
function Brick:cast_shoot()
  if self.dead then return end
  TelegraphRing{group = main.current.effects, x = self.x, y = self.y, radius = 6, color = self.color, duration = 0.15}
  shoot1:play{volume = 0.18, pitch = random:float(0.95, 1.05)}
  local x, y = self.x, self.y + 6
  local arena = main.current
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      EnemyProjectile{group = arena.main, x = x, y = y, color = self.color, speed = 70}
    end
  end)
end


-- Aimed shot: telegraphs longer than a plain shooter, then fires one fast
-- projectile straight at the paddle's current position.
function Brick:cast_sniper()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 8,
                color = red[0], duration = 0.35}
  -- Telegraph at the paddle too, so the player sees they're being targeted.
  TelegraphRing{group = arena.effects, x = arena.paddle.x, y = arena.paddle.y - 4,
                radius = 10, color = red[0], duration = 0.35}
  local sx, sy = self.x, self.y + 6
  arena.t:after(0.3, function()
    if arena.main and arena.main.world and not self.dead then
      shoot1:play{volume = 0.22, pitch = random:float(0.85, 0.95)}
      local angle = math.atan2(arena.paddle.y - sy, arena.paddle.x - sx)
      -- Sniper: very fast, snap-shot aimed dart. Top of the speed tier.
      EnemyProjectile{group = arena.main, x = sx, y = sy, color = red[0],
                      kind = 'dart', angle = angle, speed = 160, dmg = 2}
    end
  end)
end


-- Three-shot spread fan aimed straight down.
function Brick:cast_spread()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 7,
                color = self.color, duration = 0.18}
  shoot1:play{volume = 0.2, pitch = random:float(1.0, 1.1)}
  local sx, sy = self.x, self.y + 6
  local base   = math.pi/2
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      for _, off in ipairs({-0.35, 0, 0.35}) do
        -- Spreader: medium-fast triangle fan. A touch quicker than shooter
        -- so the fan still feels threatening even when offset shots miss.
        EnemyProjectile{group = arena.main, x = sx, y = sy, color = self.color,
                        kind = 'triangle', angle = base + off, speed = 90}
      end
    end
  end)
end


-- Spiral barrage: 8 projectiles around the full circle, with the start angle
-- rotating between casts so successive bursts paint a turning spiral pattern.
function Brick:cast_spiral()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 10,
                color = self.color, duration = 0.2}
  shoot1:play{volume = 0.22, pitch = random:float(0.9, 1.0)}
  self._spiral_phase = (self._spiral_phase or 0) + 0.4
  local phase = self._spiral_phase
  local sx, sy = self.x, self.y
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      for i = 0, 7 do
        local a = i*math.pi/4 + phase
        -- Spiraler: slowest of all so the rotating wall hangs in the air
        -- long enough for the player to read the spiral pattern.
        EnemyProjectile{group = arena.main, x = sx, y = sy, color = self.color,
                        kind = 'orb', angle = a, speed = 45, r_size = 3, life = 3.5}
      end
    end
  end)
end


-- Three-shot burst: three quick straight-down shots in rapid succession,
-- then a longer cooldown before the next burst.
function Brick:cast_burst()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 6,
                color = self.color, duration = 0.15}
  local sx = self.x
  for i = 0, 2 do
    arena.t:after(i*0.12, function()
      if arena.main and arena.main.world and not self.dead then
        shoot1:play{volume = 0.16, pitch = random:float(1.05, 1.2)}
        -- Burster: very fast triple bolt. Quick enough that the second and
        -- third shots can punish a player who only dodged the first.
        EnemyProjectile{group = arena.main, x = sx, y = self.y + 6,
                        color = self.color, kind = 'bolt', speed = 115}
      end
    end)
  end
end


-- Arcing homing lob: paints a danger zone near the paddle, then sends a
-- slow projectile that drifts toward that area. The paddle can still escape
-- by moving — homing turn rate is capped.
function Brick:cast_arc_lob()
  if self.dead then return end
  local arena = main.current
  local lx    = arena.paddle.x + random:float(-30, 30)
  local ly    = arena.paddle.y - 4
  -- Danger zone telegraph at the projected landing spot.
  TelegraphRing{group = arena.effects, x = lx, y = ly, radius = 20,
                color = yellow[0], duration = 0.7}
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 8,
                color = yellow[0], duration = 0.2}
  shoot1:play{volume = 0.2, pitch = random:float(0.7, 0.8)}
  local sx, sy = self.x, self.y + 6
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      local angle = math.atan2(ly - sy, lx - sx)
      -- Arc lobber: slow heavy homing lob. Slow enough that the homing curve
      -- reads visually as a tracking threat rather than an instant hit.
      EnemyProjectile{group = arena.main, x = sx, y = sy, color = yellow[0],
                      kind = 'bomb', angle = angle, speed = 55, dmg = 2,
                      homing = true, homing_turn = 1.2, life = 5}
    end
  end)
end


-- Drop a small EnemyCritter just below this brick.
function Brick:cast_spawn_critter()
  if self.dead then return end
  TelegraphRing{group = main.current.effects, x = self.x, y = self.y, radius = 6, color = purple[0], duration = 0.15}
  critter1:play{volume = 0.22, pitch = random:float(0.95, 1.05)}
  local x, y = self.x, self.y + 8
  local arena = main.current
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      EnemyCritter{group = arena.main, x = x, y = y, color = purple[0]}
    end
  end)
end


-- Knock all nearby balls outward radially.
function Brick:cast_force_push()
  if self.dead then return end
  TelegraphRing{group = main.current.effects, x = self.x, y = self.y, radius = 64, color = yellow[0], duration = 0.25}
  force1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
  local arena = main.current
  for _, hero in ipairs(arena.heroes) do
    if hero and not hero.dead and not hero.returning and hero.body then
      local d = math.distance(self.x, self.y, hero.x, hero.y)
      if d < 64 and d > 0.5 then
        local ang = math.atan2(hero.y - self.y, hero.x - self.x)
        hero:apply_impulse(math.cos(ang)*40, math.sin(ang)*40)
      end
    end
  end
end


function Brick:update(dt)
  self:update_game_object(dt)

  if self.slow_timer > 0 then
    self.slow_timer = self.slow_timer - dt
    if self.slow_timer <= 0 then self.slow_factor = 1 end
  end

  if self.burn_timer > 0 then
    self.burn_timer = self.burn_timer - dt
    self:take_damage(self.burn_dps*dt, orange[0], true)
    if random:bool(15) then
      HitParticle{
        group = main.current.effects,
        x = self.x + random:float(-self.w/3, self.w/3),
        y = self.y - self.h/2,
        color = orange[0], v = 30, r = -math.pi/2, w = 2, duration = 0.3,
      }
    end
  end

  -- Curse: vulnerability mark applied by launcher/jester/etc. Ticks down,
  -- reverts the damage multiplier to 1 when expired.
  if self.curse_timer and self.curse_timer > 0 then
    self.curse_timer = self.curse_timer - dt
    if self.curse_timer <= 0 then
      self.curse_mult, self.curse_timer = 1, 0
    end
  end

  -- Position is owned by the row; row breach checks are handled there.
end


function Brick:draw()
  local s = self.hfx.hit.x
  local hp_pct = math.clamp(self.hp/self.max_hp, 0, 1)
  local body_color = self.color
  if self.hfx.hit.f then body_color = fg[0] end
  local dark_color = Color(body_color.r*0.7, body_color.g*0.7, body_color.b*0.7, 1)

  -- O(1) "same-brick neighbour?" lookup for the connector pass.
  local has = {}
  for _, c in ipairs(self.shape_cells) do
    has[c[1]] = has[c[1]] or {}
    has[c[1]][c[2]] = true
  end
  local function has_cell(cx, cy) return has[cx] and has[cx][cy] end

  -- Scale the whole brick uniformly around its body centre so the hit-flash
  -- treats a multi-cell brick as one unit, instead of each cell wobbling
  -- around its own centre and visually tearing the shape apart.
  graphics.push(self.x, self.y, 0, s, 1/s)
    -- Cell bodies. Same look as a 1×1 brick: BRICK_W×BRICK_H body with a
    -- 1-pixel inset dark interior.
    for _, c in ipairs(self.shape_cells) do
      local cx = self.x + (c[1] - self.shape_cx) * CELL_W
      local cy = self.y + (c[2] - self.shape_cy) * CELL_H
      graphics.rectangle(cx, cy, BRICK_W, BRICK_H, 1, 1, body_color)
      graphics.rectangle(cx, cy, BRICK_W - 2, BRICK_H - 2, nil, nil, dark_color)
    end

    -- Connectors fill the 4-pixel between-cell gaps WITHIN this brick so the
    -- shape reads as one solid piece instead of N separate 1×1s. The body
    -- and dark rectangles are extended 1px into each neighbouring cell so
    -- the joint paints over the cell's rounded corners + inner-border seam
    -- — no visible line at the connection point.
    local gap_w = CELL_W - BRICK_W   -- 4
    local gap_h = CELL_H - BRICK_H   -- 4
    for _, c in ipairs(self.shape_cells) do
      if has_cell(c[1] + 1, c[2]) then
        -- Horizontal connector between (cx, cy) and (cx+1, cy).
        local mx = self.x + (c[1] + 0.5 - self.shape_cx) * CELL_W
        local my = self.y + (c[2]       - self.shape_cy) * CELL_H
        graphics.rectangle(mx, my, gap_w + 2, BRICK_H,     nil, nil, body_color)
        graphics.rectangle(mx, my, gap_w + 2, BRICK_H - 2, nil, nil, dark_color)
      end
      if has_cell(c[1], c[2] + 1) then
        -- Vertical connector between (cx, cy) and (cx, cy+1).
        local mx = self.x + (c[1]       - self.shape_cx) * CELL_W
        local my = self.y + (c[2] + 0.5 - self.shape_cy) * CELL_H
        graphics.rectangle(mx, my, BRICK_W,     gap_h + 2, nil, nil, body_color)
        graphics.rectangle(mx, my, BRICK_W - 2, gap_h + 2, nil, nil, dark_color)
      end
      -- Corner filler where four cells meet (2×2, 3×3, etc.). The four
      -- diagonal cells leave a tiny 4×4 hole in the middle that the
      -- orthogonal connectors don't cover.
      if has_cell(c[1] + 1, c[2]) and has_cell(c[1], c[2] + 1) and has_cell(c[1] + 1, c[2] + 1) then
        local mx = self.x + (c[1] + 0.5 - self.shape_cx) * CELL_W
        local my = self.y + (c[2] + 0.5 - self.shape_cy) * CELL_H
        graphics.rectangle(mx, my, gap_w + 2, gap_h + 2, nil, nil, body_color)
        graphics.rectangle(mx, my, gap_w + 2, gap_h + 2, nil, nil, dark_color)
      end
    end
  graphics.pop()

  -- HP bar: spans the full bounding-box width, sits above the topmost row.
  if hp_pct < 1 then
    local bar_cx = self.x + ((self.cell_min_cx + self.cell_max_cx)/2 - self.shape_cx) * CELL_W
    local bar_y  = self.y + (self.cell_min_cy - self.shape_cy) * CELL_H - BRICK_H/2 - 2
    local bar_w  = BRICK_W + (self.cell_max_cx - self.cell_min_cx) * CELL_W
    graphics.rectangle(bar_cx, bar_y, bar_w, 1.5, nil, nil, bg[-2])
    graphics.rectangle(bar_cx - bar_w/2 + bar_w*hp_pct/2, bar_y, bar_w*hp_pct, 1.5, nil, nil, red[0])
  end

  if self.slow_factor < 1 then
    graphics.circle(self.x, self.y, self.w*0.6, blue_transparent_weak)
  end

  -- Curse glow: faint pulsing aura around cursed bricks.
  if (self.curse_mult or 1) > 1 and self.curse_color then
    local pulse = 0.5 + 0.2*math.sin(love.timer.getTime()*5)
    local c     = Color(self.curse_color.r, self.curse_color.g, self.curse_color.b, 0.35*pulse)
    graphics.circle(self.x, self.y, self.w*0.7, c, 1.5)
  end
end


function Brick:take_damage(amount, color, no_flash)
  if self.hp <= 0 then return end
  amount = amount * (self.curse_mult or 1)
  self.hp = self.hp - amount
  if not no_flash then
    self.hfx:use('hit', 0.25, 200, 10)
    spawn_burst(main.current.effects, self.x, self.y, color or self.color, 3, 40, 100)
  end
  if self.hp <= 0 then
    self:die()
  end
end


-- Called by BallHero on collision: damage + propagate small knockback to row.
function Brick:on_ball_contact(ball)
  if self.hp <= 0 then return end
  -- Apply the ball's active charge bonus (1.0 .. 1.5) to contact damage.
  local dmg = ball.dmg*(ball.charge_dmg_mult or 1)
  self:take_damage(dmg, ball.color)
  if self.swarm and not self.dead then
    local vx, vy = ball:get_velocity()
    local mag    = math.sqrt(vx*vx + vy*vy)
    if mag > 0.5 then
      -- Push the row a tiny bit in the ball's incoming direction.
      self.swarm:apply_knockback(8, math.atan2(vy, vx))
    end
  end
end


function Brick:apply_slow(factor, duration)
  if factor < self.slow_factor then self.slow_factor = factor end
  if duration > self.slow_timer then self.slow_timer = duration end
end


-- Vulnerability mark applied by curse heroes (launcher/jester/usurer/etc).
-- Multiplies incoming damage by `mult` for `duration` seconds; refreshes if a
-- stronger or longer curse is reapplied.
function Brick:apply_curse(color, mult, duration)
  self.curse_mult  = math.max(self.curse_mult or 1, mult or 1.4)
  self.curse_timer = math.max(self.curse_timer or 0, duration or 6)
  self.curse_color = color or purple[0]
end


function Brick:apply_burn(dps, duration)
  self.burn_dps   = math.max(self.burn_dps, dps)
  self.burn_timer = math.max(self.burn_timer, duration)
end


function Brick:die()
  local arena = main.current
  arena:on_brick_killed(self)
  spawn_burst(arena.effects, self.x, self.y, self.color, 8, 60, 160)
  enemy_die1:play{volume = 0.3, pitch = random:float(0.92, 1.08)}

  -- Death triggers for two of the variants.
  if self.behavior == 'exploder' then
    self:cast_explode_on_death()
  elseif self.behavior == 'swarmer' then
    self:cast_swarmer_on_death()
  end

  -- Drop XP after world step (Box2D is locked mid-collision).
  local x, y, value = self.x, self.y, self.xp_value
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      XpOrb{group = arena.main, x = x, y = y, value = value}
    end
  end)

  -- NOTE: Powerups used to roll on brick death (a 4% / 1% weighted chance per
  -- kill). They now spawn from the arena-side pity timer in
  -- BallPit:tick_powerup_pity instead, so the drop rate is independent of
  -- which bricks the player happens to be killing. The wave-end tier-2
  -- guarantee in BallPit:advance_wave still fires.

  self.dead = true
end


-- Chain-explode neighbours within ~28px.
function Brick:cast_explode_on_death()
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 28, color = blue[0], duration = 0.25}
  explosion1:play{volume = 0.3, pitch = random:float(0.95, 1.1)}
  camera:shake(2, 0.15, 90)
  for _, o in ipairs(arena.main.objects) do
    if o:is(Brick) and not o.dead and o.id ~= self.id then
      if math.distance(self.x, self.y, o.x, o.y) <= 28 then
        o:take_damage(self.max_hp*0.4, blue[0])
      end
    end
  end
end


-- Spawn three EnemyCritters that drift toward the paddle.
function Brick:cast_swarmer_on_death()
  local arena = main.current
  critter3:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
  local x, y, color = self.x, self.y, self.color
  arena.t:after(0, function()
    if not (arena.main and arena.main.world) then return end
    for i = 1, 3 do
      EnemyCritter{
        group = arena.main,
        x = x + random:float(-6, 6),
        y = y + random:float(-2, 2),
        color = color,
      }
    end
  end)
end
