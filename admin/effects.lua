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


-- BombDrop: blinks at its fuse rate, then explodes via arena:do_splash.
BombDrop = Object:extend()
BombDrop:implement(GameObject)
function BombDrop:init(args)
  self:init_game_object(args)
  self.dmg     = self.dmg or 10
  self.radius  = self.radius or 48
  self.fuse    = self.fuse or 2
  self.color   = self.color or orange[0]
  self.elapsed = 0
  self.t:after(self.fuse, function() self:explode() end)
end
function BombDrop:update(dt)
  self:update_game_object(dt)
  self.elapsed = self.elapsed + dt
end
function BombDrop:draw()
  -- Blink frequency ramps up as the fuse runs down.
  local left = math.max(0.05, self.fuse - self.elapsed)
  local hz   = math.clamp(3 + (self.fuse - left)*4, 3, 16)
  local on   = math.floor(love.timer.getTime()*hz) % 2 == 0
  local col  = on and self.color or fg[0]
  graphics.circle(self.x, self.y, 4, col)
  graphics.circle(self.x, self.y, 2, fg[5])
end
function BombDrop:explode()
  local arena = main.current
  if arena then
    arena:do_splash(self.x, self.y, self.radius, self.dmg, self.color)
  end
  explosion1:play{volume = 0.4, pitch = random:float(0.9, 1.05)}
  self.dead = true
end


-- AllyTurret: parks above the paddle, fires projectiles at the nearest brick
-- on its own cooldown, despawns after `lifetime` seconds.
AllyTurret = Object:extend()
AllyTurret:implement(GameObject)
function AllyTurret:init(args)
  self:init_game_object(args)
  self.lifetime = self.lifetime or 10
  self.fire_cd  = self.fire_cd or 1.5
  self.range    = self.range or 96
  self.dmg      = self.dmg or 6
  self.color    = self.color or orange[0]
  self.t:after(self.lifetime, function() self.dead = true end)
  self.t:every(self.fire_cd, function() self:fire() end)
  self.born_at = love.timer.getTime()
end
function AllyTurret:update(dt) self:update_game_object(dt) end
function AllyTurret:draw()
  local age = love.timer.getTime() - self.born_at
  local fade = 1
  if age > self.lifetime - 1 then fade = math.max(0.3, self.lifetime - age) end
  graphics.rectangle(self.x, self.y, 8, 8, 2, 2, Color(self.color.r, self.color.g, self.color.b, fade))
  graphics.circle(self.x, self.y, 1.6, fg[5])
end
function AllyTurret:fire()
  local arena = main.current
  if not (arena and arena.main and arena.main.world) then return end
  local target = arena:get_nearest_brick_within(self.x, self.y, self.range)
  if not target then return end
  local r = math.atan2(target.y - self.y, target.x - self.x)
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      Projectile{group = arena.main, x = self.x, y = self.y, r = r,
                 type = 'arrow', dmg = self.dmg, speed = 180, color = self.color, pierce = 1}
    end
  end)
  shoot1:play{volume = 0.12, pitch = random:float(1.0, 1.15)}
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


-- WaterWave: a sweeping wall of water that surges from `y_start` (bottom of
-- the arena) up to `y_end` (top), shoving every swarm it touches upward as
-- it goes, then disperses with a foam-spray burst instead of blinking out.
--
-- Two phases:
--   surge    — the wavefront crawls up the arena (cubic-out ease), continuously
--              shoving every swarm whose lowest live brick is below the
--              front. Each swarm gets a one-time knockback + splash burst
--              the first time it's touched, plus per-frame pushback while
--              the wave is overlapping it.
--   disperse — the wave has peaked at the top. The body fades and breaks
--              into spray; foam particles fly upward and outward; a final
--              high splash crowns the wave. The whole effect lives ~1.2 s
--              total instead of disappearing in a single frame.
WaterWave = Object:extend()
WaterWave:implement(GameObject)
function WaterWave:init(args)
  self:init_game_object(args)
  self.x1            = self.x1 or 0
  self.x2            = self.x2 or gw
  self.y_start       = self.y_start or gh   -- wave originates here (bottom)
  self.y_end         = self.y_end or 0      -- wave settles here at peak (top)
  self.surge_dur     = self.surge_dur or 0.65
  self.disperse_dur  = self.disperse_dur or 0.55
  self.color         = self.color or blue2[0]
  self.phase         = 'surge'
  self.elapsed       = 0
  self.wave_y        = self.y_start
  self.body_alpha    = 1
  self.last_droplet  = 0
  self.swarm_touched = {}                   -- swarm.id -> true (one-time impulse already applied)
end


function WaterWave:update(dt)
  self:update_game_object(dt)
  self.elapsed = self.elapsed + dt

  if self.phase == 'surge' then
    local p     = math.clamp(self.elapsed/self.surge_dur, 0, 1)
    -- Cubic-out: surges fast off the paddle, decelerates as it nears the top.
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
    -- Lets the body settle slightly downward as it dissolves — sells "the
    -- water is collapsing" instead of "it just teleported away".
    self.wave_y      = self.y_end + p*6
    -- Sparse droplets keep raining for a bit so the screen doesn't go
    -- empty all at once.
    if random:bool(35) then self:spawn_droplets(true) end
    if p >= 1 then self.dead = true end
  end
end


-- Continuous-pushback model. While the wavefront is at or above each
-- swarm's lowest live brick (on screen — y is smaller for "higher"), the
-- swarm's y_top is pulled up by the overlap amount, so the bricks are
-- always lifted just above the wave. First touch also fires a knockback
-- impulse for the spring oscillation, plus a chunky splash burst so the
-- player sees the impact.
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
        -- Wave has reached or passed under this swarm's lowest brick.
        -- Lift the swarm so the lowest brick sits just above the front.
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


-- Big spray when the wave hits the top of the arena. Foam shoots up and
-- outward; the centre gets a chunky burst; a fading ring telegraphs the
-- dispersal moment so the player reads "this is winding down" rather than
-- "the effect ended".
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
      r         = -math.pi/2 + random:float(-1.0, 1.0),     -- fan upward
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

  -- Body of water below the wavefront. Translucent fill plus a deeper-blue
  -- band at the floor so it reads as having mass / depth. Alpha tracks the
  -- disperse phase so the body fades out smoothly.
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

  -- Wavefront crest: two stacked sine lines (dark body + bright foam) with
  -- fast phase scroll so it looks like churning water, not a static line.
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




-- A spent archer bolt stuck in the wall (SNKRX WallArrow port): a short
-- coloured shaft flashes white on impact, sits in the wall for a moment,
-- then blinks out. Pure visual — spawned by projectile.lua's wall_stick
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
