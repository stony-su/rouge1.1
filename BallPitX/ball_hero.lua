-- BallHero is the SNKRX-style hero remixed as a bouncing ball.
-- 12 heroes attack continuously on cooldown (SNKRX-style: trigger inside an
-- attack-sensor radius), while 4 exceptions (wizard, cryomancer, pyromancer,
-- cannoneer) keep on-bounce abilities. Contact damage on bounce applies to all.

BallHero = Object:extend()
BallHero:implement(GameObject)
BallHero:implement(Physics)


-- Per-character stats. r/base_speed/dmg/color are ball properties; the rest
-- depend on `behavior`, which keys into the BEHAVIORS dispatch table below.
-- Stats are adapted from SNKRX-master/player.lua: range mirrors that hero's
-- attack_sensor radius, cd mirrors their trigger:cooldown delay, etc.
-- Projectile heroes get an additional +250%/+300% (dmg/rate) buff inside
-- the shoot helpers; here we just store the base cd.
local HERO_STATS = {
  -- ----- Projectile shooters (behavior = 'shoot_arrow') -----
  vagrant     = {r = 6, base_speed = 160, dmg = 8,  color = 'fg',     behavior = 'shoot_arrow', range = 96,  cd = 0.5,  speed = 220},
  archer      = {r = 5, base_speed = 175, dmg = 10, color = 'green',  behavior = 'shoot_arrow', range = 160, cd = 0.5,  speed = 260, pierce = 4},
  outlaw      = {r = 5, base_speed = 175, dmg = 10, color = 'red',    behavior = 'shoot_arrow', range = 96,  cd = 0.75, speed = 240},
  sage        = {r = 6, base_speed = 155, dmg = 8,  color = 'purple', behavior = 'shoot_arrow', range = 96,  cd = 2.25, speed = 200},
  blade       = {r = 6, base_speed = 165, dmg = 12, color = 'yellow', behavior = 'shoot_arrow', range = 64,  cd = 1.0,  speed = 200},
  dual_gunner = {r = 6, base_speed = 165, dmg = 9,  color = 'green',  behavior = 'shoot_arrow', range = 96,  cd = 0.5,  speed = 220},
  hunter      = {r = 5, base_speed = 175, dmg = 11, color = 'green',  behavior = 'shoot_arrow', range = 160, cd = 0.5,  speed = 260},
  lich        = {r = 6, base_speed = 155, dmg = 9,  color = 'blue',   behavior = 'shoot_arrow', range = 128, cd = 1.0,  speed = 140, ricochet = 7},
  corruptor   = {r = 6, base_speed = 165, dmg = 10, color = 'orange', behavior = 'shoot_arrow', range = 160, cd = 0.5,  speed = 240, pierce = 3},
  beastmaster = {r = 6, base_speed = 170, dmg = 10, color = 'red',    behavior = 'shoot_arrow', range = 160, cd = 0.5,  speed = 240, crit_chance = 25, pierce = 2},
  arcanist    = {r = 7, base_speed = 145, dmg = 22, color = 'blue2',  behavior = 'shoot_arrow', range = 128, cd = 2.0,  speed = 80,  pierce = 10},
  merchant    = {r = 6, base_speed = 160, dmg = 8,  color = 'yellow2',behavior = 'shoot_arrow', range = 96,  cd = 1.0,  speed = 200},

  -- ----- Knife shooters (behavior = 'shoot_knife') -----
  scout       = {r = 5, base_speed = 180, dmg = 6,  color = 'red',    behavior = 'shoot_knife', range = 64,  cd = 0.5, speed = 240, ricochet = 3},
  thief       = {r = 5, base_speed = 185, dmg = 6,  color = 'red',    behavior = 'shoot_knife', range = 64,  cd = 0.5, speed = 240, ricochet = 5},
  assassin    = {r = 5, base_speed = 200, dmg = 12, color = 'purple', behavior = 'shoot_knife', range = 64,  cd = 0.5, speed = 280, pierce = 4},

  -- ----- Random-direction shooter -----
  spellblade  = {r = 6, base_speed = 160, dmg = 7,  color = 'blue',   behavior = 'random_shot', cd = 0.7, speed = 180},

  -- ----- Multi-shot burst -----
  barrager    = {r = 6, base_speed = 160, dmg = 7,  color = 'green',  behavior = 'multi_shot',  range = 128, cd = 1.5, shot_count = 3, speed = 200},

  -- ----- Melee splash (behavior = 'melee_splash') -----
  swordsman   = {r = 7, base_speed = 150, dmg = 14, color = 'yellow', behavior = 'melee_splash', range = 48,  cd = 3.0, splash = 96},
  barbarian   = {r = 8, base_speed = 140, dmg = 16, color = 'yellow', behavior = 'melee_splash', range = 48,  cd = 8.0, splash = 96},
  juggernaut  = {r = 8, base_speed = 140, dmg = 18, color = 'yellow', behavior = 'melee_splash', range = 64,  cd = 8.0, splash = 128, knockback = 80},
  elementor   = {r = 6, base_speed = 150, dmg = 14, color = 'blue',   behavior = 'melee_splash', range = 128, cd = 7.0, splash = 128},
  highlander  = {r = 6, base_speed = 155, dmg = 10, color = 'yellow', behavior = 'melee_splash', range = 36,  cd = 4.0, splash = 72},
  miner       = {r = 6, base_speed = 155, dmg = 10, color = 'yellow2',behavior = 'melee_splash', range = 48,  cd = 4.0, splash = 64},

  -- ----- Random-target splash (behavior = 'random_splash') -----
  magician    = {r = 5, base_speed = 175, dmg = 9,  color = 'blue',   behavior = 'random_splash', range = 96, cd = 2.0, splash = 32},
  psychic     = {r = 6, base_speed = 165, dmg = 9,  color = 'fg',     behavior = 'random_splash', range = 64, cd = 3.0, splash = 32},

  -- ----- Healing (behavior = 'heal') -----
  cleric      = {r = 6, base_speed = 145, dmg = 4,  color = 'green',  behavior = 'heal', heal_cd = 8,  heal_amt = 1},
  priest      = {r = 6, base_speed = 150, dmg = 5,  color = 'green',  behavior = 'heal', heal_cd = 12, heal_amt = 2},
  psykeeper   = {r = 6, base_speed = 155, dmg = 5,  color = 'fg',     behavior = 'heal', heal_cd = 10, heal_amt = 1},

  -- ----- Curse / vulnerability (behavior = 'curse') -----
  launcher    = {r = 6, base_speed = 160, dmg = 8,  color = 'yellow', behavior = 'curse', range = 96, cd = 6, curse_radius = 128, curse_targets = 4,  curse_mult = 1.4, curse_duration = 4},
  jester      = {r = 6, base_speed = 165, dmg = 8,  color = 'red',    behavior = 'curse', range = 96, cd = 6, curse_radius = 128, curse_targets = 6,  curse_mult = 1.4, curse_duration = 6},
  usurer      = {r = 6, base_speed = 155, dmg = 8,  color = 'purple', behavior = 'curse', range = 96, cd = 6, curse_radius = 128, curse_targets = 3,  curse_mult = 1.3, curse_duration = 10, curse_dot = 1.0},
  silencer    = {r = 6, base_speed = 160, dmg = 8,  color = 'blue2',  behavior = 'curse', range = 96, cd = 6, curse_radius = 128, curse_targets = 6,  curse_mult = 1.5, curse_duration = 6},
  bane        = {r = 6, base_speed = 160, dmg = 8,  color = 'purple', behavior = 'curse', range = 96, cd = 6, curse_radius = 128, curse_targets = 6,  curse_mult = 1.6, curse_duration = 6},

  -- ----- Damage-over-time clouds (behavior = 'dot_cloud') -----
  plague_doctor = {r = 6, base_speed = 155, dmg = 6, color = 'purple', behavior = 'dot_cloud', range = 96, cd = 5,  cloud_radius = 32, cloud_duration = 12, dps_mult = 0.4},
  witch         = {r = 6, base_speed = 155, dmg = 6, color = 'purple', behavior = 'dot_cloud', range = 96, cd = 4,  cloud_radius = 48, cloud_duration = 14, dps_mult = 0.5},

  -- ----- Bomb drops (behavior = 'bomb_drop') -----
  saboteur    = {r = 6, base_speed = 155, dmg = 8,  color = 'orange', behavior = 'bomb_drop', range = 128, cd = 8,  bomb_radius = 48, fuse = 2,   count = 2, blast_mult = 1.5},
  bomber      = {r = 6, base_speed = 150, dmg = 10, color = 'orange', behavior = 'bomb_drop', range = 128, cd = 8,  bomb_radius = 64, fuse = 2,   count = 1, blast_mult = 2.0},
  vulcanist   = {r = 7, base_speed = 145, dmg = 10, color = 'red',    behavior = 'bomb_drop', range = 192, cd = 12, bomb_radius = 80, fuse = 1.5, count = 1, blast_mult = 2.5},

  -- ----- Turret drops (behavior = 'turret_drop') -----
  engineer    = {r = 6, base_speed = 155, dmg = 8, color = 'orange', behavior = 'turret_drop', cd = 8,  lifetime = 10, turret_cd = 1.5, turret_range = 96,  turret_dmg = 6},
  sentry      = {r = 6, base_speed = 155, dmg = 8, color = 'green',  behavior = 'turret_drop', cd = 7,  lifetime = 10, turret_cd = 1.0, turret_range = 96,  turret_dmg = 6},
  carver      = {r = 6, base_speed = 150, dmg = 8, color = 'green',  behavior = 'turret_drop', cd = 14, lifetime = 16, turret_cd = 2.0, turret_range = 64,  turret_dmg = 10},
  artificer   = {r = 6, base_speed = 155, dmg = 8, color = 'blue2',  behavior = 'turret_drop', cd = 6,  lifetime = 12, turret_cd = 2.0, turret_range = 80,  turret_dmg = 8},

  -- ----- Force area (behavior = 'force_area') -----
  psykino     = {r = 6, base_speed = 160, dmg = 8, color = 'fg', behavior = 'force_area', range = 128, cd = 4, force_radius = 64, force_strength = 120},

  -- ----- Ally damage buff -----
  stormweaver = {r = 6, base_speed = 160, dmg = 6, color = 'blue',   behavior = 'ally_buff_dmg',  cd = 8,  buff_mult = 1.5, duration = 4},
  warden      = {r = 6, base_speed = 155, dmg = 6, color = 'yellow', behavior = 'ally_buff_dmg',  cd = 10, buff_mult = 1.3, duration = 5},

  -- ----- Ally attack-speed buff -----
  fairy       = {r = 5, base_speed = 175, dmg = 5, color = 'green',  behavior = 'ally_buff_aspd', cd = 6,  buff_mult = 2.0, duration = 6},
  squire      = {r = 6, base_speed = 155, dmg = 7, color = 'yellow', behavior = 'ally_buff_aspd', cd = 10, buff_mult = 1.5, duration = 8},

  -- ----- Pet spawns (small allies that fly up and hit bricks) -----
  host        = {r = 6, base_speed = 150, dmg = 6,  color = 'orange', behavior = 'pet_spawn', cd = 4,  count = 1, pet_speed = 70, pet_dmg = 8},
  infestor    = {r = 6, base_speed = 150, dmg = 6,  color = 'orange', behavior = 'pet_spawn', cd = 10, count = 3, pet_speed = 70, pet_dmg = 8},
  illusionist = {r = 6, base_speed = 160, dmg = 5,  color = 'blue2',  behavior = 'pet_spawn', cd = 8,  count = 2, pet_speed = 70, pet_dmg = 8},

  -- ----- Gambler-style random multi-strike -----
  gambler     = {r = 6, base_speed = 165, dmg = 8, color = 'yellow2', behavior = 'gambler_burst', cd = 2, burst_count = 3, burst_mult = 3.0},

  -- ----- Time-dilation aura (slows nearby swarm drift) -----
  chronomancer = {r = 6, base_speed = 155, dmg = 7, color = 'blue', behavior = 'time_dilation', range = 128, cd = 8, duration = 3, slow_mult = 0.4},

  -- ----- On-bounce exceptions: ability triggers per ball-bounce, not a timer.
  wizard      = {r = 5, base_speed = 170, dmg = 7,  color = 'blue',   on_bounce = 'chain_lightning', bounce_cd = 0.3},
  cryomancer  = {r = 6, base_speed = 160, dmg = 6,  color = 'blue',   on_bounce = 'slow'},
  pyromancer  = {r = 6, base_speed = 160, dmg = 8,  color = 'red',    on_bounce = 'burn', bounce_cd = 0.4},
  cannoneer   = {r = 7, base_speed = 145, dmg = 18, color = 'orange', on_bounce = 'big_splash'},
  flagellant  = {r = 6, base_speed = 160, dmg = 7,  color = 'fg',     on_bounce = 'flagellant_pulse'},
}

function BallHero.stats_for(character)
  return HERO_STATS[character] or HERO_STATS.vagrant
end


-- Returns a shaded clone of `base` so successive same-colored balls alternate
-- between lighter and darker tints around the base hue. Offsets:
--   0 -> base
--   1 -> +5% lighter
--   2 -> -5% darker
--   3 -> +10% lighter
--   4 -> -10% darker  ... etc.
function BallHero.shaded(base, offset)
  if not offset or offset == 0 then return base end
  local sign = (offset % 2 == 1) and 1 or -1
  local mag  = math.ceil(offset/2)
  return base:clone():lighten(sign*mag*0.05)
end


function BallHero:init(args)
  self:init_game_object(args)
  self.character    = self.character or 'vagrant'
  self.level        = self.level or 1
  local s           = BallHero.stats_for(self.character)
  self.stats        = s
  self.r_size       = s.r
  -- Multiple heroes can share the same base color (e.g. wizard/magician/
  -- cryomancer are all blue). BallPit:add_hero passes a shade_offset based on
  -- how many same-colored balls were already in play, so the new ball gets a
  -- slightly lighter or darker tint and stays distinguishable.
  local base_color  = character_colors[self.character] or fg[0]
  self.color        = BallHero.shaded(base_color, self.shade_offset or 0)
  self.dmg          = s.dmg * (1 + 0.4*(self.level-1))
  self.base_speed   = s.base_speed
  self.returning      = false  -- ball fell into the pit and is being pulled back to the paddle
  self.stuck          = false  -- ball is glued to the paddle awaiting an aimed launch
  self.stuck_offset_x = 0

  -- Speed-up streak: every successful paddle bounce ramps the ball faster,
  -- so missing the paddle is increasingly painful. Mult resets when the ball
  -- gets stuck after a miss (or on initial launch).
  self.speed_mult       = 1.0
  self.speed_mult_max   = 4.0     -- was 3.0 (orig 2.5)
  self.speed_mult_step  = 1.25    -- was 1.15 (orig 1.07) — +25% per bounce

  -- Charge-on-paddle: while stuck the ball fills a green ring up to
  -- charge_max_time, then blinks red at full. On launch the charge converts
  -- into a temporary speed bonus (up to +100%) and damage bonus (up to +50%)
  -- that lasts until the ball gets stuck again.
  self.charge_time      = 0
  self.charge_max_time  = 2.0
  self.charge_dmg_mult  = 1.0

  self:set_as_circle(self.r_size, 'dynamic', 'ball')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(1)
  self:set_friction(0)
  self:set_damping(0)
  self:set_angular_damping(0)
  self:set_mass(0.5)

  -- Per-bounce ability cooldown for the on-bounce exceptions that need it
  -- (wizard, pyromancer). Used to limit fire rate when bouncing rapidly.
  self.ability_ready = true
  if s.bounce_cd then
    self.t:every(s.bounce_cd, function() self.ability_ready = true end)
  end

  -- Continuous timer-based attacks for the 12 non-exception heroes.
  self:setup_continuous_attack()

  -- Drop afterimage trail particles while the ball is moving above the
  -- speed-streak threshold. Empty/no-op otherwise.
  self.t:every(0.035, function() self:maybe_spawn_trail() end)

  -- Auto-launch on next frame.
  self.t:after(0, function() self:launch_from_paddle() end)
end


function BallHero:maybe_spawn_trail()
  if self.stuck or self.returning then return end
  if (self.speed_mult or 1) < 1.3 then return end
  BallTrail{
    group    = main.current.effects,
    x        = self.x, y = self.y,
    color    = self.color,
    rs       = self.r_size*0.85,
    alpha    = math.clamp(math.remap(self.speed_mult, 1.3, 2.5, 0.35, 0.7), 0.35, 0.7),
    duration = 0.22,
  }
end


function BallHero:launch_from_paddle()
  local arena = main.current
  if not arena or not arena.paddle then return end
  local px = arena.paddle.x
  local py = arena.paddle.y - arena.paddle.h/2 - self.r_size - 1
  self:set_position(px, py)
  self.speed_mult = 1.0
  local angle = -math.pi/2 + random:float(-0.25, 0.25)
  self:set_velocity(math.cos(angle)*self.base_speed, math.sin(angle)*self.base_speed)
  self.spring:pull(0.25)
end


-- ----- Behavior dispatch -----
-- One handler per behavior key in HERO_STATS. Each handler is called once at
-- ball-init time and is responsible for wiring whatever trigger keeps the
-- attack running. Each handler must guard for stuck/returning at fire time
-- and tag its trigger 'attack' (or 'heal') so ally-buff_aspd can adjust it.

local BEHAVIORS = {}


BEHAVIORS.shoot_arrow = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    local extra = {}
    if s.pierce      then extra.pierce      = s.pierce end
    if s.ricochet    then extra.ricochet    = s.ricochet end
    if s.crit_chance and random:bool(s.crit_chance) then extra.crit = true end
    self:shoot_arrow(s.range, s.speed or 220, extra)
  end, 0, nil, 'attack')
end


BEHAVIORS.shoot_knife = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    local extra = {}
    if s.pierce   then extra.pierce   = s.pierce end
    if s.ricochet then extra.ricochet = s.ricochet end
    self:shoot_knife(s.range, s.speed or 240, extra)
  end, 0, nil, 'attack')
end


BEHAVIORS.random_shot = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    if not (arena.main and arena.main.world) then return end
    local ang = random:float(0, 2*math.pi)
    arena.t:after(0, function()
      if not (arena.main and arena.main.world) then return end
      Projectile{
        group  = arena.main, x = self.x, y = self.y, r = ang,
        type   = 'arrow', speed = s.speed or 180, color = self.color,
        dmg    = self:current_dmg()*3.5,
      }
    end)
    archer1:play{volume = 0.2, pitch = random:float(0.95, 1.05)}
  end, 0, nil, 'attack')
end


BEHAVIORS.multi_shot = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    for i = 1, (s.shot_count or 3) do
      self.t:after((i-1)*0.075, function()
        if self.stuck or self.returning then return end
        self:shoot_arrow(s.range, s.speed or 200, {})
      end)
    end
  end, 0, nil, 'attack')
end


BEHAVIORS.melee_splash = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    main.current:do_splash(self.x, self.y, s.splash, self:current_dmg(), self.color)
    swordsman1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
    if s.knockback then
      main.current:knockback_area(self.x, self.y, s.splash, s.knockback)
    end
  end, 0, nil, 'attack')
end


BEHAVIORS.random_splash = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    local t = arena:get_random_brick_within(self.x, self.y, s.range)
    if not t then return end
    arena:do_splash(t.x, t.y, s.splash, self:current_dmg(), self.color)
    if self.character == 'psychic' then
      thunder1:play{volume = 0.2, pitch = random:float(1.05, 1.15)}
    else
      wizard1:play{volume = 0.22, pitch = random:float(1.0, 1.1)}
    end
  end, 0, nil, 'attack')
end


BEHAVIORS.heal = function(self, s)
  self.t:every(s.heal_cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    if arena.player_hp < arena.player_hp_max then
      arena.player_hp = math.min(arena.player_hp_max, arena.player_hp + s.heal_amt)
      heal1:play{volume = 0.35, pitch = random:float(0.95, 1.05)}
      FloatingText{group = arena.effects, x = self.x, y = self.y - 8,
        text = '+' .. s.heal_amt .. ' HP', color = green[0]}
    end
  end, 0, nil, 'heal')
end


BEHAVIORS.curse = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    local bricks = arena:get_bricks_within(self.x, self.y, s.curse_radius)
    table.shuffle(bricks)
    local n = math.min(s.curse_targets or 6, #bricks)
    for i = 1, n do
      local b = bricks[i]
      b:apply_curse(self.color, s.curse_mult or 1.4, s.curse_duration or 6)
      if s.curse_dot then b:apply_burn(self:current_dmg()*s.curse_dot, s.curse_duration or 6) end
      -- A faint zap line from caster to target so the player sees the curse land.
      arena_zap_line(arena, self.x, self.y, b.x, b.y, self.color)
    end
    buff1:play{volume = 0.3, pitch = random:float(0.95, 1.1)}
  end, 0, nil, 'attack')
end


BEHAVIORS.dot_cloud = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    local t = arena:get_random_brick_within(self.x, self.y, s.range)
    local tx, ty = self.x, self.y
    if t then tx, ty = t.x, t.y end
    arena:burn_area(tx, ty, s.cloud_radius, self:current_dmg()*(s.dps_mult or 0.4), s.cloud_duration)
    DotCloud{group = arena.effects, x = tx, y = ty, color = self.color, rs = s.cloud_radius, duration = s.cloud_duration}
    dot1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
  end, 0, nil, 'attack')
end


BEHAVIORS.bomb_drop = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    local count = s.count or 1
    for i = 1, count do
      arena.t:after((i-1)*0.2, function()
        local t = arena:get_random_brick_within(self.x, self.y, s.range or 128)
        local tx, ty
        if t then tx, ty = t.x + random:float(-8, 8), t.y + random:float(-8, 8)
        else tx, ty = self.x + random:float(-32, 32), self.y + random:float(-32, 32) end
        BombDrop{group = arena.effects, x = tx, y = ty, color = self.color,
                 dmg = self:current_dmg()*(s.blast_mult or 2), radius = s.bomb_radius, fuse = s.fuse}
      end)
    end
    mine1:play{volume = 0.2, pitch = random:float(0.95, 1.05)}
  end, 0, nil, 'attack')
end


BEHAVIORS.turret_drop = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    local tx = math.clamp(arena.paddle.x + random:float(-arena.paddle.w/2, arena.paddle.w/2),
                          arena.x1 + 6, arena.x2 - 6)
    local ty = arena.paddle.y - random:float(20, 40)
    AllyTurret{group = arena.effects, x = tx, y = ty, color = self.color,
               lifetime = s.lifetime, fire_cd = s.turret_cd, range = s.turret_range,
               dmg = s.turret_dmg*(self.charge_dmg_mult or 1)*(self.buff_dmg_mult or 1)}
    spawn1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
  end, 0, nil, 'attack')
end


BEHAVIORS.force_area = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    local t = arena:get_random_brick_within(self.x, self.y, s.range or 128)
    local tx, ty = (t and t.x) or self.x, (t and t.y) or self.y
    arena:knockback_area(tx, ty, s.force_radius or 64, s.force_strength or 120)
    TelegraphRing{group = arena.effects, x = tx, y = ty, radius = s.force_radius or 64, color = self.color, duration = 0.3}
    force1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
  end, 0, nil, 'attack')
end


BEHAVIORS.ally_buff_dmg = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 32, color = self.color, duration = 0.3}
    for _, h in ipairs(arena.heroes) do
      if h and not h.dead then
        h.buff_dmg_mult = math.max(h.buff_dmg_mult or 1, s.buff_mult or 1.5)
        h.t:after(s.duration or 4, function() h.buff_dmg_mult = 1 end, 'ally_dmg_buff')
      end
    end
    buff1:play{volume = 0.3, pitch = random:float(1.0, 1.15)}
  end, 0, nil, 'attack')
end


BEHAVIORS.ally_buff_aspd = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = 32, color = self.color, duration = 0.3}
    local m = 1/(s.buff_mult or 2)
    for _, h in ipairs(arena.heroes) do
      if h and not h.dead and h.t.triggers and h.t.triggers.attack then
        h.t:set_every_multiplier('attack', m)
        h.t:after(s.duration or 6, function()
          if h.t.triggers and h.t.triggers.attack then h.t:set_every_multiplier('attack', 1) end
        end, 'ally_aspd_buff')
      end
    end
    buff1:play{volume = 0.3, pitch = random:float(1.1, 1.2)}
  end, 0, nil, 'attack')
end


BEHAVIORS.pet_spawn = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    local count = s.count or 1
    for i = 1, count do
      arena.t:after((i-1)*0.1, function()
        if not (arena.main and arena.main.world) then return end
        AllyCritter{
          group = arena.main, x = self.x, y = self.y,
          color = self.color, speed = s.pet_speed or 70,
          dmg = (s.pet_dmg or 8)*(self.charge_dmg_mult or 1)*(self.buff_dmg_mult or 1),
        }
      end)
    end
    critter1:play{volume = 0.25, pitch = random:float(0.95, 1.05)}
  end, 0, nil, 'attack')
end


BEHAVIORS.gambler_burst = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    for i = 1, s.burst_count or 3 do
      self.t:after((i-1)*0.18, function()
        local pool = arena:get_bricks_within(self.x, self.y, 320)
        if #pool == 0 then return end
        local t = pool[random:int(1, #pool)]
        if t and not t.dead then
          t:take_damage(self:current_dmg()*(s.burst_mult or 3), self.color)
          spawn_burst(arena.effects, t.x, t.y, self.color, 4, 60, 130)
          arena_zap_line(arena, self.x, self.y, t.x, t.y, self.color)
        end
      end)
    end
  end, 0, nil, 'attack')
end


BEHAVIORS.time_dilation = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = s.range, color = blue[0], duration = 0.4}
    local slow = s.slow_mult or 0.4
    for _, swarm in ipairs(arena.swarms.objects) do
      if not swarm.dead and swarm.cells then
        for _, cell in ipairs(swarm.cells) do
          if cell.brick and not cell.brick.dead then
            if math.distance(self.x, self.y, cell.brick.x, cell.brick.y) <= s.range then
              swarm._chrono_orig = swarm._chrono_orig or swarm.drift_speed
              swarm.drift_speed = swarm._chrono_orig*slow
              swarm.t:after(s.duration or 3, function()
                if swarm._chrono_orig then
                  swarm.drift_speed = swarm._chrono_orig
                  swarm._chrono_orig = nil
                end
              end)
              break
            end
          end
        end
      end
    end
    frost1:play{volume = 0.25, pitch = random:float(0.85, 0.95)}
  end, 0, nil, 'attack')
end


-- A short zap line drawn from (x1,y1) to (x2,y2) in the effects group. Used by
-- curse / gambler-style abilities for visual feedback.
function arena_zap_line(arena, x1, y1, x2, y2, color)
  local seg = Object:extend()
  seg:implement(GameObject)
  function seg:init(a)
    self:init_game_object(a)
    self.alpha = 0.8
    self.t:tween(0.2, self, {alpha = 0}, math.linear, function() self.dead = true end)
  end
  function seg:update(dt) self:update_game_object(dt) end
  function seg:draw()
    graphics.line(self.x1, self.y1, self.x2, self.y2, Color(self.color.r, self.color.g, self.color.b, self.alpha), 1)
  end
  seg{group = arena.effects, x = (x1+x2)/2, y = (y1+y2)/2, x1 = x1, y1 = y1, x2 = x2, y2 = y2, color = color}
end


-- Sets up the SNKRX-style cooldown attack for the current character. Skipped
-- for the on-bounce exceptions, which fire in BallHero:on_brick_hit instead.
function BallHero:setup_continuous_attack()
  local s = self.stats
  if s.on_bounce then return end
  local handler = BEHAVIORS[s.behavior]
  if handler then handler(self, s) end
end


function BallHero:can_attack(range)
  if self.stuck or self.returning then return false end
  return main.current:has_brick_within(self.x, self.y, range)
end


-- Convenience wrappers for the different projectile flavors.
-- Per-shot damage multiplier sits here (PROJECTILE_DMG_MULT) so the buff
-- doesn't bleed into contact damage on bounces.
local PROJECTILE_DMG_MULT = 3.5

-- Effective damage this ball deals right now (base × any active charge bonus
-- × any active ally damage buff from stormweaver/warden).
function BallHero:current_dmg()
  return self.dmg*(self.charge_dmg_mult or 1)*(self.buff_dmg_mult or 1)
end


function BallHero:shoot_arrow(range, speed, extra)
  if self.stuck or self.returning then return end
  local dmg = self:current_dmg()*PROJECTILE_DMG_MULT
  if extra and extra.crit then dmg = dmg*2 end
  local opts = {type = 'arrow', dmg = dmg, speed = speed, range = range, color = self.color}
  if extra then for k, v in pairs(extra) do if k ~= 'crit' then opts[k] = v end end end
  main.current:fire_projectile_at_nearest(self, opts)
  archer1:play{volume = 0.22, pitch = random:float(0.95, 1.05)}
end


function BallHero:shoot_knife(range, speed, extra)
  if self.stuck or self.returning then return end
  local opts = {type = 'knife', dmg = self:current_dmg()*PROJECTILE_DMG_MULT, speed = speed, range = range, color = self.color}
  if extra then for k, v in pairs(extra) do opts[k] = v end end
  main.current:fire_projectile_at_nearest(self, opts)
  scout1:play{volume = 0.22, pitch = random:float(0.95, 1.05)}
end


function BallHero:melee_splash(radius, dmg)
  if self.stuck or self.returning then return end
  main.current:do_splash(self.x, self.y, radius, dmg*(self.charge_dmg_mult or 1), self.color)
  swordsman1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
end


function BallHero:update(dt)
  self:update_game_object(dt)

  local arena = main.current

  if self.stuck then
    self:update_stuck(dt)
    return
  end

  if self.returning then
    self:update_return(dt)
    return
  end

  self:normalize_speed()

  -- Ball fell into the pit (no bottom wall) — magnetic recall back to paddle.
  if self.y > arena.y2 + 12 then
    self:start_return()
  end
end


-- Disable physics and lerp the ball back to a point just above the paddle.
function BallHero:start_return()
  self.returning = true
  if self.body then self.body:setActive(false) end
end


-- Pulls the ball toward the top of the paddle each frame. On arrival the
-- ball hands off to the stuck/aim system instead of auto-launching, so the
-- player gets to redirect it with arrow keys + SPACE.
function BallHero:update_return(dt)
  local arena = main.current
  if not arena or not arena.paddle then return end

  local target_x = arena.paddle.x
  local target_y = arena.paddle.y - arena.paddle.h/2 - self.r_size - 1
  local dx, dy   = target_x - self.x, target_y - self.y
  local d        = math.sqrt(dx*dx + dy*dy)

  if d < 1.5 then
    self.returning = false
    -- If space is being held, auto-fire on arrival at the arena's current aim
    -- angle (skipping the stuck/wait state). Otherwise glue to the paddle and
    -- wait for the player to aim + launch manually.
    if input.launch.down then
      if self.body then self.body:setActive(true) end
      self.speed_mult = 1.0
      local angle = arena.aim_angle or -math.pi/2
      self:set_velocity(math.cos(angle)*self.base_speed, math.sin(angle)*self.base_speed)
      self.spring:pull(0.3)
    else
      self:start_stuck()
    end
    return
  end

  local pull_speed = math.min(320, 70 + d*1.8)
  local nx, ny     = dx/d, dy/d
  self.x = self.x + nx*pull_speed*dt
  self.y = self.y + ny*pull_speed*dt
  if self.body then self.body:setPosition(self.x, self.y) end
end


-- Pin the ball to the paddle's top and wait for the player to aim + launch.
function BallHero:start_stuck()
  self.stuck            = true
  self.stuck_offset_x   = random:float(-8, 8)
  self.speed_mult       = 1.0   -- missing the paddle wipes the speed streak
  self.charge_time      = 0     -- fresh charge bar each time
  self.charge_dmg_mult  = 1.0   -- previous charge bonus is consumed
  if self.body then self.body:setActive(false) end
  local arena = main.current
  arena.stuck_count = (arena.stuck_count or 0) + 1
  -- Aim resets to straight up the first time a ball gets caught in a run; if
  -- another ball is already stuck, the existing aim is preserved.
  if arena.stuck_count == 1 then arena.aim_angle = -math.pi/2 end
  pop1:play{volume = 0.3, pitch = random:float(1.0, 1.15)}
end


function BallHero:update_stuck(dt)
  local arena = main.current
  if not arena or not arena.paddle then return end
  local px = arena.paddle.x + self.stuck_offset_x
  local py = arena.paddle.y - arena.paddle.h/2 - self.r_size - 1
  self.x, self.y = px, py
  if self.body then self.body:setPosition(px, py) end
  -- Fill the charge ring while glued. Caps at charge_max_time.
  self.charge_time = math.min(self.charge_time + (dt or 1/60), self.charge_max_time)
end


-- Release a stuck ball at the arena's current aim angle. Charge accrued while
-- glued converts into a speed bonus (up to +100%) and a damage bonus
-- (up to +50%) that persists until the ball gets stuck again.
function BallHero:launch_from_stuck(angle)
  if not self.stuck then return end
  self.stuck = false
  if self.body then self.body:setActive(true) end

  local charge_pct      = math.clamp(self.charge_time/self.charge_max_time, 0, 1)
  self.speed_mult       = 1.0 + charge_pct           -- 1x .. 2x
  self.charge_dmg_mult  = 1.0 + charge_pct*0.5       -- 1x .. 1.5x

  local launch_speed = self.base_speed*self.speed_mult
  self:set_velocity(math.cos(angle)*launch_speed, math.sin(angle)*launch_speed)
  self.spring:pull(0.3 + 0.2*charge_pct)
  if charge_pct > 0.6 then
    spawn_burst(main.current.effects, self.x, self.y, self.color, 6, 80, 160)
  end
  local arena = main.current
  arena.stuck_count = math.max(0, (arena.stuck_count or 0) - 1)
end


function BallHero:draw()
  self.spring:pull(0)
  local s = self.spring.x
  graphics.circle(self.x, self.y, self.r_size + 0.5, bg[-2])
  graphics.circle(self.x, self.y, self.r_size*s, self.color)
  graphics.circle(self.x - self.r_size*0.3, self.y - self.r_size*0.3, math.max(1, self.r_size*0.35), fg[5])

  if main.current.show_hero_labels then
    graphics.print_centered(self.character:sub(1, 3), pixul_font, self.x, self.y - self.r_size - 6, 0, 1, 1, 0, 0, fg[0])
  end

  -- Only the lead stuck ball renders its charge ring, so a paddle full of
  -- caught balls doesn't drown the player in overlapping rings.
  if self.stuck and main.current:lead_stuck_ball() == self then self:draw_charge() end
end


-- Draws the charge ring around a stuck ball. Empty hollow ring as background;
-- green arc fills clockwise from 12 o'clock; once full, the whole ring blinks
-- red to signal max charge.
function BallHero:draw_charge()
  local ring_r = self.r_size + 4
  local pct    = math.clamp(self.charge_time/self.charge_max_time, 0, 1)

  graphics.circle(self.x, self.y, ring_r, bg_transparent_weak, 1)

  if pct >= 1.0 then
    local on = math.floor(love.timer.getTime()*10) % 2 == 0
    if on then
      graphics.circle(self.x, self.y, ring_r, red[0], 2)
    end
  elseif pct > 0.02 then
    local start_a = -math.pi/2
    local end_a   = start_a + pct*2*math.pi
    graphics.arc('open', self.x, self.y, ring_r, start_a, end_a, green[0], 2)
  end
end


function BallHero:get_speed()
  local vx, vy = self:get_velocity()
  return math.sqrt(vx*vx + vy*vy)
end


function BallHero:normalize_speed()
  local target = self.base_speed * (self.speed_mult or 1)
  local vx, vy = self:get_velocity()
  local s = math.sqrt(vx*vx + vy*vy)
  if s < 1 then
    self:set_velocity(0, -target)
    return
  end
  if math.abs(s - target) > 12 then
    local k = target/s
    self:set_velocity(vx*k, vy*k)
  end
  vx, vy = self:get_velocity()
  if math.abs(vy) < target*0.15 then
    local sign = vy >= 0 and 1 or -1
    self:set_velocity(vx, sign*target*0.2)
    self:normalize_speed()
  end
end


-- Called by BallPit on every ball-vs-brick collision. Contact damage always
-- happens; the four exception heroes also fire their on-bounce ability.
function BallHero:on_brick_hit(brick)
  local arena = main.current
  -- Bricks route damage through on_ball_contact so their Row can react to the
  -- knockback. Mobile enemies (critters, projectiles) just take damage.
  if brick.on_ball_contact then
    brick:on_ball_contact(self)
  else
    brick:take_damage(self.dmg, self.color)
  end

  local trigger = self.stats.on_bounce
  if not trigger then return end

  if trigger == 'chain_lightning' then
    if self.ability_ready then
      self.ability_ready = false
      arena:do_chain_lightning(self.x, self.y, self:current_dmg()*0.7, 3 + self.level, self.color)
      wizard1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
    end

  elseif trigger == 'slow' then
    arena:slow_in_area(self.x, self.y, 32, 0.5, 2.0)
    frost1:play{volume = 0.25, pitch = random:float(0.95, 1.05)}

  elseif trigger == 'burn' then
    if self.ability_ready then
      self.ability_ready = false
      -- Burn dps buffed +400% (×5): was self.dmg*0.5 dps, now self.dmg*2.5 dps.
      arena:burn_area(self.x, self.y, 32, self:current_dmg()*2.5, 2.5)
      fire1:play{volume = 0.25, pitch = random:float(0.95, 1.05)}
    end

  elseif trigger == 'big_splash' then
    arena:do_splash(self.x, self.y, 64, self:current_dmg()*1.1, orange[0])
    explosion1:play{volume = 0.35, pitch = random:float(0.95, 1.05)}

  elseif trigger == 'flagellant_pulse' then
    -- A constant low-damage pulse on every bounce — no internal cooldown.
    arena:do_splash(self.x, self.y, 36, self:current_dmg()*0.45, fg[0])
    flagellant1:play{volume = 0.18, pitch = random:float(0.9, 1.1)}
  end
end
