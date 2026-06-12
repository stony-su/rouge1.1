-- Lightweight projectile fired by certain hero abilities (vagrant, archer, scout).
-- It travels in a straight line, optionally pierces, ricochets, or CHAINS
-- (the SNKRX scout port: leaps to a random nearby target it hasn't hit yet,
-- speeding up — and optionally ramping damage — on every hop).

Projectile = Object:extend()
Projectile:implement(GameObject)
Projectile:implement(Physics)


function Projectile:init(args)
  self:init_game_object(args)
  self.dmg      = self.dmg or 8
  self.speed    = self.speed or 220
  self.pierce   = self.pierce or 0
  self.ricochet = self.ricochet or 0
  self.chain    = self.chain or 0
  self.color    = self.color or fg[0]
  self.type     = self.type or 'arrow'
  self.life     = self.life or 1.5
  self.hits     = {}

  self:set_as_circle(2, 'dynamic', 'projectile')
  self.body:setBullet(true)
  self:set_fixed_rotation(false)
  self:set_restitution(1)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.1)
  self:set_velocity(math.cos(self.r)*self.speed, math.sin(self.r)*self.speed)
  self:set_angle(self.r)

  self.t:after(self.life, function() self.dead = true end)

  self.on_collision_enter = function(p, other, contact)
    if other and other.tag == 'brick' then
      p:on_hit_brick(other)
    end
  end
end


function Projectile:update(dt)
  self:update_game_object(dt)
  -- Keep angle aligned with motion.
  local vx, vy = self:get_velocity()
  if vx ~= 0 or vy ~= 0 then self:set_angle(math.atan2(vy, vx)) end

  -- Out of arena = die.
  local arena = main.current
  if self.x < arena.x1 - 20 or self.x > arena.x2 + 20 or self.y < arena.y1 - 20 or self.y > arena.y2 + 20 then
    self.dead = true
  end
end


function Projectile:draw()
  local r = self:get_angle() or 0
  graphics.push(self.x, self.y, r)
    if self.type == 'arrow' then
      graphics.rectangle(self.x, self.y, 8, 2, nil, nil, self.color)
      graphics.triangle(self.x + 4, self.y, 3, 3, self.color)
    else
      graphics.rectangle(self.x, self.y, 6, 2, nil, nil, self.color)
    end
  graphics.pop()
end


function Projectile:on_hit_brick(brick)
  if self.hits[brick.id] then return end
  self.hits[brick.id] = true
  brick:take_damage(self.dmg, self.color)

  if self.pierce > 0 then
    self.pierce = self.pierce - 1
    return
  end

  -- SNKRX scout chain: leap to a RANDOM brick within 48px that this knife
  -- hasn't hit yet, gaining +25% speed per hop (and +25% damage per hop when
  -- chain_dmg_ramp is set — the scout's level-3 passive). If nothing is in
  -- leap range the knife flies on and may still chain off whatever it meets.
  if self.chain > 0 then
    self.chain = self.chain - 1
    local arena = main.current
    spawn_burst(arena.effects, self.x, self.y, fg[0], 3, 50, 110)
    HitParticle{group = arena.effects, x = self.x, y = self.y, color = self.color}
    HitParticle{group = arena.effects, x = self.x, y = self.y, color = brick.color}
    -- SNKRX plays the impact sound on every chain hit, found target or not.
    hit2:play{pitch = random:float(0.95, 1.05), volume = 0.35}
    local candidates = {}
    for _, o in ipairs(arena.main.objects) do
      if o:is(Brick) and not o.dead and not self.hits[o.id]
      and math.distance(self.x, self.y, o.x, o.y) <= 48 then
        candidates[#candidates + 1] = o
      end
    end
    if #candidates > 0 then
      local target = candidates[random:int(1, #candidates)]
      self.speed = self.speed*1.25
      if self.chain_dmg_ramp then self.dmg = self.dmg*1.25 end
      local ang = math.atan2(target.y - self.y, target.x - self.x)
      self:set_velocity(math.cos(ang)*self.speed, math.sin(ang)*self.speed)
    end
    return
  end

  if self.ricochet > 0 then
    self.ricochet = self.ricochet - 1
    local arena = main.current
    local nearest = arena:get_nearest_brick(self.x, self.y, brick)
    if nearest then
      local ang = math.atan2(nearest.y - self.y, nearest.x - self.x)
      self:set_velocity(math.cos(ang)*self.speed, math.sin(ang)*self.speed)
    else
      self.dead = true
    end
    return
  end

  self.dead = true
end
