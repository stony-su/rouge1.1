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


-- Per-kind elemental icon painters. Each draws the powerup's BODY -- a small
-- vector silhouette of the effect itself (a medic cross, a stretching paddle,
-- a licking flame, a snowflake, ...) instead of the old anonymous diamond +
-- letter. Icons are drawn UPRIGHT for readability; the physics tumble stays
-- visible on the tier-2 outline ring in :draw. `s` is the catch/deflect
-- spring scale, `now` the shared clock driving each icon's mini-animation.
local ICONS = {}

-- Heal: a medic cross with a lub-dub heartbeat swell.
ICONS.heal = function(self, s, now)
  local c, r = self.color, self.r_size
  local ph   = (now*1.3) % 1
  local beat = 0
  if ph < 0.15 then beat = math.sin(ph/0.15*math.pi)
  elseif ph > 0.22 and ph < 0.37 then beat = math.sin((ph - 0.22)/0.15*math.pi) end
  local k  = (1 + 0.14*beat)*s
  local aw = r*2.2*k                                  -- cross arm length
  local at = r*0.85*k                                 -- cross arm thickness
  graphics.rectangle(self.x, self.y, aw + 1.6, at + 1.6, 1, 1, bg[-2])
  graphics.rectangle(self.x, self.y, at + 1.6, aw + 1.6, 1, 1, bg[-2])
  graphics.rectangle(self.x, self.y, aw, at, 1, 1, c)
  graphics.rectangle(self.x, self.y, at, aw, 1, 1, c)
  graphics.rectangle(self.x, self.y, at*0.55, at*0.55, nil, nil, fg[5])
end

-- Wide: the paddle bar itself, with stretch chevrons sliding off both ends.
ICONS.wide_paddle = function(self, s, now)
  local c, r = self.color, self.r_size
  local bw, bh = r*2.4*s, r*0.8*s
  graphics.rectangle(self.x, self.y, bw + 1.6, bh + 1.6, 2, 2, bg[-2])
  graphics.rectangle(self.x, self.y, bw, bh, 2, 2, c)
  local ph  = (now*1.6) % 1
  local off = bw/2 + 1 + ph*r*1.2
  local ch  = Color(c.r, c.g, c.b, 1 - ph)
  for _, dir in ipairs({1, -1}) do
    local x0 = self.x + dir*off
    graphics.line(x0, self.y - bh*0.8, x0 + dir*r*0.5, self.y, ch, 1.5)
    graphics.line(x0 + dir*r*0.5, self.y, x0, self.y + bh*0.8, ch, 1.5)
  end
end

-- Big: a ball mid-growth -- an expanding ghost ring swells off the rim.
ICONS.big_ball = function(self, s, now)
  local c, r = self.color, self.r_size
  local br = r*0.95*s
  graphics.circle(self.x, self.y, br + 0.8, bg[-2])
  graphics.circle(self.x, self.y, br, c)
  graphics.circle(self.x - br*0.3, self.y - br*0.3, br*0.32, fg[5])
  local ph = (now*1.2) % 1
  graphics.circle(self.x, self.y, br + 1 + ph*r*1.6, Color(c.r, c.g, c.b, (1 - ph)*0.8), 1.5)
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

-- Water: a deep pool badge with two crests rolling across it.
ICONS.water_wave = function(self, s, now)
  local c, r = self.color, self.r_size
  local br = r*1.3*s
  graphics.circle(self.x, self.y, br + 0.8, bg[-2])
  graphics.circle(self.x, self.y, br, Color(c.r*0.55, c.g*0.6, c.b*0.85, 1))
  local crest = Color(math.min(1, c.r*0.5 + 0.5), math.min(1, c.g*0.5 + 0.55), math.min(1, c.b*0.5 + 0.65), 1)
  for row = 0, 1 do
    local yy  = self.y + (row == 0 and -br*0.25 or br*0.35)
    local amp = br*0.22
    local pts = {crest, 1.2}
    local n   = 6
    for i = 0, n do
      pts[#pts + 1] = self.x - br*0.8 + (i/n)*br*1.6
      pts[#pts + 1] = yy + math.sin(now*4 + row*1.7 + i*1.1)*amp
    end
    graphics.polyline(unpack(pts))
  end
end

-- Multi: three little hero-balls orbiting a common centre -- the split, live.
ICONS.multi_ball = function(self, s, now)
  local c, r = self.color, self.r_size
  local orb  = r*0.55*s
  local ring = r*0.95
  for i = 0, 2 do
    local a = now*1.6 + i*(2*math.pi/3)
    local bx, by = self.x + math.cos(a)*ring, self.y + math.sin(a)*ring
    graphics.circle(bx, by, orb + 0.8, bg[-2])
    graphics.circle(bx, by, orb, c)
    graphics.circle(bx - orb*0.3, by - orb*0.3, orb*0.33, fg[5])
  end
end

-- Pierce: an arrow punched clean through a brick, shards off the exit face.
ICONS.pierce = function(self, s, now)
  local c, r = self.color, self.r_size
  local bs = r*1.5*s                                  -- the brick being pierced
  graphics.rectangle(self.x, self.y, bs + 1.6, bs + 1.6, 1, 1, bg[-2])
  graphics.rectangle(self.x, self.y, bs, bs, 1, 1, Color(c.r*0.5, c.g*0.5, c.b*0.7, 1))
  local push_x = r*0.3*math.abs(math.sin(now*4))      -- nudges forward on a loop
  local x0, x1 = self.x - r*2.2 + push_x, self.x + r*1.3 + push_x
  graphics.line(x0, self.y, x1, self.y, bg[-2], 2.6)
  graphics.line(x0, self.y, x1, self.y, c, 1.4)
  graphics.triangle(x1 + r*0.35, self.y, r*1.0 + 1.2, r*1.1 + 1.2, bg[-2])
  graphics.triangle(x1 + r*0.35, self.y, r*1.0, r*1.1, c)
  for i, dy in ipairs({-1, 1}) do                     -- exit-face shards
    local ph = (now*2 + i*0.4) % 1
    graphics.rectangle(self.x + bs/2 + 1 + ph*r*1.1, self.y + dy*(bs*0.35 + ph*r*0.7),
                       1.3, 1.3, nil, nil, Color(c.r, c.g, c.b, 1 - ph))
  end
end

-- Floor: a safety line with a ball bouncing off it, squashing on impact.
ICONS.floor = function(self, s, now)
  local c, r = self.color, self.r_size
  local fy = self.y + r*1.0
  local fw = r*2.6*s
  graphics.rectangle(self.x, fy, fw + 1.6, 2.6, 1, 1, bg[-2])
  graphics.rectangle(self.x, fy, fw, 1.6, 1, 1, c)
  local ph = math.abs(math.sin(now*3.2))
  local by = fy - 2 - ph*r*1.7
  local squash = math.min(1, 0.7 + ph)
  graphics.push(self.x, by, 0, 1, squash)
    graphics.circle(self.x, by, r*0.55 + 0.8, bg[-2])
    graphics.circle(self.x, by, r*0.55, fg[0])
  graphics.pop()
  if ph < 0.22 then                                   -- impact ticks
    local ta = 1 - ph/0.22
    graphics.line(self.x - fw*0.32, fy - 2, self.x - fw*0.32 - r*0.5, fy - 2 - r*0.4, Color(c.r, c.g, c.b, ta), 1)
    graphics.line(self.x + fw*0.32, fy - 2, self.x + fw*0.32 + r*0.5, fy - 2 - r*0.4, Color(c.r, c.g, c.b, ta), 1)
  end
end


function Powerup:draw()
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

  -- Sparkle: a few tiny offsets that orbit the icon, sold as "this is
  -- not background scenery, grab me". Clock-driven so they keep orbiting even
  -- after the body's spin damps out.
  local spark_r = self.r_size + 4
  for i = 0, 2 do
    local a = now*2 + i*(math.pi*2/3)
    local sx, sy = self.x + math.cos(a)*spark_r, self.y + math.sin(a)*spark_r
    graphics.rectangle(sx, sy, 1.4, 1.4, nil, nil, fg[5])
  end
end
