-- Powerup: a falling pickup that triggers a one-shot effect when caught.
--
-- Adapted from XpOrb (same falling + Box2D body), with two pickup tiers:
--
--   tier 1 (standard)  : first paddle contact applies the effect, like XP.
--   tier 2 (deflect)   : first paddle contact bounces the orb upward and arms
--                        it; the player must catch the orb on its second
--                        descent. Misses fizzle. This is the Breakout-style
--                        "earn it" gate for stronger effects.
--
-- Pickup is detected by a proximity check inside :update (the orb's group
-- collision is disabled against ball/projectile/wall etc., so we drive the
-- "caught" event from distance to the paddle, same as XPOrb does).

Powerup = Object:extend()
Powerup:implement(GameObject)
Powerup:implement(Physics)


-- Static description table: per-kind label, color, glyph, tier, and an
-- arena-side apply function reference (resolved by name on use so we don't
-- have to forward-declare). Tier 1 = standard catch, Tier 2 = deflect-and-
-- catch. Glyph is a single ASCII char for the pixul font.
Powerup.KINDS = {
  heal          = {label = 'heal',     color = 'green',   glyph = '+',  tier = 1},
  wide_paddle   = {label = 'wide',     color = 'yellow',  glyph = 'W',  tier = 1},
  big_ball      = {label = 'big',      color = 'orange',  glyph = 'O',  tier = 1},
  fire_trail    = {label = 'fire',     color = 'red',     glyph = 'F',  tier = 1},
  freeze_wave   = {label = 'freeze',   color = 'blue',    glyph = '*',  tier = 1},

  water_wave    = {label = 'water',    color = 'blue2',   glyph = '~',  tier = 2},
  multi_ball    = {label = 'multi',    color = 'green',   glyph = 'M',  tier = 2},
  pierce        = {label = 'pierce',   color = 'purple',  glyph = 'P',  tier = 2},
  floor         = {label = 'floor',    color = 'yellow2', glyph = '_',  tier = 2},
  -- The "level-up ball" -- levels up your ball-heroes. `solo` keeps it OUT of
  -- the generic tier_*_kinds pools below: it has its own spawn cadence
  -- (BallPit:tick_levelup_pity) and its own distinct draw (Powerup:draw_level_rune).
  level_random  = {label = 'lvl',      color = 'yellow',  glyph = 'L',  tier = 2, solo = true},
}


-- Helpers used by the generic random-powerup spawners (pity roll + wave-end
-- drop) and the admin terminal. `solo` kinds are deliberately excluded -- they
-- spawn on their own dedicated timers instead of the shared pools.
function Powerup.tier_1_kinds()
  local out = {}
  for k, v in pairs(Powerup.KINDS) do if v.tier == 1 and not v.solo then table.insert(out, k) end end
  return out
end


function Powerup.tier_2_kinds()
  local out = {}
  for k, v in pairs(Powerup.KINDS) do if v.tier == 2 and not v.solo then table.insert(out, k) end end
  return out
end


function Powerup:init(args)
  self:init_game_object(args)
  self.kind   = self.kind or 'heal'
  local def   = Powerup.KINDS[self.kind] or Powerup.KINDS.heal
  self.tier   = def.tier
  self.color  = _G[def.color][0]
  self.glyph  = def.glyph
  self.label  = def.label
  self.r_size = self.tier == 2 and 5 or 4
  self.life   = 16
  self.armed  = false               -- tier-2 only; flips true after the first paddle bounce
  self.cant_catch = 0               -- cooldown so the same contact doesn't count twice
  self.deflect_count = 0            -- safety: cap to two deflects, then fizzle

  -- 'powerup' tag has wall collision ENABLED (see BallPit:reset_run) so the
  -- orb bounces off the left/right/top walls instead of phasing through and
  -- falling out of play. Everything else (paddle, ball, brick, projectile,
  -- xp, other powerups) is disabled in the matrix; paddle catches are driven
  -- by the proximity check in :update, not Box2D contacts.
  self:set_as_circle(self.r_size, 'dynamic', 'powerup')
  -- Free rotation: the orb is a real physics body that tumbles through the air.
  -- Walls are frictionless (see Wall:init) so bounces preserve spin, exactly as
  -- a real object would in a frictionless arena; angular damping bleeds it off
  -- slowly. :draw reads the visible spin straight off the body angle.
  self:set_fixed_rotation(false)
  self:set_restitution(0.85)                          -- lively bounce off side walls
  self:set_friction(0)
  self:set_damping(0.4)
  self:set_angular_damping(0.5)                       -- spin decays gently over its life
  self:set_mass(0.2)

  -- Small toss outward so the orb doesn't fall straight down on top of the
  -- brick that spawned it. Clamped to mostly-horizontal so the first bounce
  -- off a wall feels intentional, not chaotic. Pair it with a random tumble.
  self:set_velocity(random:float(-40, 40), random:float(-15, -45))
  self:set_angular_velocity(random:float(5, 9) * (random:float(0, 1) > 0.5 and 1 or -1))

  self.t:after(self.life, function() self.dead = true end)
end


function Powerup:update(dt)
  self:update_game_object(dt)

  local arena = main.current
  if not arena or not arena.paddle then return end
  local px, py = arena.paddle.x, arena.paddle.y

  if self.cant_catch > 0 then self.cant_catch = self.cant_catch - dt end

  -- Gentle fall. Tier-1 also magnet-pulls to the paddle (like XP); tier-2
  -- gets no magnet so the player has to actually position the paddle to
  -- intercept it.
  local vx, vy = self:get_velocity()
  if self.tier == 1 and not self.armed then
    local d = math.distance(self.x, self.y, px, py)
    if d < 80 then
      local ang  = math.atan2(py - self.y, px - self.x)
      local pull = math.remap(d, 0, 80, 220, 60)
      self:set_velocity(math.cos(ang)*pull, math.sin(ang)*pull)
    else
      self:set_velocity(vx, vy + 30*dt)
    end
  else
    self:set_velocity(vx, vy + 80*dt)   -- pure ballistic
  end

  -- Paddle proximity = touch. Use a box overlap (the paddle is wide and
  -- thin, so Euclidean distance gives false hits at the corners). Tier 1
  -- applies immediately; tier 2 arms on first contact, applies on the
  -- second after the cant_catch cooldown expires.
  local pw, ph = arena.paddle.w, arena.paddle.h
  local in_box = math.abs(self.x - px) <= pw/2 + self.r_size
             and math.abs(self.y - py) <= ph/2 + self.r_size + 1
  if self.cant_catch <= 0 and in_box then
    if self.tier == 1 or self.armed then
      self:apply_and_die()
    else
      self:deflect_off_paddle()
    end
  end

  -- Fell past the paddle without being caught. Tier-1: dead. Tier-2: same,
  -- since the deflect logic only flips armed when the paddle actually hits.
  if self.y > arena.y2 + 20 then self.dead = true end
end


-- Tier-2 deflect. Mirror the ball-paddle reflection: launch the orb up at an
-- angle that depends on where it hit the paddle (centre = straight up, edge =
-- diagonal), so the player has to read the angle and re-position.
function Powerup:deflect_off_paddle()
  local arena = main.current
  local pw    = arena.paddle.w
  local off   = math.clamp((self.x - arena.paddle.x)/(pw*0.5), -1, 1)
  local ang   = -math.pi/2 + off*(math.pi*0.32)
  local speed = 180
  self:set_velocity(math.cos(ang)*speed, math.sin(ang)*speed)
  self:set_angular_velocity(off * 16)                 -- edge hits impart visible english
  self.armed       = true
  self.cant_catch  = 0.18
  self.deflect_count = self.deflect_count + 1
  pop1:play{volume = 0.25, pitch = random:float(1.05, 1.2)}
  self.spring:pull(0.3)
  if self.deflect_count >= 3 then
    -- Safety: if the orb somehow keeps hitting the paddle, fizzle on the 3rd
    -- deflect so we don't get an infinite-bounce powerup.
    self:fizzle()
  end
end


function Powerup:apply_and_die()
  local arena = main.current
  arena:apply_powerup(self.kind, self.x, self.y, self.color)
  confirm1:play{volume = 0.35, pitch = random:float(1.0, 1.15)}
  spawn_burst(arena.effects, self.x, self.y, self.color, 8, 60, 140)
  self.dead = true
end


function Powerup:fizzle()
  local arena = main.current
  spawn_burst(arena.effects, self.x, self.y, fg_alt[0], 6, 40, 80)
  self.dead = true
end


-- Level-up "rune" look for the level-up orb (kind 'level_random'). A rune square
-- stamped with an up-arrow that tumbles with the physics body, wrapped in rings
-- that ripple outward from it like a level-up cast. The rings stay radial so the
-- ripple reads no matter how the rune is rotated; the deflect/arm logic is
-- unchanged and armed just ripples faster + brighter.
function Powerup:draw_level_rune()
  local now = time or 0
  local s   = self.spring.x
  local c   = self.color

  -- Expanding ripple rings emanate from the orb -- three on a staggered phase
  -- so a ripple is always in flight; each grows outward and fades as it goes.
  local period = self.armed and 0.7 or 1.3
  local r_min  = self.r_size * 1.2
  local r_max  = self.r_size * 4.0
  for i = 0, 2 do
    local ph = ((now/period) + i/3) % 1
    local rr = r_min + (r_max - r_min)*ph
    local a  = (1 - ph) * (self.armed and 0.65 or 0.45)
    graphics.circle(self.x, self.y, rr, Color(c.r, c.g, c.b, a), 1.5)
  end

  -- Soft square glow behind the rune; brighter + strobing when armed.
  local glow_a = self.armed and (0.4 + 0.25*math.abs(math.sin(now*10))) or 0.22
  graphics.rectangle(self.x, self.y, self.r_size*3.0, self.r_size*3.0, 2, 2,
    Color(c.r, c.g, c.b, glow_a))

  -- Body: the rune tumbles with the physics body, so rotate everything attached
  -- to it by the body angle -- dark backing for contrast on the bg grid, then
  -- the bright face. Scaled by the catch/deflect spring so it still pops when
  -- grabbed. The rings above stay radial so the ripple reads at any rotation.
  local ang = self:get_angle() or 0
  local sz  = self.r_size * 2.3 * s
  local aw  = self.r_size * 1.5 * s
  local ah  = self.r_size * 1.3 * s
  graphics.push(self.x, self.y, ang)
    graphics.rectangle(self.x, self.y, sz + 1.5, sz + 1.5, 2, 2, bg[-2])
    graphics.rectangle(self.x, self.y, sz, sz, 2, 2, c)
  graphics.pop()

  -- Stamped up-arrow: -pi/2 turns the right-facing triangle to point "up" within
  -- the rune; adding the body angle makes it tumble rigidly with the square.
  graphics.push(self.x, self.y, ang - math.pi/2)
    graphics.triangle(self.x, self.y, aw, ah, bg[-2])
  graphics.pop()
end


function Powerup:draw()
  self.spring:pull(0)
  if self.kind == 'level_random' then return self:draw_level_rune() end
  local s     = self.spring.x
  local now   = time or 0
  local pulse = 1 + 0.10*math.sin(now*7)
  -- Spin is read straight off the physics body, so what you see is the orb's
  -- real angular velocity tumbling through the air (and the english from a
  -- paddle deflect), not a cosmetic clock.
  local rot = self:get_angle() or 0

  local inner_sz = self.r_size * 1.9 * s * pulse
  local outer_sz = self.r_size * 2.7 * pulse

  -- Outer halo glow. Pulses brighter when armed (tier-2 mid-flight) so the
  -- catch-attempt-that-counts is unmistakable.
  local halo_a = self.armed and (0.55 + 0.35*math.abs(math.sin(now*10))) or 0.32
  local halo_c = Color(self.color.r, self.color.g, self.color.b, halo_a)
  graphics.push(self.x, self.y, rot + math.pi/4)
    graphics.rectangle(self.x, self.y, outer_sz*1.05, outer_sz*1.05, 1, 1, halo_c)
  graphics.pop()

  -- Body. Drawn as a rotated square (= diamond) so the orb is clearly NOT
  -- a ball or an XP orb. Dark backing for contrast against the bg grid,
  -- then the coloured face, then a small highlight quad for depth.
  graphics.push(self.x, self.y, rot + math.pi/4)
    graphics.rectangle(self.x, self.y, inner_sz + 1.5, inner_sz + 1.5, 1, 1, bg[-2])
    graphics.rectangle(self.x, self.y, inner_sz, inner_sz, 1, 1, self.color)
    -- Inner darker square for facet depth.
    graphics.rectangle(self.x, self.y, inner_sz*0.65, inner_sz*0.65, 1, 1,
      Color(self.color.r*0.65, self.color.g*0.65, self.color.b*0.85, 1))
  graphics.pop()

  -- Tier-2 outline, rigidly attached to the body (offset 45 deg from the face
  -- diamond so the pair reads as a spinning star). Pure yellow = "rare one".
  if self.tier == 2 then
    graphics.push(self.x, self.y, rot)
      graphics.rectangle(self.x, self.y, outer_sz, outer_sz, 1, 1, yellow[0], 1)
    graphics.pop()
  end

  -- Center glyph: NOT inside the rotated push, so the letter stays upright
  -- and readable while the diamond spins behind it.
  graphics.print_centered(self.glyph, pixul_font, self.x, self.y - 4, 0, 1, 1, 0, 0, fg[0])

  -- Sparkle: a few tiny offsets that orbit the diamond, sold as "this is
  -- not background scenery, grab me". Clock-driven so they keep orbiting even
  -- after the body's spin damps out.
  local spark_r = self.r_size + 4
  for i = 0, 2 do
    local a = now*2 + i*(math.pi*2/3)
    local sx, sy = self.x + math.cos(a)*spark_r, self.y + math.sin(a)*spark_r
    graphics.rectangle(sx, sy, 1.4, 1.4, nil, nil, fg[5])
  end
end
