-- XP gem dropped when a brick is destroyed. Drifts down slowly and is sucked
-- toward the paddle once it gets close (vampire-survivors pickup feel).

-- Downward acceleration applied to a free-falling orb (px/s2). Shared by the
-- pop-out window and the out-of-magnet-range branch in :update.
local XP_GRAVITY = 55

-- Spawn-out: an orb swells to size as it ejects from the brick rather than
-- appearing at full size, which pairs with the scatter velocity below so a
-- kill visibly THROWS its XP instead of stamping it into the world.
local XP_SPAWN_DUR = 0.12

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
  -- Muted further: blended toward neutral, dimmed, and more transparent than
  -- before. Two reasons. A cleared swarm dumps dozens of these at once and
  -- they were still reading as a wall of beads; and enemy fire is now a single
  -- red with a bloom on it (see EnemyProjectile:draw_glow), which only works
  -- as a danger signal if the harmless pickups stay quiet by comparison.
  local MUTE, GREY, DIM = 0.35, 0.42, 0.75
  local function mute(v) return (v + (GREY - v)*MUTE)*DIM end
  self.color  = Color(mute(ramp[0].r), mute(ramp[0].g), mute(ramp[0].b), 0.4)
  self.r_size = self.value >= 5 and 1.8 or (self.value >= 2 and 1.4 or 1.1)
  -- Magnet range — the paddle pulls in any orb within this radius. Widened
  -- over time (64 -> 88 -> 130 -> 200) so the paddle vacuums up a whole column
  -- of falling XP without having to pass directly under each orb. Applies to
  -- every paddle; the terrorist loadout below still overrides it to field-wide.
  self.magnet_range = 200
  -- Terrorist paddle: auto-collect — every orb magnets in from anywhere on the
  -- field so the player never chases XP (leveling, which auto-arms balls, is the
  -- whole loop). A field-spanning range means the magnet branch always wins.
  local arena = main.current
  if arena and arena.run_mods and arena.run_mods.signature == 'terrorist' then
    self.magnet_range = 100000
  end
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

  self.spawn_t = 0

  self.t:after(self.life, function() self.dead = true end)
end


-- 0 -> 1 as the orb pops out, eased.
function XpOrb:spawn_k()
  local p = math.clamp((self.spawn_t or 0)/XP_SPAWN_DUR, 0, 1)
  return 1 - (1 - p)*(1 - p)*(1 - p)
end


function XpOrb:update(dt)
  self:update_game_object(dt)
  if (self.spawn_t or 0) < XP_SPAWN_DUR then self.spawn_t = (self.spawn_t or 0) + dt end

  local arena = main.current
  local px, py = arena.paddle.x, arena.paddle.y
  local d = math.distance(self.x, self.y, px, py)

  -- Initial pop-out: let the scatter velocity from :init carry the orb for a
  -- brief moment so it visually "ejects" from the brick.
  if self.magnet_delay > 0 then
    self.magnet_delay = self.magnet_delay - dt
    local vx, vy = self:get_velocity()
    self:set_velocity(vx, vy + XP_GRAVITY*dt)

  elseif d < self.magnet_range then
    -- In magnet range: hard snap toward the paddle (vampire-survivors-style
    -- pickup feel). Pull strength ramps up as the orb gets closer; the whole
    -- curve was boosted (150/50 -> 320/140 px/s) so caught orbs leap in fast.
    local ang  = math.atan2(py - self.y, px - self.x)
    local pull = math.remap(d, 0, self.magnet_range, 320, 140)
    self:set_velocity(math.cos(ang)*pull, math.sin(ang)*pull)

  else
    -- Out of magnet range: gentle gravity. Lowered again (160 -> 95 -> 55 px/s²)
    -- so orbs drift down noticeably more slowly and the widened magnet has time
    -- to catch them, but still well clear of the original 30 px/s² that let
    -- them stall at the damping-imposed ~15 px/s terminal velocity. Missed orbs
    -- keep falling through the bottom and despawn within the life timer rather
    -- than hanging in mid-air — a real pickup penalty.
    local vx, vy = self:get_velocity()
    self:set_velocity(vx, vy + XP_GRAVITY*dt)
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
  graphics.circle(self.x, self.y, self.r_size*s*self:spawn_k(), self.color)
end
