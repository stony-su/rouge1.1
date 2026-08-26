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
-- catch. Glyph is a single ASCII char kept for text listings only -- the
-- in-world orb bodies are the per-kind vector ICONS painters above :draw.
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
  self.spawn_t = 0        -- muzzle-style spawn-out, see Powerup:spawn_k / :draw
  self.life   = 16
  self.armed  = false               -- tier-2 only; flips true once it has been bounced enough
  self.cant_catch = 0               -- cooldown so the same contact doesn't count twice
  self.deflect_count = 0            -- how many times the paddle has bounced it so far

  -- Tier-2 orbs must be deflected off the paddle before they can be caught.
  -- Generic ones need a single bounce; the level-up orb needs as many bounces as
  -- the levels it will grant (1-5, pre-rolled now) so the required bounce count
  -- IS a preview of the reward: more bounces to earn == more levels on the catch.
  self.level_amount   = (self.kind == 'level_random') and random:int(1, 5) or 0
  self.bounces_needed = (self.kind == 'level_random') and self.level_amount
                        or (self.tier == 2 and 1 or 0)

  -- Ballistic fall gravity. Ramps up on every bounce (see deflect_off_paddle) so
  -- each successive catch attempt drops faster -- the multi-bounce level orb gets
  -- progressively harder to read the deeper into its bounce chain you go.
  self.fall_gravity = 60

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

  self.t:after(self.life, function() self.dead = true end, 'despawn')
end


function Powerup:update(dt)
  self:update_game_object(dt)
  -- Ticked before the early-out below so the drop still swells to size on a
  -- frame where the arena or paddle isn't up yet.
  self.spawn_t = (self.spawn_t or 0) + dt

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
    self:set_velocity(vx, vy + self.fall_gravity*dt)   -- ballistic; gravity ramps each bounce
  end

  -- Paddle proximity = touch. Use a box overlap (the paddle is wide and
  -- thin, so Euclidean distance gives false hits at the corners). Tier 1
  -- applies immediately; tier 2 must be bounced bounces_needed times (1 for
  -- generic orbs, up to 5 for the level orb) before a contact finally applies.
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
  -- Culled off SCREEN rather than at the arena floor (see off_screen in
  -- shared.lua), so a missed drop is watched out of play instead of blinking
  -- away just short of the bottom. It still bounces off the side walls, so the
  -- bottom is the only way out -- that containment is what keeps it catchable.
  if off_screen(self.x, self.y, self.r_size) then self.dead = true end
end


-- Tier-2 deflect. Mirror the ball-paddle reflection: launch the orb up at an
-- angle that depends on where it hit the paddle (centre = straight up, edge =
-- diagonal), so the player has to read the angle and re-position.
function Powerup:deflect_off_paddle()
  local arena = main.current
  local pw    = arena.paddle.w
  local off   = math.clamp((self.x - arena.paddle.x)/(pw*0.5), -1, 1)
  local ang   = -math.pi/2 + off*(math.pi*0.32)
  local speed = 240                                   -- bounce launch; higher = pops up higher
  self:set_velocity(math.cos(ang)*speed, math.sin(ang)*speed)
  self.deflect_count = self.deflect_count + 1

  -- A successful bounce refreshes the despawn timer: as long as you keep the orb
  -- in play you never run out the clock mid-chain (only a whiff or 16s of total
  -- inactivity drops it). This is what fixes multi-bounce level orbs timing out.
  self.t:after(self.life, function() self.dead = true end, 'despawn')

  -- Spin english from where it hit, with a floor so a dead-centre bounce never
  -- freezes the tumble -- that floor is what keeps tier-2 orbs visibly spinning
  -- through the air instead of locking up the instant they touch the paddle.
  local spin = off * 14
  if math.abs(spin) < 6 then spin = (spin < 0 and -6 or 6) end
  self:set_angular_velocity(spin)

  -- Each bounce drops a little harder than the last: nudge the ballistic gravity
  -- up so successive descents get gradually faster and lower-arc, ramping the
  -- difficulty across a long multi-bounce chain without spiking it.
  self.fall_gravity = self.fall_gravity + 25

  -- Only arm (become catchable) once it has been bounced the required number of
  -- times; until then every paddle contact just bounces it again.
  if self.deflect_count >= self.bounces_needed then self.armed = true end

  self.cant_catch    = 0.18
  pop1:play{volume = 0.25, pitch = random:float(1.05, 1.2)}
  self.spring:pull(0.3)

  -- Safety: a couple of contacts past the point where it should have armed means
  -- something went wrong, so fizzle rather than bounce forever.
  if self.deflect_count >= self.bounces_needed + 2 then self:fizzle() end
end


function Powerup:apply_and_die()
  local arena = main.current
  arena:apply_powerup(self.kind, self.x, self.y, self.color, self.level_amount)
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

  -- Remaining-bounce pips: one dot per bounce still owed before the orb arms,
  -- drawn upright (not tumbling) above the rune so the player can read how many
  -- more deflects -- and therefore how many levels -- this orb is worth.
  local remaining = (self.bounces_needed or 0) - self.deflect_count
  if remaining > 0 then
    local gap   = 3
    local total = (remaining - 1) * gap
    local py    = self.y - self.r_size * 2.4
    for i = 0, remaining - 1 do
      graphics.rectangle(self.x - total/2 + i*gap, py, 1.8, 1.8, nil, nil, c)
    end
  end
end


-- Per-kind vector icon painters.
--
-- Every icon here is built from the SAME two ideas: a stack of plain geometric
-- layers (regular polygons, discs, bars) and at least one layer turning against
-- the others. Nothing tries to illustrate what the powerup does -- the read is
-- "which emblem is that", not "what does the picture mean" -- so each kind gets
-- its own polygon family and its own rotation signature instead:
--
--   heal        3   nested triangles, outer and inner counter-turning
--   wide_paddle 4   a turning square frame around rungs that stay level
--   big_ball    o   concentric breathing rings + one orbiting arc
--   water_wave  6   two hexagons scalloping past each other
--   multi_ball  3   beads carried on a turning triangular linkage
--   pierce      4+4 two squares crossed into a folding eight-point star
--   floor       5   a pentagon shell over a bar sweeping through it
--
-- fire_trail and freeze_wave keep their literal flame/snowflake.
--
-- Icons are drawn UPRIGHT (their own spins are clock-driven, not body-driven);
-- the physics tumble stays visible on the tier-2 outline ring in :draw. `s` is
-- the catch/deflect spring scale, `now` the shared clock.

-- Vertices of a regular n-gon: radius `rad` about (cx, cy), first vertex at
-- angle `a0`. This is the one construction the redesigned icons share, which is
-- what makes them read as a set rather than seven unrelated doodles.
local function ngon(cx, cy, rad, n, a0)
  local v = {}
  for i = 0, n - 1 do
    local a = a0 + i*(2*math.pi/n)
    v[#v + 1] = cx + math.cos(a)*rad
    v[#v + 1] = cy + math.sin(a)*rad
  end
  return v
end

-- Palette shims. Layers are separated by VALUE rather than by hue, so a stack
-- stays legible at 8px without any one layer having to shout.
local function dim(c, k)  return Color(c.r*k, c.g*k, c.b*k, 1) end
local function lift(c, k) return Color(c.r + (1 - c.r)*k, c.g + (1 - c.g)*k, c.b + (1 - c.b)*k, 1) end
local function fade(c, a) return Color(c.r, c.g, c.b, a) end

local ICONS = {}

-- Heal: three triangles on two clocks. The outer ring and the solid core turn
-- together while the mid plate turns back against them, so the silhouette folds
-- through a six-point star twice a revolution and then unwinds.
ICONS.heal = function(self, s, now)
  local c, r = self.color, self.r_size
  local x, y = self.x, self.y
  local a, b = now*0.8, -now*1.2

  graphics.circle(x, y, r*1.5*s, fade(bg[-2], 0.85))

  graphics.polygon(ngon(x, y, r*1.25*s, 3, b), dim(c, 0.5))

  local o = ngon(x, y, r*1.95*s, 3, a)
  graphics.polygon(o, bg[-2], 3.2)
  graphics.polygon(o, c, 1.3)

  graphics.polygon(ngon(x, y, r*0.70*s, 3, a + math.pi), lift(c, 0.35))
end

-- Wide: a square frame turning around three rungs that never tilt. The frame and
-- its contents disagreeing about which way is up is the whole trick; a bright pip
-- slides along the middle rung so the still layer isn't actually still.
ICONS.wide_paddle = function(self, s, now)
  local c, r = self.color, self.r_size
  local x, y = self.x, self.y

  local f = ngon(x, y, r*2.0*s, 4, now*0.55)
  graphics.polygon(f, bg[-2], 3)
  graphics.polygon(f, dim(c, 0.7), 1.2)

  -- Dark plates for all three rungs first, then the faces, so a rung's backing
  -- can never cut into the rung above it.
  local rw = {r*1.15*s, r*2.0*s, r*1.15*s}
  local rh = r*0.44*s
  for i = 1, 3 do
    graphics.rectangle(x, y + (i - 2)*r*0.74*s, rw[i] + 1.5, rh + 1.5, 1, 1, bg[-2])
  end
  for i = 1, 3 do
    graphics.rectangle(x, y + (i - 2)*r*0.74*s, rw[i], rh, 1, 1, i == 2 and c or dim(c, 0.8))
  end

  graphics.rectangle(x + math.sin(now*1.7)*r*0.78*s, y, r*0.36*s, r*0.36*s, nil, nil, fg[5])
end

-- Big: the only all-curve emblem in the set, so it reads instantly against the
-- polygon ones. A solid core under two rings breathing outward on a half-beat
-- offset, with one arc orbiting the pair to give the stack a direction to turn in.
ICONS.big_ball = function(self, s, now)
  local c, r = self.color, self.r_size
  local x, y = self.x, self.y
  local br   = r*0.80*s

  for i = 0, 1 do
    local ph = ((now*0.55) + i*0.5) % 1
    graphics.circle(x, y, br + 1.4 + ph*r*1.5, fade(c, (1 - ph)*0.5), 1.2)
  end

  graphics.circle(x, y, br + 1.1, bg[-2])
  graphics.circle(x, y, br, c)
  graphics.circle(x - br*0.32, y - br*0.32, br*0.34, fg[5])

  local ao, orb = now*1.05, r*1.7*s
  graphics.arc('open', x, y, orb, ao, ao + 1.2, bg[-2], 3)
  graphics.arc('open', x, y, orb, ao, ao + 1.2, lift(c, 0.3), 1.4)
  graphics.circle(x + math.cos(ao + 1.2)*orb, y + math.sin(ao + 1.2)*orb, r*0.26*s, fg[5])
end

-- Fire: a licking flame -- round base, swaying/fluttering tip, hot core.
ICONS.fire_trail = function(self, s, now)
  local c, r = self.color, self.r_size
  local fb  = r*0.95*s                                -- flame base radius
  local by  = self.y + r*0.45                         -- base sits low
  local tip = -r*1.9 - r*0.25*math.sin(now*13)        -- tip height flutters
  local tx  = r*0.30*math.sin(now*9)                  -- ...and sways
  graphics.circle(self.x, by, fb + 0.8, bg[-2])
  graphics.polygon({self.x - fb - 0.8, by, self.x + fb + 0.8, by, self.x + tx, by + tip - 1}, bg[-2])
  graphics.circle(self.x, by, fb, c)
  graphics.polygon({self.x - fb, by, self.x + fb, by, self.x + tx, by + tip}, c)
  local core = Color(1, 0.75, 0.35, 1)
  graphics.circle(self.x, by, fb*0.55, core)
  graphics.polygon({self.x - fb*0.55, by, self.x + fb*0.55, by, self.x + tx*0.6, by + tip*0.55}, core)
  graphics.circle(self.x, by - fb*0.2, fb*0.26, Color(1, 0.95, 0.7, 1))
end

-- Freeze: a six-armed snowflake, V-ticked arms, turning lazily.
ICONS.freeze_wave = function(self, s, now)
  local c, r = self.color, self.r_size
  local al = r*1.7*s                                  -- arm length
  local a0 = now*0.7                                  -- lazy cosmetic spin
  for i = 0, 5 do                                     -- dark under-strokes first
    local a = a0 + i*(math.pi/3)
    graphics.line(self.x, self.y, self.x + math.cos(a)*al, self.y + math.sin(a)*al, bg[-2], 2.5)
  end
  for i = 0, 5 do
    local a  = a0 + i*(math.pi/3)
    local ca, sa = math.cos(a), math.sin(a)
    graphics.line(self.x, self.y, self.x + ca*al, self.y + sa*al, c, 1.2)
    local bx, by = self.x + ca*al*0.6, self.y + sa*al*0.6
    for _, da in ipairs({0.6, -0.6}) do
      graphics.line(bx, by, bx + math.cos(a + da)*r*0.55, by + math.sin(a + da)*r*0.55, c, 1)
    end
  end
  graphics.circle(self.x, self.y, r*0.4*s,
    Color(math.min(1, c.r*0.5 + 0.5), math.min(1, c.g*0.5 + 0.55), math.min(1, c.b*0.5 + 0.6), 1))
end

-- Water: two hexagons turning opposite ways, one filled and one drawn only as an
-- edge, so the gap between them scallops open and shut as they pass. A chord
-- swung on the inner ring's clock keeps the middle from reading as a flat plate.
ICONS.water_wave = function(self, s, now)
  local c, r = self.color, self.r_size
  local x, y = self.x, self.y
  local a    = now*0.5

  graphics.polygon(ngon(x, y, r*1.50*s + 1.3, 6, a), bg[-2])
  graphics.polygon(ngon(x, y, r*1.50*s, 6, a), dim(c, 0.45))
  graphics.polygon(ngon(x, y, r*1.50*s, 6, a), lift(c, 0.25), 1.1)

  local b  = -a*1.6
  local ir = r*0.90*s
  graphics.polygon(ngon(x, y, ir, 6, b + math.pi/6), lift(c, 0.45), 1.4)
  graphics.line(x + math.cos(b)*ir, y + math.sin(b)*ir,
                x - math.cos(b)*ir, y - math.sin(b)*ir, fade(bg[-2], 0.85), 1.6)

  graphics.circle(x, y, r*0.30*s, fg[5])
end

-- Multi: three beads carried on a turning triangular linkage. The linkage is
-- drawn UNDER the beads and the beads sit out past its corners, so they sweep
-- across the tier-2 ring on their way round -- the one icon with anything
-- leaving the badge.
ICONS.multi_ball = function(self, s, now)
  local c, r = self.color, self.r_size
  local x, y = self.x, self.y
  local a0   = now*1.1
  local ring = r*1.20*s

  local tri = ngon(x, y, ring, 3, a0)
  graphics.polygon(tri, bg[-2], 2.8)
  graphics.polygon(tri, fade(c, 0.5), 1)

  graphics.circle(x, y, r*0.52*s + 1, bg[-2])
  graphics.circle(x, y, r*0.52*s, dim(c, 0.65))

  local br = r*0.44*s
  for i = 0, 2 do
    local a = a0 + i*(2*math.pi/3)
    local bx, by = x + math.cos(a)*ring, y + math.sin(a)*ring
    graphics.circle(bx, by, br + 1, bg[-2])
    graphics.circle(bx, by, br, c)
    graphics.circle(bx - br*0.32, by - br*0.32, br*0.34, fg[5])
  end
end

-- Pierce: two squares crossed at different rates. Every few seconds they line up
-- into a plain diamond and then fold back out into an eight-point star -- the
-- busiest silhouette in the set, which is why both squares are outlines and only
-- the small core is solid.
ICONS.pierce = function(self, s, now)
  local c, r = self.color, self.r_size
  local x, y = self.x, self.y
  local a    = now*0.7

  for _, sq in ipairs({{a, 1.55, 0.6}, {-a*1.4, 1.28, 1.0}}) do
    local v = ngon(x, y, r*sq[2]*s, 4, sq[1])
    graphics.polygon(v, bg[-2], 3)
    graphics.polygon(v, dim(c, sq[3]), 1.3)
  end

  graphics.polygon(ngon(x, y, r*0.60*s, 4, -a*1.4), lift(c, 0.4))
end

-- Floor: a pentagon -- the only odd-sided shell here, so it never reads as the
-- square or the hex one at a glance -- turning over a bar that sweeps through it.
-- A second, shorter bar counter-sweeps at a fraction of the travel, so the two
-- cross rather than ever stacking up.
ICONS.floor = function(self, s, now)
  local c, r = self.color, self.r_size
  local x, y = self.x, self.y

  local p = ngon(x, y, r*1.55*s, 5, now*0.42 - math.pi/2)
  graphics.polygon(p, bg[-2], 3.2)
  graphics.polygon(p, c, 1.2)

  local u  = math.sin(now*1.2)
  local bw = r*1.40*s
  graphics.rectangle(x, y - u*r*0.42*s, bw*0.62, r*0.32*s, 1, 1, fade(c, 0.45))
  graphics.rectangle(x, y + u*r*0.72*s, bw + 1.5, r*0.42*s + 1.5, 1, 1, bg[-2])
  graphics.rectangle(x, y + u*r*0.72*s, bw, r*0.42*s, 1, 1, lift(c, 0.3))
end


-- Spawn-out: a drop swells up to size over POWERUP_SPAWN_DUR instead of
-- appearing whole, so it reads as being ejected by the kill that dropped it.
-- Wrapped around the whole draw (rather than threaded through every kind's
-- own shapes) because a powerup is a dozen layers -- halo, ring, body, glyph,
-- ripples -- and only a transform catches all of them.
local POWERUP_SPAWN_DUR = 0.16

function Powerup:spawn_k()
  local p = math.clamp((self.spawn_t or 0)/POWERUP_SPAWN_DUR, 0, 1)
  return 1 - (1 - p)*(1 - p)*(1 - p)
end


function Powerup:draw()
  local k = self:spawn_k()
  if k >= 1 then return self:draw_body() end
  graphics.push(self.x, self.y, 0, k, k)
  self:draw_body()
  graphics.pop()
end


function Powerup:draw_body()
  self.spring:pull(0)
  if self.kind == 'level_random' then return self:draw_level_rune() end
  local s   = self.spring.x
  local now = time or 0
  local rot = self:get_angle() or 0

  -- Outer halo glow. Pulses brighter when armed (tier-2 mid-flight) so the
  -- catch-attempt-that-counts is unmistakable.
  local halo_a = self.armed and (0.55 + 0.35*math.abs(math.sin(now*10))) or 0.28
  graphics.circle(self.x, self.y, self.r_size*2.4*(1 + 0.06*math.sin(now*7)),
                  Color(self.color.r, self.color.g, self.color.b, halo_a*0.5))

  -- Tier-2 outline ring, rigidly attached to the tumbling body -- the physics
  -- spin (and the english from a deflect) stays visible here even though the
  -- elemental icon itself is drawn upright. Pure yellow = "rare one".
  if self.tier == 2 then
    graphics.push(self.x, self.y, rot)
      graphics.rectangle(self.x, self.y, self.r_size*2.7, self.r_size*2.7, 1, 1, yellow[0], 1)
    graphics.pop()
  end

  -- Elemental icon body (see the ICONS painters above).
  local icon = ICONS[self.kind]
  if icon then
    icon(self, s, now)
  else
    -- Unknown kind fallback: the old anonymous diamond.
    local inner_sz = self.r_size*1.9*s
    graphics.push(self.x, self.y, rot + math.pi/4)
      graphics.rectangle(self.x, self.y, inner_sz + 1.5, inner_sz + 1.5, 1, 1, bg[-2])
      graphics.rectangle(self.x, self.y, inner_sz, inner_sz, 1, 1, self.color)
    graphics.pop()
  end
end
