-- Mobile enemies that aren't bricks.
--
-- EnemyCritter is a small circular enemy spawned by the swarmer/spawner brick
-- variants. It drifts toward the paddle and dies in a single hit. If it
-- reaches the paddle, it breaches like a brick would.
--
-- EnemyProjectile is a slow downward shot fired by the shooter brick variant.
-- Hits the paddle for damage. Can be destroyed by a ball.

EnemyCritter = Object:extend()
EnemyCritter:implement(GameObject)
EnemyCritter:implement(Physics)

function EnemyCritter:init(args)
  self:init_game_object(args)
  self.r_size     = 3
  self.color      = self.color or purple[0]
  self.hp         = self.hp or 1
  self.speed      = self.speed or 14
  self.xp_value   = 1
  self.player_dmg = 1

  self:set_as_circle(self.r_size, 'dynamic', 'brick')
  self:set_fixed_rotation(true)
  self:set_restitution(0.4)
  self:set_friction(0)
  self:set_damping(0.4)
  self:set_mass(0.3)
  self.hfx:add('hit', 1)

  -- Drift downward with a slight horizontal wobble so they don't all line up.
  self.wobble_phase = random:float(0, 2*math.pi)
  self.wobble_amp   = random:float(8, 16)
end

function EnemyCritter:update(dt)
  self:update_game_object(dt)
  local vx, vy = self:get_velocity()
  self.wobble_phase = self.wobble_phase + dt*2
  local target_vx = math.cos(self.wobble_phase)*self.wobble_amp
  self:set_velocity(vx + (target_vx - vx)*0.05, vy + (self.speed - vy)*0.05)

  local arena = main.current
  if self.y > arena.paddle.y + 6 then
    arena:on_brick_breached(self)
    self.dead = true
  end
end

function EnemyCritter:draw()
  local s = self.hfx.hit.x
  local col = self.hfx.hit.f and fg[0] or self.color
  graphics.circle(self.x, self.y, (self.r_size + 0.5), bg[-2])
  graphics.circle(self.x, self.y, self.r_size*s, col)
end

function EnemyCritter:take_damage(amount, color)
  self.hp = self.hp - amount
  self.hfx:use('hit', 0.25, 200, 10)
  spawn_burst(main.current.effects, self.x, self.y, color or self.color, 3, 40, 100)
  if self.hp <= 0 then
    self:die()
  end
end

function EnemyCritter:die()
  local arena = main.current
  spawn_burst(arena.effects, self.x, self.y, self.color, 5, 60, 130)
  critter2:play{volume = 0.25, pitch = random:float(0.95, 1.1)}
  local x, y, v = self.x, self.y, self.xp_value
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      XpOrb{group = arena.main, x = x, y = y, value = v}
    end
  end)
  self.dead = true
end

-- Critters don't slow/burn but the brick-targeted ability helpers may call
-- these — provide no-op stubs to avoid crashes.
function EnemyCritter:apply_slow() end
function EnemyCritter:apply_burn() end


-- Slow downward projectile fired by shooter bricks. Hits the paddle.
EnemyProjectile = Object:extend()
EnemyProjectile:implement(GameObject)
EnemyProjectile:implement(Physics)

function EnemyProjectile:init(args)
  self:init_game_object(args)
  -- Bumped from 2.5 → 3.5 so the projectile reads as a real threat, not a
  -- pickup. Hero balls can also intercept it more easily at this size.
  self.r_size = self.r_size or 3.5
  self.color  = self.color or fg[0]
  self.speed  = self.speed or 60
  self.dmg    = self.dmg or 1
  -- Firing direction in radians. Defaults to straight down (π/2) so existing
  -- callers (shooter brick) keep working without supplying an angle.
  self.angle        = self.angle or math.pi/2
  -- Optional homing: turns velocity vector toward the paddle at `homing_turn`
  -- rad/s. Used by arc-lobber variant and can be wired up by future enemies.
  self.homing       = self.homing or false
  self.homing_turn  = self.homing_turn or 1.5
  -- Visual kind. Each ranged enemy type uses a distinct kind so the screen
  -- reads at a glance even when multiple attack patterns overlap. Default
  -- 'spike' preserves the original red 4-pointed shooter look.
  --   spike    -> shooter (default)         red 4-spike, red trail/halo
  --   dart     -> sniper / boss shotgun     long needle aligned to velocity
  --   triangle -> spreader                  small pointed triangle
  --   orb      -> spiraler                  swirly orb + orbiting pixel
  --   bolt     -> burster                   short bright bolt aligned to velocity
  --   bomb     -> arc_lobber                pulsing ring + colored core
  --   boss_orb -> boss attacks              big double-aura phase-colored orb
  -- NB: this field is intentionally called `kind`, not `shape`. The Physics
  -- mixin's set_as_circle (engine/game/physics.lua) writes to self.shape with
  -- a Circle instance, which would clobber any value we put there.
  self.kind         = self.kind or 'spike'
  self.spin_t      = random:float(0, math.pi*2)
  self.spin_speed  = random:float(4, 7) * (random:bool(50) and 1 or -1)
  self.trail       = {}
  self.trail_acc   = 0

  self:set_as_circle(self.r_size, 'dynamic', 'brick')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(0)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.2)
  self:set_velocity(math.cos(self.angle)*self.speed, math.sin(self.angle)*self.speed)
  self.hfx:add('hit', 1)

  -- Optional self-destruct timer so short-range bullet-hell shots don't pile
  -- up forever when fired away from the paddle.
  if self.life then
    self.t:after(self.life, function() self.dead = true end)
  end
end

function EnemyProjectile:update(dt)
  self:update_game_object(dt)
  local arena = main.current

  -- Homing: smoothly rotate velocity toward the paddle. Capped turn rate so
  -- the player can still dodge by moving — these aren't perfect trackers.
  if self.homing and arena and arena.paddle then
    local vx, vy = self:get_velocity()
    local cur    = math.atan2(vy, vx)
    local want   = math.atan2(arena.paddle.y - self.y, arena.paddle.x - self.x)
    -- Wrap diff to [-π, π] so we always turn the short way around the circle.
    local diff   = math.loop(want - cur, 2*math.pi)
    if diff > math.pi then diff = diff - 2*math.pi end
    local step   = math.clamp(diff, -self.homing_turn*dt, self.homing_turn*dt)
    local new_a  = cur + step
    self:set_velocity(math.cos(new_a)*self.speed, math.sin(new_a)*self.speed)
  end

  -- Off-arena cleanup. Original only killed on the bottom edge — angled
  -- bullet-hell shots can also exit sideways or off the top.
  if self.y > arena.y2 + 8 or self.y < arena.y1 - 8 then self.dead = true end
  if self.x < arena.x1 - 8 or self.x > arena.x2 + 8 then self.dead = true end
  if self.y > arena.paddle.y - 4 and math.abs(self.x - arena.paddle.x) < arena.paddle.w/2 + 3 then
    -- Hit the paddle directly. Admin godmode swallows the hp loss but still
    -- plays the impact feedback so the operator can see what would have hit.
    if not arena.god then
      arena.player_hp = arena.player_hp - self.dmg
    end
    hit2:play{volume = 0.4, pitch = random:float(1.0, 1.1)}
    camera:shake(2, 0.15, 90)
    Flash{group = arena.effects, x = gw/2, y = gh/2, color = red_transparent_weak, duration = 0.08}
    if arena.player_hp <= 0 then arena:trigger_game_over() end
    self.dead = true
  end

  -- Visual state: spin + sampled trail. The trail is what most reliably
  -- separates this from an XP orb at a glance — orbs sit still and pickups
  -- drift; a streaking line below the cursor reads as "incoming."
  self.spin_t = self.spin_t + self.spin_speed*dt
  self.trail_acc = self.trail_acc + dt
  if self.trail_acc > 0.03 then
    self.trail_acc = 0
    table.insert(self.trail, 1, {x = self.x, y = self.y})
    if #self.trail > 8 then table.remove(self.trail) end
  end
end

-- Velocity-aligned facing angle, used by shapes that point along their
-- travel direction (dart/triangle/bolt). Falls back to the initial fire
-- angle when the projectile is momentarily stationary.
function EnemyProjectile:facing_angle()
  local vx, vy = self:get_velocity()
  if vx*vx + vy*vy < 1 then return self.angle end
  return math.atan2(vy, vx)
end


-- Shared back-to-front trail. Older samples are smaller and more transparent
-- so motion direction reads cleanly. Color is the only knob — each shape
-- picks whether to use its self.color or a fixed palette tone.
function EnemyProjectile:draw_trail(color)
  for i = #self.trail, 1, -1 do
    local p  = self.trail[i]
    local k  = i/(#self.trail + 1)
    local a  = (1 - k)*0.55
    local rs = self.r_size*(1 - k*0.7)
    if rs > 0.4 then
      graphics.circle(p.x, p.y, rs, Color(color.r, color.g, color.b, a))
    end
  end
end


-- Per-shape draw dispatch. The default 'spike' branch is the original
-- shooter look — kept identical so existing callers don't need updates.
function EnemyProjectile:draw()
  if     self.kind == 'dart'     then self:draw_dart()
  elseif self.kind == 'triangle' then self:draw_triangle()
  elseif self.kind == 'orb'      then self:draw_orb()
  elseif self.kind == 'bolt'     then self:draw_bolt()
  elseif self.kind == 'bomb'     then self:draw_bomb()
  elseif self.kind == 'boss_orb' then self:draw_boss_orb()
  else                                self:draw_spike() end
end


-- 'spike' (shooter, default): original red 4-pointed spike + red halo + red
-- trail. Color is hardcoded red regardless of self.color so the projectile
-- always reads as "danger" and can never be confused for a colored XP gem.
function EnemyProjectile:draw_spike()
  self:draw_trail(red[0])

  local pulse = 1 + math.sin((time or 0)*9)*0.18
  graphics.circle(self.x, self.y, (self.r_size + 2)*pulse, red_transparent_weak)

  local s   = self.hfx.hit.x or 1
  local col = self.hfx.hit.f and fg[0] or red[0]
  graphics.push(self.x, self.y, self.spin_t)
    graphics.rectangle(self.x, self.y, self.r_size*2.6*s, self.r_size*0.9*s, 0.6, 0.6, col)
    graphics.rectangle(self.x, self.y, self.r_size*0.9*s, self.r_size*2.6*s, 0.6, 0.6, col)
  graphics.pop()
  -- Bright inner core dot — keeps the projectile readable when the spike
  -- happens to align horizontally and looks like a thin bar.
  graphics.circle(self.x, self.y, self.r_size*0.5*s, fg[5])
end


-- 'dart' (sniper, boss shotgun): long thin needle aligned to the velocity
-- vector. Trail and body use self.color so boss-phase tinting works.
function EnemyProjectile:draw_dart()
  self:draw_trail(self.color)

  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local face = self:facing_angle()
  graphics.push(self.x, self.y, face)
    graphics.rectangle(self.x, self.y, self.r_size*3.4*s, self.r_size*0.7*s,  0.4, 0.4, col)
    graphics.rectangle(self.x, self.y, self.r_size*2.4*s, self.r_size*0.25*s, 0.2, 0.2, fg[5])
  graphics.pop()
end


-- 'triangle' (spreader): small triangle with tip pointing along velocity.
-- Vertices are rotated in software because polygon() draws in world space
-- and graphics.push only stacks affine transforms on the love.graphics
-- matrix — we want the same triangle, oriented to the bullet's heading.
function EnemyProjectile:draw_triangle()
  self:draw_trail(self.color)

  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local face = self:facing_angle()
  local r    = self.r_size*1.7*s
  local cos_a, sin_a = math.cos(face), math.sin(face)
  local function rot(lx, ly)
    return self.x + lx*cos_a - ly*sin_a, self.y + lx*sin_a + ly*cos_a
  end
  local x1, y1 = rot( r,       0)
  local x2, y2 = rot(-r*0.7,   r*0.85)
  local x3, y3 = rot(-r*0.7,  -r*0.85)
  graphics.polygon({x1, y1, x2, y2, x3, y3}, col)
  graphics.circle(self.x, self.y, self.r_size*0.4*s, fg[5])
end


-- 'orb' (spiraler): soft pulsing aura, filled body, one bright pixel
-- orbiting around it for an unmistakable "spinning" feel.
function EnemyProjectile:draw_orb()
  self:draw_trail(self.color)

  local s     = self.hfx.hit.x or 1
  local col   = self.hfx.hit.f and fg[0] or self.color
  local pulse = 1 + math.sin((time or 0)*8 + (self.spin_t or 0))*0.2

  graphics.circle(self.x, self.y, (self.r_size + 1.5)*pulse,
                  Color(col.r, col.g, col.b, 0.28))
  graphics.circle(self.x, self.y, self.r_size*s, col)
  local oa = self.spin_t or 0
  graphics.circle(self.x + math.cos(oa)*self.r_size*0.9,
                  self.y + math.sin(oa)*self.r_size*0.9,
                  self.r_size*0.42*s, fg[5])
end


-- 'bolt' (burster): short, crisp, fast-feeling rectangle aligned with
-- velocity. Slightly chunkier than the dart so triplet bursts read as
-- distinct shots even when they're stacked in flight.
function EnemyProjectile:draw_bolt()
  self:draw_trail(self.color)

  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local face = self:facing_angle()
  graphics.push(self.x, self.y, face)
    graphics.rectangle(self.x, self.y, self.r_size*2.3*s, self.r_size*1.1*s,  0.4, 0.4, col)
    graphics.rectangle(self.x, self.y, self.r_size*1.5*s, self.r_size*0.4*s,  0.2, 0.2, fg[5])
  graphics.pop()
end


-- 'bomb' (arc_lobber): big pulsing aura + outer ring + filled core. The
-- pulse rate is faster than the boss orb so it reads as a different threat
-- (timed area denial vs. point projectile).
function EnemyProjectile:draw_bomb()
  self:draw_trail(self.color)

  local s     = self.hfx.hit.x or 1
  local col   = self.hfx.hit.f and fg[0] or self.color
  local pulse = 1 + math.sin((time or 0)*7)*0.3

  graphics.circle(self.x, self.y, (self.r_size + 3)*pulse,
                  Color(col.r, col.g, col.b, 0.32))
  graphics.circle(self.x, self.y, self.r_size*1.35*s, col, 1.5)
  graphics.circle(self.x, self.y, self.r_size*0.7*s,  col)
  graphics.circle(self.x, self.y, self.r_size*0.3*s,  fg[5])
end


-- 'boss_orb' (boss attacks): largest visual footprint. Double-layer aura,
-- concentric rings, bright core. Color comes from the boss's current phase
-- (red → orange → purple) so the player can read phase + threat at once.
function EnemyProjectile:draw_boss_orb()
  self:draw_trail(self.color)

  local s     = self.hfx.hit.x or 1
  local col   = self.hfx.hit.f and fg[0] or self.color
  local pulse = 1 + math.sin((time or 0)*8)*0.25

  graphics.circle(self.x, self.y, (self.r_size + 4)*pulse,
                  Color(col.r, col.g, col.b, 0.28))
  graphics.circle(self.x, self.y, self.r_size*1.55*s, col, 1.5)
  graphics.circle(self.x, self.y, self.r_size*s,       col)
  graphics.circle(self.x, self.y, self.r_size*0.55*s,  fg[5], 1)
  graphics.circle(self.x, self.y, self.r_size*0.28*s,  fg[5])
end

function EnemyProjectile:take_damage(amount, color)
  self.hfx:use('hit', 0.25, 200, 10)
  spawn_burst(main.current.effects, self.x, self.y, color or self.color, 3, 40, 80)
  self.dead = true
end

function EnemyProjectile:apply_slow() end
function EnemyProjectile:apply_burn() end


-- AllyCritter: spawned by host / infestor / illusionist. A small ball that
-- flies upward, hits a brick and dies (or expires on a timer). Uses the
-- 'projectile' physics tag so it only collides with bricks.
AllyCritter = Object:extend()
AllyCritter:implement(GameObject)
AllyCritter:implement(Physics)

function AllyCritter:init(args)
  self:init_game_object(args)
  self.r_size   = 3
  self.color    = self.color or fg[0]
  self.dmg      = self.dmg or 6
  self.speed    = self.speed or 70
  self.lifetime = self.lifetime or 4

  self:set_as_circle(self.r_size, 'dynamic', 'projectile')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(0.4)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.2)

  local angle = -math.pi/2 + random:float(-0.6, 0.6)
  self:set_velocity(math.cos(angle)*self.speed, math.sin(angle)*self.speed)
  self.hfx:add('hit', 1)

  self.on_collision_enter = function(s, other, contact)
    if not other then return end
    if other.tag == 'brick' then s:on_brick_contact(other) end
  end

  self.t:after(self.lifetime, function() self.dead = true end)
end

function AllyCritter:update(dt)
  self:update_game_object(dt)
  local arena = main.current
  if arena and (self.y < arena.y1 - 8 or self.y > arena.y2 + 8) then self.dead = true end
end

function AllyCritter:draw()
  graphics.circle(self.x, self.y, self.r_size + 0.5, bg[-2])
  graphics.circle(self.x, self.y, self.r_size, self.color)
  graphics.circle(self.x - self.r_size*0.3, self.y - self.r_size*0.3, math.max(0.6, self.r_size*0.3), fg[5])
end

function AllyCritter:on_brick_contact(brick)
  if brick.dead then return end
  if brick.on_ball_contact then
    brick:on_ball_contact(self)
  elseif brick.take_damage then
    brick:take_damage(self.dmg, self.color)
  end
  spawn_burst(main.current.effects, self.x, self.y, self.color, 4, 60, 110)
  self.dead = true
end

function AllyCritter:take_damage() end


-- Wave-10 Boss: "The Prism Core".
--
-- A single large, freely-moving geometric construct that floats in the upper
-- third of the arena and fires bullet-hell patterns. Tagged 'brick' so the
-- existing ball/brick collision matrix lets hero balls damage it and bounce.
-- Has three HP-banded phases that unlock new attacks and shift its color.
-- On death the arena's boss_defeated flag is set and BallPit:update advances
-- to the next wave.
Boss = Object:extend()
Boss:implement(GameObject)
Boss:implement(Physics)


-- Phase color targets. The boss tweens from red → orange → purple as HP
-- drops, telegraphing escalation without needing dialog or UI text.
local BOSS_PHASE_COLORS = {
  function() return red[0]    end,
  function() return orange[0] end,
  function() return purple[0] end,
}


function Boss:init(args)
  self:init_game_object(args)
  self.r_outer = 28
  self.r_inner = 14

  -- HP scales with wave the same way bricks do (see Brick:init) so the
  -- fight stays meaningful if the player triggers it on a later loop.
  local wave = (main.current and main.current.wave) or 10
  self.max_hp     = 2400 * (1 + 0.2*wave)
  self.hp         = self.max_hp
  self.player_dmg = 3
  self.xp_value   = 60

  self.phase      = 1
  self.color      = BOSS_PHASE_COLORS[1]()
  self.outer_rot  = 0
  self.inner_rot  = 0
  self.spawn_t    = 0
  self.intro_done = false

  -- Status-effect compatibility with hero abilities. Same shape as Brick.
  self.slow_factor = 1
  self.slow_timer  = 0
  self.burn_timer  = 0
  self.burn_dps    = 0
  self.curse_mult  = 1
  self.curse_timer = 0

  self:set_as_circle(self.r_outer, 'kinematic', 'brick')
  self:set_restitution(1)
  self:set_friction(0)
  self.hfx:add('hit', 1)

  -- Movement anchor: where the boss orbits around. y stays high so it never
  -- breaches the paddle line.
  local arena = main.current
  self.x_anchor = (arena and arena:arena_center_x()) or gw/2
  self.y_anchor = self.y

  spawn1:play{volume = 0.5, pitch = 0.7}

  -- Schedule attacks. Phase 3 also runs a separate minion-drop timer started
  -- on phase transition (see enter_phase). Boss starts attacking after a
  -- short grace so the player has a moment to read the spawn.
  self.t:after(1.6, function()
    self.t:every({2.4, 3.4}, function() self:choose_attack() end, 0, nil, 'boss_atk')
  end)
end


function Boss:enter_phase(phase)
  if phase <= self.phase then return end
  self.phase = phase
  self.color = BOSS_PHASE_COLORS[phase]()
  spawn_burst(main.current.effects, self.x, self.y, self.color, 18, 80, 220)
  Flash{group = main.current.effects, x = gw/2, y = gh/2,
        color = Color(self.color.r, self.color.g, self.color.b, 0.35), duration = 0.18}
  TelegraphRing{group = main.current.effects, x = self.x, y = self.y,
                radius = 80, color = self.color, duration = 0.6}

  -- Speed up the attack timer slightly on each phase transition. Phase 3
  -- additionally spawns critter minions on its own cadence.
  if phase == 3 then
    self.t:cancel('boss_atk')
    self.t:every({1.6, 2.4}, function() self:choose_attack() end, 0, nil, 'boss_atk')
    self.t:every({5, 7}, function() self:spawn_minions() end, 0, nil, 'boss_minions')
  elseif phase == 2 then
    self.t:cancel('boss_atk')
    self.t:every({2.0, 2.9}, function() self:choose_attack() end, 0, nil, 'boss_atk')
  end
end


function Boss:choose_attack()
  if self.dead then return end
  -- Attack pool unlocks with phase. Phase 1 alternates spiral + aimed
  -- shotgun; phase 2 adds the 360° ring blast.
  local pool
  if self.phase == 1 then
    pool = {'spiral', 'shotgun'}
  elseif self.phase == 2 then
    pool = {'spiral', 'shotgun', 'ring'}
  else
    pool = {'spiral', 'shotgun', 'ring', 'shotgun'}  -- shotgun doubled = more aimed pressure
  end
  local pick = pool[random:int(1, #pool)]
  if     pick == 'spiral'  then self:attack_spiral()
  elseif pick == 'shotgun' then self:attack_shotgun()
  elseif pick == 'ring'    then self:attack_ring() end
end


-- Spiral barrage: 16 projectiles fired one every 0.1 sec while the firing
-- angle rotates. Reads as a turning bullet spiral.
function Boss:attack_spiral()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 22,
                color = self.color, duration = 0.25}
  shoot1:play{volume = 0.3, pitch = 0.85}
  local base = random:float(0, 2*math.pi)
  local dir  = random:bool(50) and 1 or -1
  for i = 0, 15 do
    self.t:after(i*0.1, function()
      if arena.main and arena.main.world and not self.dead then
        local a = base + dir * i * 0.42
        -- Boss spiral: slow, matches the spiraler enemy's bullet tempo so
        -- both attack types read as "swirling, lingering" threats.
        EnemyProjectile{group = arena.main, x = self.x, y = self.y, color = self.color,
                        kind = 'boss_orb', angle = a, speed = 55, r_size = 3.2, life = 4}
      end
    end)
  end
end


-- Aimed shotgun: 0.4s telegraph at paddle position, then a 5-shot fan aimed
-- at the paddle's location at the moment of fire.
function Boss:attack_shotgun()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = arena.paddle.x, y = arena.paddle.y - 4,
                radius = 16, color = self.color, duration = 0.4}
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 16,
                color = self.color, duration = 0.4}
  self.t:after(0.4, function()
    if arena.main and arena.main.world and not self.dead then
      shoot1:play{volume = 0.32, pitch = 0.95}
      local base = math.atan2(arena.paddle.y - self.y, arena.paddle.x - self.x)
      for _, off in ipairs({-0.32, -0.16, 0, 0.16, 0.32}) do
        -- Boss shotgun: fast 5-shot fan. Faster than the boss ring blast so
        -- the aimed pattern feels more urgent than the radial spray.
        EnemyProjectile{group = arena.main, x = self.x, y = self.y, color = self.color,
                        kind = 'boss_orb', angle = base + off, speed = 110, dmg = 2, r_size = 4}
      end
    end
  end)
end


-- Ring blast: 0.6s expanding telegraph, then 18 projectiles fired outward in
-- a perfect 360° circle.
function Boss:attack_ring()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 50,
                color = self.color, duration = 0.6}
  self.t:after(0.6, function()
    if arena.main and arena.main.world and not self.dead then
      shoot1:play{volume = 0.4, pitch = 0.8}
      explosion1:play{volume = 0.25, pitch = 1.3}
      Flash{group = arena.effects, x = gw/2, y = gh/2,
            color = Color(self.color.r, self.color.g, self.color.b, 0.25), duration = 0.1}
      for i = 0, 17 do
        local a = i*(2*math.pi/18)
        -- Boss ring blast: medium speed. The 360° wall is a wide spray, so
        -- a moderate speed gives players room to slip between adjacent shots.
        EnemyProjectile{group = arena.main, x = self.x, y = self.y, color = self.color,
                        kind = 'boss_orb', angle = a, speed = 80, life = 4}
      end
    end
  end)
end


function Boss:spawn_minions()
  if self.dead then return end
  local arena = main.current
  if not (arena.main and arena.main.world) then return end
  critter1:play{volume = 0.3, pitch = random:float(0.9, 1.05)}
  for _ = 1, 2 do
    local cx = self.x + random:float(-16, 16)
    local cy = self.y + 18
    arena.t:after(0, function()
      if arena.main and arena.main.world then
        EnemyCritter{group = arena.main, x = cx, y = cy, color = self.color}
      end
    end)
  end
end


function Boss:update(dt)
  self:update_game_object(dt)
  self.spawn_t = self.spawn_t + dt

  -- Phase-banded movement speed: every phase moves faster, increasing
  -- pressure as HP drops.
  local speed_factor = (self.phase == 1) and 1.0 or (self.phase == 2 and 1.3 or 1.6)
  self.outer_rot = self.outer_rot + dt * 0.9 * speed_factor
  self.inner_rot = self.inner_rot - dt * 1.4 * speed_factor

  -- Slow status reduces movement + attack rate uniformly.
  if self.slow_timer > 0 then
    self.slow_timer = self.slow_timer - dt
    if self.slow_timer <= 0 then self.slow_factor = 1 end
    speed_factor = speed_factor * self.slow_factor
  end

  -- Burn DoT: same shape as Brick's burn handling.
  if self.burn_timer > 0 then
    self.burn_timer = self.burn_timer - dt
    self:take_damage(self.burn_dps*dt, orange[0], true)
    if random:bool(15) then
      HitParticle{
        group = main.current.effects,
        x = self.x + random:float(-self.r_outer*0.6, self.r_outer*0.6),
        y = self.y - self.r_outer*0.6,
        color = orange[0], v = 30, r = -math.pi/2, w = 2, duration = 0.3,
      }
    end
  end

  if self.curse_timer > 0 then
    self.curse_timer = self.curse_timer - dt
    if self.curse_timer <= 0 then self.curse_mult = 1 end
  end

  -- Sinusoidal hover. arena_w*0.32 keeps the boss within the play area.
  local arena   = main.current
  local arena_w = (arena and (arena.x2 - arena.x1)) or gw
  local t       = self.spawn_t * speed_factor
  local nx = self.x_anchor + math.sin(t*0.6) * (arena_w*0.32)
  local ny = self.y_anchor + math.sin(t*1.1) * 4
  self:set_position(nx, ny)
end


function Boss:on_ball_contact(ball)
  -- Hero ball collided with the boss. Match the Brick contact flow but skip
  -- the formation knockback path (boss is solo).
  if self.hp <= 0 then return end
  local dmg = ball.dmg*(ball.charge_dmg_mult or 1)
  self:take_damage(dmg, ball.color)
end


function Boss:take_damage(amount, color, no_flash)
  if self.hp <= 0 then return end
  amount = amount * (self.curse_mult or 1)
  self.hp = self.hp - amount
  if not no_flash then
    self.hfx:use('hit', 0.25, 200, 10)
    spawn_burst(main.current.effects, self.x, self.y, color or self.color, 4, 50, 130)
  end

  -- Phase transitions at the 2/3 and 1/3 HP marks.
  if self.phase < 2 and self.hp <= self.max_hp*(2/3) then self:enter_phase(2) end
  if self.phase < 3 and self.hp <= self.max_hp*(1/3) then self:enter_phase(3) end

  if self.hp <= 0 then self:die() end
end


function Boss:die()
  local arena = main.current
  -- Tell the arena XP/score systems we died, same hook as bricks use.
  arena:on_brick_killed(self)

  -- Big celebratory effects.
  spawn_burst(arena.effects, self.x, self.y, self.color, 60, 80, 280)
  spawn_burst(arena.effects, self.x, self.y, fg[5],      24, 60, 220)
  Flash{group = arena.effects, x = gw/2, y = gh/2, color = white_transparent_weak, duration = 0.25}
  explosion1:play{volume = 0.7, pitch = 0.7}
  enemy_die1:play{volume = 0.6, pitch = 0.6}

  -- Big XP drop so the player gets a meaningful payoff and likely level-up.
  local x, y, v = self.x, self.y, self.xp_value
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      XpOrb{group = arena.main, x = x, y = y, value = v}
    end
  end)

  arena.boss_defeated = true
  self.dead = true
end


function Boss:apply_slow(factor, duration)
  if factor < self.slow_factor then self.slow_factor = factor end
  if duration > self.slow_timer then self.slow_timer = duration end
end


function Boss:apply_burn(dps, duration)
  self.burn_dps   = math.max(self.burn_dps, dps)
  self.burn_timer = math.max(self.burn_timer, duration)
end


function Boss:apply_curse(color, mult, duration)
  self.curse_mult  = math.max(self.curse_mult or 1, mult or 1.4)
  self.curse_timer = math.max(self.curse_timer or 0, duration or 6)
end


function Boss:draw()
  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local dark = Color(col.r*0.45, col.g*0.45, col.b*0.45, 1)

  -- Outer 12-sided ring, drawn as a polygon outline.
  local verts_out = {}
  for i = 0, 11 do
    local a = self.outer_rot + i*(2*math.pi/12)
    table.insert(verts_out, self.x + math.cos(a)*self.r_outer*s)
    table.insert(verts_out, self.y + math.sin(a)*self.r_outer*s)
  end
  graphics.polygon(verts_out, dark)
  graphics.polygon(verts_out, col, 2)

  -- Inner counter-rotating hexagon.
  local verts_in = {}
  for i = 0, 5 do
    local a = self.inner_rot + i*(2*math.pi/6)
    table.insert(verts_in, self.x + math.cos(a)*self.r_inner*s)
    table.insert(verts_in, self.y + math.sin(a)*self.r_inner*s)
  end
  graphics.polygon(verts_in, col)
  graphics.polygon(verts_in, fg[5], 1)

  -- Bright pulsing core.
  local pulse = 1 + math.sin(love.timer.getTime()*6)*0.25
  graphics.circle(self.x, self.y, 3*pulse*s, fg[5])

  -- HP bar across the top of the play area.
  local arena = main.current
  if arena then
    local pct   = math.clamp(self.hp/self.max_hp, 0, 1)
    local bar_w = (arena.x2 - arena.x1) - 16
    local bar_x = (arena.x1 + arena.x2)/2
    local bar_y = arena.y1 + 4
    graphics.rectangle(bar_x, bar_y, bar_w, 4, 1, 1, bg[-2])
    graphics.rectangle(bar_x - bar_w/2 + bar_w*pct/2, bar_y, bar_w*pct, 4, 1, 1, col)
    graphics.print_centered('THE PRISM CORE', pixul_font,
                            bar_x, bar_y + 8, 0, 1, 1, 0, 0, fg[0])
  end

  -- Slow / curse visual overlays, mirror Brick:draw idioms.
  if self.slow_factor < 1 then
    graphics.circle(self.x, self.y, self.r_outer*1.1, blue_transparent_weak)
  end
  if (self.curse_mult or 1) > 1 then
    local cp = 0.5 + 0.2*math.sin(love.timer.getTime()*5)
    graphics.circle(self.x, self.y, self.r_outer*1.15,
                    Color(purple[0].r, purple[0].g, purple[0].b, 0.35*cp), 1.5)
  end
end
