-- The player-controlled paddle that ball-heroes bounce off of.
-- Bullet-hell style: small hitbox, free movement in a dodge band at the
-- bottom of the arena. A/D pan horizontally, W/S move vertically within
-- the band so the player can dodge incoming projectiles between bounces.
--
-- Paddle LOADOUTS (see paddles.lua / PADDLES.md) feed this file:
--   * w / speed / color / aim_mult arrive as ctor args from reset_run,
--   * `flippers` switches the body to the Pinball Lobber's two-fixture rig,
--   * `move_mode = 'ice'` switches movement to the Glacier's sliding model,
--   * on_ball_bounce gates per-signature behavior (aegis parry, cannon mortar
--     launch, tesla zap, hive maggots) off arena.run_mods,
--   * the Aegis brace state (start_brace / the ticks in update / the rim flash
--     in draw) lives here — see the parry branches in on_ball_bounce and
--     EnemyProjectile:update.

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

  -- Aegis shield state (inert on every other loadout): brace_t is the open
  -- shield window, brace_lock_t the recharge cooldown after it closes.
  self.brace_t      = 0
  self.brace_lock_t = 0

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
          h.charge_dmg_mult = math.min(BAL('globals.flipper_charge_cap', 1.5),
                                       (h.charge_dmg_mult or 1)*BAL('globals.flipper_charge_step', 1.12))
          h.spring:pull(0.35)
          spawn_bounce_sparks(arena.effects, h.x, h.y, ang, h.color)
          -- Pinball RAM: every successful flip on this ball raises both its
          -- chance to enter RAM mode and how many blocks a RAM smashes.
          -- pb_flip_hits stacks PER BALL; a drain resets it (pinball_serve).
          -- Flipping a ball that is ALREADY ramming skips the roll: the RAM is
          -- maintained and gains one stack (ram_stack).
          h.pb_flip_hits = (h.pb_flip_hits or 0) + 1
          if (h.ram_left or 0) > 0 and h.ram_stack then
            h:ram_stack()
          elseif h.ram_start then
            local chance = math.min(BAL('signature.ram_chance_max', 0.65),
                                    BAL('signature.ram_chance_base', 0.18)
                                    + BAL('signature.ram_chance_step', 0.08)*(h.pb_flip_hits - 1))
            if random:bool(chance*100) then
              -- Block count grows with the flip streak AND the run level —
              -- the paddle's ram smashes deeper as the run levels up.
              local lvl_blocks = math.floor(((arena.level or 1) - 1)
                                            /BAL('signature.ram_levels_per_block', 3))
              local blocks = math.min(h:ram_cap(),
                                      BAL('signature.ram_blocks_base', 2)
                                      + math.floor((h.pb_flip_hits - 1)/2) + lvl_blocks)
              h:ram_start(blocks)
            end
          end
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

  -- Aegis shield: tick the raised window down; when it closes the shield
  -- drops into its recharge cooldown — hit or not — so raising it is a real
  -- commitment, not something to mash.
  if (self.brace_t or 0) > 0 then
    self.brace_t = self.brace_t - dt
    if self.brace_t <= 0 then
      self.brace_lock_t = self.brace_lockout or 2.5
      bounce1:play{volume = 0.2, pitch = 0.55}
    end
  elseif (self.brace_lock_t or 0) > 0 then
    self.brace_lock_t = self.brace_lock_t - dt
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

  -- Actual per-frame velocity (respects wall clamping + ice coasting). The
  -- Cannon hop reads this: a paddle charging FORWARD (up) into a ball launches a
  -- bigger hop than a stationary tap. Captured from the real position delta so a
  -- paddle pinned against a wall reads as "not moving" there.
  local px, py = self.x, self.y
  self:set_position(clamped_x, clamped_y)
  local idt = (dt > 0) and (1/dt) or 0
  self.hit_vx = (clamped_x - px)*idt
  self.hit_vy = (clamped_y - py)*idt

  self.vx = (self.move_mode == 'ice') and self.slide_vx or dx*self.speed
end


-- Aegis shield: raise it for a sustained window (E / click, see
-- BallPit:update). Anything turned while it's up is a parry — balls come off
-- charged and piercing (on_ball_bounce), bullets flip gold and fly back
-- (EnemyProjectile:reflect). When the window closes the shield recharges for
-- parry_lockout seconds; ignored while already raised or recharging.
function Paddle:start_brace()
  if (self.brace_t or 0) > 0 or (self.brace_lock_t or 0) > 0 then return end
  local arena = main.current
  local sigt  = (arena and arena.run_mods and arena.run_mods.sig) or {}
  self.brace_window  = sigt.parry_window or 0.6
  self.brace_lockout = sigt.parry_lockout or 2.5
  self.brace_t       = self.brace_window
  pop1:play{volume = 0.3, pitch = 0.8}
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

  if self.paddle_skin == 'boomerang' then
    self:draw_boomerang_paddle(s, body_color)
    return
  end

  if self.paddle_skin == 'vampire' then
    self:draw_vampire_paddle(s, body_color)
    return
  end

  if self.paddle_skin == 'hive' then
    self:draw_hive_paddle(s, body_color)
    return
  end

  if self.paddle_skin == 'tesla' then
    self:draw_tesla_paddle(s, body_color)
    return
  end

  if self.paddle_skin == 'glacier' then
    self:draw_glacier_paddle(s, body_color)
    return
  end

  if self.paddle_skin == 'terrorist' then
    self:draw_terrorist_paddle(s, body_color)
    return
  end

  if self.paddle_skin == 'cannon' then
    self:draw_cannon_paddle(s, body_color)
    return
  end

  if self.paddle_skin == 'aegis' then
    self:draw_aegis_paddle(s, body_color)
    return
  end

  graphics.push(self.x, self.y, 0, s, 1/s)
    graphics.rectangle(self.x, self.y, self.w, self.h, 2, 2, body_color)
    graphics.rectangle(self.x, self.y - self.h/2, self.w, 1, nil, nil, fg[5])
  graphics.pop()
end


-- The Aegis paddle as an ancient Greek aspis seen edge-on: a bronze-faced
-- slab with a raised central boss (omphalos), gold meander ticks along the
-- face and a riveted rim. The parry states are readable at a glance:
--   ready  -> warm bronze; the boss catch-light glints on a slow pulse
--   braced -> the face flares gold and a flat blue aura arc — the shield
--             itself — hangs above the paddle, dimming as the window closes
--   locked -> the bronze dulls cold and a thin blue re-arm bar refills along
--             the top across the recharge (full = shield ready again)
function Paddle:draw_aegis_paddle(s, color)
  local w, h    = self.w, self.h
  local t       = love.timer.getTime()
  local braced  = (self.brace_t or 0) > 0
  local locked  = (self.brace_lock_t or 0) > 0
  local k       = braced and math.clamp(self.brace_t/(self.brace_window or 0.6), 0, 1) or 0

  -- Bronze face palette; dulled while locked out, gold-flared while braced.
  local face  = Color(0.72, 0.54, 0.24, 1)
  local belly = Color(0.48, 0.35, 0.16, 1)
  local gold  = Color(1, 0.85, 0.35, 1)
  if locked then
    face  = Color(0.45, 0.36, 0.24, 1)
    belly = Color(0.30, 0.24, 0.16, 1)
  elseif braced then
    face  = Color(0.95, 0.78, 0.30, 1)
    belly = Color(0.72, 0.54, 0.20, 1)
  end
  if self.hfx.hit.f then face = fg[0] end

  graphics.push(self.x, self.y, 0, s, 1/s)
    -- Face slab, with the shield's curved belly falling into shadow below.
    graphics.rectangle(self.x, self.y, w, h, 2, 2, face)
    graphics.rectangle(self.x, self.y + h*0.25, w - 3, h*0.5, 1, 1, belly)
    -- Hammered top rim.
    graphics.rectangle(self.x, self.y - h/2, w, 1, nil, nil, braced and fg[5] or gold)
    -- Meander (Greek-key) suggestion: evenly spaced gold ticks along the face.
    local n = math.max(3, math.floor(w/10))
    for i = 0, n - 1 do
      local mx = self.x - w/2 + (i + 0.5)*(w/n)
      graphics.rectangle(mx, self.y, 1.4, h*0.35, nil, nil, gold)
    end
    -- Rim rivets.
    graphics.circle(self.x - w/2 + 2, self.y, 1.1, gold)
    graphics.circle(self.x + w/2 - 2, self.y, 1.1, gold)
    -- Central boss: a raised dome poking past the slab. Its catch-light
    -- glints on a slow pulse while the shield is ready, so "parry is up" is
    -- visible without extra chrome; it goes flat while locked out.
    local glint = (not braced and not locked) and (0.6 + 0.4*math.sin(t*3)) or 1
    local br    = h*0.95 + (braced and 1.2 or 0)
    graphics.circle(self.x, self.y, br + 1.1, belly)
    graphics.circle(self.x, self.y, br, braced and gold or face)
    graphics.circle(self.x - br*0.3, self.y - br*0.35, br*0.32,
                    Color(1, 0.92, 0.60, locked and 0.25 or 0.9*glint))
  graphics.pop()

  -- The raised shield: a flat blue aura arc floating above the paddle —
  -- layered strokes (soft glow, body, bright inner edge) so it reads as an
  -- energy barrier, dimming as the window runs out.
  if braced then
    local half = w/2 + 8
    local sag  = 8                                -- crest height over the arc's endpoints
    local R    = (half*half + sag*sag)/(2*sag)    -- circle through crest + endpoints
    local cy   = self.y - h/2 - 4 - sag + R       -- its center sits far below the crest
    local th   = math.asin(half/R)
    local a1, a2 = -math.pi/2 - th, -math.pi/2 + th
    graphics.arc('open', self.x, cy, R + 2.5, a1, a2, Color(0.45, 0.75, 1, 0.10 + 0.18*k), 5)
    graphics.arc('open', self.x, cy, R,       a1, a2, Color(0.55, 0.80, 1, 0.30 + 0.45*k), 2)
    graphics.arc('open', self.x, cy, R - 1.5, a1, a2, Color(0.85, 0.95, 1, 0.25 + 0.35*k), 1)
  elseif locked then
    -- Re-arm readout: refills left-to-right across the recharge.
    local rk = 1 - math.clamp(self.brace_lock_t/(self.brace_lockout or 2.5), 0, 1)
    if rk > 0 then
      graphics.rectangle(self.x - w/2 + (w*rk)/2, self.y - h/2 - 3, w*rk, 1,
                         nil, nil, Color(0.55, 0.80, 1, 0.5))
    end
  end
end


-- The Terrorist paddle as a detonator rig: a dark armored slab striped with
-- yellow/black hazard chevrons, topped by a little red plunger-box detonator
-- with a blinking arm light. Stays inside the standard hitbox footprint; uses
-- the hit-flash colour + spring scale like the standard paddle.
function Paddle:draw_terrorist_paddle(s, color)
  local w, h = self.w, self.h
  local x, y = self.x, self.y
  local t    = love.timer.getTime()

  graphics.push(x, y, 0, s, 1/s)
    -- Dark armored base slab.
    graphics.rectangle(x, y, w, h + 2, 2, 2, Color(0.13, 0.11, 0.11, 1))
    -- Hazard chevrons: alternating amber/red diagonal bars across the slab.
    local n = math.max(2, math.floor(w/7))
    for i = 0, n do
      local sx = x - w/2 + 2 + i*(w/n)
      if sx > x - w/2 + 1 and sx < x + w/2 - 1 then
        local col = (i % 2 == 0) and Color(0.95, 0.74, 0.12, 0.95) or Color(0.78, 0.16, 0.11, 0.95)
        graphics.line(sx - 1.5, y + h/2, sx + 1.5, y - h/2, col, 1.6)
      end
    end
    -- Bright top edge so the bounce surface still reads clearly.
    graphics.rectangle(x, y - h/2, w, 1, nil, nil, color)
  graphics.pop()

  -- Plunger-box detonator hanging under the slab, handle pointing down. On an
  -- E press (plunger_at, stamped by terror_manual_detonate) the plunger SLAMS
  -- in -- knob against the box with a white pop, box jolting down -- then
  -- eases back out over a beat as if re-priming, so the detonate press reads
  -- on the paddle itself.
  local pk = math.clamp(1 - (t - (self.plunger_at or -10))/0.35, 0, 1)
  pk = pk*pk                                     -- ease-out: fast slam, slow re-prime
  local by  = y + h/2 + 3.5 + pk*1.2
  local ext = 3*(1 - 0.92*pk)                    -- stem extension: ~0 at the slam
  graphics.rectangle(x, by, 8, 4, 1, 1, Color(0.62, 0.12, 0.09, 1))
  graphics.rectangle(x, by, 8, 4, 1, 1, Color(1, 0.5, 0.4, 0.7), 1)
  graphics.rectangle(x, by + 1.1 + ext/2, 2, ext + 1, nil, nil, Color(0.25, 0.25, 0.25, 1))  -- plunger stem
  graphics.circle(x, by + 1.6 + ext, 1.6, Color(0.85, 0.2, 0.15, 1))                         -- plunger knob
  if pk > 0.55 then                              -- press pop: brief white flash on the knob
    graphics.circle(x, by + 1.6 + ext, 2.2, Color(1, 1, 1, (pk - 0.55)/0.45*0.8))
  end
  -- Blinking "armed" light at the right end of the slab.
  local lit = math.sin(t*8) > 0
  graphics.circle(x + w/2 - 3, y - 0.5, 1.5, lit and Color(1, 0.35, 0.2, 1) or Color(0.4, 0.12, 0.1, 1))
end


-- The Cannon paddle as a siege gun-carriage: a dark armored slab on two
-- spoked wheels, banded with rivets, with a breathing heat-haze aura. FLAT on
-- top — no mortar barrel; the launcher fantasy lives in the ball hops it
-- strikes, not in a muzzle. Cosmetic only — the hitbox is the flat bar.
function Paddle:draw_cannon_paddle(s, color)
  local t      = love.timer.getTime()
  local x, y   = self.x, self.y
  local w, h   = self.w, self.h
  local pulse  = 0.5 + 0.5*math.sin(t*3)

  -- Breathing orange heat-haze aura.
  graphics.rectangle(x, y, w + 5 + pulse*2, h + 6, (h + 6)/2, (h + 6)/2,
                     Color(color.r, color.g*0.45, 0.05, 0.13 + 0.10*pulse))

  -- Two spoked carriage wheels at the ends (drawn under the slab).
  for _, sx in ipairs({-1, 1}) do
    local wx, wy = x + sx*(w/2 - 3), y + h/2 + 1.5
    graphics.circle(wx, wy, 2.6, Color(0.10, 0.09, 0.08, 1))
    graphics.circle(wx, wy, 2.6, Color(color.r*0.75, color.g*0.4, 0.1, 0.85), 1)
    graphics.line(wx - 1.8, wy, wx + 1.8, wy, Color(0.4, 0.32, 0.24, 0.9), 1)
    graphics.line(wx, wy - 1.8, wx, wy + 1.8, Color(0.4, 0.32, 0.24, 0.9), 1)
    graphics.circle(wx, wy, 0.8, Color(0.55, 0.45, 0.34, 1))
  end

  graphics.push(x, y, 0, s, 1/s)
    -- Dark armored gun-carriage slab.
    graphics.rectangle(x, y, w, h + 2, 2, 2, Color(0.16, 0.13, 0.11, 1))
    -- Iron reinforcing band + a row of rivets.
    graphics.rectangle(x, y, w*0.94, h*0.5, 1, 1, Color(0.30, 0.24, 0.20, 1))
    local n = math.max(3, math.floor(w/8))
    for i = 0, n do
      local rx = x - w/2 + 3 + i*((w - 6)/n)
      graphics.circle(rx, y, 0.7, Color(0.55, 0.45, 0.35, 0.9))
    end
    -- Bright bounce edge on top in the loadout colour.
    graphics.rectangle(x, y - h/2, w*0.96, 1, nil, nil, color)
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


-- The Boomerang paddle as a thrown boomerang at rest: a shallow wooden chevron
-- (two tapered arms + a centre hub bolt) with a bright leading edge, rocking
-- gently and trailing faint return-swirls to sell the "it always comes back"
-- theme. Purely cosmetic — the hitbox is still the flat paddle rectangle.
function Paddle:draw_boomerang_paddle(s, color)
  local t    = love.timer.getTime()
  local x, y = self.x, self.y
  local half = self.w/2
  local th   = self.h + 1.5
  local peak, droop = 2.5, 2.5
  local rock = math.sin(t*2.2)*0.05
  graphics.push(x, y, rock, s, 1/s)
    -- faint spinning return-swirls behind the body
    for i = 1, 2 do
      local ga = t*3 + i*math.pi
      graphics.arc('open', x, y, half*(0.55 + 0.14*i), ga, ga + 1.1,
                   Color(color.r, color.g, color.b, 0.10), 1.5)
    end
    self:draw_boomerang_arm(x, y - peak, x - half, y + droop, th, color)
    self:draw_boomerang_arm(x, y - peak, x + half, y + droop, th, color)
    -- centre hub bolt
    graphics.circle(x, y - peak + 0.5, th*0.55, color)
    graphics.circle(x, y - peak + 0.5, math.max(1, th*0.28), fg[5])
  graphics.pop()
end


-- One boomerang arm: a tapered rounded bar from the hub to a rounded tip, with
-- a darker wood-grain streak and a bright top edge.
function Paddle:draw_boomerang_arm(hx, hy, tx, ty, th, color)
  local ang    = math.atan2(ty - hy, tx - hx)
  local len    = math.distance(hx, hy, tx, ty)
  local cx, cy = (hx + tx)/2, (hy + ty)/2
  local dark   = Color(color.r*0.62, color.g*0.62, color.b*0.62, 1)
  graphics.push(cx, cy, ang)
    graphics.rectangle(cx, cy, len, th, th/2, th/2, color)            -- arm body
    graphics.rectangle(cx, cy, len*0.9, th*0.4, th*0.2, th*0.2, dark) -- wood grain streak
    graphics.rectangle(cx, cy - th/2, len*0.9, 1, nil, nil, fg[5])    -- bright top edge
  graphics.pop()
  graphics.circle(tx, ty, th*0.5, color)        -- rounded tip
  graphics.circle(tx, ty, th*0.24, fg[5])       -- tip cap glint
end


-- The Vampire paddle: a dark, glossy blood-slab that breathes a crimson glow,
-- with two fangs hanging beneath the centre and a blood drip that forms, falls
-- and fades on a loop. Purely cosmetic — same flat hitbox as the standard bar.
function Paddle:draw_vampire_paddle(s, color)
  local t      = love.timer.getTime()
  local x, y   = self.x, self.y
  local w, h   = self.w, self.h
  local pulse  = 0.5 + 0.5*math.sin(t*3)
  graphics.push(x, y, 0, s, 1/s)
    -- breathing crimson glow aura
    graphics.rectangle(x, y, w + 5 + pulse*2, h + 5, (h + 5)/2, (h + 5)/2,
                       Color(color.r, color.g*0.15, color.b*0.15, 0.16 + 0.12*pulse))
    -- dark glossy body + bright blood top band + edge
    graphics.rectangle(x, y, w, h, 2, 2, Color(color.r*0.62, color.g*0.16, color.b*0.18, 1))
    graphics.rectangle(x, y - h*0.16, w, h*0.42, 1, 1,
                       Color(math.min(1, color.r*1.15), color.g*0.28, color.b*0.30, 1))
    graphics.rectangle(x, y - h/2, w*0.96, 1, nil, nil, fg[5])
    -- two fangs hanging beneath the centre
    local fy = y + h/2
    graphics.polygon({x - 3.5, fy, x - 1, fy, x - 2.25, fy + 4.5}, Color(1, 1, 1, 0.92))
    graphics.polygon({x + 1, fy, x + 3.5, fy, x + 2.25, fy + 4.5}, Color(1, 1, 1, 0.92))
    -- a blood drip that forms at a fang, falls and fades on a loop
    local drip = (t*0.8) % 1
    graphics.circle(x - 2.25, fy + 3 + drip*7, math.max(0.6, 1.4*(1 - drip)),
                    Color(color.r, color.g*0.18, color.b*0.20, 1 - drip))
  graphics.pop()
end


-- The Hive paddle as a living nest: an amber comb of honey-cells with two bugs
-- crawling along it and a rot spore drip oozing off the bottom — the colony
-- that breeds the infesting maggots. Purely cosmetic; same flat hitbox.
function Paddle:draw_hive_paddle(s, color)
  local t      = love.timer.getTime()
  local x, y   = self.x, self.y
  local w, h   = self.w, self.h
  local pulse  = 0.5 + 0.5*math.sin(t*2.5)
  graphics.push(x, y, 0, s, 1/s)
    -- warm nest glow that breathes
    graphics.rectangle(x, y, w + 4 + pulse*2, h + 4, (h + 4)/2, (h + 4)/2,
                       Color(color.r, color.g*0.55, 0.08, 0.16 + 0.10*pulse))
    -- comb body
    graphics.rectangle(x, y, w, h, 2, 2, color)
    -- a row of honey-cells
    local n = math.max(3, math.floor(w/8))
    for i = 1, n do
      local hx = x - w/2 + (i - 0.5)*(w/n)
      graphics.circle(hx, y, h*0.32, Color(color.r*0.55, color.g*0.40, 0.06, 1))
    end
    graphics.rectangle(x, y - h/2, w*0.95, 1, nil, nil, fg[5])
    -- two bugs crawling back and forth along the comb
    for i = 0, 1 do
      local bx = x + math.sin(t*1.3 + i*3.1)*(w*0.42)
      graphics.circle(bx, y - h*0.10, 1.6, Color(0.10, 0.10, 0.08, 1))
    end
    -- a rot spore drip that forms, falls and fades on a loop
    local drip = (t*0.6) % 1
    graphics.circle(x + math.sin(t*0.9)*w*0.3, y + h/2 + drip*6,
                    math.max(0.6, 1.3*(1 - drip)), Color(0.30, 0.42, 0.08, 1 - drip))
  graphics.pop()
end


-- The Tesla paddle as a charged generator: a dark metallic bar with a bright
-- coil terminal at the centre that crackles little arcs, wrapped in a breathing
-- electric-blue glow. The conduction web (TeslaWeb) roots at this node.
function Paddle:draw_tesla_paddle(s, color)
  local t      = love.timer.getTime()
  local x, y   = self.x, self.y
  local w, h   = self.w, self.h
  local pulse  = 0.5 + 0.5*math.sin(t*5)
  graphics.push(x, y, 0, s, 1/s)
    -- breathing electric glow
    graphics.rectangle(x, y, w + 5 + pulse*3, h + 5, (h + 5)/2, (h + 5)/2,
                       Color(color.r*0.5, color.g*0.7, 1.0, 0.16 + 0.12*pulse))
    -- dark metallic body + charged top band + edge
    graphics.rectangle(x, y, w, h, 2, 2, Color(color.r*0.7, color.g*0.8, color.b, 1))
    graphics.rectangle(x, y - h*0.16, w, h*0.42, 1, 1, Color(0.55, 0.78, 1.0, 0.95))
    graphics.rectangle(x, y - h/2, w*0.95, 1, nil, nil, fg[5])
    -- coil terminal at the centre
    local ty = y - h/2 - 1
    graphics.circle(x, ty, 2.4, Color(0.85, 0.94, 1.0, 1))
    -- little arcs flicking off the terminal
    for i = 0, 2 do
      if math.sin(t*20 + i*2.1) > 0.3 then
        local a   = -math.pi/2 + (i - 1)*0.7 + math.sin(t*7 + i)*0.2
        local len = 4 + 3*pulse
        graphics.line(x, ty, x + math.cos(a)*len, ty + math.sin(a)*len, Color(0.7, 0.9, 1.0, 0.85), 1)
      end
    end
  graphics.pop()
end


-- The Glacier paddle as an air-hockey mallet: a flat round striker (drawn as a
-- vertically-squashed disc so it reads top-down on the thin paddle) with a
-- frosted rim, a recessed ring and a bright central grip-knob, wrapped in a
-- faint cold halo with a slow shimmer sweep. Cosmetic; the hitbox stays the bar.
function Paddle:draw_glacier_paddle(s, color)
  local t    = love.timer.getTime()
  local x, y = self.x, self.y
  local rx   = self.w/2
  local yc   = (self.h/2 + 5)/rx   -- vertical squash -> flat top-down disc
  graphics.push(x, y, 0, s, 1/s)
    graphics.push(x, y, 0, 1, yc)
      graphics.circle(x, y, rx + 2.5, Color(0.5, 0.78, 1.0, 0.16))                 -- cold halo
      graphics.circle(x, y, rx, Color(color.r, color.g, color.b, 1))               -- disc body
      graphics.circle(x, y, rx, Color(0.85, 0.95, 1.0, 0.55), 1)                   -- frosted rim
      graphics.circle(x, y, rx*0.58, Color(0.16, 0.40, 0.62, 1))                   -- recessed ring well
      graphics.circle(x, y, rx*0.36, Color(0.88, 0.96, 1.0, 1))                    -- central grip knob
      graphics.circle(x - rx*0.12, y - rx*0.12, rx*0.16, Color(1, 1, 1, 0.95))     -- knob highlight
      -- a slow shimmer sweep across the disc
      local sx = x + math.sin(t*1.6)*rx*0.6
      graphics.line(sx, y - rx*0.7, sx + 3, y + rx*0.7, Color(1, 1, 1, 0.14), 1)
    graphics.pop()
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


-- UI preview of a paddle loadout using the REAL in-game draw path (Paddle:draw
-- + the per-loadout skin painters above), so the shop cards show exactly what
-- the player will pilot. Renders through a cached lightweight stub per paddle
-- id -- no physics body, a faked hit-flash -- at the loadout's true in-game
-- width (36 * Size stat). The Pinball rig gets a compact (60%) flipper pose
-- that idly demo-flips on the shared frame clock.
local paddle_preview_stubs = {}
function Paddle.draw_preview(id, def, x, y)
  local stub = paddle_preview_stubs[id]
  if not stub then
    local sig = def.sig or {}
    stub = setmetatable({
      w   = math.floor(36*(def.size or 1) + 0.5),
      h   = 4,
      hfx = {hit = {x = 1, f = false}},
      -- Same signature -> skin map reset_run uses when it builds the real paddle.
      paddle_skin = ({mitosis = 'mitosis', boomerang = 'boomerang', vampire = 'vampire',
                      hive = 'hive', tesla = 'tesla', glacier = 'glacier',
                      terrorist = 'terrorist', cannon = 'cannon', aegis = 'aegis'})[def.signature],
    }, Paddle)
    if def.signature == 'flippers' then
      stub.flippers      = true
      stub.flipper_gap   = (sig.gap or 14)*0.6
      stub.flip_window   = sig.flip_window or 0.16
      stub.flipper_len   = (sig.flipper_len or 34)*0.6
      stub.flipper_thick = math.max(3, (sig.flipper_thick or 5) - 1)
      stub.rest_tilt     = sig.rest_tilt or 0.30
      stub.flip_up       = sig.flip_up or 0.62
      stub.flip_l_t, stub.flip_r_t = 0, 0
    end
    paddle_preview_stubs[id] = stub
  end
  stub.x, stub.y = x, y
  stub.color = _G[def.color_key][0]
  if stub.flippers then
    -- Idle demo flips: each bat kicks up on its own beat.
    local t  = time or 0
    local fw = stub.flip_window
    stub.flip_l_t = (math.max(0, math.sin(t*1.6))^6)*fw
    stub.flip_r_t = (math.max(0, math.sin(t*1.6 + math.pi))^6)*fw
  end
  stub:draw()
end


-- Called when a ball collides with the paddle. Tilts the reflection so the
-- player can aim by hitting the ball with the edge of the paddle, and ramps
-- the ball's speed multiplier so chained bounces feel rewarding.
-- Loadout signatures hook in here: Aegis parries braced balls (and skips the
-- ramp on soft blocks), Cannon launches charged balls into the mortar arc,
-- Tesla/Hive fire their per-bounce effects after the reflection.
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
    if (self.brace_t or 0) > 0 then
      -- PERFECT PARRY: a ball turned by the raised shield comes off charged —
      -- its next few brick contacts hit for parry_dmg_mult and punch straight
      -- through (see BallHero:apply_parry / on_brick_hit) — and gets shoved
      -- out fast.
      local sigt = (mods and mods.sig) or {}
      ball:apply_parry(sigt.parry_hits or 4, sigt.parry_dmg_mult or 2.5)
      ball.speed_mult = math.min(ball.speed_mult_max or 4,
                                 math.max(ball.speed_mult or 1, sigt.parry_speed_mult or 1.6))
      -- Success juice: a gold ring snaps out of the point of contact so the
      -- parry itself (not just its aftermath) is visible.
      if arena then
        TelegraphRing{group = arena.effects, x = ball.x, y = ball.y, radius = 16,
                      color = Color(1, 0.85, 0.35, 1), duration = 0.25}
      end
      buff1:play{volume = 0.4, pitch = random:float(1.15, 1.3)}
      camera:shake(2, 0.12, 90)
    else
      -- Soft block: the resting shield just returns the ball — no speed ramp,
      -- no wipe. The loadout's damage budget lives in the parry window.
      ball.spring:pull(0.2)
      bounce1:play{volume = 0.3, pitch = 0.75}
    end
  elseif sig == 'glacier' then
    -- Ice rink: the air-hockey mallet COOLS the puck — touching it zeroes the
    -- glide charge, so its built-up speed + damage bleed back to base. The
    -- reward is keeping pucks gliding out in the field, not juggling them here.
    ball.glide_t         = 0
    ball.speed_mult      = 1.0
    ball.charge_dmg_mult = 1.0
    bounce1:play{volume = 0.35, pitch = random:float(0.85, 1.0)}
  else
    -- Ramp the ball's speed multiplier. Capped so chains plateau instead of
    -- spiraling into uncontrollable speed.
    ball.speed_mult = math.min(ball.speed_mult_max, (ball.speed_mult or 1)*(ball.speed_mult_step or 1.07))
  end

  -- Cannon: striking a ball launches it into a z-axis HOP (on top of the normal
  -- reflection below). A stationary "tap" gives a weak hop; the faster the
  -- paddle is charging FORWARD (up, into the ball) when it connects, the higher +
  -- harder the hop — so pulling the paddle back then driving it up into the ball
  -- is rewarded. Lateral motion adds a little. Each landing rebounds smaller
  -- (BallHero:update_hop) until the hop dies out and the ball settles back to
  -- flat xy on its own, ready for the next strike.
  if sig == 'cannon' and ball.start_hop then
    local maxspd  = self.speed or 220
    local up      = math.max(0, -(self.hit_vy or 0))    -- charging forward = moving up
    local lateral = math.abs(self.hit_vx or 0)
    local power   = math.clamp(0.12 + (up + lateral*0.4)/maxspd*0.95, 0.12, 1)
    ball:start_hop(power)
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

  -- Post-bounce signature hooks. (Tesla is no longer bounce-gated — its
  -- conduction web runs persistently from BallPit:tesla_tick.)
  if arena then
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
