-- Lightweight projectile fired by certain hero abilities (vagrant, archer, scout).
-- It travels in a straight line, optionally pierces and ricochets.

Projectile = Object:extend()
Projectile:implement(GameObject)
Projectile:implement(Physics)


function Projectile:init(args)
  self:init_game_object(args)
  self.dmg      = self.dmg or 8
  self.speed    = self.speed or 220
  self.pierce   = self.pierce or 0
  self.ricochet = self.ricochet or 0
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
