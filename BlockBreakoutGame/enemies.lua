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
  enemy_fx_sound(critter2, 0.25, random:float(0.95, 1.1))
  -- Orb only on a loadout that still runs the orb economy (BallPit:uses_xp_orbs).
  if arena.uses_xp_orbs and arena:uses_xp_orbs() then
    local x, y, v = self.x, self.y, self.xp_value
    arena.t:after(0, function()
      if arena.main and arena.main.world then
        XpOrb{group = arena.main, x = x, y = y, value = v}
      end
    end)
  end
  self.dead = true
end

-- Critters don't slow/burn but the brick-targeted ability helpers may call
-- these — provide no-op stubs to avoid crashes.
function EnemyCritter:apply_slow() end
function EnemyCritter:apply_burn() end


-- Fraction of a BRICK's max HP a parried (reflected) shot deals when it lands.
-- Percent-of-max-HP rather than the flat reflect_dmg so turning a bullet stays
-- decisive however far the wave has scaled brick HP -- the parry is a committed,
-- locked-out read and it should be worth the commitment. The BOSS is
-- deliberately excluded: it is not a "block", and 75% of a boss bar per parried
-- shot would end wave 10 in two. It keeps the flat reflect payload.
local PARRY_MAX_HP_FRAC = 0.75

-- How many enemies a turned (parried) shot punches through before it burns out.
-- A parry used to burst on the first thing it reached; skewering a line of them
-- is what makes reading the shield worth the locked-out commitment. Counted in
-- TARGETS directly (unlike Projectile.pierce, which counts pass-throughs), so
-- this number is the number of things the shot actually hits.
local PARRY_PIERCE_TARGETS = 5



-- Slow downward projectile fired by shooter bricks. Hits the paddle.
EnemyProjectile = Object:extend()
EnemyProjectile:implement(GameObject)
EnemyProjectile:implement(Physics)

function EnemyProjectile:init(args)
  self:init_game_object(args)
  -- Bumped from 2.5 → 3.5 so the projectile reads as a real threat, not a
  -- pickup. Hero balls can also intercept it more easily at this size.
  self.r_size = self.r_size or 3.5
  -- ONE colour for every enemy shot. Callers used to pass their own (the
  -- spreader's hue, the boss's phase tint, etc.) and the screen ended up with
  -- incoming fire in five palettes, several of which are also hero-ball or
  -- XP-gem colours. Red is now the single "this will hurt you" channel, and
  -- nothing friendly uses it: the ONLY thing that repaints a shot after this
  -- is EnemyProjectile:reflect, which turns a parried bullet gold precisely
  -- because it has stopped being an enemy shot. Cloned rather than aliased so
  -- a shot can never mutate the shared palette entry.
  self.color  = Color(red[0].r, red[0].g, red[0].b, 1)
  self.speed  = self.speed or 60
  self.dmg    = self.dmg or 1
  -- Firing direction in radians. Defaults to straight down (π/2) so existing
  -- callers (shooter brick) keep working without supplying an angle.
  self.angle        = self.angle or math.pi/2
  -- Optional homing: turns velocity vector toward the paddle at `homing_turn`
  -- rad/s. Used by arc-lobber variant and can be wired up by future enemies.
  -- Tracking is a WINDOW, not forever: the turn rate decays to zero across
  -- homing_time seconds (see update), so a dodged seeker overshoots and flies
  -- straight instead of circling back to re-acquire endlessly.
  self.homing       = self.homing or false
  self.homing_turn  = self.homing_turn or 1.0
  self.homing_time  = self.homing_time or 3.0
  self.homing_t     = 0
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
  -- Muzzle spawn-out: the shot swells from a hot point to full size as it
  -- clears the shooter, the mirror of the burn-out below, so a bullet grows out
  -- of an enemy instead of popping into existence in mid-air. Lengthened from
  -- 0.08s and started from a much smaller seed -- at 0.3 scale over 5 frames the
  -- growth was there but too slight to read as anything.
  self.spawn_dur = self.spawn_dur or 0.12
  self.spawn_t   = 0

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

  -- No self-destruct timer. Enemy fire is culled by GEOMETRY only -- it lives
  -- until it actually leaves the playfield (see the cull in update). A clock
  -- deleted shots in mid-flight over open arena, which reads as the game taking
  -- back a threat the player had already committed to dodging.
end

-- Burn-out. A shot that was spent -- shot down, or swept up by a blank -- used to
-- blink off in a single frame, which reads as a rendering glitch rather than
-- "that one is gone". It now leaves the FIGHT immediately
-- (update bails before every hit test below, so it cannot strike the paddle,
-- be parried, or damage a brick) while continuing to drift and draw for
-- despawn_dur, fading out under a ring that pushes off it.
--
-- The body is deliberately left active: enemy shots collide with nothing at
-- the Box2D level anyway (the paddle hit is a manual sweep in update), so a
-- burning-out shot coasting on its last heading is free and looks better than
-- one that freezes. Idempotent -- take_damage, the blank sweep and a stray caller
-- can all reach it. (Flying out of the playfield is NOT this: that path just
-- clears the shot, since there is nothing on screen left to animate.)
function EnemyProjectile:begin_despawn(dur)
  if self.expiring or self.dead then return end
  self.expiring    = true
  self.despawn_dur = dur or 0.22
  self.despawn_t   = self.despawn_dur
end


-- 0 -> 1 as the shot clears the muzzle, eased.
function EnemyProjectile:spawn_k()
  if (self.spawn_dur or 0) <= 0 then return 1 end
  local p = math.clamp((self.spawn_t or 0)/self.spawn_dur, 0, 1)
  return 1 - (1 - p)*(1 - p)*(1 - p)
end


-- 1 in normal flight, 1 -> 0 across the burn-out.
function EnemyProjectile:despawn_factor()
  if not (self.expiring and self.despawn_dur) then return 1 end
  return math.clamp(self.despawn_t/self.despawn_dur, 0, 1)
end


-- Turn this shot: the Aegis PERFECT PARRY payload, extracted so the TWO places
-- a braced shield can catch a bullet share it -- the paddle's own hit test in
-- update, and the dome's deploy sweep (Paddle:brace_shove). Before this the
-- sweep silently ATE parries: it threw shots clear of the paddle bar, which is
-- where the parry test lives, so bracing into incoming fire deflected the shot
-- without ever reflecting it. Returns false for anything a shield can't turn.
function EnemyProjectile:parry_by_shield()
  local arena = main.current
  if not arena then return false end
  if self.reflected or self.unbreakable or self.dead or self.expiring then return false end
  local sigt  = (arena.run_mods and arena.run_mods.sig) or {}
  -- A Greater dome doubles the return damage; each turned bullet banks bulwark
  -- toward the next Greater raise, and refunds a slug of combo points.
  local gmult = (arena.paddle and arena.paddle.greater and (sigt.greater_reflect_mult or 2)) or 1
  self:reflect((sigt.reflect_dmg or 60)*gmult)
  spawn_burst(arena.effects, self.x, self.y, self.color, 8, 90, 170)
  -- Parry cue: a metallic ting off the shield face, with the magical shimmer
  -- kept underneath and pulled back so the ting carries.
  mine1:play{volume = 0.35, pitch = random:float(1.50, 1.70)}
  buff1:play{volume = 0.22, pitch = random:float(1.25, 1.4)}
  if arena.add_combo_points then arena:add_combo_points(sigt.parry_combo or 25) end
  if arena.bulwark_add then arena:bulwark_add(sigt.bulwark_bullet or 1) end
  return true
end


-- Nearest enemy whose BODY a parried shot is actually touching. The shared
-- get_nearest_brick_within measures to a brick's CENTRE, which is wrong for the
-- return trip: a multi-cell brick's body sits at its shape centroid -- up to
-- ~22px inside a 3x3 -- so a returning shot could pass clean through one
-- without ever coming within the old 13.5px radius, and the parry would land
-- nothing. Box-tests the real footprint instead, and uses the boss's true outer
-- radius (r_outer) rather than an r_size it does not have.
function EnemyProjectile:reflected_target()
  local arena = main.current
  if not (arena and arena.main) then return nil end
  local r    = self.r_size
  local hits = self.hits or {}
  for _, o in ipairs(arena.main.objects) do
    if o.is and o:is(Brick) and not o.dead and not hits[o.id] then
      if math.abs(self.x - o.x) <= (o.w or 18)/2 + r
      and math.abs(self.y - o.y) <= (o.h or 10)/2 + r then return o end
    end
  end
  if arena.boss and not arena.boss.dead and not hits[arena.boss.id]
  and math.distance(self.x, self.y, arena.boss.x, arena.boss.y)
      < r + (arena.boss.r_outer or 14) then
    return arena.boss
  end
  return nil
end


-- The BLANK. A shot landing on the paddle sets off an Enter the Gungeon style
-- blank: a repulsion front sweeps out from the PADDLE across the whole arena,
-- clearing enemy fire as it passes (see BlankWave in effects.lua), and the enemy
-- ranks are locked out of firing for BLANK_LOCK seconds behind it -- otherwise
-- the same shooters simply refill the space the blank just made.
--
-- Bullet-hell fire arrives in CLUSTERS and the paddle is a 4px bar, so without
-- this one mistake routinely cost three or four hearts in a row before the
-- player could move. The blank turns one hit into one hit and hands back a clean
-- screen to recover on.
--
-- Radius is the arena's full WIDTH, taken from the paddle at the bottom, which
-- reaches all but the very top corners of the playfield -- so in practice it
-- clears the screen.
local BLANK_LOCK = 1.0

-- Margin above the arena's top edge before a shot counts as having flown past the
-- spawn line. Enemies enter a few px below y1, so a shot has to clear the whole
-- top of the playfield -- not merely be level with the front rank -- before it is
-- culled for leaving.
local SPAWN_CULL_PAD = 16

local function trigger_blank()
  local arena = main.current
  if not (arena and arena.paddle) then return end
  arena.fire_lock_t = math.max(arena.fire_lock_t or 0, BLANK_LOCK)
  BlankWave{group = arena.effects, x = arena.paddle.x, y = arena.paddle.y,
            radius = arena.x2 - arena.x1, color = blue[0]}
end


function EnemyProjectile:update(dt)
  self:update_game_object(dt)
  local arena = main.current
  if (self.spawn_t or 0) < (self.spawn_dur or 0) then
    self.spawn_t = (self.spawn_t or 0) + dt
  end

  -- Burning out: still drifting, still drawing, but out of the fight. Every
  -- branch below this point is fight logic, so bail here rather than adding a
  -- `not self.expiring` guard to each of them and hoping none is missed.
  if self.expiring then
    self.despawn_t = self.despawn_t - dt
    if self.despawn_t <= 0 then self.dead = true end
    self.spin_t = self.spin_t + self.spin_speed*dt
    return
  end

  -- Homing: smoothly rotate velocity toward the target. Capped turn rate so
  -- the player can still dodge by moving — these aren't perfect trackers —
  -- and the tracking STRENGTH fades to zero over homing_time, so late in its
  -- flight the shot commits to a straight line instead of endlessly curving
  -- back onto the paddle. A REFLECTED (parried) shot hunts the other way:
  -- its target is the nearest brick, or the boss when no bricks are up.
  local home_x, home_y
  if self.reflected then
    local ht = arena and arena:get_nearest_brick(self.x, self.y)
    if not ht and arena and arena.boss and not arena.boss.dead then ht = arena.boss end
    if ht then home_x, home_y = ht.x, ht.y end
  elseif arena and arena.paddle then
    home_x, home_y = arena.paddle.x, arena.paddle.y
  end
  if self.homing and home_x then
    self.homing_t = (self.homing_t or 0) + dt
    local strength = 1 - math.clamp(self.homing_t/(self.homing_time or 3.0), 0, 1)
    if strength > 0 then
      local vx, vy = self:get_velocity()
      local cur    = math.atan2(vy, vx)
      local want   = math.atan2(home_y - self.y, home_x - self.x)
      -- Wrap diff to [-π, π] so we always turn the short way around the circle.
      local diff   = math.loop(want - cur, 2*math.pi)
      if diff > math.pi then diff = diff - 2*math.pi end
      local turn   = self.homing_turn*strength
      local step   = math.clamp(diff, -turn*dt, turn*dt)
      local new_a  = cur + step
      self:set_velocity(math.cos(new_a)*self.speed, math.sin(new_a)*self.speed)
    end
  end

  -- Cull. A shot dies when it FLIES OUT, never on a clock: up past the spawn line
  -- at the top of the arena (where the swarms and the boss enter -- there is
  -- nothing above it left to hit), or out of sight on any other edge. Enemy fire
  -- is filtered out of colliding with the arena walls (see the fixture mask in
  -- init), so a shot that reaches a side or the bottom flies straight THROUGH and
  -- keeps going until it is genuinely gone -- see off_screen in shared.lua for
  -- why the canvas, not the arena, is the line there.
  local spawn_y = ((arena and arena.y1) or 0) - SPAWN_CULL_PAD
  if self.y + self.r_size < spawn_y or off_screen(self.x, self.y, self.r_size) then
    self.dead = true
  end
  -- Paddle hit. Swept vertical test over the segment the bullet travelled this
  -- frame, instead of the old "anywhere below paddle.y - 4" column — that acted
  -- like an infinitely tall hitbox under the paddle, so lifting the paddle in
  -- its dodge band let bullets far below it still score hits. Sweeping also
  -- stops fast shots tunnelling through the thin (4px) bar between frames.
  local _, p_vy  = self:get_velocity()
  local p_prev_y = self.y - p_vy*dt
  local p_ylo    = math.min(p_prev_y, self.y) - self.r_size
  local p_yhi    = math.max(p_prev_y, self.y) + self.r_size
  -- Phased (the wide powerup): the paddle is INTANGIBLE to enemy fire. The
  -- whole hit test is skipped, so a shot flies straight THROUGH and carries on
  -- instead of striking a paddle that merely happens to take no damage.
  if  not self.reflected and not arena.paddle.phased
  -- CORE only: the paddle is wider than its hurtbox now, and the ghosted wings
  -- let a shot pass straight through (Paddle:core_hit). Tested against what is
  -- actually drawn solid, so the transparency is not decorative. The Pinball rig
  -- answers with two circles at the bat ends rather than one centred band, which
  -- is why this asks the paddle instead of measuring the span itself.
  and arena.paddle:core_hit(self.x, self.r_size)
  and p_yhi >= arena.paddle.y - arena.paddle.h/2
  and p_ylo <= arena.paddle.y + arena.paddle.h/2 then
    local sig    = arena.run_mods and arena.run_mods.signature
    local braced = sig == 'aegis' and arena.paddle and (arena.paddle.brace_t or 0) > 0
    if braced and not self.unbreakable then
      -- Aegis PERFECT PARRY: only a BRACED shield turns a shot (see
      -- Paddle:start_brace). An unbraced Aegis paddle eats bullets like any
      -- other loadout (below); unbreakable boss bullets punch through, so the
      -- boss stays honest. Shared with the dome's deploy sweep -- see
      -- EnemyProjectile:parry_by_shield.
      self:parry_by_shield()
    else
      -- Hit the paddle directly. Routed through damage_player so the
      -- Vampire bar takes the equivalent of self.dmg hearts.
      arena:damage_player(self.dmg)
      hit2:play{volume = 0.4, pitch = random:float(1.0, 1.1)}
      enemy_shake(2, 0.15, 90)
      -- Blank: sweep the screen and lock the ranks out (see trigger_blank).
      trigger_blank()
      Flash{group = arena.effects, x = gw/2, y = gh/2, color = red_transparent_weak, duration = 0.08}
      if arena.player_hp <= 0 then arena:trigger_game_over() end
      self.dead = true
    end
  end

  -- GREATER AEGIS dome: while it's up, hero balls THEMSELVES turn bullets —
  -- any breakable shot that touches a ball is reflected at the dome's
  -- doubled damage. Proximity test (bullets phase through balls at the
  -- Box2D level by design, so there's no contact callback to hook).
  local gpad = arena.paddle
  if gpad and gpad.greater and (gpad.brace_t or 0) > 0
  and not self.reflected and not self.unbreakable and not self.dead then
    for _, hball in ipairs(arena.heroes or {}) do
      if hball and not hball.dead and not hball.stuck
      and math.distance(self.x, self.y, hball.x, hball.y) < (hball.r_size or 6) + self.r_size + 2 then
        local sigt = arena.run_mods.sig or {}
        self:reflect((sigt.reflect_dmg or 60)*(sigt.greater_reflect_mult or 2))
        spawn_burst(arena.effects, self.x, self.y, self.color, 6, 80, 150)
        mine1:play{volume = 0.22, pitch = random:float(1.55, 1.75)}
        buff1:play{volume = 0.16, pitch = random:float(1.3, 1.45)}
        break
      end
    end
  end

  -- Reflected (parried) bullet: it fights for the player now — it SKEWERS up to
  -- PARRY_PIERCE_TARGETS enemies, spending one charge each, and burns out when
  -- they run out. Manual proximity test because enemy shots never collide with
  -- bricks at the Box2D level (they'd die at the muzzle otherwise). Falls back
  -- to the boss so a parry still lands something during the fight's
  -- breakable-bullet phases.
  if self.reflected and not self.dead then
    local hit = self:reflected_target()
    if hit then
      -- 75% of the brick's MAX HP (see PARRY_MAX_HP_FRAC). The boss is not a
      -- block, so it keeps the flat reflect payload.
      local pdmg = (hit.is and hit:is(Brick) and hit.max_hp)
                   and hit.max_hp*PARRY_MAX_HP_FRAC or self.dmg
      if hit.id then self.hits[hit.id] = true end
      hit:take_damage(pdmg, self.color)
      -- Spend a charge. The LAST hit gets the full burst + pop; the
      -- pass-throughs are deliberately lighter, because five shots' worth of
      -- full-strength feedback in half a second is a mess.
      self.pierce_left = (self.pierce_left or 1) - 1
      local spent = self.pierce_left <= 0
      spawn_burst(arena.effects, self.x, self.y, self.color, spent and 8 or 5, 80, 160)
      pop1:play{volume = spent and 0.3 or 0.18, pitch = random:float(1.2, 1.35)}
      if spent then self:begin_despawn(0.12) end
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

-- Aegis PERFECT PARRY (the braced branch in update): flip THIS bullet to the
-- player's side — molten gold, faster, and hunting the nearest brick (boss
-- fallback). update branches on self.reflected for the homing target, the
-- skipped paddle test and the brick-contact burst; the shape keeps drawing
-- itself, just in gold, so the returned shot stays recognizable instead of
-- shrinking into a stand-in pellet.
function EnemyProjectile:reflect(dmg)
  self.reflected   = true
  self.color       = Color(1, 0.84, 0.25, 1)
  self.dmg         = dmg or 60
  -- A turned shot SKEWERS (see PARRY_PIERCE_TARGETS). `hits` stops it spending
  -- a charge twice on the same enemy across the several frames it spends
  -- overlapping one -- without it a single fat brick would eat the whole shot.
  self.pierce_left = PARRY_PIERCE_TARGETS
  self.hits        = {}
  self.speed       = math.max((self.speed or 60)*1.5, 300)
  -- Fresh, harder tracking window than any enemy seeker gets: the return
  -- trip is a reward, it should feel like it wants to land.
  self.homing      = true
  self.homing_turn = 5.0
  self.homing_time = 2.5
  self.homing_t    = 0
  local arena = main.current
  local t = arena and arena:get_nearest_brick(self.x, self.y)
  if not t and arena and arena.boss and not arena.boss.dead then t = arena.boss end
  local a = t and math.atan2(t.y - self.y, t.x - self.x) or -math.pi/2
  self:set_velocity(math.cos(a)*self.speed, math.sin(a)*self.speed)
  self.hfx:use('hit', 0.2, 200, 10)
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


-- Shared glow, drawn UNDER every shot shape. Now that all enemy fire is one
-- red, the shape alone is what separates a bullet from a hero ball or an XP
-- gem -- and at 3.5px, in a busy field, shape is not enough. Two cheap layers
-- fix it:
--
--   * a red BLOOM, three soft rings breathing on the shot's own spin clock.
--     Neither a hero ball nor an XP orb glows, so a halo means "incoming"
--     before the player has parsed the shape at all.
--   * a dark BACKING disc right under the body, which punches the bullet out
--     of the (near-black) grid so the silhouette stays crisp instead of the
--     bloom washing into it.
--
-- Alphas are deliberately low: a bullet-hell screen is dozens of these at
-- once, and they have to add up to legible, not to a red fog.
function EnemyProjectile:draw_glow()
  local c = self.color
  local p = 0.85 + 0.15*math.sin((time or 0)*7 + (self.spin_t or 0))
  local r = self.r_size
  graphics.circle(self.x, self.y, r*2.9*p, Color(c.r, c.g, c.b, 0.05))
  graphics.circle(self.x, self.y, r*2.0*p, Color(c.r, c.g, c.b, 0.10))
  graphics.circle(self.x, self.y, r*1.35,  Color(c.r, c.g, c.b, 0.18))
  graphics.circle(self.x, self.y, r + 0.8, Color(bg[-2].r, bg[-2].g, bg[-2].b, 0.85))
end


-- Per-shape draw dispatch. Every shape sits on the shared glow above; the
-- shapes themselves still differ so attack patterns stay tellable apart.
function EnemyProjectile:draw()
  -- One multiplier fades the shape, its glow AND its sampled trail together.
  -- The trail builds its own per-sample alphas, so it cannot be faded by
  -- passing a colour in -- see graphics.alpha_mult.
  local f = self:despawn_factor()
  if f < 1 then graphics.alpha_mult = f end
  -- Muzzle spawn-out, scaled about the shot's own position so every shape, the
  -- glow and the armour layer below all come along for free rather than each
  -- needing its own factor threaded through.
  local sk     = self:spawn_k()
  local scaled = sk < 1
  if scaled then
    local ss = 0.12 + 0.88*sk
    graphics.push(self.x, self.y, 0, ss, ss)
  end

  self:draw_glow()
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
  -- A reflected (parried) shot wears a thin gilded halo so the gold reads as
  -- "ours now" even on shapes with busy bodies.
  if self.reflected then
    graphics.circle(self.x, self.y, self.r_size + 1.5, Color(1, 0.90, 0.50, 0.4), 1)
  end
  -- Release the muzzle scale before the flare and the burn-out ring, both of
  -- which are full-size effects and must not be shrunk with the body.
  if scaled then graphics.pop() end

  -- Muzzle flare: a hot bloom that collapses as the shot reaches full size. The
  -- scale alone is legible only if you are already looking at that spot; the
  -- flare is what makes a shot being FIRED catch the eye across the arena.
  if sk < 1 then
    local wh = 1 - sk
    graphics.circle(self.x, self.y, self.r_size*(1 + 2.6*wh), Color(1, 0.72, 0.45, 0.40*wh))
    graphics.circle(self.x, self.y, self.r_size*(0.5 + 1.1*wh), Color(1, 0.95, 0.85, 0.55*wh))
  end

  -- Burn-out ring: pushes outward off the shot as it fades, so the shot reads
  -- as dissipating rather than simply getting dimmer. Drawn at full strength
  -- (its own alpha already carries the fade) after the multiplier is released.
  if f < 1 then
    graphics.alpha_mult = 1
    local c = self.color
    graphics.circle(self.x, self.y, self.r_size*(1 + 2.4*(1 - f)),
                    Color(c.r, c.g, c.b, 0.4*f), 1)
  end
end


-- 'spike' (shooter, default): 4-pointed spike + halo + trail. This branch used
-- to hardcode red[0] because it was the only shot guaranteed to read as danger;
-- every shot is red now (see init), so it just uses self.color like the others
-- -- which is also what keeps a parried spike gold.
function EnemyProjectile:draw_spike()
  local base = self.color
  self:draw_trail(base)

  local pulse = 1 + math.sin((time or 0)*9)*0.18
  graphics.circle(self.x, self.y, (self.r_size + 2)*pulse,
                  Color(base.r, base.g, base.b, 0.22))

  local s   = self.hfx.hit.x or 1
  local col = self.hfx.hit.f and fg[0] or base
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
  if self.expiring then return end          -- already burning out; don't re-burst
  self.hfx:use('hit', 0.25, 200, 10)
  spawn_burst(main.current.effects, self.x, self.y, color or self.color, 3, 40, 80)
  -- Shot down: the burst is the impact, the burn-out is the shot leaving. It
  -- used to be deleted on this frame, which is the case the player sees most
  -- often -- balls knock these out constantly -- so it is the one that most
  -- needed a way out. Quicker than a timeout: this one was killed, not spent.
  self:begin_despawn(0.14)
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
  -- Seeking maggots (Hive) steer at the nearest brick instead of flying the
  -- fixed launch heading; see AllyCritter:steer. The infestor's pets leave
  -- this off and keep their original straight drift.
  self.turn_rate = self.turn_rate or 3.0     -- radians/sec of steering authority
  self.wig_t     = random:float(0, 2*math.pi)
  self.wig_f     = random:float(7, 10)       -- grub crawl, so it isn't a missile

  self:set_as_circle(self.r_size, 'dynamic', 'projectile')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(0.4)
  self:set_friction(0)
  self:set_damping(0)
  self:set_mass(0.2)

  local angle = -math.pi/2 + random:float(-0.6, 0.6)
  self.head = angle          -- own heading, turned by :steer (wiggle is cosmetic)
  self:set_velocity(math.cos(angle)*self.speed, math.sin(angle)*self.speed)
  self.hfx:add('hit', 1)

  self.on_collision_enter = function(s, other, contact)
    if not other then return end
    if other.tag == 'brick' then s:on_brick_contact(other) end
  end

  self.t:after(self.lifetime, function() self.dead = true end)
end

-- Nearest live enemy worth biting, re-picked when the current one dies. The
-- boss counts: it is tagged 'brick', so a maggot that reaches it lands a bite
-- through on_brick_contact like anything else.
function AllyCritter:retarget()
  local arena = main.current
  if not (arena and arena.main) then return end
  local best, bd = nil, 1e9
  for _, o in ipairs(arena.main.objects) do
    if not o.dead and o.is and (o:is(Brick) or o:is(Boss)) then
      local d = math.distance(self.x, self.y, o.x, o.y)
      if d < bd then bd = d; best = o end
    end
  end
  self.target = best
end


-- Turn toward the target at a limited rate -- NOT the Locust's hard per-frame
-- heading set -- and lay a shallow sine over the result, so the maggot reads as
-- something crawling through the air rather than a guided missile.
function AllyCritter:steer(dt)
  if not self.target or self.target.dead then self:retarget() end
  local tgt = self.target
  if not tgt then return end
  local want = math.atan2(tgt.y - self.y, tgt.x - self.x)
  local d    = (want - self.head + math.pi)%(2*math.pi) - math.pi   -- shortest turn
  local lim  = self.turn_rate*dt
  self.head  = self.head + math.clamp(d, -lim, lim)
  self.wig_t = self.wig_t + dt*self.wig_f
  local a = self.head + math.sin(self.wig_t)*0.25
  self:set_velocity(math.cos(a)*self.speed, math.sin(a)*self.speed)
end


function AllyCritter:update(dt)
  self:update_game_object(dt)
  local arena = main.current
  -- Hive maggots home. Straight-line flight is fine for the infestor's pets,
  -- which are dropped in the middle of the field right beside their target,
  -- but the Hive paddle also vents a maggot on every PADDLE bounce -- down at
  -- y~618, with the swarm entering at y~18. At the old 85px/s x 4s that is
  -- 340px of travel: it expired around mid-arena and the paddle-spawned half
  -- of the signature never landed a bite. Steering plus the longer fuse
  -- (sig.maggot_life) is what makes those arrive.
  if self.seek then self:steer(dt) end
  if arena and (self.y < arena.y1 - 8 or self.y > arena.y2 + 8) then self.dead = true end
end

function AllyCritter:draw()
  graphics.circle(self.x, self.y, self.r_size + 0.5, bg[-2])
  graphics.circle(self.x, self.y, self.r_size, self.color)
  graphics.circle(self.x - self.r_size*0.3, self.y - self.r_size*0.3, math.max(0.6, self.r_size*0.3), fg[5])
end

function AllyCritter:on_brick_contact(brick)
  if brick.dead then return end
  -- Hive (Infestation Contagion): the maggot SEEDS a self-spreading rot instead
  -- of a flat bite — the plague is the damage. The rot eats this brick and
  -- creeps to its neighbours (see Brick:apply_infest / infest_spread).
  if self.infest and brick.apply_infest then
    brick:apply_infest(1)   -- full potency; rot is necrotic green, not the bug's hue
    spawn_burst(main.current.effects, self.x, self.y, Color(0.30, 0.42, 0.08, 0.9), 5, 50, 110)
    self.dead = true
    return
  end
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


-- Motion-trail tuning. The boss samples its own position every TRAIL_SAMPLE
-- seconds (see Boss:update), keeping TRAIL_LEN_MAX of them. The ribbon is drawn
-- from every sample it walks; the body aftershadows from every
-- TRAIL_GHOST_STRIDE-th one.
--
-- Length is PER PHASE. The buffer always holds the phase-3 maximum and the draw
-- walks only as far into it as the current phase earns, so both the ribbon and
-- the ghosts lengthen at every transition -- and because the stride is fixed,
-- the ghost COUNT grows with them (4 -> 6 -> 7). Escalation is then legible in
-- how the boss MOVES, not only in the phase colour shift, which matters most in
-- phase 3 where it is also moving 1.6x faster.
--
-- TRAIL_FULL_SPEED is the speed (px/s) at which the trail reaches full strength
-- -- below it the whole effect fades out proportionally, so a boss easing
-- through the slow part of a curve doesn't sit in a static smear.
local TRAIL_SAMPLE       = 0.02
local TRAIL_LEN_BY_PHASE = {22, 30, 38}
local TRAIL_LEN_MAX      = 38
local TRAIL_GHOST_STRIDE = 5
local TRAIL_FULL_SPEED   = 150


function Boss:init(args)
  self:init_game_object(args)
  self.r_outer = 28
  self.r_inner = 14

  -- HP scales with wave the same way bricks do (see Brick:init line 81) so
  -- the fight stays meaningful if the player triggers it on a later loop.
  local wave = (main.current and main.current.wave) or 10
  -- Base pool cut again, -33% (3200 -> 2400 -> 1800 -> 1206): the fight was
  -- running long once the bumpers started feeding balls back at it, and a boss
  -- that outlasts the player's attention is a worse boss than one that dies a
  -- little early.
  self.max_hp     = 1206 * (1 + 0.2*wave)
  self.hp         = self.max_hp
  self.player_dmg = 3
  self.xp_value   = 60

  self.phase      = 1
  self.color      = BOSS_PHASE_COLORS[1]()
  self.outer_rot  = 0
  self.inner_rot  = 0
  self.spawn_t    = 0
  self.intro_done = false

  -- Motion trail + aftershadow state. path_trail is a short position history
  -- (newest first) holding both rotations, so an echo of the body can be redrawn
  -- exactly as it looked at that instant. trail_k tracks how fast the boss is
  -- actually moving and scales the whole effect, so the smear only appears when
  -- there is real motion to smear (see Boss:update / Boss:draw_trail).
  self.path_trail = {}
  self.trail_t    = 0
  self.trail_k    = 0
  self.prev_x     = self.x
  self.prev_y     = self.y

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
-- the boss's live position and — crucially — flagged unbreakable. Returns the
-- projectile (or nil), and no-ops safely when called from a deferred timer
-- after the world is gone / the boss has died.
--
-- No colour is passed: every enemy shot is red now (EnemyProjectile:init), so
-- the boss's phase tint stays on the boss BODY, which is where it was always
-- most readable -- its bullets no longer carry it.
function Boss:fire(opts)
  local arena = main.current
  if not (arena and arena.main and arena.main.world and not self.dead) then return end
  opts.group = arena.main
  if opts.x == nil then opts.x = self.x end
  if opts.y == nil then opts.y = self.y end
  if opts.unbreakable == nil then opts.unbreakable = true end
  -- No `life` on boss bullets (or any other enemy shot): they are culled when
  -- they leave the playfield, which is what the floor this used to clamp was
  -- approximating anyway -- the slow orbs never reached it before flying out.
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
  enemy_shot_sound(0.3, 0.85)
  local base = random:float(0, 2*math.pi)
  local dir  = random:bool(50) and 1 or -1
  for i = 0, 15 do
    self.t:after(i*0.1, function()
      -- Boss spiral: slow, matches the spiraler enemy's bullet tempo so both
      -- attack types read as "swirling, lingering" threats.
      self:fire{kind = 'boss_orb', angle = base + dir*i*0.42, speed = 55, r_size = 3.2}
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
  enemy_shot_sound(0.32, 0.78)
  local base = random:float(0, 2*math.pi)
  for i = 0, 17 do
    self.t:after(i*0.08, function()
      self:fire{kind = 'boss_orb', angle = base + i*0.34,           speed = 52, r_size = 3}
      self:fire{kind = 'boss_orb', angle = base + math.pi - i*0.34, speed = 52, r_size = 3}
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
  enemy_shot_sound(0.3, 1.0)
  local base = random:float(0, 2*math.pi)
  local dir  = random:bool(50) and 1 or -1
  for i = 0, 13 do
    self.t:after(i*0.085, function()
      for arm = 0, arms - 1 do
        local a = base + dir*i*0.30 + arm*(2*math.pi/arms)
        self:fire{kind = 'star', angle = a, speed = 58, r_size = 3}
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
    enemy_shot_sound(0.32, 0.95)
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
      enemy_shot_sound(0.3, 1.15)
      local a = math.atan2(arena.paddle.y - self.y, arena.paddle.x - self.x)
      self:fire{kind = 'dart', angle = a, speed = 150, dmg = 2, r_size = 3.4}
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
    enemy_shot_sound(0.4, 0.8)
    enemy_fx_sound(explosion1, 0.25, 1.3)
    Flash{group = arena.effects, x = gw/2, y = gh/2,
          color = Color(self.color.r, self.color.g, self.color.b, 0.25), duration = 0.1}
    for i = 0, 17 do
      local a = i*(2*math.pi/18)
      -- Medium speed so players can slip between adjacent shots.
      self:fire{kind = 'boss_orb', angle = a, speed = 80}
      if self.phase >= 3 then
        self:fire{kind = 'boss_orb', angle = a + math.pi/18, speed = 55}
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
    enemy_shot_sound(0.4, 0.7)
    for i = 0, n - 1 do
      if not is_gap(i) then
        local px = math.lerp(i/(n - 1), x1, x2)
        self:fire{x = px, y = y0, kind = 'diamond', angle = math.pi/2, speed = 64}
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
    enemy_shot_sound(0.3, 0.9)
    for _, off in ipairs({-0.5, 0, 0.5}) do
      self:fire{kind = 'comet', angle = math.pi/2 + off, speed = 60, r_size = 3.4,
                homing = true, homing_turn = 0.55}
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

  -- ---- Motion trail ------------------------------------------------------
  -- Measured speed (not the target's) drives the trail's strength, smoothed so
  -- the per-frame ease jitter can't make it flicker. Sampling runs on its own
  -- fixed clock rather than per frame, so the ribbon's spacing is a function of
  -- how far the boss travelled, not of the frame rate.
  local moved = math.distance(self.prev_x, self.prev_y, self.x, self.y)
  local sp    = (dt > 0) and (moved/dt) or 0
  self.prev_x, self.prev_y = self.x, self.y
  local want_k = math.clamp(sp/TRAIL_FULL_SPEED, 0, 1)
  self.trail_k = self.trail_k + (want_k - self.trail_k)*math.min(1, dt*6)

  self.trail_t = self.trail_t + dt
  if self.trail_t >= TRAIL_SAMPLE then
    self.trail_t = 0
    table.insert(self.path_trail, 1,
                 {x = self.x, y = self.y, o = self.outer_rot, i = self.inner_rot})
    if #self.path_trail > TRAIL_LEN_MAX then table.remove(self.path_trail) end
  end
end


function Boss:on_ball_contact(ball)
  -- Hero ball collided with the boss. Match the Brick contact flow but skip
  -- the formation knockback path (boss is solo).
  if self.hp <= 0 then return end
  -- A bumper's lock-on is spent the moment it lands (see BallHero:steer_boss_lock).
  -- Cleared before the damage guard below so a ball that connects always drops
  -- it, even on the frame the boss dies.
  ball.boss_lock = false
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


-- Boss payout. Held back until the destruction has played out (see BossDeath),
-- so the drafts don't open over the explosion. The three paddle levels arrive
-- as three drafts in sequence: BallPit:level_up queues them through
-- pending_levelups, so calling it three times in a row is safe. The ball levels
-- go through apply_level_random, which caps itself at however many balls can
-- still take one, so it never promises more than it delivers.
local BOSS_PADDLE_LEVELS = 3
local BOSS_BALL_LEVELS   = 5
local BOSS_REWARD_DELAY  = 1.1


function Boss:die()
  local arena = main.current
  -- Tell the arena XP/score systems we died, same hook as bricks use.
  arena:on_brick_killed(self)

  -- Destruction: a staged implode -> detonate -> embers sequence that takes over
  -- the core's own silhouette (BossDeath, effects.lua), carrying its own layered
  -- sound stack. Replaces the single burst + white screen flash this used to be.
  BossDeath{group = arena.effects, x = self.x, y = self.y, color = self.color,
            r_outer = self.r_outer, r_inner = self.r_inner}

  -- The payout (see BOSS_PADDLE_LEVELS above).
  arena.t:after(BOSS_REWARD_DELAY, function()
    if not (arena.main and arena.main.world) then return end
    if arena.apply_level_random then arena:apply_level_random(BOSS_BALL_LEVELS) end
    for _ = 1, BOSS_PADDLE_LEVELS do arena:level_up() end
  end)

  -- Big XP drop, on the loadouts that still collect XP (BallPit:uses_xp_orbs).
  -- The real payout is the levels granted above, which every loadout gets.
  if arena.uses_xp_orbs and arena:uses_xp_orbs() then
    local x, y, v = self.x, self.y, self.xp_value
    arena.t:after(0, function()
      if arena.main and arena.main.world then
        XpOrb{group = arena.main, x = x, y = y, value = v}
      end
    end)
  end

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


-- Motion trail + aftershadow, drawn UNDER the body from the position history
-- update samples. Two layers off the one buffer:
--   * the ribbon -- a soft core-colored disc at every sample, tapering in radius
--     and alpha toward the tail, so the curve the boss is tracing reads as a
--     streak instead of a jump between frames;
--   * the aftershadow -- every TRAIL_GHOST_STRIDE-th sample also re-draws the
--     12-gon ring and inner hexagon as dim outlines at THAT frame's rotations,
--     so the shape itself echoes behind the boss rather than just a blur.
-- Both are scaled by trail_k, so a slow boss barely smudges and a phase-3 boss
-- (1.6x movement) drags a full comet. Deliberately uses self.color rather than
-- the hit-flash color, so the trail doesn't strobe white on every ball contact.
function Boss:draw_trail()
  local k = self.trail_k or 0
  if k <= 0.02 then return end
  local col = self.color
  -- Phase length (see TRAIL_LEN_BY_PHASE): the buffer holds the phase-3
  -- maximum, but the draw only walks as far back as this phase has earned.
  -- Deriving `fade` from this n rather than the buffer size is what keeps the
  -- taper landing on zero at the tail at every length.
  local want = TRAIL_LEN_BY_PHASE[math.clamp(self.phase or 1, 1, #TRAIL_LEN_BY_PHASE)]
  local n    = math.min(#self.path_trail, want or TRAIL_LEN_MAX)
  for i = 1, n do
    local p    = self.path_trail[i]
    local fade = 1 - (i - 1)/n            -- 1 at the head, ~0 at the tail

    -- Ribbon: a soft disc shrinking toward the tail.
    graphics.circle(p.x, p.y, self.r_inner*0.55*fade,
                    Color(col.r, col.g, col.b, 0.22*fade*fade*k))

    -- Aftershadow: a dim echo of the whole body every few samples. Skipped at
    -- i == 1, which sits under the real body and would only thicken its outline.
    if i > 1 and i % TRAIL_GHOST_STRIDE == 0 then
      local ga = 0.24*fade*k
      local gs = 0.72 + 0.28*fade        -- older echoes shrink as they dissipate
      local vo = {}
      for j = 0, 11 do
        local a = p.o + j*(2*math.pi/12)
        vo[#vo+1] = p.x + math.cos(a)*self.r_outer*gs
        vo[#vo+1] = p.y + math.sin(a)*self.r_outer*gs
      end
      graphics.polygon(vo, Color(col.r, col.g, col.b, ga), 1)
      local vi = {}
      for j = 0, 5 do
        local a = p.i + j*(2*math.pi/6)
        vi[#vi+1] = p.x + math.cos(a)*self.r_inner*gs
        vi[#vi+1] = p.y + math.sin(a)*self.r_inner*gs
      end
      graphics.polygon(vi, Color(col.r, col.g, col.b, ga*0.7), 1)
    end
  end
end


function Boss:draw()
  local s    = self.hfx.hit.x or 1
  local col  = self.hfx.hit.f and fg[0] or self.color
  local dark = Color(col.r*0.45, col.g*0.45, col.b*0.45, 1)

  -- Trail + aftershadow first, so every echo sits behind the solid body.
  self:draw_trail()

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

  -- (The HP readout lives in the HUD strip now -- BallPit:draw_boss_bar paints
  -- the core as a prismatic crystal that shatters. Nothing to draw here.)

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
