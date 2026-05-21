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
