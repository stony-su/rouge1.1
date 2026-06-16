-- Mobile enemies that aren't bricks.
--
-- EnemyCritter is a small circular enemy that drifts downward and dies in a
-- single hit; crossing the red defense line breaches like a swarm would
-- (costs the player HP). NOTE: nothing spawns it anymore (the swarmer brick
-- and the boss's phase-3 minions were removed) — the class is kept so splash
-- targeting / live_block_count code that references it stays valid.
--
-- EnemyProjectile is a slow downward shot fired by the shooter brick variant.
-- Hits the paddle for damage. Can be destroyed by a ball.

EnemyCritter = Object:extend()
EnemyCritter:implement(GameObject)
EnemyCritter:implement(Physics)

function EnemyCritter:init(args)
  self:init_game_object(args)
  self.r_size     = 3
  self.color      = self.color or purple[0]
  self.hp         = self.hp or 1
  self.speed      = self.speed or 14
  self.xp_value   = 1
  self.player_dmg = 1

  self:set_as_circle(self.r_size, 'dynamic', 'brick')
  self:set_fixed_rotation(true)
  self:set_restitution(0.4)
  self:set_friction(0)
  self:set_damping(0.4)
  self:set_mass(0.3)
  self.hfx:add('hit', 1)

  -- Drift downward with a slight horizontal wobble so they don't all line up.
  self.wobble_phase = random:float(0, 2*math.pi)
  self.wobble_amp   = random:float(8, 16)
end

function EnemyCritter:update(dt)
  self:update_game_object(dt)
  local vx, vy = self:get_velocity()
  self.wobble_phase = self.wobble_phase + dt*2
  local target_vx = math.cos(self.wobble_phase)*self.wobble_amp
  self:set_velocity(vx + (target_vx - vx)*0.05, vy + (self.speed - vy)*0.05)

  local arena = main.current
  -- Breach at the red defense line (top of the paddle's dodge band) -- the same
  -- boundary swarms use -- instead of wandering all the way down to the paddle.
  if self.y > arena:breach_line_y() then
    arena:on_brick_breached(self)
    self.dead = true
  end
end

-- Reworked to match the rest of the bullet-hell enemy projectile suite (see
-- EnemyProjectile's per-kind draws). The critter reads as a "cursed wisp":
-- soft pulsing outer aura, mid-tone shell, dark void in the middle and a
-- bright soul-core that throbs at a different frequency from the aura so the
-- whole thing feels alive instead of being a flat-shaded disc.
function EnemyCritter:draw()
  local s        = self.hfx.hit.x or 1
  local col      = self.hfx.hit.f and fg[0] or self.color
  local t        = love.timer.getTime()
  -- Tying the pulse phases to the existing wobble_phase makes each critter
  -- pulse out of sync with its neighbours, so a swarm reads as a cloud of
  -- individual things rather than a flashing block of pixels.
  local aura_p   = 1 + math.sin(t*5  + self.wobble_phase)*0.20
  local core_p   = 1 + math.sin(t*9  + self.wobble_phase)*0.30

  -- Outer aura — large, semi-transparent. Carries the "purple haze" read.
  graphics.circle(self.x, self.y, (self.r_size + 3)*aura_p,
                  Color(col.r, col.g, col.b, 0.22))

  -- Mid shell — darker tint of the same colour, gives the wisp depth so it
  -- doesn't look like a flat single-colour blob next to the aura.
  graphics.circle(self.x, self.y, (self.r_size + 1.2)*aura_p,
                  Color(col.r*0.55, col.g*0.55, col.b*0.7, 0.55))

  -- Body. Scaled by hit-flash so damage feedback is unchanged.
  graphics.circle(self.x, self.y, self.r_size*s, col)

  -- Dark inner void — the "hollow" centre of the wisp. Reads as
  -- silhouette/skull-socket against the purple body.
  graphics.circle(self.x, self.y, self.r_size*0.5*s, bg[-2])

  -- Bright soul-core, pulses at its own faster rate so the eye is always
  -- drawn to the centre even when the aura is dim.
  graphics.circle(self.x, self.y, self.r_size*0.28*s*core_p, fg[5])
end

function EnemyCritter:take_damage(amount, color)
  self.hp = self.hp - amount
  self.hfx:use('hit', 0.25, 200, 10)
  spawn_burst(main.current.effects, self.x, self.y, color or self.color, 3, 40, 100)
  if self.hp <= 0 then
    self:die()
  end
end

function EnemyCritter:die()
  local arena = main.current
  spawn_burst(arena.effects, self.x, self.y, self.color, 5, 60, 130)
  critter2:play{volume = 0.25, pitch = random:float(0.95, 1.1)}
  local x, y, v = self.x, self.y, self.xp_value
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      XpOrb{group = arena.main, x = x, y = y, value = v}
    end
  end)
  self.dead = true
end

-- Critters don't slow/burn but the brick-targeted ability helpers may call
-- these — provide no-op stubs to avoid crashes.
function EnemyCritter:apply_slow() end
function EnemyCritter:apply_burn() end


-- Slow downward projectile fired by shooter bricks. Hits the paddle.
EnemyProjectile = Object:extend()
EnemyProjectile:implement(GameObject)
EnemyProjectile:implement(Physics)

function EnemyProjectile:init(args)
  self:init_game_object(args)
  -- Bumped from 2.5 → 3.5 so the projectile reads as a real threat, not a
  -- pickup. Hero balls can also intercept it more easily at this size.
  self.r_size = self.r_size or 3.5
  self.color  = self.color or fg[0]
  self.speed  = self.speed or 60
  self.dmg    = self.dmg or 1
  -- Firing direction in radians. Defaults to straight down (π/2) so existing
  -- callers (shooter brick) keep working without supplying an angle.
  self.angle        = self.angle or math.pi/2
  -- Optional homing: turns velocity vector toward the paddle at `homing_turn`
  -- rad/s. Used by arc-lobber variant and can be wired up by future enemies.
  self.homing       = self.homing or false
  self.homing_turn  = self.homing_turn or 1.5
  -- Visual kind. Each ranged enemy type uses a distinct kind so the screen
  -- reads at a glance even when multiple attack patterns overlap. Default
  -- 'spike' preserves the original red 4-pointed shooter look.
  --   spike    -> shooter (default)         red 4-spike, red trail/halo
  --   dart     -> sniper / boss shotgun     long needle aligned to velocity
  --   triangle -> spreader                  small pointed triangle
  --   orb      -> spiraler                  swirly orb + orbiting pixel
  --   bolt     -> burster                   short bright bolt aligned to velocity
  --   bomb     -> arc_lobber                pulsing ring + colored core
  --   boss_orb -> boss attacks              big double-aura phase-colored orb
  -- NB: this field is intentionally called `kind`, not `shape`. The Physics
  -- mixin's set_as_circle (engine/game/physics.lua) writes to self.shape with
  -- a Circle instance, which would clobber any value we put there.
  self.kind         = self.kind or 'spike'
  -- Unbreakable bullets are fired only by the boss: hero balls phase straight
  -- through them (see the mask tweak below) and can never destroy them, so the
  -- player must dodge with the paddle instead of batting them away. Defaults
  -- off, so every existing brick-enemy caller keeps fully breakable shots.
  self.unbreakable  = self.unbreakable or false
  self.spin_t      = random:float(0, math.pi*2)
  self.spin_speed  = random:float(4, 7) * (random:bool(50) and 1 or -1)
  self.trail       = {}
  self.trail_acc   = 0

  self:set_as_circle(self.r_size, 'dynamic', 'brick')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(0)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.2)
  self:set_velocity(math.cos(self.angle)*self.speed, math.sin(self.angle)*self.speed)
  self.hfx:add('hit', 1)

  -- Enemy shots phase through hero balls: drop the 'ball' category from this
  -- fixture's collide mask so balls pass through without a bounce, a collision
  -- callback, or destroying the shot. Ranged fire is dodged with the paddle
  -- (the manual hit-test in update), never batted away. This used to be
  -- boss-only ('unbreakable'); applying it to EVERY enemy projectile stops
  -- shots fired into a field full of bouncing balls from being wiped out at
  -- the muzzle. We start from the shared 'brick' don't-collide masks
  -- (paddle/brick/wall) and add 'ball'.
  if self.fixture and self.group and self.group.collision_tags then
    local brick_tag = self.group.collision_tags['brick']
    local ball_tag  = self.group.collision_tags['ball']
    if brick_tag and ball_tag then
      local m = {}
      for _, c in ipairs(brick_tag.masks) do m[#m + 1] = c end
      m[#m + 1] = ball_tag.category
      self.fixture:setMask(unpack(m))
    end
  end

  -- Optional self-destruct timer so short-range bullet-hell shots don't pile
  -- up forever when fired away from the paddle.
  if self.life then
    self.t:after(self.life, function() self.dead = true end)
  end
end

function EnemyProjectile:update(dt)
  self:update_game_object(dt)
  local arena = main.current

  -- Homing: smoothly rotate velocity toward the paddle. Capped turn rate so
  -- the player can still dodge by moving — these aren't perfect trackers.
  if self.homing and arena and arena.paddle then
    local vx, vy = self:get_velocity()
    local cur    = math.atan2(vy, vx)
    local want   = math.atan2(arena.paddle.y - self.y, arena.paddle.x - self.x)
    -- Wrap diff to [-π, π] so we always turn the short way around the circle.
    local diff   = math.loop(want - cur, 2*math.pi)
    if diff > math.pi then diff = diff - 2*math.pi end
    local step   = math.clamp(diff, -self.homing_turn*dt, self.homing_turn*dt)
    local new_a  = cur + step
    self:set_velocity(math.cos(new_a)*self.speed, math.sin(new_a)*self.speed)
  end

  -- Off-arena cleanup. Original only killed on the bottom edge — angled
  -- bullet-hell shots can also exit sideways or off the top.
  if self.y > arena.y2 + 8 or self.y < arena.y1 - 8 then self.dead = true end
  if self.x < arena.x1 - 8 or self.x > arena.x2 + 8 then self.dead = true end
  -- Paddle hit. Swept vertical test over the segment the bullet travelled this
  -- frame, instead of the old "anywhere below paddle.y - 4" column — that acted
  -- like an infinitely tall hitbox under the paddle, so lifting the paddle in
  -- its dodge band let bullets far below it still score hits. Sweeping also
  -- stops fast shots tunnelling through the thin (4px) bar between frames.
  local _, p_vy  = self:get_velocity()
  local p_prev_y = self.y - p_vy*dt
  local p_ylo    = math.min(p_prev_y, self.y) - self.r_size
  local p_yhi    = math.max(p_prev_y, self.y) + self.r_size
  if  math.abs(self.x - arena.paddle.x) < arena.paddle.w/2 + self.r_size
  and p_yhi >= arena.paddle.y - arena.paddle.h/2
  and p_ylo <= arena.paddle.y + arena.paddle.h/2 then
    local sig = arena.run_mods and arena.run_mods.signature
    if sig == 'aegis' and not self.unbreakable then
      -- Aegis loadout: the paddle PARRIES bullets — the shot dies and is
      -- flipped into a friendly projectile aimed at the nearest brick.
      -- Unbreakable boss bullets punch through (the boss stays honest).
      local bx, by = self.x, self.y
      spawn_burst(arena.effects, bx, by, blue2[0], 6, 70, 140)
      buff1:play{volume = 0.3, pitch = random:float(1.2, 1.35)}
      local t = arena:get_nearest_brick(bx, by)
      local r = t and math.atan2(t.y - by, t.x - bx) or -math.pi/2
      local reflect_dmg = (arena.run_mods.sig and arena.run_mods.sig.reflect_dmg) or 20
      arena.t:after(0, function()
        if arena.main and arena.main.world then
          Projectile{group = arena.main, x = bx, y = by, r = r,
                     type = 'arrow', dmg = reflect_dmg, speed = 260, color = blue2[0]}
        end
      end)
      self.dead = true
    else
      -- Hit the paddle directly. Admin godmode swallows the hp loss but still
      -- plays the impact feedback so the operator can see what would have hit.
      -- Routed through damage_player so the Vampire bar takes hearts-worth.
      if not arena.god then
        arena:damage_player(self.dmg)
      end
      hit2:play{volume = 0.4, pitch = random:float(1.0, 1.1)}
      camera:shake(2, 0.15, 90)
      Flash{group = arena.effects, x = gw/2, y = gh/2, color = red_transparent_weak, duration = 0.08}
      if arena.player_hp <= 0 then arena:trigger_game_over() end
      self.dead = true
    end
  end

  -- Visual state: spin + sampled trail. The trail is what most reliably
  -- separates this from an XP orb at a glance — orbs sit still and pickups
  -- drift; a streaking line below the cursor reads as "incoming."
  self.spin_t = self.spin_t + self.spin_speed*dt
  self.trail_acc = self.trail_acc + dt
  if self.trail_acc > 0.03 then
    self.trail_acc = 0
    table.insert(self.trail, 1, {x = self.x, y = self.y})
    if #self.trail > 8 then table.remove(self.trail) end
  end
end

-- Velocity-aligned facing angle, used by shapes that point along their
-- travel direction (dart/triangle/bolt). Falls back to the initial fire
-- angle when the projectile is momentarily stationary.
function EnemyProjectile:facing_angle()
  local vx, vy = self:get_velocity()
  if vx*vx + vy*vy < 1 then return self.angle end
  return math.atan2(vy, vx)
end


-- Shared back-to-front trail. Older samples are smaller and more transparent
-- so motion direction reads cleanly. Color is the only knob — each shape
-- picks whether to use its self.color or a fixed palette tone.
function EnemyProjectile:draw_trail(color)
  for i = #self.trail, 1, -1 do
    local p  = self.trail[i]
    local k  = i/(#self.trail + 1)
    local a  = (1 - k)*0.55
    local rs = self.r_size*(1 - k*0.7)
    if rs > 0.4 then
      graphics.circle(p.x, p.y, rs, Color(color.r, color.g, color.b, a))
    end
  end
end


-- Per-shape draw dispatch. The default 'spike' branch is the original
-- shooter look — kept identical so existing callers don't need updates.
function EnemyProjectile:draw()
  if     self.kind == 'dart'     then self:draw_dart()
  elseif self.kind == 'triangle' then self:draw_triangle()
  elseif self.kind == 'orb'      then self:draw_orb()
  elseif self.kind == 'bolt'     then self:draw_bolt()
  elseif self.kind == 'bomb'     then self:draw_bomb()
  elseif self.kind == 'boss_orb' then self:draw_boss_orb()
  elseif self.kind == 'star'     then self:draw_star()
  elseif self.kind == 'comet'    then self:draw_comet()
  elseif self.kind == 'diamond'  then self:draw_diamond()
  else                                self:draw_spike() end
  -- Unbreakable (boss) bullets get a bright crystalline shell on top of
  -- whatever shape they are, so the player can tell at a glance which shots
  -- can't be blocked by a ball.
  if self.unbreakable then self:draw_armor() end
end


-- 'spike' (shooter, default): original red 4-pointed spike + red halo + red
-- trail. Color is hardcoded red regardless of self.color so the projectile
-- always reads as "danger" and can never be confused for a colored XP gem.
function EnemyProjectile:draw_spike()
  self:draw_trail(red[0])

  local pulse = 1 + math.sin((time or 0)*9)*0.18
  graphics.circle(self.x, self.y, (self.r_size + 2)*pulse, red_transparent_weak)

  local s   = self.hfx.hit.x or 1
  local col = self.hfx.hit.f and fg[0] or red[0]
  graphics.push(self.x, self.y, self.spin_t)
    graphics.rectangle(self.x, self.y, self.r_size*2.6*s, self.r_size*0.9*s, 0.6, 0.6, col)
    graphics.rectangle(self.x, self.y, self.r_size*0.9*s, self.r_size*2.6*s, 0.6, 0.6, col)
  graphics.pop()
  -- Bright inner core dot — keeps the projectile readable when the spike
  -- happens to align horizontally and looks like a thin bar.
  graphics.circle(self.x, self.y, self.r_size*0.5*s, fg[5])
end


-- 'dart' (sniper, boss shotgun): long thin needle aligned to the velocity
-- vector. Trail and body use self.color so boss-phase tinting works.
function EnemyProjectile:draw_dart()
  self:draw_trail(self.color)

  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local face = self:facing_angle()
  graphics.push(self.x, self.y, face)
    graphics.rectangle(self.x, self.y, self.r_size*3.4*s, self.r_size*0.7*s,  0.4, 0.4, col)
    graphics.rectangle(self.x, self.y, self.r_size*2.4*s, self.r_size*0.25*s, 0.2, 0.2, fg[5])
  graphics.pop()
end


-- 'triangle' (spreader): small triangle with tip pointing along velocity.
-- Vertices are rotated in software because polygon() draws in world space
-- and graphics.push only stacks affine transforms on the love.graphics
-- matrix — we want the same triangle, oriented to the bullet's heading.
function EnemyProjectile:draw_triangle()
  self:draw_trail(self.color)

  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local face = self:facing_angle()
  local r    = self.r_size*1.7*s
  local cos_a, sin_a = math.cos(face), math.sin(face)
  local function rot(lx, ly)
    return self.x + lx*cos_a - ly*sin_a, self.y + lx*sin_a + ly*cos_a
  end
  local x1, y1 = rot( r,       0)
  local x2, y2 = rot(-r*0.7,   r*0.85)
  local x3, y3 = rot(-r*0.7,  -r*0.85)
  graphics.polygon({x1, y1, x2, y2, x3, y3}, col)
  graphics.circle(self.x, self.y, self.r_size*0.4*s, fg[5])
end


-- 'orb' (spiraler): soft pulsing aura, filled body, one bright pixel
-- orbiting around it for an unmistakable "spinning" feel.
function EnemyProjectile:draw_orb()
  self:draw_trail(self.color)

  local s     = self.hfx.hit.x or 1
  local col   = self.hfx.hit.f and fg[0] or self.color
  local pulse = 1 + math.sin((time or 0)*8 + (self.spin_t or 0))*0.2

  graphics.circle(self.x, self.y, (self.r_size + 1.5)*pulse,
                  Color(col.r, col.g, col.b, 0.28))
  graphics.circle(self.x, self.y, self.r_size*s, col)
  local oa = self.spin_t or 0
  graphics.circle(self.x + math.cos(oa)*self.r_size*0.9,
                  self.y + math.sin(oa)*self.r_size*0.9,
                  self.r_size*0.42*s, fg[5])
end


-- 'bolt' (burster): short, crisp, fast-feeling rectangle aligned with
-- velocity. Slightly chunkier than the dart so triplet bursts read as
-- distinct shots even when they're stacked in flight.
function EnemyProjectile:draw_bolt()
  self:draw_trail(self.color)

  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local face = self:facing_angle()
  graphics.push(self.x, self.y, face)
    graphics.rectangle(self.x, self.y, self.r_size*2.3*s, self.r_size*1.1*s,  0.4, 0.4, col)
    graphics.rectangle(self.x, self.y, self.r_size*1.5*s, self.r_size*0.4*s,  0.2, 0.2, fg[5])
  graphics.pop()
end


-- 'bomb' (arc_lobber): big pulsing aura + outer ring + filled core. The
-- pulse rate is faster than the boss orb so it reads as a different threat
-- (timed area denial vs. point projectile).
function EnemyProjectile:draw_bomb()
  self:draw_trail(self.color)

  local s     = self.hfx.hit.x or 1
  local col   = self.hfx.hit.f and fg[0] or self.color
  local pulse = 1 + math.sin((time or 0)*7)*0.3

  graphics.circle(self.x, self.y, (self.r_size + 3)*pulse,
                  Color(col.r, col.g, col.b, 0.32))
  graphics.circle(self.x, self.y, self.r_size*1.35*s, col, 1.5)
  graphics.circle(self.x, self.y, self.r_size*0.7*s,  col)
  graphics.circle(self.x, self.y, self.r_size*0.3*s,  fg[5])
end


-- 'boss_orb' (boss attacks): largest visual footprint. Double-layer aura,
-- concentric rings, bright core. Color comes from the boss's current phase
-- (red → orange → purple) so the player can read phase + threat at once.
function EnemyProjectile:draw_boss_orb()
  self:draw_trail(self.color)

  local s     = self.hfx.hit.x or 1
  local col   = self.hfx.hit.f and fg[0] or self.color
  local pulse = 1 + math.sin((time or 0)*8)*0.25

  graphics.circle(self.x, self.y, (self.r_size + 4)*pulse,
                  Color(col.r, col.g, col.b, 0.28))
  graphics.circle(self.x, self.y, self.r_size*1.55*s, col, 1.5)
  graphics.circle(self.x, self.y, self.r_size*s,       col)
  graphics.circle(self.x, self.y, self.r_size*0.55*s,  fg[5], 1)
  graphics.circle(self.x, self.y, self.r_size*0.28*s,  fg[5])
end


-- 'star' (boss flower spiral): a spinning 4-point star, clearly different from
-- the round boss_orb so overlapping flower + spiral patterns stay legible.
function EnemyProjectile:draw_star()
  self:draw_trail(self.color)
  local s   = self.hfx.hit.x or 1
  local col = self.hfx.hit.f and fg[0] or self.color
  local r   = self.r_size*s
  local verts = {}
  for i = 0, 7 do
    local a  = (self.spin_t or 0) + i*(math.pi/4)
    local rr = (i % 2 == 0) and r*2.2 or r*0.85
    verts[#verts + 1] = self.x + math.cos(a)*rr
    verts[#verts + 1] = self.y + math.sin(a)*rr
  end
  graphics.polygon(verts, col)
  graphics.circle(self.x, self.y, r*0.5, fg[5])
end


-- 'comet' (boss homing seeker): a glowing pulsing head riding its own trail,
-- so a curving shot reads as "tracking you" rather than a stray spiral bullet.
function EnemyProjectile:draw_comet()
  self:draw_trail(self.color)
  local s     = self.hfx.hit.x or 1
  local col   = self.hfx.hit.f and fg[0] or self.color
  local pulse = 1 + math.sin((time or 0)*12 + (self.spin_t or 0))*0.3
  graphics.circle(self.x, self.y, (self.r_size + 2.5)*pulse,
                  Color(col.r, col.g, col.b, 0.30))
  graphics.circle(self.x, self.y, self.r_size*s, col)
  graphics.circle(self.x, self.y, self.r_size*0.45*s, fg[5])
end


-- 'diamond' (boss gap wall): a slowly spinning rhombus. A flat row of these
-- marching down reads cleanly as a barrier with a gap to slip the paddle into.
function EnemyProjectile:draw_diamond()
  self:draw_trail(self.color)
  local s   = self.hfx.hit.x or 1
  local col = self.hfx.hit.f and fg[0] or self.color
  local r   = self.r_size*1.6*s
  local a   = (self.spin_t or 0)*0.5
  local ca, sa = math.cos(a), math.sin(a)
  local function rot(lx, ly) return self.x + lx*ca - ly*sa, self.y + lx*sa + ly*ca end
  local x1, y1 = rot(0, -r)
  local x2, y2 = rot(r*0.7, 0)
  local x3, y3 = rot(0, r)
  local x4, y4 = rot(-r*0.7, 0)
  graphics.polygon({x1, y1, x2, y2, x3, y3, x4, y4}, col)
  graphics.circle(self.x, self.y, self.r_size*0.4*s, fg[5])
end


-- Overlay drawn on top of any unbreakable (boss) bullet: a bright shell that
-- pulses on its own beat, signalling "this one can't be blocked."
function EnemyProjectile:draw_armor()
  local p = 0.55 + 0.45*math.sin((time or 0)*10 + (self.spin_t or 0))
  graphics.circle(self.x, self.y, self.r_size*1.9 + 0.5, Color(1, 1, 1, 0.20*p), 1)
end


function EnemyProjectile:take_damage(amount, color)
  -- Unbreakable boss bullets can't be destroyed. Balls already phase through
  -- them (see the init mask) and the arena's AoE abilities skip non-Brick
  -- objects, so reaching here is unexpected — absorb it rather than dying.
  if self.unbreakable then return end
  self.hfx:use('hit', 0.25, 200, 10)
  spawn_burst(main.current.effects, self.x, self.y, color or self.color, 3, 40, 80)
  self.dead = true
end

function EnemyProjectile:apply_slow() end
function EnemyProjectile:apply_burn() end


-- AllyCritter: spawned by infestor pets and Hive maggots. A small ball that
-- flies upward, hits a brick and dies (or expires on a timer). Uses the
-- 'projectile' physics tag so it only collides with bricks.
AllyCritter = Object:extend()
AllyCritter:implement(GameObject)
AllyCritter:implement(Physics)

function AllyCritter:init(args)
  self:init_game_object(args)
  self.r_size   = 3
  self.color    = self.color or fg[0]
  self.dmg      = self.dmg or 6
  self.speed    = self.speed or 70
  self.lifetime = self.lifetime or 4

  self:set_as_circle(self.r_size, 'dynamic', 'projectile')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(0.4)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.2)

  local angle = -math.pi/2 + random:float(-0.6, 0.6)
  self:set_velocity(math.cos(angle)*self.speed, math.sin(angle)*self.speed)
  self.hfx:add('hit', 1)

  self.on_collision_enter = function(s, other, contact)
    if not other then return end
    if other.tag == 'brick' then s:on_brick_contact(other) end
  end

  self.t:after(self.lifetime, function() self.dead = true end)
end

function AllyCritter:update(dt)
  self:update_game_object(dt)
  local arena = main.current
  if arena and (self.y < arena.y1 - 8 or self.y > arena.y2 + 8) then self.dead = true end
end

function AllyCritter:draw()
  graphics.circle(self.x, self.y, self.r_size + 0.5, bg[-2])
  graphics.circle(self.x, self.y, self.r_size, self.color)
  graphics.circle(self.x - self.r_size*0.3, self.y - self.r_size*0.3, math.max(0.6, self.r_size*0.3), fg[5])
end

function AllyCritter:on_brick_contact(brick)
  if brick.dead then return end
  -- Hive maggots carry their source hero's element onto the brick they hit.
  if self.effect == 'burn' and brick.apply_burn then
    brick:apply_burn(self.dmg*0.5, 2)
  elseif self.effect == 'slow' and brick.apply_slow then
    brick:apply_slow(0.6, 1.5)
  end
  if brick.on_ball_contact then
    brick:on_ball_contact(self)
  elseif brick.take_damage then
    brick:take_damage(self.dmg, self.color)
  end
  spawn_burst(main.current.effects, self.x, self.y, self.color, 4, 60, 110)
  self.dead = true
end

function AllyCritter:take_damage() end


-- Locust: the Hive hero's bug (Swarm Pressure). A tiny erratic critter that
-- ZIGZAGS toward a target brick, gnaws it, and -- a fraction of the time -- RICOCHETS
-- onward to another brick before dying. Uses the 'projectile' tag (collides only
-- with bricks). On a killing bite it pings its parent hero for a brief feeding
-- frenzy. Steers actively each frame (so it homes), unlike the straight-up
-- AllyCritter. Modeled on AllyCritter; damage is applied flat (NOT routed through
-- on_ball_contact) so a dense drizzle doesn't spam the combo meter.
Locust = Object:extend()
Locust:implement(GameObject)
Locust:implement(Physics)

function Locust:init(args)
  self:init_game_object(args)
  self.r_size   = 2.6
  self.color    = self.color or green[0]
  self.dmg      = self.dmg or 5
  self.speed    = self.speed or 155
  self.ric      = self.ric or 0
  self.lifetime = self.lifetime or 2.2
  self.zig_t    = random:float(0, 2*math.pi)
  self.zig_f    = random:float(26, 34)
  self.hit_ids  = {}

  self:set_as_circle(self.r_size, 'dynamic', 'projectile')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(0.2)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.15)

  local a = self.r or -math.pi/2
  self:set_velocity(math.cos(a)*self.speed, math.sin(a)*self.speed)
  self.hfx:add('hit', 1)

  self.on_collision_enter = function(s, other, contact)
    if other and other.tag == 'brick' then s:on_brick_contact(other) end
  end
  self.t:after(self.lifetime, function() self.dead = true end)
end

-- Nearest live brick we haven't gnawed yet this flight.
function Locust:retarget()
  local arena = main.current
  if not arena then return end
  local best, bd = nil, 1e9
  for _, o in ipairs(arena.main.objects) do
    if o:is(Brick) and not o.dead and not self.hit_ids[o.id] then
      local d = math.distance(self.x, self.y, o.x, o.y)
      if d < bd then bd = d; best = o end
    end
  end
  self.target = best
end

function Locust:update(dt)
  self:update_game_object(dt)
  local arena = main.current
  if not arena then return end
  if not self.target or self.target.dead then self:retarget() end
  self.zig_t = self.zig_t + dt*self.zig_f
  if self.target then
    -- Base heading toward the target + a perpendicular zigzag wobble.
    local want = math.atan2(self.target.y - self.y, self.target.x - self.x)
    local perp = want + math.pi/2
    local zig  = math.sin(self.zig_t)*0.9
    self:set_velocity(math.cos(want)*self.speed + math.cos(perp)*zig*45,
                      math.sin(want)*self.speed + math.sin(perp)*zig*45)
  end
  if self.x < arena.x1 - 8 or self.x > arena.x2 + 8 or self.y < arena.y1 - 8 or self.y > arena.y2 + 8 then
    self.dead = true
  end
end

function Locust:draw()
  local vx, vy = self:get_velocity()
  local a = math.atan2(vy or 0, vx or -1)
  local ca, sa = math.cos(a), math.sin(a)
  -- a tiny dark dash along its heading + a bright body fleck of the hero colour
  graphics.line(self.x - ca*3, self.y - sa*3, self.x + ca*2, self.y + sa*2, Color(0.18, 0.20, 0.10, 1), 2)
  graphics.circle(self.x, self.y, 1.2, self.hfx.hit.f and fg[0] or self.color)
end

function Locust:on_brick_contact(brick)
  if brick.dead or self.hit_ids[brick.id] then return end
  self.hit_ids[brick.id] = true
  if brick.take_damage then brick:take_damage(self.dmg, self.color) end
  local killed = brick.dead or (brick.hp ~= nil and brick.hp <= 0)
  spawn_burst(main.current.effects, self.x, self.y, self.color, 3, 50, 100)
  self.hfx:use('hit', 0.2)
  -- Feeding frenzy: a kill spurs the parent hive to vent faster for a beat.
  if killed and self.parent and not self.parent.dead then
    self.parent.locust_frenzy = math.max(self.parent.locust_frenzy or 0, 0.5)
  end
  -- Ricochet onward to a fresh brick, else die.
  if self.ric > 0 then
    self.ric = self.ric - 1
    self:retarget()
    if self.target then return end
  end
  self.dead = true
end

function Locust:take_damage() end


-- Wave-10 Boss: "The Prism Core".
--
-- A single large, freely-moving geometric construct that floats in the upper
-- third of the arena and fires bullet-hell patterns. Tagged 'brick' so the
-- existing ball/brick collision matrix lets hero balls damage it and bounce.
-- Has three HP-banded phases that unlock new attacks and shift its color.
-- On death the arena's boss_defeated flag is set and BallPit:update advances
-- to the next wave.
Boss = Object:extend()
Boss:implement(GameObject)
Boss:implement(Physics)


-- Phase color targets. The boss tweens from red → orange → purple as HP
-- drops, telegraphing escalation without needing dialog or UI text.
local BOSS_PHASE_COLORS = {
  function() return red[0]    end,
  function() return orange[0] end,
  function() return purple[0] end,
}


function Boss:init(args)
  self:init_game_object(args)
  self.r_outer = 28
  self.r_inner = 14

  -- HP scales with wave the same way bricks do (see Brick:init line 81) so
  -- the fight stays meaningful if the player triggers it on a later loop.
  local wave = (main.current and main.current.wave) or 10
  self.max_hp     = 2400 * (1 + 0.2*wave)
  self.hp         = self.max_hp
  self.player_dmg = 3
  self.xp_value   = 60

  self.phase      = 1
  self.color      = BOSS_PHASE_COLORS[1]()
  self.outer_rot  = 0
  self.inner_rot  = 0
  self.spawn_t    = 0
  self.intro_done = false

  -- Status-effect compatibility with hero abilities. Same shape as Brick.
  self.slow_factor = 1
  self.slow_timer  = 0
  self.burn_timer  = 0
  self.burn_dps    = 0
  self.curse_mult  = 1
  self.curse_timer = 0

  self:set_as_circle(self.r_outer, 'kinematic', 'brick')
  self:set_restitution(1)
  self:set_friction(0)
  self.hfx:add('hit', 1)

  -- Vertical anchor for the path modes (the recenter target in update). y stays
  -- high so the boss never reaches the paddle line.
  self.y_anchor = self.y

  -- Movement state machine. The boss eases toward a target traced by one of
  -- several smooth parametric path modes (see choose_move_mode / movement_point).
  -- Each mode is anchored to begin exactly where the boss is, so switching modes
  -- is seamless; path_cx/cy then recenter slowly so it never drifts to an edge.
  self.move_mode     = 'orbit'
  self.move_ease     = 3.0
  self.move_w        = 1.0
  self.move_period   = 2*math.pi
  self.path_clock    = 0
  self.path_cx       = self.x
  self.path_cy       = self.y
  self.shape_dir     = 1
  self.shape_k       = 3
  self.shape_phase   = 0
  self:choose_move_mode()

  spawn1:play{volume = 0.5, pitch = 0.7}

  -- Schedule attacks. Phase 3 also runs a separate minion-drop timer started
  -- on phase transition (see enter_phase). Boss starts attacking after a
  -- short grace so the player has a moment to read the spawn.
  self.t:after(1.6, function()
    self.t:every({2.4, 3.4}, function() self:choose_attack() end, 0, nil, 'boss_atk')
  end)
end


function Boss:enter_phase(phase)
  if phase <= self.phase then return end
  self.phase = phase
  self.color = BOSS_PHASE_COLORS[phase]()
  spawn_burst(main.current.effects, self.x, self.y, self.color, 18, 80, 220)
  Flash{group = main.current.effects, x = gw/2, y = gh/2,
        color = Color(self.color.r, self.color.g, self.color.b, 0.35), duration = 0.18}
  TelegraphRing{group = main.current.effects, x = self.x, y = self.y,
                radius = 80, color = self.color, duration = 0.6}

  -- Speed up the attack timer slightly on each phase transition.
  if phase == 3 then
    self.t:cancel('boss_atk')
    self.t:every({1.6, 2.4}, function() self:choose_attack() end, 0, nil, 'boss_atk')
  elseif phase == 2 then
    self.t:cancel('boss_atk')
    self.t:every({2.0, 2.9}, function() self:choose_attack() end, 0, nil, 'boss_atk')
  end
end


-- Every projectile the boss fires routes through here, so it always spawns at
-- the boss's live position, in its current phase colour, and — crucially —
-- flagged unbreakable. Returns the projectile (or nil), and no-ops safely when
-- called from a deferred timer after the world is gone / the boss has died.
function Boss:fire(opts)
  local arena = main.current
  if not (arena and arena.main and arena.main.world and not self.dead) then return end
  opts.group = arena.main
  if opts.x == nil then opts.x = self.x end
  if opts.y == nil then opts.y = self.y end
  opts.color = opts.color or self.color
  if opts.unbreakable == nil then opts.unbreakable = true end
  -- Boss bullets must survive long enough to cross the tall (~600px) arena and
  -- then despawn at the edge via EnemyProjectile's off-screen cleanup, instead
  -- of self-destructing mid-flight. The per-attack `life` values were far
  -- shorter than the slow bullets' arena-crossing time, so enforce a floor.
  opts.life = math.max(opts.life or 0, 16)
  return EnemyProjectile(opts)
end


function Boss:choose_attack()
  if self.dead then return end
  -- Attack pool unlocks with phase; each tier layers denser / harder-to-read
  -- patterns on top of the last.
  --   p1: spiral, aimed shotgun, fast snipe darts
  --   p2: + 360° ring, multi-arm flower spiral, sweeping gap wall
  --   p3: + counter-rotating double spiral, homing seekers (shotgun drops out;
  --       the phase-3 pressure comes from the denser radial patterns instead)
  local pool
  if self.phase == 1 then
    pool = {'spiral', 'shotgun', 'snipe'}
  elseif self.phase == 2 then
    pool = {'spiral', 'shotgun', 'ring', 'snipe', 'flower', 'wall'}
  else
    pool = {'ring', 'flower', 'wall', 'spiral_double', 'homing', 'snipe', 'flower'}
  end
  local pick = pool[random:int(1, #pool)]
  if     pick == 'spiral'        then self:attack_spiral()
  elseif pick == 'shotgun'       then self:attack_shotgun()
  elseif pick == 'ring'          then self:attack_ring()
  elseif pick == 'snipe'         then self:attack_snipe()
  elseif pick == 'flower'        then self:attack_flower()
  elseif pick == 'wall'          then self:attack_wall()
  elseif pick == 'spiral_double' then self:attack_spiral_double()
  elseif pick == 'homing'        then self:attack_homing() end
end


-- Spiral barrage: 16 projectiles fired one every 0.1 sec while the firing
-- angle rotates. Reads as a turning bullet spiral.
function Boss:attack_spiral()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 22,
                color = self.color, duration = 0.25}
  shoot1:play{volume = 0.3, pitch = 0.85}
  local base = random:float(0, 2*math.pi)
  local dir  = random:bool(50) and 1 or -1
  for i = 0, 15 do
    self.t:after(i*0.1, function()
      -- Boss spiral: slow, matches the spiraler enemy's bullet tempo so both
      -- attack types read as "swirling, lingering" threats.
      self:fire{kind = 'boss_orb', angle = base + dir*i*0.42, speed = 55, r_size = 3.2, life = 4}
    end)
  end
end


-- Counter-rotating double spiral (phase 3): two arms turning in opposite
-- directions at once, weaving a much denser lattice than the single spiral.
-- Slightly faster per-shot cadence so the screen fills quickly.
function Boss:attack_spiral_double()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 26,
                color = self.color, duration = 0.3}
  shoot1:play{volume = 0.32, pitch = 0.78}
  local base = random:float(0, 2*math.pi)
  for i = 0, 17 do
    self.t:after(i*0.08, function()
      self:fire{kind = 'boss_orb', angle = base + i*0.34,           speed = 52, r_size = 3, life = 4.5}
      self:fire{kind = 'boss_orb', angle = base + math.pi - i*0.34, speed = 52, r_size = 3, life = 4.5}
    end)
  end
end


-- Multi-arm "flower" spiral: several arms fired together and rotated each step,
-- painting overlapping petals. Uses the spinning star bullet so it reads as
-- distinct from the round boss_orb spirals even when they overlap.
function Boss:attack_flower()
  if self.dead then return end
  local arena = main.current
  local arms  = (self.phase >= 3) and 5 or 4
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 24,
                color = self.color, duration = 0.3}
  shoot1:play{volume = 0.3, pitch = 1.0}
  local base = random:float(0, 2*math.pi)
  local dir  = random:bool(50) and 1 or -1
  for i = 0, 13 do
    self.t:after(i*0.085, function()
      for arm = 0, arms - 1 do
        local a = base + dir*i*0.30 + arm*(2*math.pi/arms)
        self:fire{kind = 'star', angle = a, speed = 58, r_size = 3, life = 4.5}
      end
    end)
  end
end


-- Aimed shotgun: 0.4s telegraph at paddle position, then a 5-shot fan aimed
-- at the paddle's location at the moment of fire.
function Boss:attack_shotgun()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = arena.paddle.x, y = arena.paddle.y - 4,
                radius = 16, color = self.color, duration = 0.4}
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 16,
                color = self.color, duration = 0.4}
  self.t:after(0.4, function()
    if not (arena.main and arena.main.world and not self.dead) then return end
    shoot1:play{volume = 0.32, pitch = 0.95}
    local base = math.atan2(arena.paddle.y - self.y, arena.paddle.x - self.x)
    for _, off in ipairs({-0.32, -0.16, 0, 0.16, 0.32}) do
      -- Boss shotgun: fast 5-shot fan. Faster than the ring blast so the aimed
      -- pattern feels more urgent than the radial spray.
      self:fire{kind = 'boss_orb', angle = base + off, speed = 110, dmg = 2, r_size = 4}
    end
  end)
end


-- Snipe: a short telegraph then three fast darts, each RE-AIMED at the paddle's
-- live position as it fires, so a player who just strafes gets tracked. Much
-- faster and narrower than the shotgun fan, rewarding a committed dodge.
function Boss:attack_snipe()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = arena.paddle.x, y = arena.paddle.y - 4,
                radius = 14, color = self.color, duration = 0.45}
  for shot = 0, 2 do
    self.t:after(0.45 + shot*0.13, function()
      if not (arena.main and arena.main.world and not self.dead) then return end
      shoot1:play{volume = 0.3, pitch = 1.15}
      local a = math.atan2(arena.paddle.y - self.y, arena.paddle.x - self.x)
      self:fire{kind = 'dart', angle = a, speed = 150, dmg = 2, r_size = 3.4, life = 5}
    end)
  end
end


-- Ring blast: 0.6s expanding telegraph, then 18 projectiles fired outward in a
-- perfect 360° circle. Phase 3 adds a second, slower ring offset half a step,
-- doubling it into a denser 36-shot lattice.
function Boss:attack_ring()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 50,
                color = self.color, duration = 0.6}
  self.t:after(0.6, function()
    if not (arena.main and arena.main.world and not self.dead) then return end
    shoot1:play{volume = 0.4, pitch = 0.8}
    explosion1:play{volume = 0.25, pitch = 1.3}
    Flash{group = arena.effects, x = gw/2, y = gh/2,
          color = Color(self.color.r, self.color.g, self.color.b, 0.25), duration = 0.1}
    for i = 0, 17 do
      local a = i*(2*math.pi/18)
      -- Medium speed so players can slip between adjacent shots.
      self:fire{kind = 'boss_orb', angle = a, speed = 80, life = 4}
      if self.phase >= 3 then
        self:fire{kind = 'boss_orb', angle = a + math.pi/18, speed = 55, life = 5}
      end
    end
  end)
end


-- Sweeping gap wall: a full-width row of bullets spawns at the top of the arena
-- and marches straight down, leaving one (phase 1-2) or two (phase 3) gaps the
-- player must line the paddle up with. Telegraphed by per-column rings during
-- the wind-up; the gap columns get no ring, so the safe lane is readable.
function Boss:attack_wall()
  if self.dead then return end
  local arena = main.current
  local n     = 13
  local x1    = arena.x1 + 10
  local x2    = arena.x2 - 10
  local y0    = arena.y1 + 8
  -- Pick gap columns, avoiding the two outermost so the gap stays reachable.
  local gaps  = { random:int(1, n - 2) }
  if self.phase >= 3 then
    local g2
    repeat g2 = random:int(1, n - 2) until math.abs(g2 - gaps[1]) >= 3
    gaps[#gaps + 1] = g2
  end
  local function is_gap(i)
    for _, g in ipairs(gaps) do if i == g then return true end end
    return false
  end
  for i = 0, n - 1 do
    if not is_gap(i) then
      local px = math.lerp(i/(n - 1), x1, x2)
      TelegraphRing{group = arena.effects, x = px, y = y0, radius = 9,
                    color = self.color, duration = 0.7}
    end
  end
  self.t:after(0.7, function()
    if not (arena.main and arena.main.world and not self.dead) then return end
    shoot1:play{volume = 0.4, pitch = 0.7}
    for i = 0, n - 1 do
      if not is_gap(i) then
        local px = math.lerp(i/(n - 1), x1, x2)
        self:fire{x = px, y = y0, kind = 'diamond', angle = math.pi/2, speed = 64, life = 8}
      end
    end
  end)
end


-- Homing seekers (phase 3): a few slow orbs that gently curve toward the
-- paddle. Turn rate is deliberately low so committed movement still shakes
-- them, but they punish standing still after another pattern goes out.
function Boss:attack_homing()
  if self.dead then return end
  local arena = main.current
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 20,
                color = self.color, duration = 0.4}
  self.t:after(0.4, function()
    if not (arena.main and arena.main.world and not self.dead) then return end
    shoot1:play{volume = 0.3, pitch = 0.9}
    for _, off in ipairs({-0.5, 0, 0.5}) do
      self:fire{kind = 'comet', angle = math.pi/2 + off, speed = 60, r_size = 3.4,
                life = 7, homing = true, homing_turn = 0.85}
    end
  end)
end


-- Base angular frequency per movement mode. movement_point builds every curve
-- from integer multiples of this, so each pattern is exactly periodic with
-- period 2*pi/w. Lower w → a slower, larger trace; the elaborate multi-lobe
-- curves get lower values so they don't whip around too fast.
local MOVE_W = {
  figure8 = 0.90, orbit = 1.00, spirograph = 0.65, rose = 0.65,
  log_spiral = 0.50, epitrochoid = 0.60,
}


-- Picks the next movement path mode from a phase-gated pool and rolls fresh
-- shape parameters for it, so a repeated mode traces a different-looking curve.
-- Every mode is a smooth, continuous parametric path, drawn to completion (one
-- full period) before the next is chosen. Avoids repeating a mode back-to-back.
function Boss:choose_move_mode()
  local arena   = main.current
  local arena_w = (arena and (arena.x2 - arena.x1)) or gw

  local pool
  if self.phase == 1 then
    pool = {'figure8', 'orbit', 'rose', 'log_spiral'}
  elseif self.phase == 2 then
    pool = {'figure8', 'orbit', 'spirograph', 'rose', 'log_spiral'}
  else
    pool = {'orbit', 'spirograph', 'figure8', 'epitrochoid', 'rose', 'log_spiral'}
  end

  -- Re-roll up to a few times so we don't immediately repeat the same mode.
  local pick = self.move_mode
  for _ = 1, 6 do
    pick = pool[random:int(1, #pool)]
    if pick ~= self.move_mode then break end
  end
  self.move_mode  = pick
  self.path_clock = 0

  -- Fresh shape params each time: rotation direction, petal / frequency count
  -- and a phase offset, so the same pattern looks different on repeat.
  self.shape_dir   = random:bool(50) and 1 or -1
  self.shape_k     = random:int(2, 4)
  self.shape_phase = random:float(0, 2*math.pi)

  -- Base frequency + exact period for this mode. The boss traces one full
  -- period (see update) before switching, so the pattern always completes.
  self.move_w      = MOVE_W[pick] or 0.9
  self.move_period = 2*math.pi / self.move_w
  self.move_ease   = 3.0

  -- Anchor the pattern so its t=0 point is exactly the boss's current position:
  -- the curve begins where the boss already is, so a mode switch never jumps it
  -- to a far spot. update() then recenters path_cx/cy slowly so the boss doesn't
  -- drift to an edge over many modes.
  local rx0, ry0 = self:movement_point(0, arena_w)
  self.path_cx = self.x - rx0
  self.path_cy = self.y - ry0
end


-- Returns the curve's DISPLACEMENT (rx, ry) from its centre at per-mode time
-- `mt`, for the current mode. update() adds it to the (recentering) pattern
-- centre path_cx/cy; choose_move_mode anchors that centre so mt=0 lands on the
-- boss, making mode switches seamless. A is the horizontal reach. Every branch
-- is a smooth, continuous parametric curve.
function Boss:movement_point(mt, arena_w)
  local A  = arena_w*0.34
  local d  = self.shape_dir or 1
  local ph = self.shape_phase or 0
  local w  = self.move_w or 0.9
  local m  = self.move_mode
  local rx, ry
  if m == 'figure8' then
    -- Lissajous 1:2 — a crossing figure-eight (closes in one period).
    rx = math.sin(w*mt)*A
    ry = math.sin(2*w*mt)*22
  elseif m == 'orbit' then
    -- Plain elliptical orbit.
    rx = math.cos(d*w*mt + ph)*A*0.78
    ry = math.sin(d*w*mt + ph)*34
  elseif m == 'spirograph' then
    -- Epitrochoid (1:3): a fast small circle riding a slow big one → rosette
    -- loops. The two radii sum to 1 so it stays inside the play box.
    local a1, a2 = w*mt, d*3*w*mt + ph
    rx = (math.cos(a1)*0.64 + math.cos(a2)*0.36)*A
    ry = (math.sin(a1)*0.64 + math.sin(a2)*0.36)*40
  elseif m == 'rose' then
    -- Rhodonea (rose): the radius swings with the angle, sweeping petals out
    -- through the centre and back; closes after one revolution.
    local ang = d*w*mt + ph
    local rr  = math.cos((self.shape_k or 3)*ang)
    rx = rr*math.cos(ang)*A
    ry = rr*math.sin(ang)*40
  elseif m == 'log_spiral' then
    -- Logarithmic (equiangular) spiral, traced out from the centre and back:
    -- the radius grows exponentially with the winding angle, so successive
    -- loops sit exponentially farther apart, then it retraces inward to close.
    local u    = w*mt
    local ang  = d*3*u + ph
    local env  = (1 - math.cos(u))*0.5                        -- 0->1->0
    local radn = (math.exp(1.7*env) - 1)/(math.exp(1.7) - 1)  -- exp growth, 0..1
    rx = math.cos(ang)*A*radn
    ry = math.sin(ang)*38*radn
  elseif m == 'epitrochoid' then
    -- Epitrochoid (1:5, subtractive): a small circle rolling around a big one,
    -- tracing a ring of ~four outer loops — busier than the spirograph.
    local big, small = d*w*mt + ph, d*5*w*mt + ph
    rx = (math.cos(big) - 0.45*math.cos(small))*A*0.69
    ry = (math.sin(big) - 0.45*math.sin(small))*38*0.69
  else  -- safety fallback (no pool uses this): hold at the pattern centre.
    rx, ry = 0, 0
  end
  return rx, ry
end


function Boss:update(dt)
  self:update_game_object(dt)
  self.spawn_t = self.spawn_t + dt

  -- Phase-banded movement speed: every phase moves faster, increasing
  -- pressure as HP drops.
  local speed_factor = (self.phase == 1) and 1.0 or (self.phase == 2 and 1.3 or 1.6)
  self.outer_rot = self.outer_rot + dt * 0.9 * speed_factor
  self.inner_rot = self.inner_rot - dt * 1.4 * speed_factor

  -- Slow status reduces movement + attack rate uniformly.
  if self.slow_timer > 0 then
    self.slow_timer = self.slow_timer - dt
    if self.slow_timer <= 0 then self.slow_factor = 1 end
    speed_factor = speed_factor * self.slow_factor
  end

  -- Burn DoT: same shape as Brick's burn handling (brick.lua:260).
  if self.burn_timer > 0 then
    self.burn_timer = self.burn_timer - dt
    self:take_damage(self.burn_dps*dt, orange[0], true)
    if random:bool(15) then
      HitParticle{
        group = main.current.effects,
        x = self.x + random:float(-self.r_outer*0.6, self.r_outer*0.6),
        y = self.y - self.r_outer*0.6,
        color = orange[0], v = 30, r = -math.pi/2, w = 2, duration = 0.3,
      }
    end
  end

  if self.curse_timer > 0 then
    self.curse_timer = self.curse_timer - dt
    if self.curse_timer <= 0 then self.curse_mult = 1 end
  end

  -- ---- Path logic --------------------------------------------------------
  -- path_clock integrates *scaled* time each frame (so a phase or slow change
  -- can't jump the curve) and resets to 0 in choose_move_mode. The boss switches
  -- modes only once it has traced one full period of the current curve, so every
  -- pattern is drawn start-to-end instead of being cut off by a timer.
  self.path_clock = self.path_clock + dt*speed_factor
  -- The boss EASES toward the target, so it trails the curve by ~1/move_ease (in
  -- path-clock units). Trace that bit past one full period before switching, so
  -- the boss reaches the loop's closing point instead of cutting it a little short.
  if self.path_clock >= self.move_period + 1.5/self.move_ease then self:choose_move_mode() end

  local arena   = main.current
  local arena_w = (arena and (arena.x2 - arena.x1)) or gw

  -- Slowly recenter the pattern toward its home so the boss doesn't wander to an
  -- edge over many modes (choose_move_mode anchors the centre where the boss is,
  -- so it starts off-centre; this eases it back with no visible jump). The home
  -- y sits low enough that even the tallest curve's full swing clears the top.
  local rcx = (arena and arena:arena_center_x()) or gw/2
  local rcy = self.y_anchor + 100
  self.path_cx = self.path_cx + (rcx - self.path_cx)*math.min(1, dt*0.2)
  self.path_cy = self.path_cy + (rcy - self.path_cy)*math.min(1, dt*0.2)

  -- Target = pattern centre + the curve's offset at the current per-mode time.
  -- Because choose_move_mode anchored the centre so the curve starts at the
  -- boss's position, switching modes is seamless — the boss flows from one
  -- pattern straight into the next instead of darting to a new spot.
  local rx, ry = self:movement_point(self.path_clock, arena_w)
  local tx, ty = self.path_cx + rx, self.path_cy + ry

  -- Clamp inside the arena. The lower bound is 0.5*height so the tall curves
  -- (plus their anchor offset) have headroom and never flatten against an edge.
  local margin  = self.r_outer + 4
  local ay1     = (arena and arena.y1) or 0
  local arena_h = (arena and (arena.y2 - arena.y1)) or gh
  tx = math.clamp(tx, (arena and arena.x1 or 0) + margin, (arena and arena.x2 or gw) - margin)
  ty = math.clamp(ty, ay1 + self.r_outer + 6, ay1 + arena_h*0.5)

  -- Frame-rate-independent ease, clamped so a frame spike can't overshoot.
  local k = math.min(1, self.move_ease * speed_factor * dt)
  self:set_position(self.x + (tx - self.x)*k, self.y + (ty - self.y)*k)
end


function Boss:on_ball_contact(ball)
  -- Hero ball collided with the boss. Match the Brick contact flow but skip
  -- the formation knockback path (boss is solo).
  if self.hp <= 0 then return end
  local dmg = ball.dmg*(ball.charge_dmg_mult or 1)
  self:take_damage(dmg, ball.color)
end


function Boss:take_damage(amount, color, no_flash)
  if self.hp <= 0 then return end
  amount = amount * (self.curse_mult or 1)
  self.hp = self.hp - amount
  if not no_flash then
    self.hfx:use('hit', 0.25, 200, 10)
    spawn_burst(main.current.effects, self.x, self.y, color or self.color, 4, 50, 130)
  end

  -- Phase transitions at the 2/3 and 1/3 HP marks.
  if self.phase < 2 and self.hp <= self.max_hp*(2/3) then self:enter_phase(2) end
  if self.phase < 3 and self.hp <= self.max_hp*(1/3) then self:enter_phase(3) end

  if self.hp <= 0 then self:die() end
end


function Boss:die()
  local arena = main.current
  -- Tell the arena XP/score systems we died, same hook as bricks use.
  arena:on_brick_killed(self)

  -- Big celebratory effects.
  spawn_burst(arena.effects, self.x, self.y, self.color, 60, 80, 280)
  spawn_burst(arena.effects, self.x, self.y, fg[5],      24, 60, 220)
  Flash{group = arena.effects, x = gw/2, y = gh/2, color = white_transparent_weak, duration = 0.25}
  explosion1:play{volume = 0.7, pitch = 0.7}
  enemy_die1:play{volume = 0.6, pitch = 0.6}

  -- Big XP drop so the player gets a meaningful payoff and likely level-up.
  local x, y, v = self.x, self.y, self.xp_value
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      XpOrb{group = arena.main, x = x, y = y, value = v}
    end
  end)

  arena.boss_defeated = true
  self.dead = true
end


function Boss:apply_slow(factor, duration)
  if factor < self.slow_factor then self.slow_factor = factor end
  if duration > self.slow_timer then self.slow_timer = duration end
end


function Boss:apply_burn(dps, duration)
  self.burn_dps   = math.max(self.burn_dps, dps)
  self.burn_timer = math.max(self.burn_timer, duration)
end


function Boss:apply_curse(color, mult, duration)
  self.curse_mult  = math.max(self.curse_mult or 1, mult or 1.4)
  self.curse_timer = math.max(self.curse_timer or 0, duration or 6)
end


function Boss:draw()
  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local dark = Color(col.r*0.45, col.g*0.45, col.b*0.45, 1)

  -- Outer 12-sided ring, drawn as a polygon outline.
  local verts_out = {}
  for i = 0, 11 do
    local a = self.outer_rot + i*(2*math.pi/12)
    table.insert(verts_out, self.x + math.cos(a)*self.r_outer*s)
    table.insert(verts_out, self.y + math.sin(a)*self.r_outer*s)
  end
  graphics.polygon(verts_out, dark)
  graphics.polygon(verts_out, col, 2)

  -- Inner counter-rotating hexagon.
  local verts_in = {}
  for i = 0, 5 do
    local a = self.inner_rot + i*(2*math.pi/6)
    table.insert(verts_in, self.x + math.cos(a)*self.r_inner*s)
    table.insert(verts_in, self.y + math.sin(a)*self.r_inner*s)
  end
  graphics.polygon(verts_in, col)
  graphics.polygon(verts_in, fg[5], 1)

  -- Bright pulsing core.
  local pulse = 1 + math.sin(love.timer.getTime()*6)*0.25
  graphics.circle(self.x, self.y, 3*pulse*s, fg[5])

  -- HP bar across the top of the play area.
  local arena = main.current
  if arena then
    local pct   = math.clamp(self.hp/self.max_hp, 0, 1)
    local bar_w = (arena.x2 - arena.x1) - 16
    local bar_x = (arena.x1 + arena.x2)/2
    local bar_y = arena.y1 + 4
    graphics.rectangle(bar_x, bar_y, bar_w, 4, 1, 1, bg[-2])
    graphics.rectangle(bar_x - bar_w/2 + bar_w*pct/2, bar_y, bar_w*pct, 4, 1, 1, col)
    graphics.print_centered('THE PRISM CORE', pixul_font,
                            bar_x, bar_y + 8, 0, 1, 1, 0, 0, fg[0])
  end

  -- Slow / curse visual overlays, mirror Brick:draw idioms.
  if self.slow_factor < 1 then
    graphics.circle(self.x, self.y, self.r_outer*1.1, blue_transparent_weak)
  end
  if (self.curse_mult or 1) > 1 then
    local cp = 0.5 + 0.2*math.sin(love.timer.getTime()*5)
    graphics.circle(self.x, self.y, self.r_outer*1.15,
                    Color(purple[0].r, purple[0].g, purple[0].b, 0.35*cp), 1.5)
  end
end
