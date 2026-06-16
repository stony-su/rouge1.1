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
-- 120px (was 80) pushes the red defense line higher, giving the paddle more
-- room to weave between bullets; the breach boundary moves up with it (keep
-- BallPit:breach_line_y's no-paddle fallback in sync: band + 14px spawn
-- offset).
local DODGE_BAND_UP   = 120
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
    local sig          = self.flipper_sig or {}
    self.flipper_gap   = self.flipper_gap or 14
    self.flip_window   = self.flip_window or 0.16
    self.flipper_len   = sig.flipper_len   or 34   -- long real-table bats (was an 18px stub)
    self.flipper_thick = sig.flipper_thick or 5
    self.rest_tilt     = sig.rest_tilt     or 0.30 -- resting bats droop toward the drain gap
    self.flip_up       = sig.flip_up       or 0.62 -- how far the tip kicks up on a flip
    self.launch_speed  = sig.launch_speed  or 150  -- "100%" unit; flip_launch scales it 2x-4x
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


-- Distance from point (px,py) to segment a->b, plus the parametric position
-- t along the segment (0 = a, 1 = b). Used by the flipper catch test.
local function point_segment_distance(px, py, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local len2   = dx*dx + dy*dy
  local t      = (len2 > 0) and ((px - ax)*dx + (py - ay)*dy)/len2 or 0
  t = math.clamp(t, 0, 1)
  local cx, cy = ax + t*dx, ay + t*dy
  return math.sqrt((px - cx)^2 + (py - cy)^2), t
end


-- Pinball Lobber: two long flipper bats with a central drain gap, both
-- fixtures riding one kinematic body. The bats pivot OUTBOARD with their tips
-- sloping down toward the gap (a real table's resting pose), so a ball that
-- lands on a bat rolls into the drain unless you flip. The fixtures stay in
-- the resting pose — one body can't rotate two bats independently — so the
-- flip itself is an upward impulse applied to nearby balls (see flip_launch),
-- while draw() animates the visible kick. Physics:destroy and
-- set_restitution/set_friction iterate self.fixtures, so the second bat rides
-- the mixin lifecycle. `scale` lets the wide_paddle powerup lengthen the rig.
function Paddle:build_flipper_rig(scale)
  local px, py = self.x, self.y
  if self.body then self:destroy() end
  self.x, self.y = px, py

  self.flipper_scale = scale or 1
  local len   = self.flipper_len*self.flipper_scale
  local thick = self.flipper_thick
  local gap   = self.flipper_gap or 14
  local tilt  = self.rest_tilt
  self.cur_len = len
  -- Logical span (gap + both bats) — the bullet hit-test, xp magnet and
  -- powerup catch all read paddle.w, so it has to span the whole rig.
  self.w = gap + 2*len*math.cos(tilt)

  local tag  = 'paddle'
  self.tag   = tag
  self.shape = Rectangle(self.x, self.y, self.w, thick + 6)
  self.body  = love.physics.newBody(self.group.world, self.x, self.y, 'kinematic')

  self.fixtures = {}
  self.fixture  = nil
  for _, s in ipairs({-1, 1}) do
    -- Bat midpoint + long-axis angle in body-local space, pivot outboard.
    local mx  = s*(gap/2 + (len/2)*math.cos(tilt))
    local my  = (len/2)*math.sin(tilt)
    local ang = (s == 1) and (math.pi - tilt) or tilt
    local shape = love.physics.newRectangleShape(mx, my, len, thick, ang)
    local f = love.physics.newFixture(self.body, shape)
    f:setUserData(self.id)
    f:setCategory(self.group.collision_tags[tag].category)
    f:setMask(unpack(self.group.collision_tags[tag].masks))
    f:setRestitution(0.1)   -- balls settle + roll off the bats, they don't ping
    f:setFriction(0.6)
    if not self.fixture then self.fixture = f else table.insert(self.fixtures, f) end
  end
  self.body:setFixedRotation(true)
end


-- World-space pose of one flipper bat (side = -1 left, 1 right), folding in the
-- live flip animation: returns pivot (px,py), tip (tx,ty), the bat elevation
-- angle and the 0..1 raise amount. The pivot is fixed outboard; the tip swings
-- from a resting droop up to flip_up while a flip window is live.
function Paddle:flipper_pose(side)
  local ft    = (side == -1) and (self.flip_l_t or 0) or (self.flip_r_t or 0)
  local raise = (self.flip_window > 0) and math.clamp(ft/self.flip_window, 0, 1) or 0
  local elev  = self.rest_tilt + (-self.flip_up - self.rest_tilt)*raise
  local len   = self.cur_len or self.flipper_len
  local gap   = self.flipper_gap or 14
  local pivx  = self.x + side*(gap/2 + len*math.cos(self.rest_tilt))
  local pivy  = self.y
  local tipx  = pivx + (-side*math.cos(elev))*len
  local tipy  = pivy + math.sin(elev)*len
  return pivx, pivy, tipx, tipy, elev, raise
end


-- A live flip kicks every ball resting on (or just above) that bat up and
-- infield. This is the Lobber's whole offense: gravity rolls balls down to the
-- flippers, a well-timed tap lobs them back up into the swarm. The pop is
-- deliberately gentle (launch_speed) so balls stay slow and catchable; the
-- reward for good timing is a per-flip damage ramp, not raw speed.
function Paddle:flip_launch(side)
  local arena = main.current
  if not (arena and arena.heroes) then return end
  local pivx, pivy, tipx, tipy = self:flipper_pose(side)
  local catch_r = (self.flipper_thick or 5) + 15
  local hit_any = false
  for _, h in ipairs(arena.heroes) do
    if h and not h.dead and h.body and not h.stuck and not h.returning then
      local d, t = point_segment_distance(h.x, h.y, pivx, pivy, tipx, tipy)
      if d < catch_r + (h.r_size or 6) then
        local _, vy = h:get_velocity()
        if (vy or 0) > -60 then     -- don't re-fire a ball already flying up
          -- Position-scaled launch, like a real flipper: a hit out by the
          -- pivot gives a +200% pop (2x), scaling up to +400% (4x) as you catch
          -- the ball nearer the inner tip — the "middle" of the table by the
          -- drain. t runs 0 at the pivot to 1 at the tip.
          local boost = 2.0 + 2.0*t
          local ang   = -math.pi/2 - side*random:float(0.12, 0.34)
          local spd   = (self.launch_speed or 150)*boost
          h:set_velocity(math.cos(ang)*spd, math.sin(ang)*spd)
          h.charge_dmg_mult = math.min(1.5, (h.charge_dmg_mult or 1)*1.12)
          h.spring:pull(0.35)
          spawn_bounce_sparks(arena.effects, h.x, h.y, ang, h.color)
          hit_any = true
        end
      end
    end
  end
  if hit_any then
    bounce1:play{volume = 0.5, pitch = 1.2}
    camera:shake(1, 0.1)
  end
end


function Paddle:update(dt)
  self:update_game_object(dt)

  local arena = main.current

  -- Pinball flip taps. The Lobber never catches a ball (it has no stick/aim
  -- flow), so the arrow keys are pure flips — left/right kick that bat up and
  -- lob any ball resting on it back into play (see flip_launch).
  if self.flippers then
    self.flip_l_t = math.max(0, (self.flip_l_t or 0) - dt)
    self.flip_r_t = math.max(0, (self.flip_r_t or 0) - dt)
    if input.aim_left.pressed  then self.flip_l_t = self.flip_window; self:flip_launch(-1) end
    if input.aim_right.pressed then self.flip_r_t = self.flip_window; self:flip_launch( 1) end
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
    for _, side in ipairs({-1, 1}) do
      local pivx, pivy, tipx, tipy = self:flipper_pose(side)
      self:draw_flipper(pivx, pivy, tipx, tipy, body_color)
    end
    return
  end

  if self.paddle_skin == 'mitosis' then
    self:draw_mitosis_paddle(s, body_color)
    return
  end

  graphics.push(self.x, self.y, 0, s, 1/s)
    graphics.rectangle(self.x, self.y, self.w, self.h, 2, 2, body_color)
    graphics.rectangle(self.x, self.y - self.h/2, self.w, 1, nil, nil, fg[5])
  graphics.pop()
end


-- The Mitosis paddle as a living cell colony: a soft membrane capsule of
-- cytoplasm with a row of nuclei that pulse + drift and pinch into budding
-- twins, hinting at constant cell division. Uses the hit-flash colour + spring
-- scale like the standard paddle, and stays within the same hitbox footprint.
function Paddle:draw_mitosis_paddle(s, color)
  local t    = love.timer.getTime()
  local w, h = self.w, self.h
  local x, y = self.x, self.y
  local mh   = h + 3   -- the membrane bulges a touch past the hitbox so it reads as a cell
  graphics.push(x, y, 0, s, 1/s)
    graphics.rectangle(x, y, w + 3, mh + 3, (mh + 3)/2, (mh + 3)/2, Color(color.r, color.g, color.b, 0.18))  -- outer glow
    graphics.rectangle(x, y, w, mh, mh/2, mh/2, Color(color.r, color.g, color.b, 0.85))                      -- cytoplasm
    graphics.rectangle(x, y, w, mh, mh/2, mh/2, Color(color.r, color.g, color.b, 0.55), 1)                   -- membrane outline
    local n = 3
    for i = 1, n do
      local nx    = x - w/2 + (i - 0.5)*(w/n)
      local pulse = 0.78 + 0.22*math.sin(t*3 + i*1.3)
      local drift = math.sin(t*2 + i*1.7)*1.1
      local nr    = mh*0.32*pulse
      graphics.circle(nx + drift, y, nr, Color(color.r*0.5, color.g*0.5, color.b*0.5, 0.9))
      -- a budding twin nucleus that pinches out and back (division motif)
      local sep = (0.5 + 0.5*math.sin(t*1.6 + i*2.1))*mh*0.5
      graphics.circle(nx + drift + sep, y, nr*0.55, Color(color.r*0.6, color.g*0.6, color.b*0.6, 0.7))
    end
    graphics.rectangle(x, y - mh/2, w*0.92, 1, nil, nil, fg[5])   -- bright top edge
  graphics.pop()
end


-- Draw one flipper as a tapered bat (wide at the pivot, narrowing to a rounded
-- tip) with a pivot bolt — reads like a real pinball flipper. Endpoints come
-- from flipper_pose so the bat visibly kicks up while a flip is live.
function Paddle:draw_flipper(pivx, pivy, tipx, tipy, color)
  local ang    = math.atan2(tipy - pivy, tipx - pivx)
  local wbase  = (self.flipper_thick or 5) + 3
  local wtip   = math.max(2, (self.flipper_thick or 5) - 1)
  local nx, ny = -math.sin(ang), math.cos(ang)   -- unit normal to the bat axis
  graphics.polygon({
    pivx + nx*wbase/2, pivy + ny*wbase/2,
    pivx - nx*wbase/2, pivy - ny*wbase/2,
    tipx - nx*wtip/2,  tipy - ny*wtip/2,
    tipx + nx*wtip/2,  tipy + ny*wtip/2,
  }, color)
  graphics.circle(tipx, tipy, wtip/2, color)
  graphics.circle(pivx, pivy, wbase/2 + 1, color)
  graphics.circle(pivx, pivy, math.max(1, wbase/2 - 1.5), fg[5])
end


-- Called when a ball collides with the paddle. Tilts the reflection so the
-- player can aim by hitting the ball with the edge of the paddle, and ramps
-- the ball's speed multiplier so chained bounces feel rewarding.
-- Loadout signatures hook in here: Aegis wipes the streak instead of ramping,
-- Cannon launches charged balls into the mortar arc, Tesla/Hive fire their
-- per-bounce effects after the reflection.
function Paddle:on_ball_bounce(ball)
  self.hfx:use('hit', 0.18, 200, 10)

  -- Pinball Lobber: a ball that lands on a bat ROLLS (low restitution +
  -- gravity), it doesn't ping back — the launch is the flip (see flip_launch),
  -- not this contact. So leave the ball's velocity alone here; just soft juice.
  if self.flippers then
    ball.boomerang_home = nil
    ball.spring:pull(0.12)
    if random:bool(45) then bounce1:play{volume = 0.16, pitch = random:float(0.9, 1.05)} end
    return
  end

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

  -- Edge-offset reflection: hit with the paddle edge to steer. The loadout's
  -- Aim stat widens/narrows the arc, clamped short of horizontal so a wide-aim
  -- paddle can never reflect a ball flat.
  local hit_offset = math.clamp((ball.x - self.x)/(self.w/2), -1, 1)
  local spread = math.clamp(hit_offset*(math.pi/3)*(self.aim_mult or 1), -1.45, 1.45)
  local angle = -math.pi/2 + spread
  local speed = ball.base_speed*ball.speed_mult
  ball:set_velocity(speed*math.cos(angle), speed*math.sin(angle))

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
