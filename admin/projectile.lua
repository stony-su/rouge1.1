-- Lightweight projectile fired by certain hero abilities (vagrant, archer, scout).
-- It travels in a straight line, optionally pierces, ricochets, or CHAINS
-- (the SNKRX scout port: leaps to a random nearby target it hasn't hit yet,
-- speeding up — and optionally ramping damage — on every hop).
-- wall_stick (the SNKRX archer port): projectiles don't collide with walls in
-- the physics matrix, so update() bounces the bolt off the arena bounds while
-- it has ricochet charges left and otherwise thunks it in as a WallArrow.

-- Spawn-out / burn-out timing. Every bolt grows out of its muzzle over
-- SPAWN_DUR and, once it is spent, shrinks and fades over DESPAWN_DUR instead
-- of blinking off in a single frame -- a bolt vanishing mid-air reads as a
-- rendering glitch rather than "that one is done". Both are per-shot
-- overridable (the engineer's turret asks for a slower muzzle).
local PROJECTILE_SPAWN_DUR   = 0.07
local PROJECTILE_DESPAWN_DUR = 0.13

Projectile = Object:extend()
Projectile:implement(GameObject)
Projectile:implement(Physics)


function Projectile:init(args)
  self:init_game_object(args)
  self.dmg      = self.dmg or 8
  -- Percent-of-max-HP damage. When > 0 the shot ignores its flat dmg on any
  -- enemy that tracks a max_hp and takes that fraction of it instead (engineer
  -- turret bolts 33%, archer bolts 100%), so a single shot stays meaningful
  -- against late-wave bricks whose HP scales with the wave. Enemies with no
  -- max_hp (EnemyCritter) fall back to the flat dmg. See Projectile:damage_to.
  self.max_hp_frac = self.max_hp_frac or 0
  -- Muzzle spawn-out: the bolt is born SHORT and white-hot and stretches to
  -- full length over spawn_dur under a shrinking muzzle flare, so it reads as
  -- being fired out of a barrel rather than appearing mid-air already at size.
  -- On for every shot now; pass spawn_dur = 0 to opt a particular one out.
  self.spawn_dur = self.spawn_dur or PROJECTILE_SPAWN_DUR
  self.spawn_t   = 0
  self.speed    = self.speed or 220
  self.pierce   = self.pierce or 0
  self.ricochet = self.ricochet or 0
  self.chain    = self.chain or 0
  self.color    = self.color or fg[0]
  self.type     = self.type or 'arrow'
  -- Per-shot size multiplier on both the drawn body and the physics circle.
  -- Three different heroes fire type='arrow' (vagrant, archer, the turret in
  -- effects.lua), so a bigger bolt has to be opt-in per shot rather than baked
  -- into the type -- hence a scalar carried on the projectile itself.
  self.proj_scale = self.proj_scale or 1
  -- Assassin extras: crit doubles the strike (already baked into dmg by the
  -- caller) and adds a burst on hit; bleed is the TOTAL DoT applied to every
  -- brick the knife pierces, spread over bleed_dur (see on_hit_brick).
  self.crit      = self.crit or false
  self.bleed     = self.bleed or 0
  self.bleed_dur = self.bleed_dur or 3
  -- Homing: steer the heading toward the nearest brick each frame. Used by the
  -- jester's level-3 "Pandemonium" death-knives (SNKRX jester, enemies.lua:632),
  -- so the cross a hexed brick bursts into hunts down the rest of the swarm.
  self.homing      = self.homing or false
  self.homing_turn = self.homing_turn or 6   -- max steer rate, rad/s
  -- Spellblade spiral: orbit_vr is the angular velocity of the heading (rad/s);
  -- the velocity vector rotates by orbit_vr each second while orbit_vr decays,
  -- so the blade curls outward in a spiral that opens up (SNKRX spellblade).
  -- spin / btrail drive the spinning-blade draw and its curved afterimage trail.
  self.orbit_vr = self.orbit_vr or 0
  self.spin     = 0
  if self.type == 'spellblade' then
    self.spin_speed = 20*(self.orbit_vr >= 0 and 1 or -1)
    self.btrail     = {}
    self._tr_t      = 0
    -- Dissolve-out state: instead of popping out at end-of-life, the shard fades
    -- + shrinks over fade_dur (see the end-of-life timer + draw_spellblade_shard).
    self.fade       = 1
    self.fade_dur   = 0.28
  end
  -- Cannonball (SNKRX cannoneer port): a heavy iron shell that DETONATES into a
  -- splash on the first thing it touches (brick or wall) instead of piercing.
  -- blast_radius + dmg (= the blast damage) drive the explosion; bombard schedules
  -- the level-3 aftershocks. It tumbles + sheds gunsmoke as it flies (see update).
  if self.type == 'cannonball' then
    self.cball_spin = random:float(0, 2*math.pi)
    self._smoke_t   = 0
  end
  -- Wall-sticking bolts live long enough to cross the arena and spend their
  -- ricochets; they end at a wall (or the open pit), not on a timer.
  -- Spellblade shards travel a shorter distance before dissolving (was 1.5s ->
  -- ~300px at speed 200; now ~0.85s -> ~170px, fading out over the last fade_dur).
  self.life     = self.life or (self.wall_stick and 6 or (self.type == 'spellblade' and 0.85 or 1.5))
  self.hits     = {}

  -- The hit circle scales with the drawn body, so a visibly fatter bolt
  -- actually catches more -- it isn't just a bigger sprite on the same dot.
  self:set_as_circle(2*self.proj_scale, 'dynamic', 'projectile')
  self.body:setBullet(true)
  -- SENSOR, not a solid body. projectile:brick is the only physical pair a shot
  -- has left (ball/paddle/wall/xp/powerup are all disabled in reset_run), and
  -- leaving it solid meant every "pierce" ALSO took the solver's bounce impulse
  -- off the brick -- bricks are kinematic (infinite mass) and both sides carry
  -- restitution 1, so a bolt deflected hard off the very thing it was supposed
  -- to punch through. As a sensor the contact still reports (the engine routes
  -- sensor contacts to on_trigger_enter instead of on_collision_enter, see
  -- Group:set_as_physics_world) but Box2D applies no response, so the shot holds
  -- its line. Set on the MAIN fixture so it keeps the 'projectile' category and
  -- mask; the engine's own sensor fixture would default to category 1 ('paddle')
  -- and be filtered out by the brick.
  self.fixture:setSensor(true)
  self:set_fixed_rotation(false)
  self:set_restitution(1)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.1)
  self:set_velocity(math.cos(self.r)*self.speed, math.sin(self.r)*self.speed)
  self:set_angle(self.r)

  if self.type == 'spellblade' then
    -- Dissolve instead of popping out of existence: hold full life, then fade +
    -- shrink out over fade_dur, shedding a couple of arcane sparks as it breaks up.
    self.t:after(math.max(0, self.life - self.fade_dur), function()
      for _ = 1, 2 do
        ArcaneSpark{group = main.current.effects, x = self.x, y = self.y, color = self.color,
                    rs = random:float(2, 3), alpha = 0.6, spin = random:float(-8, 8), duration = self.fade_dur}
      end
      self.t:tween(self.fade_dur, self, {fade = 0}, math.linear, function() self.dead = true end)
    end)
  else
    self.t:after(self.life, function() self:begin_despawn() end)
  end

  -- Sensor contact (see setSensor above). Fires once per begin-overlap, which
  -- is what a piercing shot wants: one hit per brick as it passes through.
  self.on_trigger_enter = function(p, other, contact)
    if other and other.tag == 'brick' then
      p:on_hit_brick(other)
    end
  end
end


-- Muzzle spawn-out progress, 0 -> 1, eased. Reads 1 the whole time for shots
-- that didn't ask for the animation (spawn_dur == 0).
function Projectile:spawn_k()
  if (self.spawn_dur or 0) <= 0 then return 1 end
  local p = math.clamp(self.spawn_t/self.spawn_dur, 0, 1)
  return 1 - (1 - p)*(1 - p)*(1 - p)
end


-- Burn-out. A bolt that ran out of life, spent its last pierce, or found no
-- ricochet target used to blink off in one frame, which reads as a glitch
-- rather than "that one is spent". It now leaves the FIGHT at once while
-- coasting on its last heading for despawn_dur, shrinking and fading out.
--
-- The body is deliberately NOT deactivated: on_hit_brick runs inside a Box2D
-- collision callback, where the world is locked and setActive would throw. The
-- fight logic is gated instead -- update bails below, and on_hit_brick carries
-- its own `expiring` guard. Idempotent: the life timer, on_hit_brick and a
-- stray caller can all reach it.
function Projectile:begin_despawn(dur)
  if self.expiring or self.dead then return end
  self.expiring    = true
  self.despawn_dur = dur or PROJECTILE_DESPAWN_DUR
  self.despawn_t   = self.despawn_dur
end


-- 1 in normal flight, 1 -> 0 across the burn-out.
function Projectile:despawn_factor()
  if not (self.expiring and self.despawn_dur) then return 1 end
  return math.clamp(self.despawn_t/self.despawn_dur, 0, 1)
end


function Projectile:update(dt)
  self:update_game_object(dt)
  if self.spawn_t < self.spawn_dur then self.spawn_t = self.spawn_t + dt end

  -- Burning out: still coasting, still drawing, but out of the fight. Every
  -- branch below is flight/hit logic, so bail here rather than guarding each
  -- of them and hoping none is missed.
  if self.expiring then
    self.despawn_t = self.despawn_t - dt
    if self.despawn_t <= 0 then self.dead = true end
    return
  end
  -- Keep angle aligned with motion.
  local vx, vy = self:get_velocity()
  if vx ~= 0 or vy ~= 0 then self:set_angle(math.atan2(vy, vx)) end

  -- Spellblade spiral: rotate the heading by orbit_vr each frame (decaying), so
  -- the blade curls outward then straightens. Also spin the blade for the draw
  -- and sample a short position history for the curved afterimage trail.
  if self.type == 'spellblade' then
    if self.orbit_vr ~= 0 then
      local sp  = math.sqrt(vx*vx + vy*vy)
      local ang = math.atan2(vy, vx) + self.orbit_vr*dt
      self:set_velocity(math.cos(ang)*sp, math.sin(ang)*sp)
      self.orbit_vr = self.orbit_vr*(1 - 2.5*dt)
      if math.abs(self.orbit_vr) < 0.05 then self.orbit_vr = 0 end
    end
    self.spin  = self.spin + (self.spin_speed or 20)*dt
    self._tr_t = (self._tr_t or 0) + dt
    if self._tr_t >= 0.02 then
      self._tr_t = 0
      table.insert(self.btrail, 1, {x = self.x, y = self.y})
      if #self.btrail > 6 then table.remove(self.btrail) end
    end
  end

  local arena = main.current

  -- Cannonball: tumble, shed gunsmoke, and DETONATE the instant it reaches a
  -- wall (projectiles don't physically collide with walls, so test the bounds).
  if self.type == 'cannonball' then
    self.cball_spin = (self.cball_spin or 0) + 6*dt
    self._smoke_t   = (self._smoke_t or 0) + dt
    if self._smoke_t >= 0.03 then
      self._smoke_t = 0
      SmokePuff{group = arena.effects, x = self.x, y = self.y,
                color = Color(0.32, 0.30, 0.28, 1), rs = random:float(1.6, 3), alpha = random:float(0.2, 0.4),
                vx = random:float(-8, 8), vy = random:float(-14, 4), duration = random:float(0.3, 0.6)}
    end
    if self.x <= arena.x1 + 2 or self.x >= arena.x2 - 2 or self.y <= arena.y1 + 2 then
      self:cannon_explode()
      return
    end
  end

  -- Homing: curve the heading toward the nearest brick (jester death-knives at
  -- level 3). Only the direction is rotated -- speed is preserved -- so the knife
  -- banks after its target instead of snapping to it.
  if self.homing then
    local target = arena.get_nearest_brick and arena:get_nearest_brick(self.x, self.y)
    if target then
      local cur  = math.atan2(vy, vx)
      local want = math.atan2(target.y - self.y, target.x - self.x)
      local diff = math.loop(want - cur, 2*math.pi)
      if diff > math.pi then diff = diff - 2*math.pi end
      local sp   = math.sqrt(vx*vx + vy*vy)
      local na   = cur + math.clamp(diff, -self.homing_turn*dt, self.homing_turn*dt)
      vx, vy = math.cos(na)*sp, math.sin(na)*sp
      self:set_velocity(vx, vy)
    end
  end

  -- SNKRX archer wall behavior: with ricochet charges the bolt reflects off
  -- the side/top walls; spent, it sticks in as a WallArrow and dies. The
  -- bottom stays open (the pit) — bolts that exit there just fly off.
  if self.wall_stick then
    local nx, ny = 0, 0
    if     self.x <= arena.x1 + 2 and vx < 0 then nx = 1
    elseif self.x >= arena.x2 - 2 and vx > 0 then nx = -1
    elseif self.y <= arena.y1 + 2 and vy < 0 then ny = 1 end
    if nx ~= 0 or ny ~= 0 then
      _G[random:table{'arrow_hit_wall1', 'arrow_hit_wall2'}]:play{pitch = random:float(0.9, 1.1), volume = 0.2}
      if self.ricochet > 0 then
        self.ricochet = self.ricochet - 1
        if nx ~= 0 then vx = -vx end
        if ny ~= 0 then vy = -vy end
        self:set_velocity(vx, vy)
        self.r = math.atan2(vy, vx)
      else
        self.dead = true
        WallArrow{group = arena.effects, x = self.x, y = self.y,
                  r = math.atan2(vy, vx), color = self.color}
      end
      return
    end
  end

  -- Out of arena = die.
  if self.x < arena.x1 - 20 or self.x > arena.x2 + 20 or self.y < arena.y1 - 20 or self.y > arena.y2 + 20 then
    self.dead = true
  end
end


function Projectile:draw()
  if self.type == 'spellblade' then
    self:draw_spellblade_shard()
    return
  end
  if self.type == 'cannonball' then
    self:draw_cannonball()
    return
  end
  -- Fully burnt out: nothing left to draw (and a zero-size rectangle is not
  -- worth handing to the renderer).
  if self:despawn_factor() <= 0.02 then return end
  local r = self:get_angle() or 0
  graphics.push(self.x, self.y, r)
    -- One pair of factors drives both ends of the bolt's life: k grows it out
    -- of the muzzle, f shrinks and fades it away when it is spent. Length
    -- carries both, so the shot stretches out of the barrel and retracts as it
    -- burns out rather than popping in and out at full size.
    local ps = self.proj_scale
    local k  = self:spawn_k()
    local f  = self:despawn_factor()
    local wh = 1 - k                      -- white-hot for the instant it fires
    local c  = self.color
    local col = Color(c.r + (1 - c.r)*wh*0.85,
                      c.g + (1 - c.g)*wh*0.85,
                      c.b + (1 - c.b)*wh*0.85, f)
    local L  = (0.35 + 0.65*k)*f
    -- Muzzle flare, shrinking away as the bolt reaches full size.
    if wh > 0.02 then
      graphics.circle(self.x, self.y, (2 + 5*wh)*ps, Color(1, 0.92, 0.6, 0.5*wh))
    end
    if self.type == 'arrow' then
      graphics.rectangle(self.x, self.y, 8*ps*L, 2*ps*f, nil, nil, col)
      graphics.triangle(self.x + 4*ps*L, self.y, 3*ps*f, 3*ps*f, col)
    else
      graphics.rectangle(self.x, self.y, 6*L, 2*f, nil, nil, col)
    end
  graphics.pop()
end


-- Alpha a spellblade shard keeps once it is fully below the breach line. Far
-- lower than anything else that fades down there (see pit_fade_at in shared.lua):
-- the spellblade fires constantly and each shard drags a spiral trail behind it,
-- so a pack of them in the paddle's half is the single worst thing on screen for
-- reading incoming bullets. Left as a ghost rather than hidden outright, so the
-- player can still see where their shots went.
local SPELLBLADE_PIT_ALPHA = 0.06

-- The spellblade shard: a spinning arcane blade with a white-hot core and a
-- curved afterimage trail tracing its spiral path. Drawn in world space (the
-- trail samples are world positions) and spinning on its own angle (self.spin),
-- independent of the travel direction so the spiral reads clearly.
function Projectile:draw_spellblade_shard()
  local c = self.color
  -- Dissolve factor (1 -> 0 over the last fade_dur of life): scales every alpha
  -- and shrinks the blade so the shard melts away instead of popping out.
  local f = self.fade or 1
  -- Everything below runs through the breach-line fade. Restored on the single
  -- exit at the bottom of the function.
  local prev = graphics.alpha_mult
  -- Curved trail (newest first): fading dots along the spiral path. Each sample
  -- fades by its OWN y: a spiral straddling the line thins only on the half of
  -- the curl that is actually down in the paddle's half.
  for i, p in ipairs(self.btrail or {}) do
    local k = 1 - (i - 1)*0.15
    graphics.alpha_mult = prev*pit_fade_at(p.y, SPELLBLADE_PIT_ALPHA)
    graphics.circle(p.x, p.y, 2.4*k*f, Color(c.r, c.g, c.b, (0.5 - (i - 1)*0.075)*f))
  end
  graphics.alpha_mult = prev*pit_fade_at(self.y, SPELLBLADE_PIT_ALPHA)
  -- Soft glow.
  graphics.circle(self.x, self.y, 4.5*f, Color(c.r, c.g, c.b, 0.28*f))
  -- A 4-point blade: one long axis (the blade) and one short (the crossguard);
  -- both shrink toward the core as it dissolves.
  local bl = 6.5*(0.4 + 0.6*f)
  local cg = 3*(0.4 + 0.6*f)
  local a  = self.spin or 0
  local pa = a + math.pi/2
  graphics.line(self.x - math.cos(a)*bl, self.y - math.sin(a)*bl,
                self.x + math.cos(a)*bl, self.y + math.sin(a)*bl, Color(c.r, c.g, c.b, f), 2)
  graphics.line(self.x - math.cos(pa)*cg, self.y - math.sin(pa)*cg,
                self.x + math.cos(pa)*cg, self.y + math.sin(pa)*cg, Color(c.r, c.g, c.b, f), 1.5)
  -- White-hot core.
  graphics.circle(self.x, self.y, 2*f, Color(1, 1, 1, 0.9*f))
  graphics.alpha_mult = prev
end


-- Damage this projectile deals to `target`: a fraction of the target's MAX HP
-- when max_hp_frac is set and the target tracks one, otherwise the flat dmg.
-- (Brick and Boss both carry max_hp; EnemyCritter doesn't, so it takes flat dmg.)
--
-- The BOSS is the one exception. Percent-max-HP shots are budgeted against a
-- BRICK's pool; the boss carries two orders of magnitude more, so the same
-- fraction would delete it outright -- the archer's 100% bolt in a single hit.
-- Against the boss the shot pays its flat damage instead. (The engineer's turret
-- used to come through here too; its bolts are flat damage now.)
function Projectile:damage_to(target)
  if self.max_hp_frac > 0 and target.max_hp and not (Boss and target.is and target:is(Boss)) then
    return target.max_hp*self.max_hp_frac
  end
  return self.dmg
end


function Projectile:on_hit_brick(brick)
  -- Already burning out: out of the fight, but the body still lives (see
  -- begin_despawn), so the collision callback can still fire. Ignore it.
  if self.expiring then return end
  -- Cannonball: ignore the single target -- detonate into a splash that covers it.
  if self.type == 'cannonball' then self:cannon_explode(); return end
  if self.hits[brick.id] then return end
  self.hits[brick.id] = true
  brick:take_damage(self:damage_to(brick), self.color, nil, self.source or self.type)

  -- Assassin on-hit: the struck brick starts bleeding, and a crit sprays extra
  -- particles. bleed is the TOTAL over bleed_dur, so pass it through as dps.
  -- Guarded so it no-ops on enemy types that don't implement apply_bleed.
  if self.bleed > 0 and brick.apply_bleed then
    brick:apply_bleed(self.bleed/self.bleed_dur, self.bleed_dur, self.color)
  end
  if self.crit then
    spawn_burst(main.current.effects, self.x, self.y, self.color, 5, 70, 150)
  end

  if self.pierce > 0 then
    self.pierce = self.pierce - 1
    local arena = main.current
    if self.type == 'spellblade' then
      -- Light, quiet feedback -- the spellblade pierces constantly, so avoid
      -- particle/sound spam: one arcane spark, no per-hit chime.
      HitParticle{group = arena.effects, x = self.x, y = self.y, color = self.color}
      return
    end
    -- SNKRX pierce feedback: flash + particles + thunk on every target the
    -- projectile punches through, not just the one that stops it.
    spawn_burst(arena.effects, self.x, self.y, fg[0], 3, 50, 110)
    HitParticle{group = arena.effects, x = self.x, y = self.y, color = self.color}
    HitParticle{group = arena.effects, x = self.x, y = self.y, color = brick.color}
    hit2:play{pitch = random:float(0.95, 1.05), volume = 0.35}
    return
  end

  -- SNKRX scout chain: leap to a RANDOM brick within 48px that this knife
  -- hasn't hit yet, gaining +25% speed per hop (and +25% damage per hop when
  -- chain_dmg_ramp is set — the scout's level-3 passive). If nothing is in
  -- leap range the knife flies on and may still chain off whatever it meets.
  if self.chain > 0 then
    self.chain = self.chain - 1
    local arena = main.current
    spawn_burst(arena.effects, self.x, self.y, fg[0], 3, 50, 110)
    HitParticle{group = arena.effects, x = self.x, y = self.y, color = self.color}
    HitParticle{group = arena.effects, x = self.x, y = self.y, color = brick.color}
    -- SNKRX plays the impact sound on every chain hit, found target or not.
    hit2:play{pitch = random:float(0.95, 1.05), volume = 0.35}
    local candidates = {}
    for _, o in ipairs(arena.main.objects) do
      if o:is(Brick) and not o.dead and not self.hits[o.id]
      and math.distance(self.x, self.y, o.x, o.y) <= 48 then
        candidates[#candidates + 1] = o
      end
    end
    if #candidates > 0 then
      local target = candidates[random:int(1, #candidates)]
      self.speed = self.speed*BAL('globals.chain_hop_speed_mult', 1.25)
      if self.chain_dmg_ramp then self.dmg = self.dmg*BAL('globals.chain_hop_dmg_mult', 1.25) end
      local ang = math.atan2(target.y - self.y, target.x - self.x)
      self:set_velocity(math.cos(ang)*self.speed, math.sin(ang)*self.speed)
    end
    return
  end

  if self.ricochet > 0 then
    self.ricochet = self.ricochet - 1
    local arena = main.current
    local nearest = arena:get_nearest_brick(self.x, self.y, brick)
    if nearest then
      local ang = math.atan2(nearest.y - self.y, nearest.x - self.x)
      self:set_velocity(math.cos(ang)*self.speed, math.sin(ang)*self.speed)
    else
      self:begin_despawn()
    end
    return
  end

  self:begin_despawn()
end


-- Cannonball detonation (SNKRX cannoneer Projectile:die -> Area, player.lua:2208).
-- A wide flat-damage splash (do_splash deals the burst + ring + shake), a puff of
-- gunsmoke, and -- at level 3 -- a short bombardment of weaker aftershocks that
-- walk outward from the impact. dmg here is the full blast damage the caller baked
-- (current_dmg * blast_mult). Safe to call from on_hit_brick (a collision callback):
-- do_splash only flags bricks dead + spawns non-physics effects, never builds bodies.
function Projectile:cannon_explode()
  if self.exploded then return end
  self.exploded = true
  self.dead     = true
  local arena = main.current
  if not arena then return end
  local radius = self.blast_radius or 56
  local dmg    = self.dmg
  local col    = self.color
  local src    = self.source or self.type
  arena:do_splash(self.x, self.y, radius, dmg, col, src)
  explosion1:play{volume = 0.5, pitch = random:float(0.9, 1.0)}
  for _ = 1, 6 do
    SmokePuff{group = arena.effects, x = self.x + random:float(-radius*0.4, radius*0.4),
              y = self.y + random:float(-radius*0.4, radius*0.4),
              color = Color(0.30, 0.28, 0.26, 1), rs = random:float(3, 6), alpha = random:float(0.3, 0.5),
              vx = random:float(-22, 22), vy = random:float(-44, -10), duration = random:float(0.5, 0.9)}
  end
  -- Level-3 bombardment: a few weaker blasts march outward over the next ~0.9s.
  -- Driven off the ARENA timer (self.t dies with the projectile this frame).
  local n = self.bombard or 0
  if n > 0 then
    for i = 1, n do
      local bx = self.x + random:float(-44, 44)
      local by = self.y + random:float(-44, 44)
      arena.t:after(i*0.18, function()
        local a = main.current
        if not (a and a.world) then return end
        a:do_splash(bx, by, radius*BAL('effects.mortar_cluster_radius_mult', 0.7),
                    dmg*BAL('effects.mortar_cluster_dmg_mult', 0.5), col, src)
        explosion1:play{volume = 0.3, pitch = random:float(0.95, 1.1)}
      end)
    end
  end
end


-- Heavy iron shell: a dark sphere ringed with a hot rim, a metal highlight, and a
-- glowing fuse ember on top. The gunsmoke trail is shed in update.
function Projectile:draw_cannonball()
  local rs = 4.5
  local c  = self.color
  graphics.circle(self.x, self.y, rs + 1, bg[-2])
  graphics.circle(self.x, self.y, rs, Color(0.18, 0.17, 0.19, 1))            -- iron body
  graphics.circle(self.x, self.y, rs, Color(c.r, c.g, c.b, 0.5), 1)          -- hot rim
  graphics.circle(self.x - rs*0.35, self.y - rs*0.35, rs*0.35, fg[5])        -- highlight
  local e = 0.55 + 0.45*math.sin((self.cball_spin or 0)*3)                   -- fuse ember pulse
  graphics.circle(self.x + rs*0.3, self.y - rs*0.85, 1.5, Color(1, 0.7, 0.3, e))
end
