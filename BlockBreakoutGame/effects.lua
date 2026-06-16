-- Small visual feedback helpers.

HitParticle = Object:extend()
HitParticle:implement(GameObject)
function HitParticle:init(args)
  self:init_game_object(args)
  self.color    = self.color or fg[0]
  self.w        = self.w or 3
  self.v        = self.v or 60
  self.r        = self.r or random:float(0, 2*math.pi)
  self.duration = self.duration or 0.35
  self.t:tween(self.duration, self, {w = 0}, math.linear, function() self.dead = true end)
end

function HitParticle:update(dt)
  self:update_game_object(dt)
  self.x = self.x + self.v*math.cos(self.r)*dt
  self.y = self.y + self.v*math.sin(self.r)*dt
end

function HitParticle:draw()
  graphics.push(self.x, self.y, self.r)
    graphics.rectangle(self.x, self.y, self.w, self.w, 1, 1, self.color)
  graphics.pop()
end


-- Burst a few HitParticles at a spot.
function spawn_burst(group, x, y, color, n, vmin, vmax)
  for i = 1, n or 6 do
    HitParticle{
      group = group, x = x, y = y, color = color or fg[0],
      duration = random:float(0.25, 0.45),
      w = random:float(2, 4),
      v = random:float(vmin or 80, vmax or 140),
    }
  end
end


-- Floating "+N" text that drifts upward and fades.
FloatingText = Object:extend()
FloatingText:implement(GameObject)
function FloatingText:init(args)
  self:init_game_object(args)
  self.text     = self.text or '+1'
  self.color    = self.color or yellow[0]
  self.vy       = -22
  self.alpha    = 1
  self.duration = self.duration or 0.7
  self.t:after(self.duration*0.5, function()
    self.t:tween(self.duration*0.5, self, {alpha = 0}, math.linear, function() self.dead = true end)
  end)
end

function FloatingText:update(dt)
  self:update_game_object(dt)
  self.y = self.y + self.vy*dt
end

function FloatingText:draw()
  local c = Color(self.color.r, self.color.g, self.color.b, self.alpha)
  graphics.print_centered(self.text, pixul_font, self.x, self.y, 0, 1, 1, 0, 0, c)
end


-- Brief flash overlay across the whole arena.
Flash = Object:extend()
Flash:implement(GameObject)
function Flash:init(args)
  self:init_game_object(args)
  self.duration = self.duration or 0.05
  self.t:after(self.duration, function() self.dead = true end)
end

function Flash:update(dt)
  self:update_game_object(dt)
end

function Flash:draw()
  graphics.rectangle(self.x, self.y, gw, gh, nil, nil, self.color or white_transparent_weak)
end


-- Telegraph: a thin ring or rectangle that scales up briefly to warn the player
-- of an incoming area attack. Filled at the start, then fades to outline as it
-- expands.
TelegraphRing = Object:extend()
TelegraphRing:implement(GameObject)
function TelegraphRing:init(args)
  self:init_game_object(args)
  self.radius   = self.radius or 24
  self.color    = self.color or fg[0]
  self.duration = self.duration or 0.25
  self.rs       = 1
  self.alpha    = 0.85
  self.t:tween(self.duration, self, {rs = self.radius, alpha = 0}, math.cubic_out, function() self.dead = true end)
end

function TelegraphRing:update(dt) self:update_game_object(dt) end

function TelegraphRing:draw()
  local c = Color(self.color.r, self.color.g, self.color.b, self.alpha)
  graphics.circle(self.x, self.y, self.rs, c, 2)
end


-- Square version of the telegraph for box-shaped attacks.
TelegraphSquare = Object:extend()
TelegraphSquare:implement(GameObject)
function TelegraphSquare:init(args)
  self:init_game_object(args)
  self.size     = self.size or 32
  self.color    = self.color or fg[0]
  self.duration = self.duration or 0.25
  self.s        = 1
  self.alpha    = 0.85
  self.t:tween(self.duration, self, {s = self.size, alpha = 0}, math.cubic_out, function() self.dead = true end)
end

function TelegraphSquare:update(dt) self:update_game_object(dt) end

function TelegraphSquare:draw()
  local c = Color(self.color.r, self.color.g, self.color.b, self.alpha)
  graphics.rectangle(self.x, self.y, self.s, self.s, 1, 1, c, 2)
end


-- FlickTick: a short, thin line that darts outward from a point along `r`, then
-- shrinks and fades to nothing. A few fired together in an ability's direction
-- are the whole tell for an enemy-block cast -- compact and self-dispersing, so
-- they replace the old ring + word-label + particle-spray combo without
-- cluttering the play area.
FlickTick = Object:extend()
FlickTick:implement(GameObject)
function FlickTick:init(args)
  self:init_game_object(args)
  self.color    = self.color or fg[0]
  self.r        = self.r or 0        -- travel direction, radians
  self.dist     = self.dist or 9     -- how far the segment darts out
  self.len      = self.len or 6      -- segment length
  self.width    = self.width or 2
  self.duration = self.duration or 0.32
  self.age      = 0
  self.travel   = 0
  self.alpha    = 1
  self.t:after(self.duration, function() self.dead = true end)
end

function FlickTick:update(dt)
  self:update_game_object(dt)
  self.age = self.age + dt
  local k  = math.min(1, self.age/self.duration)
  -- Dart outward fast then ease (cubic-out). Hold full brightness for most of
  -- the life and only fade over the last stretch, so the flick actually
  -- registers before it disperses (a straight alpha tween vanished too fast).
  self.travel = self.dist*(1 - (1 - k)^3)
  self.alpha  = (k < 0.55) and 1 or math.max(0, 1 - (k - 0.55)/0.45)
end

function FlickTick:draw()
  local dx, dy = math.cos(self.r), math.sin(self.r)
  local bx, by = self.x + dx*self.travel, self.y + dy*self.travel
  local tx, ty = bx + dx*self.len,        by + dy*self.len
  graphics.line(bx, by, tx, ty, Color(self.color.r, self.color.g, self.color.b, self.alpha), self.width)
end


-- Fire a small set of FlickTicks from (x, y), one per angle in `dirs`. The
-- standard "enemy block did something" tell: pass downward angles for a lunge or
-- shot, a full radial spread for a shove, a single aimed angle for a snipe, etc.
-- opts overrides dist/len/duration/width; values are jittered slightly so the
-- ticks never look mechanical.
function spawn_flicks(group, x, y, color, dirs, opts)
  opts = opts or {}
  for _, a in ipairs(dirs) do
    FlickTick{
      group = group, x = x, y = y, color = color or fg[0], r = a,
      dist     = opts.dist     or random:float(8, 11),
      len      = opts.len      or random:float(5, 7),
      duration = opts.duration or random:float(0.28, 0.38),
      width    = opts.width    or 2,
    }
  end
end


-- DotCloud: a persistent damage zone painted by plague_doctor / witch.
-- Doesn't apply damage itself — BallPit:burn_area runs that side via the
-- existing brick burn timer. The cloud is purely the visual.
DotCloud = Object:extend()
DotCloud:implement(GameObject)
function DotCloud:init(args)
  self:init_game_object(args)
  self.rs       = self.rs or 24
  self.color    = self.color or purple[0]
  self.duration = self.duration or 8
  self.t:after(self.duration, function() self.dead = true end)
end
function DotCloud:update(dt) self:update_game_object(dt) end
function DotCloud:draw()
  local pulse = 0.55 + 0.18*math.sin(love.timer.getTime()*4)
  local fill  = Color(self.color.r, self.color.g, self.color.b, 0.18*pulse)
  local ring  = Color(self.color.r, self.color.g, self.color.b, 0.55)
  graphics.circle(self.x, self.y, self.rs, fill)
  graphics.circle(self.x, self.y, self.rs, ring, 1)
end


-- FrostArea (SNKRX cryomancer port: player.lua:481 / DotArea). A rotating blue
-- frost field that FOLLOWS the cryomancer ball, chilling every enemy inside: each
-- tick it refreshes a SLOW on bricks in range and deals cold DoT. Level 3
-- ("Frostbite") slows harder + hits harder. The signature look (straight from
-- SNKRX) is a transparent disc + four rim arc-segments that rotate as `vr`
-- accumulates, here over an inner counter-rotating ring for depth. Bound to a
-- parent ball: it tracks the ball and dies with it.
FrostArea = Object:extend()
FrostArea:implement(GameObject)
function FrostArea:init(args)
  self:init_game_object(args)
  self.rs          = self.rs or 58
  self.color       = self.color or blue[0]
  self.dmg         = self.dmg or 5          -- damage per TICK to enemies inside
  self.tick        = self.tick or 0.5
  self.slow_factor = self.slow_factor or 0.5
  self.slow_dur    = self.slow_dur or 1.5
  self.level       = self.level or 1
  self.vr          = random:float(0, 2*math.pi)             -- rim-arc rotation angle
  self.dvr         = random:table{-1, 1}*random:float(0.5, 1.0)  -- slow spin, random direction
  self.pulse       = random:float(0, 6.28)
  self.hit_pulse   = 0
  self.appear      = 0
  self.t:tween(0.25, self, {appear = 1}, math.cubic_in_out)
  self.t:every(self.tick, function() self:chill() end)
end
function FrostArea:update(dt)
  self:update_game_object(dt)
  self.pulse     = self.pulse + dt
  self.vr        = self.vr + self.dvr*dt
  self.hit_pulse = math.max(0, self.hit_pulse - dt*3)
  -- Follow the cryomancer ball; die with it.
  if self.parent then
    if self.parent.dead then self.dead = true return end
    self.x, self.y = self.parent.x, self.parent.y
  end
end
function FrostArea:chill()
  local arena = main.current
  if not (arena and arena.main) then return end
  local lvl3 = self.level >= 3
  local sf   = lvl3 and (self.slow_factor*0.7) or self.slow_factor   -- harder slow at lvl3
  local dmg  = self.dmg * (lvl3 and 1.6 or 1)
  local hit_any = false
  for _, o in ipairs(arena.main.objects) do
    if not o.dead and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
      if math.distance(self.x, self.y, o.x, o.y) <= self.rs then
        hit_any = true
        if o.apply_slow   then o:apply_slow(sf, self.slow_dur) end
        if o.take_damage  then o:take_damage(dmg, self.color, true) end
        if random:bool(40) then
          SmokePuff{group = arena.effects, x = o.x + random:float(-4, 4), y = o.y + random:float(-4, 4),
                    color = Color(0.72, 0.86, 1, 1), rs = random:float(0.8, 1.6), alpha = 0.7,
                    vx = random:float(-10, 10), vy = random:float(-14, 6), duration = random:float(0.3, 0.6)}
        end
      end
    end
  end
  if hit_any then
    self.hit_pulse = 1
    if self.parent then self.parent.frost_flash_t = 0.2 end
    frost1:play{volume = 0.25, pitch = random:float(0.9, 1.1)}
  end
end
function FrostArea:draw()
  local c  = self.color
  local rs = self.rs*(self.appear or 1)*(1 + (self.hit_pulse or 0)*0.06)
  local pulse = 0.5 + 0.5*math.sin((self.pulse or 0)*2.5)
  -- Transparent chill fill.
  graphics.circle(self.x, self.y, rs, Color(c.r, c.g, c.b, 0.06 + 0.03*pulse + (self.hit_pulse or 0)*0.05))
  -- Faint full ring.
  graphics.circle(self.x, self.y, rs, Color(c.r, c.g, c.b, 0.18 + 0.15*(self.hit_pulse or 0)), 1)
  -- Four rotating rim arc-segments (the SNKRX signature), spun by vr.
  for i = 1, 4 do
    local b = self.vr + (i - 1)*math.pi/2 + math.pi/4
    graphics.arc('open', self.x, self.y, rs, b - math.pi/8, b + math.pi/8, c, 3)
  end
  -- Inner counter-rotating arcs for depth (thinner, paler).
  for i = 1, 3 do
    local b = -self.vr*1.4 + (i - 1)*2*math.pi/3
    graphics.arc('open', self.x, self.y, rs*0.62, b - 0.22, b + 0.22, Color(c.r, c.g, c.b, 0.55), 1.5)
  end
end


-- BombDrop (bomber "reactor core" rework). A planted UNSTABLE CONTAINMENT CELL:
-- a hexagonal casing with rotating containment brackets straining around a pulsing
-- plasma core -- deliberately distinct from the bomber ball's round vented core.
-- There is NO fuse countdown: it detonates the instant a brick drifts within
-- trigger_radius (a proximity mine); a silent `fuse` lifetime only cleans up cells
-- that are never touched, with no visible blink. The blast is the multi-stage
-- ReactorBlast (implosion -> flash -> shockwaves -> radiating arcs).
BombDrop = Object:extend()
BombDrop:implement(GameObject)
function BombDrop:init(args)
  self:init_game_object(args)
  self.dmg            = self.dmg or 20
  self.radius         = self.radius or 60
  self.fuse           = self.fuse or 8     -- SILENT cleanup lifetime (no visible countdown)
  self.trigger_radius = self.trigger_radius or 16
  self.color          = self.color or orange[0]
  self.lvl3           = self.lvl3 or false
  self.armed          = false              -- brief arming delay so it doesn't pop on the planter
  self.exploded       = false
  self.settle         = 1                  -- drop-and-settle squash on landing
  self.spin           = random:float(0, 2*math.pi)
  self.t:after(0.35, function() self.armed = true end)
  self.t:after(self.fuse, function() self:explode() end)
end
function BombDrop:update(dt)
  self:update_game_object(dt)
  self.settle = self.settle*(1 - math.min(1, 8*dt))   -- ease the landing squash out
  self.spin   = self.spin + 1.2*dt
  -- Proximity detonation: blow the instant a live brick enters trigger_radius.
  if self.armed and not self.exploded then
    local arena = main.current
    if arena and arena.has_brick_within and arena:has_brick_within(self.x, self.y, self.trigger_radius) then
      self:explode()
    end
  end
end
function BombDrop:draw()
  local c     = self.color
  local t     = love.timer.getTime()
  local pulse = 0.5 + 0.5*math.sin(t*6)
  local rs    = self.lvl3 and 8 or 7
  local sx    = 1 + self.settle*0.4
  local sy    = 1 - self.settle*0.3
  -- Faint steady blast-radius hint (NOT a countdown -- just reads the AoE).
  graphics.circle(self.x, self.y, self.radius, Color(c.r, c.g, c.b, 0.05 + 0.03*pulse))
  -- Hexagonal dark casing -- a distinct silhouette from the round bomber ball.
  local hex = {}
  for i = 0, 5 do
    local a = self.spin + i*math.pi/3
    hex[#hex+1] = self.x + math.cos(a)*rs*1.15*sx
    hex[#hex+1] = self.y + math.sin(a)*rs*1.15*sy
  end
  graphics.polygon(hex, Color(0.10, 0.09, 0.12, 1))
  graphics.polygon(hex, Color(c.r*0.55, c.g*0.45, c.b*0.30, 0.85), 1.5)
  -- Rotating containment brackets (4 short arcs) straining around the core.
  for i = 0, 3 do
    local a = -self.spin*1.6 + i*math.pi/2
    graphics.arc('open', self.x, self.y, rs*0.95, a + 0.2, a + 0.95,
                 Color(c.r, c.g*0.7, c.b*0.35, 0.75), 2)
  end
  -- Unstable plasma core: orange -> yellow -> white-hot, pulsing.
  graphics.circle(self.x, self.y, rs*(0.55 + 0.15*pulse), Color(c.r, c.g, c.b, 0.95))
  graphics.circle(self.x, self.y, rs*(0.32 + 0.10*pulse), Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.95))
  graphics.circle(self.x, self.y, rs*0.16, Color(1, 1, 1, 0.95))
end
function BombDrop:explode()
  if self.exploded then return end
  self.exploded = true
  local arena = main.current
  if arena then
    ReactorBlast{group = arena.effects, x = self.x, y = self.y,
                 radius = self.radius, dmg = self.dmg, color = self.color, lvl3 = self.lvl3}
  end
  self.dead = true
end


-- ReactorBlast: the bomber's intricate detonation (a reactor going critical). A
-- multi-stage sequence rather than a single pop:
--   1. implosion  -- a ring sucks inward + the core whites out (first 0.1s),
--   2. detonation -- a white core flash, three staggered expanding shockwave rings,
--      eight radiating energy spokes, and a spray of plasma debris + smoke,
-- The AoE damage (do_splash) lands at the detonation beat; level 3 adds a delayed
-- aftershock. Self-contained: BombDrop just spawns one of these and dies.
ReactorBlast = Object:extend()
ReactorBlast:implement(GameObject)
function ReactorBlast:init(args)
  self:init_game_object(args)
  self.radius    = self.radius or 60
  self.dmg       = self.dmg or 20
  self.color     = self.color or orange[0]
  self.lvl3      = self.lvl3 or false
  self.age       = 0
  self.detonated = false
  self.t:after(0.1,  function() self:detonate() end)
  self.t:after(0.85, function() self.dead = true end)
end
function ReactorBlast:detonate()
  if self.detonated then return end
  self.detonated = true
  local arena = main.current
  if not arena then return end
  arena:do_splash(self.x, self.y, self.radius, self.dmg, self.color)
  -- Plasma debris + smoke spray on top of the splash.
  spawn_burst(arena.effects, self.x, self.y, self.color, 14, 90, 240)
  spawn_burst(arena.effects, self.x, self.y, Color(yellow[0].r, yellow[0].g, yellow[0].b, 1), 8, 60, 180)
  for _ = 1, 8 do
    local a = random:float(0, 2*math.pi)
    local sp = random:float(40, 120)
    SmokePuff{group = arena.effects, x = self.x, y = self.y, color = Color(0.30, 0.28, 0.30, 1),
              rs = random:float(3, 6), alpha = 0.4, vx = math.cos(a)*sp, vy = math.sin(a)*sp - 10,
              duration = random:float(0.5, 0.9)}
  end
  camera:shake(self.lvl3 and 6 or 4, 0.3, 120)
  explosion1:play{volume = 0.5, pitch = random:float(0.9, 1.05)}
  -- Level-3 "Demoman": a second, smaller aftershock a beat later.
  if self.lvl3 then
    local x, y, r, d, col = self.x, self.y, self.radius*0.7, self.dmg*0.55, self.color
    self.t:after(0.18, function()
      if arena.main and arena.main.world then
        arena:do_splash(x, y, r, d, col)
        camera:shake(3, 0.2, 120)
        explosion1:play{volume = 0.35, pitch = random:float(0.95, 1.1)}
      end
    end)
  end
end
function ReactorBlast:update(dt)
  self:update_game_object(dt)
  self.age = self.age + dt
end
function ReactorBlast:draw()
  local c = self.color
  if not self.detonated then
    -- Stage 1 -- implosion: a bright ring contracts inward + the core whites out.
    local k  = math.clamp(self.age/0.1, 0, 1)
    local rr = self.radius*0.6*(1 - k)
    graphics.circle(self.x, self.y, math.max(0, rr), Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.5), 2)
    graphics.circle(self.x, self.y, 3 + k*7, Color(1, 1, 1, 0.4 + 0.6*k))
    return
  end
  -- Stage 2 -- detonation visuals over the remaining ~0.75s.
  local k = math.clamp((self.age - 0.1)/0.75, 0, 1)
  -- Core flash fading.
  graphics.circle(self.x, self.y, math.max(0, 16*(1 - k)), Color(1, 1, 1, 1 - k))
  -- Three staggered expanding shockwave rings.
  for i = 1, 3 do
    local kk = math.clamp(k*1.25 - (i - 1)*0.18, 0, 1)
    if kk > 0 and kk < 1 then
      graphics.circle(self.x, self.y, self.radius*(0.3 + kk), Color(c.r, c.g, c.b, 0.7*(1 - kk)), 2.6 - i*0.5)
    end
  end
  -- Eight radiating energy spokes shooting outward, fading.
  local spoke = self.radius*(0.25 + k*0.95)
  local fade  = 1 - k
  for i = 0, 7 do
    local a  = i*math.pi/4 + self.age*4
    local r1 = spoke*0.55
    graphics.line(self.x + math.cos(a)*r1, self.y + math.sin(a)*r1,
                  self.x + math.cos(a)*spoke, self.y + math.sin(a)*spoke,
                  Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.7*fade), 1.5)
  end
end


-- AllyTurret: parks above the paddle, fires projectiles at the nearest brick
-- on its own cooldown, despawns after `lifetime` seconds.
-- AllyTurret (SNKRX engineer port: player.lua:3196 Turret). A deployed gun
-- emplacement planted by the engineer: a bolted hex base + a barrel that rotates to
-- track the nearest brick, firing a BURST of burst_count shots every burst_cd. It
-- deploys with a pop, persists for `lifetime`, then folds up in a spark puff. Level
-- 3 ("Upgrade!!!") turrets (upgraded) fire faster, hit harder (baked into dmg) and
-- wear a twin barrel + a "+" mark.
AllyTurret = Object:extend()
AllyTurret:implement(GameObject)
function AllyTurret:init(args)
  self:init_game_object(args)
  self.lifetime    = self.lifetime or 16
  self.burst_cd    = self.burst_cd or 3.0
  self.burst_count = self.burst_count or 3
  self.burst_gap   = self.burst_gap or 0.12
  self.range       = self.range or 256
  self.dmg         = self.dmg or 8
  self.shot_speed  = self.shot_speed or 220
  self.color       = self.color or orange[0]
  self.upgraded    = self.upgraded or false
  self.aim_a       = -math.pi/2     -- barrel angle, smoothed toward the nearest brick
  self.gear_a      = random:float(0, 2*math.pi)
  self.flash_t     = 0              -- muzzle flash timer
  self.deploy_t    = 1              -- deploy pop (eases 1 -> 0)
  self.born_at     = love.timer.getTime()
  self.t:after(self.lifetime, function() self:expire() end)
  -- Upgraded turrets fire 50% faster (SNKRX "Upgrade!!!" attack-speed boost).
  self.t:every(self.burst_cd/(self.upgraded and 1.5 or 1), function() self:fire_burst() end)
  spawn1:play{volume = 0.25, pitch = random:float(1.05, 1.2)}
end
function AllyTurret:update(dt)
  self:update_game_object(dt)
  self.gear_a = self.gear_a + 1.5*dt
  if self.flash_t  > 0 then self.flash_t  = self.flash_t - dt end
  if self.deploy_t > 0 then self.deploy_t = math.max(0, self.deploy_t - dt*4) end
  -- Track the nearest brick: smoothly rotate the barrel toward it.
  local arena = main.current
  local target = arena and arena.get_nearest_brick_within and arena:get_nearest_brick_within(self.x, self.y, self.range)
  if target then
    local want = math.atan2(target.y - self.y, target.x - self.x)
    local diff = math.loop(want - self.aim_a, 2*math.pi)
    if diff > math.pi then diff = diff - 2*math.pi end
    self.aim_a = self.aim_a + math.clamp(diff, -6*dt, 6*dt)
  end
end
function AllyTurret:fire_burst()
  local arena = main.current
  if not (arena and arena.main and arena.main.world) then return end
  if not arena:get_nearest_brick_within(self.x, self.y, self.range) then return end
  local bl = self.upgraded and 11 or 9
  for i = 0, self.burst_count - 1 do
    self.t:after(i*self.burst_gap, function()
      if not (arena.main and arena.main.world) then return end
      local tgt = arena:get_nearest_brick_within(self.x, self.y, self.range)
      if not tgt then return end
      local r = math.atan2(tgt.y - self.y, tgt.x - self.x)
      self.aim_a   = r
      self.flash_t = 0.1
      local mx, my = self.x + math.cos(r)*bl, self.y + math.sin(r)*bl
      Projectile{group = arena.main, x = mx, y = my, r = r, type = 'arrow',
                 dmg = self.dmg, speed = self.shot_speed, color = self.color, pierce = 1}
      spawn_burst(arena.effects, mx, my, self.color, 2, 40, 90)
      shoot1:play{volume = 0.12, pitch = random:float(1.0, 1.15)}
    end)
  end
end
function AllyTurret:expire()
  spawn_burst(main.current.effects, self.x, self.y, self.color, 5, 40, 110)
  self.dead = true
end
function AllyTurret:draw()
  local age  = love.timer.getTime() - self.born_at
  local fade = 1
  if age > self.lifetime - 1.2 then fade = math.max(0.25, (self.lifetime - age)/1.2) end
  local c   = self.color
  local pop = 1 + self.deploy_t*0.4
  local a   = self.aim_a or -math.pi/2
  local bl  = (self.upgraded and 11 or 9)*pop

  -- Bolted hex base (slowly turning).
  local hb = {}
  for i = 0, 5 do
    local ha = self.gear_a*0.3 + i*math.pi/3
    hb[#hb+1] = self.x + math.cos(ha)*5.5*pop
    hb[#hb+1] = self.y + math.sin(ha)*5.5*pop
  end
  graphics.polygon(hb, Color(0.16, 0.15, 0.17, fade))
  graphics.polygon(hb, Color(c.r*0.55, c.g*0.45, c.b*0.3, 0.85*fade), 1)

  -- Barrel(s) aimed along aim_a (twin barrels when upgraded).
  local function barrel(off)
    local pa  = a + math.pi/2
    local cxm = self.x + math.cos(a)*bl*0.5 + math.cos(pa)*off
    local cym = self.y + math.sin(a)*bl*0.5 + math.sin(pa)*off
    graphics.push(cxm, cym, a, 1, 1)
      graphics.rectangle(cxm, cym, bl, 3, 1, 1, Color(c.r*0.6, c.g*0.5, c.b*0.35, fade))
    graphics.pop()
  end
  if self.upgraded then barrel(-2.2); barrel(2.2) else barrel(0) end

  -- Muzzle flash at the barrel tip while firing.
  if self.flash_t > 0 then
    local k = self.flash_t/0.1
    local mx, my = self.x + math.cos(a)*bl, self.y + math.sin(a)*bl
    graphics.circle(mx, my, 2 + 3*k, Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.8*k))
    graphics.circle(mx, my, 1.2, Color(1, 1, 1, k))
  end

  -- Sensor light on the base (pulses; brighter on upgraded turrets).
  local pulse = 0.5 + 0.5*math.sin(love.timer.getTime()*5)
  graphics.circle(self.x, self.y, (self.upgraded and 2.6 or 2.0), Color(c.r, c.g, c.b, fade))
  graphics.circle(self.x, self.y, 1.1 + 0.5*pulse, Color(yellow[0].r, yellow[0].g, yellow[0].b, (0.7 + 0.3*pulse)*fade))

  -- Upgraded turrets wear a small "+" mark.
  if self.upgraded then
    graphics.line(self.x - 7, self.y - 7, self.x - 4, self.y - 7, Color(yellow[0].r, yellow[0].g, yellow[0].b, fade), 1)
    graphics.line(self.x - 5.5, self.y - 8.5, self.x - 5.5, self.y - 5.5, Color(yellow[0].r, yellow[0].g, yellow[0].b, fade), 1)
  end
end


-- BallTrail: a fading colored disc dropped behind fast-moving balls so the
-- speed is readable at a glance. Lives in the effects group and shrinks +
-- fades out over its duration.
BallTrail = Object:extend()
BallTrail:implement(GameObject)
function BallTrail:init(args)
  self:init_game_object(args)
  self.rs       = self.rs or 4
  self.color    = self.color or fg[0]
  self.alpha    = self.alpha or 0.5
  self.duration = self.duration or 0.22
  self.t:tween(self.duration, self, {alpha = 0, rs = 0}, math.linear, function() self.dead = true end)
end

function BallTrail:update(dt) self:update_game_object(dt) end

function BallTrail:draw()
  local c = Color(self.color.r, self.color.g, self.color.b, self.alpha)
  graphics.circle(self.x, self.y, self.rs, c)
end


-- SmokePuff: a soft wisp that drifts (usually upward), GROWS and fades out over
-- its lifetime. Used by the assassin's Shadowstalker trail so the ball sheds
-- inky smoke that dissipates as it rises. Decelerates as it climbs.
SmokePuff = Object:extend()
SmokePuff:implement(GameObject)
function SmokePuff:init(args)
  self:init_game_object(args)
  self.color    = self.color or Color(0.10, 0.07, 0.14, 1)
  self.rs       = self.rs or 3
  self.alpha    = self.alpha or 0.4
  self.vx       = self.vx or 0
  self.vy       = self.vy or -18
  self.duration = self.duration or 0.5
  self.t:tween(self.duration, self, {alpha = 0, rs = self.rs*2.2}, math.linear, function() self.dead = true end)
end

function SmokePuff:update(dt)
  self:update_game_object(dt)
  self.x  = self.x + self.vx*dt
  self.y  = self.y + self.vy*dt
  self.vy = self.vy*(1 - 0.6*dt)   -- ease the rise so it billows then settles
end

function SmokePuff:draw()
  graphics.circle(self.x, self.y, self.rs, Color(self.color.r, self.color.g, self.color.b, self.alpha))
end


-- ArcaneSpark: a small spinning blade-glyph (a 4-point cross) that shrinks and
-- fades. Used by the spellblade's aftertrail so the ball leaves a ribbon of
-- arcane glyphs instead of a plain disc.
ArcaneSpark = Object:extend()
ArcaneSpark:implement(GameObject)
function ArcaneSpark:init(args)
  self:init_game_object(args)
  self.color    = self.color or blue[0]
  self.rs       = self.rs or 3
  self.alpha    = self.alpha or 0.7
  self.a        = self.a or random:float(0, 2*math.pi)
  self.spin     = self.spin or random:float(-8, 8)
  self.duration = self.duration or 0.4
  self.t:tween(self.duration, self, {alpha = 0, rs = 0}, math.linear, function() self.dead = true end)
end

function ArcaneSpark:update(dt)
  self:update_game_object(dt)
  self.a = self.a + self.spin*dt
end

function ArcaneSpark:draw()
  local c = Color(self.color.r, self.color.g, self.color.b, self.alpha)
  for _, off in ipairs({0, math.pi/2}) do
    local sa = self.a + off
    graphics.line(self.x - math.cos(sa)*self.rs, self.y - math.sin(sa)*self.rs,
                  self.x + math.cos(sa)*self.rs, self.y + math.sin(sa)*self.rs, c, 1)
  end
end


-- SporeMote: a tiny spore/pollen mote puffed off the cleric and blown outward,
-- decelerating and fading to nothing -- a fine drift of fading particles rather
-- than tumbling shapes. Also puffs off bricks the Consecrated Ground burns.
SporeMote = Object:extend()
SporeMote:implement(GameObject)
function SporeMote:init(args)
  self:init_game_object(args)
  self.color    = self.color or green[0]
  self.vx       = self.vx or random:float(-24, 24)
  self.vy       = self.vy or random:float(-24, 24)
  self.rs       = self.rs or random:float(0.8, 1.7)
  self.alpha    = self.alpha or random:float(0.45, 0.8)
  self.duration = self.duration or random:float(0.4, 0.8)
  self.t:tween(self.duration, self, {alpha = 0}, math.linear, function() self.dead = true end)
end

function SporeMote:update(dt)
  self:update_game_object(dt)
  self.x  = self.x + self.vx*dt
  self.y  = self.y + self.vy*dt
  self.vx = self.vx*(1 - 2.4*dt)   -- the puff disperses + slows
  self.vy = self.vy*(1 - 2.4*dt)
end

function SporeMote:draw()
  graphics.circle(self.x, self.y, self.rs, Color(self.color.r, self.color.g, self.color.b, self.alpha))
end


-- JesterMote: a scrap of harlequin confetti shed by the jester. A small spinning
-- diamond pip flung outward that tumbles, flutters down on a little gravity, and
-- fades. The jester sheds a steady drizzle of these as its trail, and bursts a
-- ring of them on each curse cast and on every knife-burst death.
JesterMote = Object:extend()
JesterMote:implement(GameObject)
function JesterMote:init(args)
  self:init_game_object(args)
  self.color    = self.color or red[0]
  self.vx       = self.vx or random:float(-40, 40)
  self.vy       = self.vy or random:float(-50, 10)
  self.rs       = self.rs or random:float(1.4, 2.6)
  self.alpha    = self.alpha or random:float(0.55, 0.9)
  self.a        = self.a or random:float(0, 2*math.pi)
  self.spin     = self.spin or random:float(-14, 14)
  self.duration = self.duration or random:float(0.4, 0.85)
  self.t:tween(self.duration, self, {alpha = 0, rs = 0}, math.linear, function() self.dead = true end)
end

function JesterMote:update(dt)
  self:update_game_object(dt)
  self.x  = self.x + self.vx*dt
  self.y  = self.y + self.vy*dt
  self.vx = self.vx*(1 - 2.0*dt)            -- air drag
  self.vy = self.vy*(1 - 2.0*dt) + 80*dt    -- ...and a little gravity, so it flutters down
  self.a  = self.a + self.spin*dt
end

function JesterMote:draw()
  local c      = Color(self.color.r, self.color.g, self.color.b, self.alpha)
  local ca, sa = math.cos(self.a), math.sin(self.a)
  local r      = self.rs
  -- A diamond pip: four points rotated by self.a.
  local px = {0, r, 0, -r}
  local py = {-r, 0, r, 0}
  local v  = {}
  for i = 1, 4 do
    v[#v+1] = self.x + px[i]*ca - py[i]*sa
    v[#v+1] = self.y + px[i]*sa + py[i]*ca
  end
  graphics.polygon(v, c)
end


-- LightningArc: a jagged electric bolt drawn between two points, built by
-- recursive midpoint displacement -- each segment's midpoint is kicked
-- perpendicular by a halving offset, so the line frays into a forked bolt. It
-- snaps in bright and fades fast, draws a hot near-white core over a coloured
-- glow, and peels off a couple of short branches. The stormweaver's chain
-- links are drawn with these. Ported from SNKRX's LightningLine
-- (assets_from_SNKRX/objects.lua:40 + :69 generate) -- same midpoint-displacement
-- idea, rebuilt as a Ball Pit effect: ordered subdivision (no greedy re-sort),
-- segment-drawn (no unpack), plus forked branches.
LightningArc = Object:extend()
LightningArc:implement(GameObject)
function LightningArc:init(args)
  self:init_game_object(args)
  self.x        = self.x  or self.x1
  self.y        = self.y  or self.y1
  self.color    = self.color or blue[0]
  self.w        = self.w or 2.5
  self.duration = self.duration or 0.13
  self.gens     = self.gens or 4
  self.offset   = self.offset or 9
  self.alpha    = 1
  self:generate()
  self.t:tween(self.duration, self, {alpha = 0, w = math.max(1, self.w*0.4)}, math.linear,
    function() self.dead = true end)
  -- A spark at each endpoint so the bolt reads as landing on something.
  for _ = 1, 2 do HitParticle{group = self.group, x = self.x1, y = self.y1, color = self.color} end
  HitParticle{group = self.group, x = self.x2, y = self.y2, color = self.color}
end

-- Subdivide a straight segment into a jagged polyline (flat {x,y,x,y,...}).
function LightningArc:jag(x1, y1, x2, y2, gens, offset)
  local pts = {x1, y1, x2, y2}
  local off = offset
  for _ = 1, gens do
    local np = {}
    for i = 1, #pts - 2, 2 do
      local ax, ay = pts[i], pts[i+1]
      local bx, by = pts[i+2], pts[i+3]
      np[#np+1] = ax; np[#np+1] = ay
      local mx, my = (ax+bx)/2, (ay+by)/2
      local dx, dy = bx-ax, by-ay
      local len = math.sqrt(dx*dx + dy*dy)
      if len > 0 then
        local k = random:float(-off, off)
        mx = mx + (-dy/len)*k
        my = my + ( dx/len)*k
      end
      np[#np+1] = mx; np[#np+1] = my
    end
    np[#np+1] = pts[#pts-1]; np[#np+1] = pts[#pts]
    pts = np
    off = off*0.5
  end
  return pts
end

function LightningArc:generate()
  self.points   = self:jag(self.x1, self.y1, self.x2, self.y2, self.gens, self.offset)
  self.branches = {}
  local p = self.points
  for _ = 1, 2 do
    if #p >= 6 then
      local idx = (random:int(1, (#p/2) - 1))*2 - 1
      local bx, by = p[idx], p[idx+1]
      local a, bl  = random:float(0, 2*math.pi), random:float(6, 16)
      self.branches[#self.branches+1] = self:jag(bx, by, bx + math.cos(a)*bl, by + math.sin(a)*bl, 2, 4)
    end
  end
end

function LightningArc:update(dt) self:update_game_object(dt) end

local function draw_bolt_points(p, color, w)
  for i = 1, #p - 3, 2 do graphics.line(p[i], p[i+1], p[i+2], p[i+3], color, w) end
end

function LightningArc:draw()
  local c    = self.color
  local glow = Color(c.r, c.g, c.b, self.alpha*0.5)
  local core = Color(math.min(1, c.r*0.5 + 0.6), math.min(1, c.g*0.5 + 0.6),
                     math.min(1, c.b*0.5 + 0.7), self.alpha)
  draw_bolt_points(self.points, glow, self.w + 1.5)         -- coloured outer glow
  draw_bolt_points(self.points, core, math.max(1, self.w*0.6))  -- hot core
  for _, b in ipairs(self.branches) do draw_bolt_points(b, glow, 1) end
end


-- StormSpark: a tiny flickering zigzag spark shed by the stormweaver -- a 2-seg
-- electric tick that tumbles, decelerates, blinks on/off and fades. Used both as
-- its moving trail/emission and as the crackle burst on each discharge / bounce.
-- (Distinct from ArcaneSpark's spinning cross and SporeMote's soft dot.)
StormSpark = Object:extend()
StormSpark:implement(GameObject)
function StormSpark:init(args)
  self:init_game_object(args)
  self.color    = self.color or blue[0]
  self.vx       = self.vx or random:float(-30, 30)
  self.vy       = self.vy or random:float(-30, 30)
  self.len      = self.len or random:float(2.5, 5.5)
  self.a        = self.a or random:float(0, 2*math.pi)
  self.alpha    = self.alpha or random:float(0.5, 0.9)
  self.duration = self.duration or random:float(0.16, 0.38)
  self.vis      = true
  self.t:every(0.035, function() self.vis = not self.vis end)   -- electric flicker
  self.t:tween(self.duration, self, {alpha = 0}, math.linear, function() self.dead = true end)
end

function StormSpark:update(dt)
  self:update_game_object(dt)
  self.x  = self.x + self.vx*dt
  self.y  = self.y + self.vy*dt
  self.vx = self.vx*(1 - 3.2*dt)
  self.vy = self.vy*(1 - 3.2*dt)
  self.a  = self.a + 14*dt
end

function StormSpark:draw()
  if not self.vis then return end
  local c = Color(math.min(1, self.color.r*0.5 + 0.55), math.min(1, self.color.g*0.5 + 0.55),
                  math.min(1, self.color.b*0.5 + 0.65), self.alpha)
  local hl     = self.len/2
  local ca, sa = math.cos(self.a), math.sin(self.a)
  local k      = self.len*0.35
  graphics.line(self.x - ca*hl, self.y - sa*hl, self.x - sa*k, self.y + ca*k, c, 1)
  graphics.line(self.x - sa*k,  self.y + ca*k,  self.x + ca*hl, self.y + sa*hl, c, 1)
end


-- ConsecratedGround: the cleric's healing sigil (Consecrated Ground rework). A
-- verdant ring planted at the paddle -- while the paddle sits inside it the
-- player regenerates 1 HP per heal_interval, and bricks caught in the ring take
-- steady holy damage (dmg per second). Fades in, holds for `duration`, fades
-- out. Themed to match the Lifebloom cleric: soft fill, slow rotating rings,
-- a wreath of leaves orbiting the rim.
ConsecratedGround = Object:extend()
ConsecratedGround:implement(GameObject)
function ConsecratedGround:init(args)
  self:init_game_object(args)
  self.rs            = self.rs or 64
  self.color         = self.color or green[0]
  self.mode          = self.mode or 'heal'      -- 'heal' (pink, regen) | 'damage' (red, blades)
  self.duration      = self.duration or 6
  self.dmg           = self.dmg or 3            -- damage per SECOND to enemies inside
  self.heal_interval = self.heal_interval or 2.0
  self.heal_t        = 0
  self.dmg_t         = 0
  self.spin_a        = random:float(0, 2*math.pi)
  self.pulse         = 0
  self.alpha         = 0
  self.t:tween(0.3, self, {alpha = 1}, math.cubic_in_out)
  self.t:after(self.duration - 0.45, function()
    self.t:tween(0.45, self, {alpha = 0}, math.linear, function() self.dead = true end)
  end)
end

function ConsecratedGround:update(dt)
  self:update_game_object(dt)
  self.spin_a = self.spin_a + 1.5*dt   -- spins the pink flower at the sigil's heart
  self.pulse  = self.pulse + dt
  local arena = main.current
  if not arena then return end

  if self.mode == 'damage' then
    -- Razor blades: enemies are sliced only when a spinning petal sweeps over
    -- them, within the petals' reach (matches the flower, NOT the full ring).
    -- Each cut sits on a short per-target cooldown so it reads as discrete
    -- slices rather than a uniform burn pool.
    self.slice_cd = self.slice_cd or {}
    for id, t in pairs(self.slice_cd) do
      local nt = t - dt
      if nt <= 0 then self.slice_cd[id] = nil else self.slice_cd[id] = nt end
    end
    local reach     = self.rs*0.58       -- ~ the outer petals' tip reach
    local sector    = 2*math.pi/8        -- 8 outer blades (matches draw)
    local slice_dmg = self.dmg*0.6
    if arena.main then
      for _, o in ipairs(arena.main.objects) do
        if not o.dead and o.take_damage and o.id
        and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
          if not self.slice_cd[o.id]
          and math.distance(self.x, self.y, o.x, o.y) <= reach then
            -- offset to the nearest blade's angle; a hit only lands when a blade
            -- is actually sweeping over the target (the gaps between blades miss).
            local rel = (math.atan2(o.y - self.y, o.x - self.x) - self.spin_a) % sector
            if rel > sector/2 then rel = rel - sector end
            if math.abs(rel) <= 0.30 then
              o:take_damage(slice_dmg, red[0], true)
              self.slice_cd[o.id] = 0.45
              spawn_burst(arena.effects, o.x, o.y, red[0], 3, 60, 150)
            end
          end
        end
      end
    end
    return
  end

  -- Heal mode: a gentle consecrated burn over the whole ring, then regen.
  self.dmg_t = self.dmg_t + dt
  if self.dmg_t >= 0.2 then
    local tick = self.dmg*self.dmg_t
    self.dmg_t = 0
    if arena.main then
      for _, o in ipairs(arena.main.objects) do
        if not o.dead and o.take_damage
        and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
          if math.distance(self.x, self.y, o.x, o.y) <= self.rs then
            o:take_damage(tick, self.color, true)
            if random:bool(8) then
              SporeMote{group = arena.effects, x = o.x + random:float(-4, 4), y = o.y,
                        color = self.color, vx = random:float(-18, 18), vy = random:float(-26, -6),
                        rs = random:float(0.8, 1.6), duration = random:float(0.4, 0.7)}
            end
          end
        end
      end
    end
  end

  -- Regen the player while the paddle sits in the heal sigil.
  local p = arena.paddle
  if p and math.distance(self.x, self.y, p.x, p.y) <= self.rs then
    self.heal_t = self.heal_t + dt
    if self.heal_t >= self.heal_interval then
      self.heal_t = self.heal_t - self.heal_interval
      local healed = arena.heal_hearts and arena:heal_hearts(1) or 0
      if healed > 0 then
        heal1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
        FloatingText{group = arena.effects, x = p.x, y = p.y - 16, text = '+1 HP', color = green[0]}
      end
    end
  else
    self.heal_t = 0   -- must stay inside to keep the regen building
  end
end

-- One curled flower petal as a strip of convex quads (LOVE fills convex only),
-- for the spinning flower at the heart of the sigil. cx,cy = centre; a = base
-- angle; L = length; W = max width; hook = tip curl.
local function sigil_flower_petal(cx, cy, a, L, W, hook, col)
  local SEG = 6
  local ca, sa = math.cos(a), math.sin(a)
  local lx, ly, rx, ry = {}, {}, {}, {}
  for i = 0, SEG do
    local u = i/SEG
    local mx, my = u*L, hook*L*u*u
    local tx, ty = L, hook*L*2*u
    local tl = math.sqrt(tx*tx + ty*ty); tx, ty = tx/tl, ty/tl
    local nx, ny = -ty, tx
    local w = (math.sin(u*math.pi))^0.8 * W*0.5
    local axx, ayy = mx + nx*w, my + ny*w
    local bxx, byy = mx - nx*w, my - ny*w
    lx[i+1] = cx + axx*ca - ayy*sa; ly[i+1] = cy + axx*sa + ayy*ca
    rx[i+1] = cx + bxx*ca - byy*sa; ry[i+1] = cy + bxx*sa + byy*ca
  end
  for i = 1, SEG do
    graphics.polygon({lx[i], ly[i], rx[i], ry[i], rx[i+1], ry[i+1], lx[i+1], ly[i+1]}, col)
  end
end


function ConsecratedGround:draw()
  local A = self.alpha
  local dmg_mode = (self.mode == 'damage')
  local ring   = dmg_mode and red[0] or self.color
  local petal  = dmg_mode and Color(0.95, 0.24, 0.30, 0.85*A) or Color(0.96, 0.46, 0.72, 0.85*A)
  local petalL = dmg_mode and Color(1.00, 0.50, 0.50, 0.90*A) or Color(1.00, 0.72, 0.86, 0.90*A)
  local breathe = 0.85 + 0.15*math.sin(self.pulse*3)

  if dmg_mode then
    -- Damage sigil is JUST the spinning razor flower -- its blades ARE the
    -- hitbox (~rs*0.58). A faint edge ring marks the reach; no big burn pool.
    local edge = self.rs*0.58
    graphics.circle(self.x, self.y, edge, Color(ring.r, ring.g, ring.b, 0.08*A))
    graphics.circle(self.x, self.y, edge, Color(ring.r, ring.g, ring.b, 0.35*A), 1)
  else
    -- Heal sigil: soft fill + the full ring over the whole heal area.
    local r = self.rs*breathe
    graphics.circle(self.x, self.y, r, Color(ring.r, ring.g, ring.b, 0.10*A))
    graphics.circle(self.x, self.y, r, Color(ring.r, ring.g, ring.b, 0.5*A), 2)
    graphics.circle(self.x, self.y, self.rs*0.85, Color(ring.r, ring.g, ring.b, 0.22*A), 1)
  end

  -- The spinning flower (heal = pink petals; damage = red razor blades).
  local spin = self.spin_a
  for i = 0, 7 do
    sigil_flower_petal(self.x, self.y, spin + i*math.pi/4, self.rs*0.52, self.rs*0.34, 0.22, petal)
  end
  for i = 0, 5 do
    sigil_flower_petal(self.x, self.y, -spin*0.8 + (i + 0.5)*math.pi/3, self.rs*0.30, self.rs*0.22, 0.18, petalL)
  end
  graphics.circle(self.x, self.y, self.rs*0.13, Color(0.96, 0.9, 0.55, 0.95*A))
  graphics.circle(self.x, self.y, self.rs*0.07, Color(1, 1, 1, 0.8*A))
end


-- A brick-bounce "spark" — three tiny particles at the impact point, plus a
-- short scale-flash on the bouncing object.
function spawn_bounce_sparks(group, x, y, normal_angle, color)
  for i = 1, 3 do
    HitParticle{
      group = group, x = x, y = y, color = color or fg[0],
      duration = random:float(0.15, 0.25),
      w = random:float(1.5, 2.5),
      r = (normal_angle or 0) + random:float(-0.5, 0.5),
      v = random:float(60, 120),
    }
  end
end


-- WaterWave: a sweeping wall of water that surges from `y_start` (bottom of
-- the arena) up to `y_end` (top), shoving every swarm it touches upward as
-- it goes, then disperses with a foam-spray burst instead of blinking out.
WaterWave = Object:extend()
WaterWave:implement(GameObject)
function WaterWave:init(args)
  self:init_game_object(args)
  self.x1            = self.x1 or 0
  self.x2            = self.x2 or gw
  self.y_start       = self.y_start or gh
  self.y_end         = self.y_end or 0
  self.surge_dur     = self.surge_dur or 0.65
  self.disperse_dur  = self.disperse_dur or 0.55
  self.color         = self.color or blue2[0]
  self.phase         = 'surge'
  self.elapsed       = 0
  self.wave_y        = self.y_start
  self.body_alpha    = 1
  self.last_droplet  = 0
  self.swarm_touched = {}
end


function WaterWave:update(dt)
  self:update_game_object(dt)
  self.elapsed = self.elapsed + dt

  if self.phase == 'surge' then
    local p     = math.clamp(self.elapsed/self.surge_dur, 0, 1)
    local eased = 1 - (1 - p)*(1 - p)*(1 - p)
    self.wave_y = self.y_start + (self.y_end - self.y_start)*eased

    self:push_swarms()
    self:spawn_droplets(false)

    if p >= 1 then
      self.phase   = 'disperse'
      self.elapsed = 0
      self:disperse_burst()
    end

  elseif self.phase == 'disperse' then
    local p          = math.clamp(self.elapsed/self.disperse_dur, 0, 1)
    self.body_alpha  = 1 - p
    self.wave_y      = self.y_end + p*6
    if random:bool(35) then self:spawn_droplets(true) end
    if p >= 1 then self.dead = true end
  end
end


function WaterWave:push_swarms()
  local arena = main.current
  if not arena then return end
  for _, sw in ipairs(arena.swarms.objects) do
    if sw and not sw.dead then
      local lowest, has_live = -1e9, false
      for _, cell in ipairs(sw.cells or {}) do
        if cell.brick and not cell.brick.dead then
          -- bottom_y accounts for multi-cell shapes; the brick body sits at
          -- the shape centroid, so a 3-tall brick extends well past its dy.
          local by = cell.brick:bottom_y()
          if by > lowest then lowest = by end
          has_live = true
        end
      end
      if has_live and self.wave_y < lowest + 6 then
        local overlap = (lowest + 6) - self.wave_y
        sw.y_top = math.max(arena.y1 + 8, sw.y_top - overlap)
        if not self.swarm_touched[sw.id] then
          self.swarm_touched[sw.id] = true
          if sw.apply_knockback then sw:apply_knockback(140, -math.pi/2) end
          spawn_burst(arena.effects, sw.x_center, lowest, self.color, 10, 100, 180)
          spawn_burst(arena.effects, sw.x_center, lowest, fg[5], 4, 60, 140)
          if pop1 then pop1:play{volume = 0.25, pitch = random:float(0.7, 0.9)} end
        end
      end
    end
  end
end


function WaterWave:spawn_droplets(sparse)
  local count = sparse and 1 or 4
  for _ = 1, count do
    local dx     = random:float(self.x1 + 4, self.x2 - 4)
    local color  = (random:bool(40) and fg[5]) or self.color
    HitParticle{
      group     = main.current.effects,
      x         = dx, y = self.wave_y + random:float(-3, 3),
      color     = color,
      v         = random:float(80, 160),
      r         = -math.pi/2 + random:float(-0.7, 0.7),
      w         = random:float(1, 2.5),
      duration  = random:float(0.3, 0.65),
    }
  end
end


function WaterWave:disperse_burst()
  local arena = main.current
  if not arena then return end
  for _ = 1, 36 do
    local dx     = random:float(self.x1 + 4, self.x2 - 4)
    local color  = (random:bool(50) and fg[5]) or self.color
    HitParticle{
      group     = arena.effects,
      x         = dx, y = self.wave_y,
      color     = color,
      v         = random:float(80, 200),
      r         = -math.pi/2 + random:float(-1.0, 1.0),
      w         = random:float(1.5, 3),
      duration  = random:float(0.45, 0.9),
    }
  end
  spawn_burst(arena.effects, (self.x1 + self.x2)/2, self.wave_y, fg[5], 12, 60, 160)
  TelegraphRing{group = arena.effects, x = (self.x1 + self.x2)/2, y = self.wave_y,
                radius = (self.x2 - self.x1)*0.55, color = self.color, duration = 0.45}
end


function WaterWave:draw()
  local w  = self.x2 - self.x1
  local cx = (self.x1 + self.x2)/2

  local body_h = self.y_start - self.wave_y
  if body_h > 1 then
    local base_a = (self.phase == 'disperse') and (0.34*self.body_alpha) or 0.34
    graphics.rectangle(cx, self.wave_y + body_h/2, w, body_h, nil, nil,
      Color(self.color.r, self.color.g, self.color.b, base_a))
    if body_h > 12 then
      local deep_h = math.min(body_h, 26)
      graphics.rectangle(cx, self.y_start - deep_h/2, w, deep_h, nil, nil,
        Color(self.color.r*0.5, self.color.g*0.5, self.color.b*0.95, base_a*1.15))
    end
  end

  local front_a
  if self.phase == 'surge' then front_a = 0.9
  else                          front_a = math.max(0, self.body_alpha*0.75) end
  if front_a > 0.05 then
    local segs  = 40
    local amp   = 4 + 3*math.sin(self.elapsed*22)
    local phase = self.elapsed*20
    local body_c  = Color(self.color.r*0.7, self.color.g*0.7, self.color.b, front_a)
    local crest_c = Color(1, 1, 1, front_a*0.85)
    local prev_xb, prev_yb = self.x1, self.wave_y
    local prev_xc, prev_yc = self.x1, self.wave_y - 2
    for i = 1, segs do
      local t      = i/segs
      local x      = self.x1 + t*w
      local y_body = self.wave_y + math.sin(t*math.pi*5 + phase)*amp
      local y_crest = y_body - 2.5 - 0.5*math.sin(t*math.pi*7 - phase*0.55)
      graphics.line(prev_xb, prev_yb, x, y_body,  body_c,  2)
      graphics.line(prev_xc, prev_yc, x, y_crest, crest_c, 1)
      prev_xb, prev_yb = x, y_body
      prev_xc, prev_yc = x, y_crest
    end
  end
end


-- CleaveArea: the swordsman's Cleave, ported from SNKRX's Area (player.lua).
-- A rotated square that hits everything inside ONCE at spawn — total damage
-- grows +15% per target hit (the Cleave), doubled at level 3 (SNKRX's
-- max-level passive). The visual is the SNKRX original: white corner
-- brackets + a faint fill snap out in 0.05s, flip to the hero colour after
-- 0.2s, then blink away. Lives in the effects group — pure visual after the
-- instant hit, no physics body.
CleaveArea = Object:extend()
CleaveArea:implement(GameObject)
function CleaveArea:init(args)
  self:init_game_object(args)
  self.r     = self.r or 0
  self.dmg   = self.dmg or 10
  self.level = self.level or 1
  local full_w = self.w or 96    -- visual square side; the hit square is 1.5x

  -- Hit test: every live target whose centre falls inside the rotated square
  -- of side 1.5*w (the same 1.5x ratio as SNKRX's Rectangle hit shape).
  -- Unlike do_splash this includes the Boss and critters — the cleave is the
  -- swordsman's whole offense, so it has to work on everything.
  local arena = main.current
  local half  = full_w*1.5/2
  local cos_r, sin_r = math.cos(self.r), math.sin(self.r)
  local targets = {}
  if arena and arena.main then
    for _, o in ipairs(arena.main.objects) do
      if not o.dead and o.take_damage
      and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
        local dx, dy = o.x - self.x, o.y - self.y
        local lx =  dx*cos_r + dy*sin_r
        local ly = -dx*sin_r + dy*cos_r
        if math.abs(lx) <= half and math.abs(ly) <= half then
          targets[#targets + 1] = o
        end
      end
    end
  end

  if #targets > 0 then
    local total = self.dmg*(1 + 0.15*#targets)
    if self.level >= 3 then total = total*2 end
    for _, o in ipairs(targets) do
      o:take_damage(total, self.color)
      HitParticle{group = self.group, x = o.x, y = o.y, color = self.color}
      HitParticle{group = self.group, x = o.x, y = o.y, color = o.color}
    end
    -- One impact sound per cleave — per-target stacking gets loud fast.
    hit2:play{pitch = random:float(0.95, 1.05), volume = 0.35}
  end

  -- SNKRX Area visual: snap out white, flip to the hero colour, blink away.
  local body_color = self.color
  self.color = fg[0]
  self.color_transparent = Color(body_color.r, body_color.g, body_color.b, 0.08)
  self.w = 0
  self.hidden = false
  self.t:tween(0.05, self, {w = full_w}, math.cubic_in_out, function() self.spring:pull(0.15) end)
  self.t:after(0.2, function()
    self.color = body_color
    self.t:every_immediate(0.05, function() self.hidden = not self.hidden end, 7, function() self.dead = true end)
  end)
end

function CleaveArea:update(dt)
  self:update_game_object(dt)
end

function CleaveArea:draw()
  if self.hidden then return end
  graphics.push(self.x, self.y, self.r, self.spring.x, self.spring.x)
  local w = self.w/2
  local w10 = self.w/10
  local x1, y1 = self.x - w, self.y - w
  local x2, y2 = self.x + w, self.y + w
  local lw = math.remap(w, 32, 256, 2, 4)
  graphics.polyline(self.color, lw, x1, y1 + w10, x1, y1, x1 + w10, y1)
  graphics.polyline(self.color, lw, x2 - w10, y1, x2, y1, x2, y1 + w10)
  graphics.polyline(self.color, lw, x2 - w10, y2, x2, y2, x2, y2 - w10)
  graphics.polyline(self.color, lw, x1, y2 - w10, x1, y2, x1 + w10, y2)
  graphics.rectangle((x1+x2)/2, (y1+y2)/2, x2-x1, y2-y1, nil, nil, self.color_transparent)
  graphics.pop()
end




-- HexSlamArea: the barbarian's Hammer Slam -- the swordsman's CleaveArea scaled
-- up and reshaped into a big HEXAGON shockwave. Hits everything inside ONCE at
-- spawn (+15% total damage per target, x2 at level 3, exactly like the Cleave),
-- then a thick hex outline + faint fill snaps out, a shockwave ring expands and
-- dust kicks up, and it blinks away. self.w is the hexagon's circumradius; the
-- hit test is a true regular-hexagon point test (3 edge-normal projections).
HexSlamArea = Object:extend()
HexSlamArea:implement(GameObject)
function HexSlamArea:init(args)
  self:init_game_object(args)
  -- Start at a varied angle and spin as it snaps out, so no two slams look the
  -- same and the hexagon reads as a whirling shockwave rather than a static
  -- stamp. The instant hit below uses this spawn angle; the spin is visual.
  self.r     = (self.r or 0) + random:float(0, math.pi/3)
  self.spin  = (random:bool(50) and 1 or -1)*random:float(4, 7)
  self.dmg   = self.dmg or 10
  self.level = self.level or 1
  local full_w = self.w or 110   -- hexagon circumradius (vertex distance)

  -- Hit test: a point is inside a regular hexagon if its projection onto each
  -- of the 3 edge-normals is within the apothem (R*cos(30deg)).
  local arena   = main.current
  local apothem = full_w*math.cos(math.pi/6)
  local targets = {}
  if arena and arena.main then
    for _, o in ipairs(arena.main.objects) do
      if not o.dead and o.take_damage
      and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
        local dx, dy = o.x - self.x, o.y - self.y
        local inside = true
        for k = 0, 2 do
          local na = self.r + math.pi/6 + k*math.pi/3
          if math.abs(dx*math.cos(na) + dy*math.sin(na)) > apothem then
            inside = false
            break
          end
        end
        if inside then targets[#targets + 1] = o end
      end
    end
  end

  if #targets > 0 then
    local total = self.dmg*(1 + 0.15*#targets)
    if self.level >= 3 then total = total*2 end
    for _, o in ipairs(targets) do
      o:take_damage(total, self.color)
      HitParticle{group = self.group, x = o.x, y = o.y, color = self.color}
      HitParticle{group = self.group, x = o.x, y = o.y, color = o.color}
    end
    -- One heavy, low-pitched impact per slam.
    hit2:play{pitch = random:float(0.7, 0.85), volume = 0.5}
  end

  -- Slam juice (regardless of hits): an expanding shockwave ring + a kick of
  -- dust at the impact point.
  TelegraphRing{group = self.group, x = self.x, y = self.y, radius = full_w*1.15, color = self.color, duration = 0.3}
  spawn_burst(self.group, self.x, self.y, fg[0], 8, 90, 210)

  -- SNKRX Area visual: snap out white, flip to the hero colour, blink away.
  local body_color = self.color
  self.color = fg[0]
  self.color_transparent = Color(body_color.r, body_color.g, body_color.b, 0.10)
  self.w = 0
  self.hidden = false
  self.t:tween(0.06, self, {w = full_w}, math.cubic_in_out, function() self.spring:pull(0.2) end)
  self.t:after(0.22, function()
    self.color = body_color
    self.t:every_immediate(0.05, function() self.hidden = not self.hidden end, 7, function() self.dead = true end)
  end)
end

function HexSlamArea:update(dt)
  self:update_game_object(dt)
  self.r = self.r + (self.spin or 0)*dt   -- whirl the hexagon as it expands/fades
end

function HexSlamArea:draw()
  if self.hidden then return end
  graphics.push(self.x, self.y, self.r, self.spring.x, self.spring.x)
  local verts = {}
  for k = 0, 5 do
    local a = k*math.pi/3
    verts[#verts + 1] = self.x + math.cos(a)*self.w
    verts[#verts + 1] = self.y + math.sin(a)*self.w
  end
  local lw = math.remap(self.w, 32, 256, 3, 6)
  graphics.polygon(verts, self.color_transparent)
  graphics.polygon(verts, self.color, lw)
  graphics.pop()
end


-- A spent archer bolt stuck in the wall (SNKRX WallArrow port): a short
-- coloured shaft flashes white on impact, sits in the wall for a moment,
-- then blinks out. Pure visual -- spawned by projectile.lua's wall_stick
-- handling when a bolt runs out of ricochets at a wall.
WallArrow = Object:extend()
WallArrow:implement(GameObject)
function WallArrow:init(args)
  self:init_game_object(args)
  self.r       = self.r or 0
  self.flash_t = 0.25
  self.t:after({0.8, 2}, function()
    self.t:every_immediate(0.05, function() self.hidden = not self.hidden end, 7, function() self.dead = true end)
  end)
end

function WallArrow:update(dt)
  self:update_game_object(dt)
  if self.flash_t > 0 then self.flash_t = self.flash_t - dt end
end

function WallArrow:draw()
  if self.hidden then return end
  graphics.push(self.x, self.y, self.r)
  graphics.rectangle(self.x, self.y, 10, 3, 1, 1, (self.flash_t > 0) and fg[0] or self.color)
  graphics.pop()
end




-- The volcano's eruption blast (SNKRX Area port, flat damage): a rotated
-- square that hits everything inside ONCE at spawn for the full damage —
-- no per-target scaling; that's the swordsman's CleaveArea above. Visual is
-- the same SNKRX snap: white corner brackets + faint fill flip to the owner
-- colour after 0.2s, then blink away.
EruptionArea = Object:extend()
EruptionArea:implement(GameObject)
function EruptionArea:init(args)
  self:init_game_object(args)
  self.r       = self.r or 0
  self.dmg     = self.dmg or 10
  local full_w = self.w or 72    -- visual square side; the hit square is 1.5x

  local arena = main.current
  local half  = full_w*1.5/2
  local cos_r, sin_r = math.cos(self.r), math.sin(self.r)
  if arena and arena.main then
    for _, o in ipairs(arena.main.objects) do
      if not o.dead and o.take_damage
      and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
        local dx, dy = o.x - self.x, o.y - self.y
        local lx =  dx*cos_r + dy*sin_r
        local ly = -dx*sin_r + dy*cos_r
        if math.abs(lx) <= half and math.abs(ly) <= half then
          o:take_damage(self.dmg, self.color)
          HitParticle{group = self.group, x = o.x, y = o.y, color = self.color}
          HitParticle{group = self.group, x = o.x, y = o.y, color = o.color}
        end
      end
    end
  end

  -- SNKRX Area visual: snap out white, flip to the owner colour, blink away.
  local body_color = self.color
  self.color = fg[0]
  self.color_transparent = Color(body_color.r, body_color.g, body_color.b, 0.08)
  self.w = 0
  self.hidden = false
  self.t:tween(0.05, self, {w = full_w}, math.cubic_in_out, function() self.spring:pull(0.15) end)
  self.t:after(0.2, function()
    self.color = body_color
    self.t:every_immediate(0.05, function() self.hidden = not self.hidden end, 7, function() self.dead = true end)
  end)
end

function EruptionArea:update(dt)
  self:update_game_object(dt)
end

function EruptionArea:draw()
  if self.hidden then return end
  graphics.push(self.x, self.y, self.r, self.spring.x, self.spring.x)
  local w = self.w/2
  local w10 = self.w/10
  local x1, y1 = self.x - w, self.y - w
  local x2, y2 = self.x + w, self.y + w
  local lw = math.remap(w, 32, 256, 2, 4)
  graphics.polyline(self.color, lw, x1, y1 + w10, x1, y1, x1 + w10, y1)
  graphics.polyline(self.color, lw, x2 - w10, y1, x2, y1, x2, y1 + w10)
  graphics.polyline(self.color, lw, x2 - w10, y2, x2, y2, x2, y2 - w10)
  graphics.polyline(self.color, lw, x1, y2 - w10, x1, y2, x1 + w10, y2)
  graphics.rectangle((x1+x2)/2, (y1+y2)/2, x2-x1, y2-y1, nil, nil, self.color_transparent)
  graphics.pop()
end




-- The vulcanist's Volcano (SNKRX port): plants at the cast point with a big
-- shake + earth/fire blast, then erupts an EruptionArea once a second 4
-- times (level 3: every 0.5s, 8 times — the Lava Burst passive), each with
-- its own shake and earth/fire rumble, and blinks out after 4s. Damage is
-- read live off the parent ball at every eruption so charge/ally/loadout
-- buffs apply per tick. Pure effect — unlike SNKRX it has no physics body
-- (swarm movement here is spring-driven, so nothing would bounce off it).
Volcano = Object:extend()
Volcano:implement(GameObject)
function Volcano:init(args)
  self:init_game_object(args)
  self.level   = self.level or 1
  self.area    = self.area or 72
  self.rs_full = self.rs or 24

  -- Crown rotation: the four rim arcs drift at a random angular speed.
  self.vr  = 0
  self.dvr = random:float(-math.pi/4, math.pi/4)

  -- Snap-in: white -> owner colour, radius 0 -> full (the SNKRX Area snap).
  self.body_color        = self.color
  self.color             = fg[0]
  self.color_transparent = Color(self.body_color.r, self.body_color.g, self.body_color.b, 0.08)
  self.rs     = 0
  self.hidden = false
  self.t:tween(0.05, self, {rs = self.rs_full}, math.cubic_in_out, function() self.spring:pull(0.15) end)
  self.t:after(0.2, function() self.color = self.body_color end)

  camera:shake(6, 1)
  earth1:play{pitch = random:float(0.95, 1.05), volume = 0.5}
  fire1:play{pitch = random:float(0.95, 1.05), volume = 0.5}

  -- The eruption loop, on the exact SNKRX cadence.
  self.t:every(self.level >= 3 and 0.5 or 1, function()
    camera:shake(4, 0.5)
    _G[random:table{'earth1', 'earth2', 'earth3'}]:play{pitch = random:float(0.95, 1.05), volume = 0.25}
    _G[random:table{'fire1', 'fire2', 'fire3'}]:play{pitch = random:float(0.95, 1.05), volume = 0.25}
    local dmg = self.dmg or 10
    if self.parent and not self.parent.dead and self.parent.current_dmg then
      dmg = self.parent:current_dmg()
    end
    -- dmg_mult carries the ranged pace-tuning bonus (see ball_hero.lua).
    dmg = dmg*(self.dmg_mult or 1)
    EruptionArea{group = self.group, x = self.x, y = self.y, w = self.area,
                 r = random:float(0, 2*math.pi), color = self.body_color, dmg = dmg}
  end, self.level >= 3 and 8 or 4)

  self.t:after(4, function()
    self.t:every_immediate(0.05, function() self.hidden = not self.hidden end, 7, function() self.dead = true end)
  end)
end

function Volcano:update(dt)
  self:update_game_object(dt)
  self.vr = self.vr + self.dvr*dt
end

function Volcano:draw()
  if self.hidden then return end
  -- The cone: an upward triangle (push by -pi/2 because the engine's
  -- triangles point right at angle 0) — same 13.5-wide outline as SNKRX.
  graphics.push(self.x, self.y, -math.pi/2, self.spring.x, self.spring.x)
    graphics.triangle_equilateral(self.x, self.y, 13.5, self.color, 3)
  graphics.pop()
  -- The crown: faint disc + four slowly drifting arc segments at the rim.
  graphics.push(self.x, self.y, self.vr, self.spring.x, self.spring.x)
    graphics.circle(self.x, self.y, self.rs, self.color_transparent)
    for i = 1, 4 do
      graphics.arc('open', self.x, self.y, self.rs,
                   (i - 1)*math.pi/2 + math.pi/4 - math.pi/8,
                   (i - 1)*math.pi/2 + math.pi/4 + math.pi/8, self.color, 2)
    end
  graphics.pop()
end
