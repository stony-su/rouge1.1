-- The player-controlled paddle that ball-heroes bounce off of.
-- Bullet-hell style: small hitbox, free movement in a dodge band at the
-- bottom of the arena. A/D pan horizontally, W/S move vertically within
-- the band so the player can dodge incoming projectiles between bounces.
--
-- Paddle LOADOUTS (see paddles.lua / PADDLES.md) feed this file:
--   * w / speed / color / aim_mult arrive as ctor args from reset_run,
--   * `flippers` switches the body to the Pinball Lobber's two-fixture rig,
--   * `move_mode = 'ice'` switches movement to the Glacier's sliding model,
--   * on_ball_bounce gates per-signature behavior (aegis wipe, cannon mortar
--     launch, tesla zap, hive maggots) off arena.run_mods.

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
  self.w        = self.w or 36          -- was 56 — shrunk for bullet-hell pressure
  self.h        = self.h or 4           -- was 6
  self.speed    = self.speed or 220
  self.aim_mult = self.aim_mult or 1    -- loadout Aim stat: scales the reflection arc
  -- Remember the spawn y so the dodge band is centred wherever the arena
  -- placed us, no matter the resolution / playfield height.
  self.y_anchor = self.y
  -- Top of the dodge band — the highest point the paddle can climb to. The
  -- arena draws a red "defense line" here and treats it as the enemy breach
  -- boundary (anything that crosses it costs the player HP), so expose it for
  -- swarm.lua / enemies.lua / the HUD instead of hiding it behind the band const.
  self.top_reach = self.y_anchor - DODGE_BAND_UP
  self.color = self.color or fg[0]

  if self.flippers then
    self.flipper_gap = self.flipper_gap or 8
    self.flip_window = self.flip_window or 0.15
    self.flip_l_t, self.flip_r_t = 0, 0
    self:build_flipper_rig(1)
  else
    self:set_as_rectangle(self.w, self.h, 'kinematic', 'paddle')
    self:set_restitution(1)
  end

  self.t:after(0, function()
    if self.body then self.body:setFixedRotation(true) end
  end)
  self.hfx:add('hit', 1)
end


-- Pinball Lobber: the paddle is two small angled flippers with a drain gap
-- between them, both fixtures on one kinematic body. Physics:destroy and
-- set_restitution/set_friction already iterate self.fixtures, so the second
-- fixture rides along with the mixin's lifecycle. `scale` lets the
-- wide_paddle powerup grow/shrink the whole rig (it can't rebuild_rect_body
-- a two-fixture paddle).
function Paddle:build_flipper_rig(scale)
  local px, py = self.x, self.y
  if self.body then self:destroy() end
  self.x, self.y = px, py

  self.flipper_scale = scale or 1
  self.flipper_w     = 18*self.flipper_scale
  self.flipper_tilt  = 0.22
  local gap          = self.flipper_gap or 8
  self.flipper_off   = (gap + self.flipper_w)/2
  -- Logical span including the gap — the bullet hit-test, xp magnet and
  -- powerup catch all read paddle.w, so they keep working over the whole rig.
  self.w             = self.flipper_w*2 + gap

  local tag  = 'paddle'
  self.tag   = tag
  self.shape = Rectangle(self.x, self.y, self.w, self.h + 6)
  self.body  = love.physics.newBody(self.group.world, self.x, self.y, 'kinematic')
  -- Resting pose: each flipper slopes down toward the centre gap (y-down, so
  -- +tilt drops the left flipper's inner end). The fixtures never physically
  -- rotate on a flip — the lob in flipper_bounce overrides the reflection.
  local left_shape  = love.physics.newRectangleShape(-self.flipper_off, 0, self.flipper_w, self.h,  self.flipper_tilt)
  local right_shape = love.physics.newRectangleShape( self.flipper_off, 0, self.flipper_w, self.h, -self.flipper_tilt)
  self.fixture  = love.physics.newFixture(self.body, left_shape)
  local right_f = love.physics.newFixture(self.body, right_shape)
  self.fixtures = {right_f}
  for _, f in ipairs({self.fixture, right_f}) do
    f:setUserData(self.id)
    f:setCategory(self.group.collision_tags[tag].category)
    f:setMask(unpack(self.group.collision_tags[tag].masks))
    f:setRestitution(1)
    f:setFriction(0)
  end
  self.body:setFixedRotation(true)
end


function Paddle:update(dt)
  self:update_game_object(dt)

  local arena = main.current

  -- Pinball flip taps. The arrow keys double as aim keys while a ball is
  -- stuck (or space is held) — aiming wins, flips only register otherwise.
  if self.flippers then
    self.flip_l_t = math.max(0, (self.flip_l_t or 0) - dt)
    self.flip_r_t = math.max(0, (self.flip_r_t or 0) - dt)
    local aiming = arena and ((arena.stuck_count or 0) > 0 or input.launch.down)
    if not aiming then
      if input.aim_left.pressed  then self.flip_l_t = self.flip_window end
      if input.aim_right.pressed then self.flip_r_t = self.flip_window end
    end
  end

  -- A/D move horizontally; W/S move vertically inside the dodge band. Aim
  -- (arrow keys) and movement are separate bindings, so the paddle keeps
  -- moving freely even when a ball is stuck.
  local left  = input.move_left.down  and 1 or 0
  local right = input.move_right.down and 1 or 0
  local up    = input.move_up.down    and 1 or 0
  local down  = input.move_down.down  and 1 or 0
  local dx    = right - left
  local dy    = down - up

  local target_x, target_y
  if self.move_mode == 'ice' then
    -- Glacier: the paddle slides on ice — input accelerates it, releasing
    -- the keys coasts it down instead of stopping dead.
    self.slide_vx = self.slide_vx or 0
    self.slide_vy = self.slide_vy or 0
    if dx ~= 0 then
      self.slide_vx = math.clamp(self.slide_vx + dx*900*dt, -self.speed, self.speed)
    else
      local dec = 250*dt
      if math.abs(self.slide_vx) <= dec then self.slide_vx = 0
      else self.slide_vx = self.slide_vx - dec*(self.slide_vx > 0 and 1 or -1) end
    end
    if dy ~= 0 then
      self.slide_vy = math.clamp(self.slide_vy + dy*600*dt, -self.speed, self.speed)
    else
      local dec = 150*dt
      if math.abs(self.slide_vy) <= dec then self.slide_vy = 0
      else self.slide_vy = self.slide_vy - dec*(self.slide_vy > 0 and 1 or -1) end
    end
    target_x = self.x + self.slide_vx*dt
    target_y = self.y + self.slide_vy*dt
  else
    target_x = self.x + dx*self.speed*dt
    target_y = self.y + dy*self.speed*dt
  end

  local clamped_x = math.clamp(target_x, arena.x1 + self.w/2, arena.x2 - self.w/2)
  local clamped_y = math.clamp(target_y, self.y_anchor - DODGE_BAND_UP,
                                         self.y_anchor + DODGE_BAND_DOWN)
  -- Kill slide momentum against the walls so an ice paddle doesn't stay
  -- pinned there fighting its own stored velocity.
  if self.move_mode == 'ice' then
    if clamped_x ~= target_x then self.slide_vx = 0 end
    if clamped_y ~= target_y then self.slide_vy = 0 end
  end

  self:set_position(clamped_x, clamped_y)

  self.vx = (self.move_mode == 'ice') and self.slide_vx or dx*self.speed
end


function Paddle:draw()
  local s = self.hfx.hit.x
  local body_color = self.hfx.hit.f and fg[0] or self.color

  if self.flippers then
    for side = -1, 1, 2 do
      local ft = (side == -1) and (self.flip_l_t or 0) or (self.flip_r_t or 0)
      -- Resting pose slopes down toward the gap; a live flip window snaps the
      -- flipper up the other way.
      local a  = (ft > 0) and side*0.45 or -side*self.flipper_tilt
      local fx = self.x + side*self.flipper_off
      graphics.push(fx, self.y, a, s, 1/s)
        graphics.rectangle(fx, self.y, self.flipper_w, self.h, 2, 2, body_color)
        graphics.rectangle(fx, self.y - self.h/2, self.flipper_w, 1, nil, nil, fg[5])
      graphics.pop()
    end
    return
  end

  graphics.push(self.x, self.y, 0, s, 1/s)
    graphics.rectangle(self.x, self.y, self.w, self.h, 2, 2, body_color)
    graphics.rectangle(self.x, self.y - self.h/2, self.w, 1, nil, nil, fg[5])
  graphics.pop()
end


-- Called when a ball collides with the paddle. Tilts the reflection so the
-- player can aim by hitting the ball with the edge of the paddle, and ramps
-- the ball's speed multiplier so chained bounces feel rewarding.
-- Loadout signatures hook in here: Aegis wipes the streak instead of ramping,
-- Cannon launches charged balls into the mortar arc, Tesla/Hive fire their
-- per-bounce effects after the reflection.
function Paddle:on_ball_bounce(ball)
  self.hfx:use('hit', 0.18, 200, 10)

  local arena = main.current
  local mods  = arena and arena.run_mods or nil
  local sig   = mods and mods.signature or nil

  -- Pierce buff: every paddle bounce that happens while the buff is active
  -- re-arms this specific ball's pierce. The ball punches up through bricks
  -- (no damage), bonks the ceiling, becomes a normal ball, ricochets among
  -- the top bricks until it comes back here, and gets re-armed for the next
  -- upward pass while the buff is still up.
  if arena and arena.pierce_active and ball.set_piercing then
    ball:set_piercing(true)
  end

  -- A boomerang ball that made it home resumes normal flight.
  ball.boomerang_home = nil

  if sig == 'aegis' then
    -- Aegis "hurts" balls: touching the paddle wipes the speed/charge streak.
    -- You want balls living on the bottom wall, not on you.
    ball.speed_mult      = 1.0
    ball.charge_dmg_mult = 1.0
    ball.bounces         = 0
    ball.spring:pull(0.3)
    bounce1:play{volume = 0.35, pitch = 0.7}
  else
    -- Ramp the ball's speed multiplier. Capped so chains plateau instead of
    -- spiraling into uncontrollable speed.
    ball.speed_mult = math.min(ball.speed_mult_max, (ball.speed_mult or 1)*(ball.speed_mult_step or 1.07))
  end

  -- Cannon: a charged-up ball launches into the mortar arc instead of
  -- reflecting. The ramp above IS the charge — dropping a ball into the pit
  -- resets speed_mult, which resets the mortar too.
  if sig == 'cannon' and not ball.mortar and ball.start_mortar
  and (ball.speed_mult or 1) >= ((mods.sig and mods.sig.launch_at) or 1.5) then
    local off = math.clamp((ball.x - self.x)/(self.w/2), -1, 1)
    ball:start_mortar(off)
    return
  end

  if self.flippers then
    self:flipper_bounce(ball)
  else
    -- Edge-offset reflection: hit with the paddle edge to steer. The
    -- loadout's Aim stat widens/narrows the arc, clamped short of horizontal
    -- so a wide-aim paddle can never reflect a ball flat.
    local hit_offset = math.clamp((ball.x - self.x)/(self.w/2), -1, 1)
    local spread = math.clamp(hit_offset*(math.pi/3)*(self.aim_mult or 1), -1.45, 1.45)
    local angle = -math.pi/2 + spread
    local speed = ball.base_speed*ball.speed_mult
    ball:set_velocity(speed*math.cos(angle), speed*math.sin(angle))
  end

  -- Pitch + spark count both scale with the streak so the feedback escalates.
  local pitch_lift = math.min(0.35, (ball.speed_mult - 1)*0.5)
  bounce1:play{volume = 0.4, pitch = random:float(0.95, 1.05) + pitch_lift}
  spawn_bounce_sparks(main.current.effects, ball.x, ball.y, -math.pi/2, ball.color)
  if ball.speed_mult > 1.6 then
    spawn_bounce_sparks(main.current.effects, ball.x, ball.y, -math.pi/2, ball.color)
  end

  -- Post-bounce signature hooks.
  if arena then
    if sig == 'tesla' and arena.tesla_zap then arena:tesla_zap(ball) end
    if sig == 'hive' and arena.hive_spawn_maggot then arena:hive_spawn_maggot(ball) end
  end
end


-- Reflect (or lob) a ball off the Pinball Lobber's flipper rig. A flipper
-- whose flip window is live LOBS the ball up toward the centre of the arena
-- with extra speed and an extra charge step — that's the Lobber's whole
-- reward loop. A resting flipper reflects against its own centre, with the
-- resting tilt biasing the ball outward like a real table.
function Paddle:flipper_bounce(ball)
  local side = (ball.x < self.x) and -1 or 1
  local ft   = (side == -1) and (self.flip_l_t or 0) or (self.flip_r_t or 0)

  if ft > 0 then
    -- Active flip: extra charge step + boosted launch speed, aimed upfield
    -- toward the opposite side (left flipper lobs up-right and vice versa).
    ball.speed_mult = math.min(ball.speed_mult_max, ball.speed_mult*(ball.speed_mult_step or 1.07))
    local speed = ball.base_speed*ball.speed_mult*1.35
    local angle = -math.pi/2 - side*random:float(0.1, 0.45)
    ball:set_velocity(speed*math.cos(angle), speed*math.sin(angle))
    ball.spring:pull(0.4)
    if side == -1 then self.flip_l_t = 0 else self.flip_r_t = 0 end
    bounce1:play{volume = 0.5, pitch = 1.25}
  else
    local fx = self.x + side*self.flipper_off
    local hit_offset = math.clamp((ball.x - fx)/(self.flipper_w/2), -1, 1)
    local spread = math.clamp(hit_offset*(math.pi/3)*(self.aim_mult or 1) + side*0.18, -1.45, 1.45)
    local angle = -math.pi/2 + spread
    local speed = ball.base_speed*ball.speed_mult
    ball:set_velocity(speed*math.cos(angle), speed*math.sin(angle))
  end
end


-- Phantom's dropped anchor: a frozen, translucent copy of the paddle that
-- still bounces balls — the ball collision callback dispatches on the
-- 'paddle' tag, and this shares Paddle's bounce handler wholesale (aim_mult,
-- charge ramp and all). Consumed when the player blinks back to it.
GhostPaddle = Object:extend()
GhostPaddle:implement(GameObject)
GhostPaddle:implement(Physics)

function GhostPaddle:init(args)
  self:init_game_object(args)
  self.w        = self.w or 36
  self.h        = self.h or 4
  self.aim_mult = self.aim_mult or 1
  self.color    = purple[0]
  self.vx       = 0
  self:set_as_rectangle(self.w, self.h, 'static', 'paddle')
  self:set_restitution(1)
  self.hfx:add('hit', 1)
end

GhostPaddle.on_ball_bounce = Paddle.on_ball_bounce

function GhostPaddle:update(dt)
  self:update_game_object(dt)
end

function GhostPaddle:draw()
  local pulse = 0.4 + 0.18*math.sin(love.timer.getTime()*5)
  graphics.rectangle(self.x, self.y, self.w, self.h, 2, 2,
                     Color(purple[0].r, purple[0].g, purple[0].b, pulse), 1)
  graphics.rectangle(self.x, self.y, self.w + 4, self.h + 4, 3, 3,
                     Color(purple[0].r, purple[0].g, purple[0].b, pulse*0.4), 1)
end
