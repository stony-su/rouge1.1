-- XP gem dropped when a brick is destroyed. Drifts down slowly and is sucked
-- toward the paddle once it gets close (vampire-survivors pickup feel).

XpOrb = Object:extend()
XpOrb:implement(GameObject)
XpOrb:implement(Physics)


function XpOrb:init(args)
  self:init_game_object(args)
  self.value  = self.value or 1
  -- Muted, semi-transparent dots. A cleared swarm dumps a lot of XP at once;
  -- the old bright beads (full-alpha fill + dark outline + specular pip) piled
  -- up and cluttered the arena, so keep each orb small and low-contrast -- a
  -- shower now reads as a faint scatter you can see through. Value still tints
  -- the orb (blue < green < yellow) and nudges its size, just more subtly.
  local ramp  = self.value >= 5 and yellow or (self.value >= 2 and green or blue)
  self.color  = Color(ramp[0].r, ramp[0].g, ramp[0].b, 0.6)
  self.r_size = self.value >= 5 and 2.5 or (self.value >= 2 and 2 or 1.5)
  -- Magnet range — the paddle pulls in any orb within this radius. Widened
  -- over time (64 -> 88 -> 130) so the paddle vacuums up a whole column of
  -- falling XP without having to pass directly under each orb.
  self.magnet_range = 130
  -- Short pop-out window so the orb's initial scatter velocity from :init is
  -- visible before gravity / magnet takes over.
  self.magnet_delay = 0.35
  -- Lifetime safety net. With the gentle gravity below, an unpicked orb still
  -- drifts off the bottom of the arena well within this window on its own, so
  -- this only fires if a physics edge case strands an orb in mid-air.
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
    self:set_velocity(vx, vy + 95*dt)

  elseif d < self.magnet_range then
    -- In magnet range: hard snap toward the paddle (vampire-survivors-style
    -- pickup feel). Pull strength ramps up as the orb gets closer; the whole
    -- curve was boosted (150/50 -> 320/140 px/s) so caught orbs leap in fast.
    local ang  = math.atan2(py - self.y, px - self.x)
    local pull = math.remap(d, 0, self.magnet_range, 320, 140)
    self:set_velocity(math.cos(ang)*pull, math.sin(ang)*pull)

  else
    -- Out of magnet range: gentle gravity. Lowered from 160 px/s² so orbs
    -- drift down noticeably more slowly, but still well clear of the original
    -- 30 px/s² that let them stall at the damping-imposed ~15 px/s terminal
    -- velocity. Missed orbs keep falling through the bottom and despawn within
    -- the life timer rather than hanging in mid-air — a real pickup penalty.
    local vx, vy = self:get_velocity()
    self:set_velocity(vx, vy + 95*dt)
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
  -- Single soft dot: no dark outline ring or bright specular pip, so clustered
  -- orbs blend into a faint scatter instead of a wall of beads.
  graphics.circle(self.x, self.y, self.r_size*s, self.color)
end
