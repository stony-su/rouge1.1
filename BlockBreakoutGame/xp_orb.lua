-- XP gem dropped when a brick is destroyed. Drifts down slowly and is sucked
-- toward the paddle once it gets close (vampire-survivors pickup feel).

XpOrb = Object:extend()
XpOrb:implement(GameObject)
XpOrb:implement(Physics)


function XpOrb:init(args)
  self:init_game_object(args)
  self.value  = self.value or 1
  self.color  = self.value >= 5 and yellow[0] or (self.value >= 2 and green[0] or blue[0])
  self.r_size = self.value >= 5 and 3.5 or (self.value >= 2 and 3 or 2.5)
  -- Finite magnet range — the paddle has to get reasonably close before the
  -- orb snaps in. Slightly wider than the original 64 so a paddle traveling
  -- along the bottom can sweep up a column of falling orbs without having to
  -- be perfectly underneath each one.
  self.magnet_range = 88
  -- Short pop-out window so the orb's initial scatter velocity from :init is
  -- visible before gravity / magnet takes over.
  self.magnet_delay = 0.35
  -- Lifetime safety net. With the stronger gravity below, an unpicked orb
  -- falls off the bottom of the arena in ~6 s on its own, so this only fires
  -- if a physics edge case strands an orb in mid-air.
  self.life   = 20

  self:set_as_circle(self.r_size, 'dynamic', 'xp')
  self:set_fixed_rotation(true)
  self:set_restitution(0.2)
  self:set_friction(0)
  self:set_damping(2)
  self:set_mass(0.1)

  self:set_velocity(random:float(-30, 30), random:float(-20, -50))

  self.t:after(self.life, function() self.dead = true end)
end


function XpOrb:update(dt)
  self:update_game_object(dt)

  local arena = main.current
  local px, py = arena.paddle.x, arena.paddle.y
  local d = math.distance(self.x, self.y, px, py)

  -- Initial pop-out: let the scatter velocity from :init carry the orb for a
  -- brief moment so it visually "ejects" from the brick.
  if self.magnet_delay > 0 then
    self.magnet_delay = self.magnet_delay - dt
    local vx, vy = self:get_velocity()
    self:set_velocity(vx, vy + 160*dt)

  elseif d < self.magnet_range then
    -- In magnet range: full snap toward the paddle (vampire-survivors-style
    -- pickup feel). Pull strength ramps up as the orb gets closer.
    local ang  = math.atan2(py - self.y, px - self.x)
    local pull = math.remap(d, 0, self.magnet_range, 240, 60)
    self:set_velocity(math.cos(ang)*pull, math.sin(ang)*pull)

  else
    -- Out of magnet range: gravity. Bumped up from the original 30 px/s² so
    -- orbs actually reach the bottom of the arena in a few seconds instead
    -- of stalling out at the damping-imposed ~15 px/s terminal velocity and
    -- vanishing in place when the 18 s life timer expired. Missed orbs now
    -- visibly fall through the bottom and despawn — a real pickup penalty.
    local vx, vy = self:get_velocity()
    self:set_velocity(vx, vy + 160*dt)
  end

  if d < 8 then
    arena:gain_xp(self.value)
    orb1:play{volume = 0.2, pitch = random:float(1.0, 1.15)}
    spawn_burst(arena.effects, self.x, self.y, self.color, 4, 40, 80)
    self.dead = true
  end

  -- Despawn once the orb falls off the bottom of the arena.
  if self.y > arena.y2 + 20 then self.dead = true end
end


function XpOrb:draw()
  self.spring:pull(0)
  local s = self.spring.x
  graphics.circle(self.x, self.y, self.r_size + 0.5, bg[-2])
  graphics.circle(self.x, self.y, self.r_size*s, self.color)
  graphics.circle(self.x - self.r_size*0.3, self.y - self.r_size*0.3, math.max(0.5, self.r_size*0.3), fg[5])
end
