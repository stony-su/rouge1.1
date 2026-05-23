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
  self.r_size = 2.5
  self.color  = self.color or fg[0]
  self.speed  = self.speed or 60
  self.dmg    = self.dmg or 1

  self:set_as_circle(self.r_size, 'dynamic', 'brick')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(0)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.2)
  self:set_velocity(0, self.speed)
  self.hfx:add('hit', 1)
end

function EnemyProjectile:update(dt)
  self:update_game_object(dt)
  local arena = main.current
  if self.y > arena.y2 + 4 then self.dead = true end
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
end

function EnemyProjectile:draw()
  local s = self.hfx.hit.x
  local col = self.hfx.hit.f and fg[0] or self.color
  graphics.circle(self.x, self.y, self.r_size + 0.5, bg[-2])
  graphics.circle(self.x, self.y, self.r_size*s, col)
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
