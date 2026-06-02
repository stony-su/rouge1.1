-- The player-controlled paddle that ball-heroes bounce off of.
-- Bullet-hell style: small hitbox, free movement in a dodge band at the
-- bottom of the arena. A/D pan horizontally, W/S move vertically within
-- the band so the player can dodge incoming projectiles between bounces.

Paddle = Object:extend()
Paddle:implement(GameObject)
Paddle:implement(Physics)

-- Vertical dodge band: how far above the spawn y the paddle can climb.
-- ~80px gives enough room to weave between bullets without reaching into
-- the brick-fall zone in the upper arena.
local DODGE_BAND_UP   = 80
local DODGE_BAND_DOWN = 2

function Paddle:init(args)
  self:init_game_object(args)
  self.w     = self.w or 36           -- was 56 — shrunk for bullet-hell pressure
  self.h     = self.h or 4            -- was 6
  self.speed = self.speed or 220
  -- Remember the spawn y so the dodge band is centred wherever the arena
  -- placed us, no matter the resolution / playfield height.
  self.y_anchor = self.y
  self.color = fg[0]
  self:set_as_rectangle(self.w, self.h, 'kinematic', 'paddle')
  self:set_restitution(1)
  self.t:after(0, function()
    if self.body then self.body:setFixedRotation(true) end
  end)
  self.hfx:add('hit', 1)
end

function Paddle:update(dt)
  self:update_game_object(dt)

  local arena = main.current

  -- A/D move horizontally; W/S move vertically inside the dodge band. Aim
  -- (arrow keys) and movement are separate bindings, so the paddle keeps
  -- moving freely even when a ball is stuck.
  local left  = input.move_left.down  and 1 or 0
  local right = input.move_right.down and 1 or 0
  local up    = input.move_up.down    and 1 or 0
  local down  = input.move_down.down  and 1 or 0
  local dx    = right - left
  local dy    = down - up

  local target_x = self.x + dx*self.speed*dt
  target_x = math.clamp(target_x, arena.x1 + self.w/2, arena.x2 - self.w/2)

  local target_y = self.y + dy*self.speed*dt
  target_y = math.clamp(target_y, self.y_anchor - DODGE_BAND_UP,
                                  self.y_anchor + DODGE_BAND_DOWN)

  self:set_position(target_x, target_y)

  self.vx = dx*self.speed
end

function Paddle:draw()
  local s = self.hfx.hit.x
  local body_color = self.hfx.hit.f and fg[0] or self.color
  graphics.push(self.x, self.y, 0, s, 1/s)
    graphics.rectangle(self.x, self.y, self.w, self.h, 2, 2, body_color)
    graphics.rectangle(self.x, self.y - self.h/2, self.w, 1, nil, nil, fg[5])
  graphics.pop()
end

-- Called when a ball collides with the paddle. Tilts the reflection so the
-- player can aim by hitting the ball with the edge of the paddle, and ramps
-- the ball's speed multiplier so chained bounces feel rewarding.
function Paddle:on_ball_bounce(ball)
  self.hfx:use('hit', 0.18, 200, 10)

  -- Ramp the ball's speed multiplier. Capped so chains plateau instead of
  -- spiraling into uncontrollable speed.
  ball.speed_mult = math.min(ball.speed_mult_max, (ball.speed_mult or 1)*(ball.speed_mult_step or 1.07))

  -- Pitch + spark count both scale with the streak so the feedback escalates.
  local pitch_lift = math.min(0.35, (ball.speed_mult - 1)*0.5)
  bounce1:play{volume = 0.4, pitch = random:float(0.95, 1.05) + pitch_lift}
  spawn_bounce_sparks(main.current.effects, ball.x, ball.y, -math.pi/2, ball.color)
  if ball.speed_mult > 1.6 then
    spawn_bounce_sparks(main.current.effects, ball.x, ball.y, -math.pi/2, ball.color)
  end

  local hit_offset = (ball.x - self.x) / (self.w/2)
  hit_offset = math.clamp(hit_offset, -1, 1)
  local angle = -math.pi/2 + hit_offset*(math.pi/3)
  local speed = ball.base_speed*ball.speed_mult
  ball:set_velocity(speed*math.cos(angle), speed*math.sin(angle))
end
