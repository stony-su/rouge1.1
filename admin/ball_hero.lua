-- BallHero is the SNKRX-style hero remixed as a bouncing ball.
-- The 20-ball roster (trimmed from the full 57 SNKRX archetypes so every
-- pick has a distinct effect): most heroes attack continuously on cooldown
-- (SNKRX-style: trigger inside an attack-sensor radius), while 3 exceptions
-- (wizard, cryomancer, pyromancer) keep on-bounce abilities.
-- Contact damage on bounce applies to all.

BallHero = Object:extend()
BallHero:implement(GameObject)
BallHero:implement(Physics)


-- Global pace tuning:
--   * Balls launch at a third of their old speed (BASE_SPEED_MULT); the
--     paddle-bounce speed streak — doubled, see speed_mult_step in init —
--     is the way back up.
--   * The RANGED auto-attacks (the timer behaviors that damage from afar:
--     every projectile shooter plus the vulcanist's volcano) fire 4x slower
--     (RANGED_CD_MULT, applied to cd in init) but hit 2.5x harder
--     (RANGED_DMG_MULT, applied at the attack sites), so each shot is a
--     bigger moment in the slowed-down game. Melee splash/cleave, support
--     casts and the on-bounce contact abilities are untouched.
local BASE_SPEED_MULT  = 0.33
local RANGED_CD_MULT   = 4.0
local RANGED_DMG_MULT  = 2.5
local RANGED_BEHAVIORS = {
  shoot_arrow = true, crossbow = true, chain_knife = true,
  shoot_knife = true, random_shot = true, volcano = true,
}

-- Per-character stats. r/base_speed/dmg/color are ball properties; the rest
-- depend on `behavior`, which keys into the BEHAVIORS dispatch table below.
-- Stats are adapted from SNKRX-master/player.lua: range mirrors that hero's
-- attack_sensor radius, cd mirrors their trigger:cooldown delay, etc.
-- Projectile heroes get an additional +250%/+300% (dmg/rate) buff inside
-- the shoot helpers; here we just store the base cd.
local HERO_STATS = {
  -- ----- Projectile shooters (behavior = 'shoot_arrow') -----
  vagrant     = {r = 6, base_speed = 160, dmg = 8,  color = 'fg',     behavior = 'shoot_arrow', range = 96,  cd = 0.5,  speed = 220},

  -- ----- Crossbow bolt (SNKRX archer port; behavior = 'crossbow') -----
  -- Every 2s, a bolt at the CLOSEST brick in the 160px sensor with infinite
  -- pierce — it skewers the whole lane and only stops at a wall, sticking in
  -- as a WallArrow. Level 3: the bolt ricochets off the side/top walls 3
  -- times first. skin draws the ball as a tower base with a compact
  -- swiveling crossbow turret mounted on top.
  archer      = {r = 5, base_speed = 175, dmg = 10, color = 'green',  behavior = 'crossbow', range = 160, cd = 2.0,  speed = 260, skin = 'crossbow'},

  -- ----- Chain knife (SNKRX scout port; behavior = 'chain_knife') -----
  -- The knife CHAINS: on each hit it leaps to a random nearby brick it
  -- hasn't hit, +25% speed per hop. Level 3: 6 chains and +25% damage per
  -- hop on top. skin switches the draw to the spinning bandit shuriken.
  scout       = {r = 5, base_speed = 180, dmg = 6,  color = 'red',    behavior = 'chain_knife', range = 64, cd = 2.0, speed = 240, chain = 3, skin = 'shuriken'},

  -- ----- Assassin (SNKRX assassin port; behavior = 'assassinate') -----
  -- SNKRX player.lua:587 -- every cd seconds with a brick in the 64px sensor,
  -- hurl a knife at the CLOSEST one with pierce 1000 so it skewers the whole
  -- lane. Every brick it touches BLEEDS (player.lua:2356): a bleed_dur-second
  -- DoT worth dmg/2 normally, 4x dmg on a crit. The rogue "assassination" crit
  -- (crit_chance%, +10% per level) also doubles the strike. skin = 'shadow' is
  -- the Shadowstalker look (smoke trail, breathing aura, blink-lunge slash).
  assassin    = {r = 5, base_speed = 200, dmg = 12, color = 'purple', behavior = 'assassinate', range = 64, cd = 2.0, speed = 320, pierce = 1000, crit_chance = 25, bleed_dur = 3, skin = 'shadow'},

  -- ----- Spellblade (SNKRX spellblade port; behavior = 'blade_storm') -----
  -- SNKRX player.lua:400 + :2013 -- a spinning blade-shard fired in a RANDOM
  -- direction with pierce 1000; the projectile's heading SPINS (orbit_vr starts
  -- fast and decays) so it curls outward in a tight spiral that opens up. Ball
  -- Pit fires it as a CONSTANT stream (tiny cd) instead of SNKRX's 2s tick, for
  -- a perpetual blade-nova. skin = 'spellblade' is an arcane core orbited by
  -- blade-shards; SPELLBLADE_DMG_MULT keeps per-shot damage modest (see below).
  spellblade  = {r = 6, base_speed = 160, dmg = 7, color = 'blue', behavior = 'blade_storm', cd = 0.1, range = 9999, speed = 200, orbit_vr = 6, skin = 'spellblade'},

  -- ----- Cleave (SNKRX swordsman port; behavior = 'cleave') -----
  -- area = the visual square side; the hit square is 1.5x that (see
  -- CleaveArea in effects.lua). skin switches the draw to the crescent-slash
  -- body instead of the plain ball.
  swordsman   = {r = 7, base_speed = 150, dmg = 14, color = 'yellow', behavior = 'cleave', range = 48, cd = 3.0, area = 96, skin = 'crescent'},

  -- ----- Melee splash (behavior = 'melee_splash') -----
  -- ----- Barbarian (SNKRX barbarian port; behavior = 'hammer_slam') -----
  -- SNKRX player.lua:460 -- the barbarian shares the swordsman's Area attack
  -- (self:attack(96)) but slower and with a stun. Here it's reshaped into a
  -- HAMMER SLAM: the same Cleave logic (hit-once, +15% total dmg per target,
  -- x2 at level 3) but VERY BIG and drawn as a HEXAGON shockwave instead of a
  -- square slash (see HexSlamArea in effects.lua). skin = 'hammer' is a heavy
  -- maul-head orb that recoils on each slam. area = hexagon circumradius.
  barbarian   = {r = 8, base_speed = 140, dmg = 16, color = 'yellow', behavior = 'hammer_slam', range = 96, cd = 5.0, area = 110, skin = 'hammer'},

  -- ----- Consecrated Ground (cleric rework; behavior = 'consecrate') -----
  -- Every cd seconds the cleric plants a verdant healing sigil at the paddle:
  -- while the paddle sits inside it the player regenerates 1 HP per heal_interval,
  -- and bricks caught in the ring take steady holy damage (holy_mult x dmg per
  -- second). skin = 'lifebloom' is a leaf-wreathed bud that blooms on each cast.
  cleric      = {r = 6, base_speed = 145, dmg = 4, color = 'green', behavior = 'consecrate', cd = 7, ground_rs = 64, ground_duration = 6, heal_interval = 2.0, holy_mult = 0.6, blade_mult = 1.5, skin = 'lifebloom'},

  -- ----- Jester "Pandemonium" (SNKRX jester port; behavior = 'pandemonium') -----
  -- SNKRX player.lua:525 -- every cd seconds with a brick in the 96px attack
  -- sensor, HEX up to curse_targets bricks inside the 128px wide sensor for
  -- curse_duration. The hex deals NO damage itself; instead a hexed brick that
  -- DIES bursts into a cross of 4 knives (Brick:die), and at level 3
  -- ("Pandemonium") those knives HOME and PIERCE twice -- so one kill can ripple
  -- through the whole hexed swarm. knife_mult scales each knife off current_dmg.
  -- The jester ball itself is FAST and restless, weaving a chaotic, bouncy path
  -- and shedding harlequin confetti (skin = 'jester').
  jester      = {r = 6, base_speed = 190, dmg = 8,  color = 'red',    behavior = 'pandemonium', range = 96, cd = 6, curse_radius = 128, curse_targets = 6, curse_duration = 6, knife_mult = 2.5, knife_speed = 250, skin = 'jester'},

  -- ----- Damage-over-time clouds (behavior = 'dot_cloud') -----
  witch       = {r = 6, base_speed = 155, dmg = 6, color = 'purple', behavior = 'dot_cloud', range = 96, cd = 4,  cloud_radius = 48, cloud_duration = 14, dps_mult = 0.5},

  -- ----- Bomber "Reactor Core" (SNKRX bomber port; behavior = 'bomb_drop') -----
  -- SNKRX player.lua:301 / Bomb:3395 -- every cd seconds the bomber PLANTS an
  -- unstable containment cell at its own position. It detonates the instant a brick
  -- drifts within trigger_radius (proximity mine; the `fuse` is now just a SILENT
  -- cleanup lifetime, no visible countdown). The blast is a big AoE (do_splash)
  -- worth current_dmg*blast_mult over bomb_radius, staged as a ReactorBlast
  -- (implosion -> flash -> shockwaves). Level 3 ("Demoman") DOUBLES blast radius +
  -- damage and adds an aftershock. The bomber ball is a heavy reactor core: SLOW +
  -- dampened, lumbering on drooping arcs, venting plasma (skin = 'bomber').
  bomber      = {r = 7, base_speed = 125, dmg = 10, color = 'orange', behavior = 'bomb_drop', cd = 7, bomb_radius = 60, fuse = 8, trigger_radius = 16, count = 1, blast_mult = 2.0, skin = 'bomber'},

  -- ----- Engineer "Builder" (SNKRX engineer port; behavior = 'turret_drop') -----
  -- SNKRX player.lua:409 / Turret:3196 -- every cd seconds the engineer DEPLOYS a
  -- turret at its own position. Each turret aims at the nearest brick and fires a
  -- BURST of burst_count shots, persisting for `lifetime` then folding up. Level 3
  -- ("Upgrade!!!") drops lvl3_count turrets per deploy and UPGRADES them all (+50%
  -- damage & fire rate). The engineer ball is a steady fabricator drone: medium
  -- speed, mildly dampened, hovering on a gentle bob (skin = 'engineer').
  engineer    = {r = 6, base_speed = 150, dmg = 8, color = 'orange', behavior = 'turret_drop', cd = 8, lifetime = 16, turret_cd = 3.0, burst_count = 3, burst_gap = 0.12, turret_range = 256, turret_mult = 2.0, shot_speed = 220, lvl3_count = 2, skin = 'engineer'},

  -- ----- Force area (behavior = 'force_area') -----
  psykino     = {r = 6, base_speed = 160, dmg = 8, color = 'fg', behavior = 'force_area', range = 128, cd = 4, force_radius = 64, force_strength = 120},

  -- ----- Chain lightning (SNKRX stormweaver port; behavior = 'chain_lightning') -----
  -- SNKRX's stormweaver is a passive that infuses every allied unit so their hits
  -- fork lightning to 2 (+2 at lvl3) nearby enemies (player.lua:308, :2360-2380).
  -- Ball Pit has no allied roster, so this stormweaver INITIATES the arc itself:
  -- every cd it zaps the nearest brick, then the bolt forks onward through the
  -- swarm, each hop a falloff of its damage. links/radius grow at lvl3 like SNKRX.
  -- Movement: a moderate base that ramps FAST + bouncy, on an erratic crackling
  -- zigzag path (see the stormweaver skin blocks + do_chain_lightning).
  stormweaver = {r = 6, base_speed = 150, dmg = 7, color = 'blue', behavior = 'chain_lightning', skin = 'stormweaver',
                 cd = 1.3, range = 122, links = 2, chain_radius = 64, hop_falloff = 0.55,
                 zigzag = 7.0, bounce_scramble = 0.7},

  -- ----- Pet spawns (small allies that fly up and hit bricks) -----
  infestor    = {r = 6, base_speed = 150, dmg = 6,  color = 'orange', behavior = 'pet_spawn', cd = 10, count = 3, pet_speed = 70, pet_dmg = 8},

  -- ----- Gambler-style random multi-strike -----
  gambler     = {r = 6, base_speed = 165, dmg = 8, color = 'yellow2', behavior = 'gambler_burst', cd = 2, burst_count = 3, burst_mult = 3.0},

  -- ----- Volcano (SNKRX vulcanist port; behavior = 'volcano') -----
  -- Every 12s, plants a Volcano at the midpoint between this ball and the
  -- centre of the enemy mass; it erupts a 72px rotated-square blast once a
  -- second 4 times (level 3: every 0.5s, 8 times — Lava Burst), then blinks
  -- out. See Volcano/EruptionArea in effects.lua. skin draws the ball as the
  -- rune-furnace ring instead of a plain ball.
  vulcanist   = {r = 6, base_speed = 150, dmg = 14, color = 'red', behavior = 'volcano', cd = 12, area = 72, volcano_rs = 24, skin = 'rune'},

  -- ----- Cannon (SNKRX cannoneer port; behavior = 'cannon_shot') -----
  -- SNKRX's cannoneer fires at the closest enemy in a 128 sensor every 6s; the
  -- shell flies, then DETONATES into a wide Area for 2x damage (player.lua:326,
  -- :2208-2218), with a level-3 aftershock bombardment. Ported here as a heavy
  -- mortar: fires an exploding cannonball every cd (blast = current_dmg*blast_mult
  -- over blast_radius, +bombard aftershocks at level 3). Slow, dampened, heavy-arc
  -- movement, and the shot RECOILS the ball backward (see shoot_cannonball + skin).
  cannoneer   = {r = 7, base_speed = 132, dmg = 16, color = 'orange', behavior = 'cannon_shot', skin = 'cannon',
                 cd = 2.2, range = 150, ball_speed = 150, blast_radius = 56, blast_mult = 1.7,
                 recoil = 90, bombard = 4},

  -- ----- On-bounce exceptions: ability triggers per ball-bounce, not a timer.
  wizard      = {r = 5, base_speed = 170, dmg = 7,  color = 'blue',   on_bounce = 'chain_lightning', bounce_cd = 0.3},
  cryomancer  = {r = 6, base_speed = 160, dmg = 6,  color = 'blue',   on_bounce = 'slow'},
  pyromancer  = {r = 6, base_speed = 160, dmg = 8,  color = 'red',    on_bounce = 'burn', bounce_cd = 0.4},
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
  -- Paddle-loadout run modifiers (ball/charge/dmg multipliers + signature
  -- tunables), passed explicitly by BallPit:add_hero so they're valid during
  -- reset_run ordering and for clones. See paddles.lua.
  local mods        = self.run_mods or {}
  local s           = BallHero.stats_for(self.character)
  -- Twin Cast halves ability cooldowns. Work on a shallow copy so the shared
  -- HERO_STATS table is never mutated across runs.
  if mods.sig and mods.sig.cd_mult then
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    if copy.cd        then copy.cd        = copy.cd*mods.sig.cd_mult end
    if copy.heal_cd   then copy.heal_cd   = copy.heal_cd*mods.sig.cd_mult end
    if copy.bounce_cd then copy.bounce_cd = copy.bounce_cd*mods.sig.cd_mult end
    s = copy
  end
  -- Ranged auto-attacks fire RANGED_CD_MULT slower across the board (see the
  -- pace-tuning block above HERO_STATS). Same shallow-copy discipline.
  if RANGED_BEHAVIORS[s.behavior] and s.cd then
    local copy = {}
    for k, v in pairs(s) do copy[k] = v end
    copy.cd = copy.cd*RANGED_CD_MULT
    s = copy
  end
  self.stats        = s
  self.r_size       = s.r
  -- Multiple heroes can share the same base color (e.g. wizard/spellblade/
  -- cryomancer are all blue). BallPit:add_hero passes a shade_offset based on
  -- how many same-colored balls were already in play, so the new ball gets a
  -- slightly lighter or darker tint and stays distinguishable.
  local base_color  = character_colors[self.character] or fg[0]
  self.color        = BallHero.shaded(base_color, self.shade_offset or 0)
  self.dmg          = s.dmg * (1 + 0.4*(self.level-1)) * (mods.dmg or 1)
  -- Kept separately for damage paths that bypass self.dmg (pet/turret drops).
  self.run_dmg_mult = mods.dmg or 1
  -- Scale base ball speed by the live arena height (relative to the original
  -- 228px playfield) so balls still cross the arena in a similar bounce
  -- cadence when the canvas is taller. At gh=270 the factor is 1.0 (no
  -- change), so existing tuning is preserved on the default resolution.
  -- The loadout's Ball stat multiplies on top.
  -- BASE_SPEED_MULT is the global slow-launch cut (pace tuning, see top).
  self.base_speed   = s.base_speed * BASE_SPEED_MULT * ((gh - 42)/228) * (mods.ball or 1)
  self.returning      = false  -- ball fell into the pit and is being pulled back to the paddle
  self.stuck          = false  -- ball is glued to the paddle awaiting an aimed launch
  self.stuck_offset_x = 0

  -- Speed-up streak: every successful paddle bounce ramps the ball faster,
  -- so missing the paddle is increasingly painful. Mult resets when the ball
  -- gets stuck after a miss (or on initial launch).
  self.speed_mult       = 1.0
  self.speed_mult_max   = 4.0     -- was 3.0 (orig 2.5)
  -- Per-bounce ramp increment (+50% at baseline — doubled as part of the
  -- slow-launch pace tuning, see BASE_SPEED_MULT at top). The loadout's
  -- Charge stat scales it: Aegis 0.2 -> x1.10/bounce, Pinball 1.8 -> x1.90.
  self.speed_mult_step  = 1 + 0.5*(mods.charge or 1)

  -- ULTRAKILL-style chain counter. Increments on every brick bounce; resets
  -- when the ball is caught by the paddle or falls into the pit. Multiplies
  -- damage through arena:bounce_dmg_mult in Brick:on_ball_contact.
  self.bounces          = 0

  -- Per-ball pierce state. Toggle via :set_piercing(on); never write to
  -- self.piercing directly because the setter also flips the Box2D mask on
  -- this ball's fixture so it physically ignores bricks (true ghost-through,
  -- not a velocity-restore hack). While piercing:
  --   * Ball passes cleanly through bricks — beginContact never fires for
  --     ball-vs-brick so there is no bounce, no stuck-against-brick edge case
  --   * on_brick_hit (and therefore damage / combo / chain_lightning /
  --     big_splash / fire trail) doesn't run because no contact event fires
  -- Cleared when the ball hits the top wall (see BallPit collision callback).
  self.piercing         = false

  -- Charge-on-paddle: while stuck the ball fills a green ring up to
  -- charge_max_time, then blinks red at full. On launch the charge converts
  -- into a temporary speed bonus (up to +100%) and damage bonus (up to +50%)
  -- that lasts until the ball gets stuck again.
  self.charge_time      = 0
  self.charge_max_time  = 2.0
  self.charge_dmg_mult  = 1.0

  -- Crescent-slash skin (swordsman): facing angle (banks into the travel
  -- direction, see update), post-cleave slash-ring timer, and a tiny sampled
  -- position history that draws as fading arc afterimages (draw_crescent).
  if s.skin == 'crescent' then
    self.face_a         = -math.pi/2
    self.cleave_flash_t = 0
    self.cres_trail     = {}
    self.t:every(0.06, function()
      if self.stuck or self.returning or self.mortar then
        self.cres_trail = {}
        return
      end
      table.insert(self.cres_trail, 1, {x = self.x, y = self.y, a = self.face_a})
      if #self.cres_trail > 2 then table.remove(self.cres_trail) end
    end)
  end

  -- Bandit-shuriken skin (scout): spin angle, post-throw flick timer, and a
  -- ninja shadow-trail — recently sampled positions drawn as fading,
  -- shrinking ghost stars behind the body (see draw_shuriken).
  if s.skin == 'shuriken' then
    self.spin_a         = random:float(0, 2*math.pi)
    self.throw_flick_t  = 0
    self.shuriken_trail = {}
    self.t:every(0.045, function()
      if self.stuck or self.returning or self.mortar then
        self.shuriken_trail = {}
        return
      end
      table.insert(self.shuriken_trail, 1, {x = self.x, y = self.y, a = self.spin_a})
      if #self.shuriken_trail > 4 then table.remove(self.shuriken_trail) end
    end)
  end

  -- Crossbow-tower skin (archer): the ball stays as the tower base with a
  -- compact crossbow turret on top. The turret swivels toward the nearest
  -- brick (aim_want sampled on a short timer, smoothed into aim_a in update),
  -- the string cocks back as the 2s cooldown refills, and the whole tower
  -- drags ghost afterimages behind it (see draw_crossbow).
  if s.skin == 'crossbow' then
    self.aim_a         = -math.pi/2
    self.aim_want      = -math.pi/2
    self.bolt_recoil_t = 0
    self.bow_trail     = {}
    self.t:every(0.06, function()
      if self.stuck or self.returning or self.mortar then
        self.bow_trail = {}
        return
      end
      table.insert(self.bow_trail, 1, {x = self.x, y = self.y, a = self.aim_a})
      if #self.bow_trail > 3 then table.remove(self.bow_trail) end
    end)
    -- Retarget on a timer, not every frame, to keep the nearest-brick scan
    -- cheap. While stuck the update forces the turret back to pointing up.
    self.t:every(0.08, function()
      local arena = main.current
      if not arena or self.stuck or self.returning or self.mortar then return end
      local target = arena.get_nearest_brick and arena:get_nearest_brick(self.x, self.y)
      if target then self.aim_want = math.atan2(target.y - self.y, target.x - self.x) end
    end)
  end

  -- Rune-furnace skin (vulcanist): a ring of volcanic stone whose 8 runes
  -- ignite one by one as the 12s volcano timer fills, around a molten pupil
  -- that seethes brighter with charge. ring_a spins lazily (whipped fast for
  -- a beat on each cast — cast_flash_t); a molten afterimage trail — fading,
  -- shrinking ghost rings with the spin angle baked in — drags behind it
  -- (see draw_rune_furnace).
  if s.skin == 'rune' then
    self.ring_a       = random:float(0, 2*math.pi)
    self.cast_flash_t = 0
    self.rune_trail   = {}
    self.t:every(0.05, function()
      if self.stuck or self.returning or self.mortar then
        self.rune_trail = {}
        return
      end
      table.insert(self.rune_trail, 1, {x = self.x, y = self.y, a = self.ring_a})
      if #self.rune_trail > 4 then table.remove(self.rune_trail) end
    end)
  end

  -- Shadowstalker skin (assassin): the inky smoke-clone trail, the breathing
  -- shadow aura and the per-throw strike state. shadow_t is the idle "breathe"
  -- clock (see update/draw); assassin_strike_t + strike_a drive the blink-lunge
  -- cross-slash, armed in shoot_assassin_knife. shadow_trail samples recent
  -- positions for the ghost clones, and each sample peels off a rising wisp.
  if s.skin == 'shadow' then
    self.shadow_t          = random:float(0, 2*math.pi)
    self.assassin_strike_t = 0
    self.strike_a          = -math.pi/2
    self.shadow_trail      = {}
    self.t:every(0.04, function()
      if self.stuck or self.returning or self.mortar then
        self.shadow_trail = {}
        return
      end
      table.insert(self.shadow_trail, 1, {x = self.x, y = self.y})
      if #self.shadow_trail > 6 then table.remove(self.shadow_trail) end
      if random:bool(60) then
        SmokePuff{
          group = main.current.effects,
          x = self.x + random:float(-1.5, 1.5), y = self.y,
          color = Color(self.color.r*0.5, self.color.g*0.4, self.color.b*0.6, 1),
          rs = self.r_size*0.55, alpha = 0.30,
          vx = random:float(-6, 6), vy = random:float(-22, -12),
          duration = random:float(0.4, 0.7),
        }
      end
    end)
  end

  -- Spellblade skin: an arcane core orbited by blade-shards (orbit_a), a slow
  -- arcane pulse (spell_t), and a fire-flash (spell_flash_t) that whips the
  -- shards on each cast. It also sheds a unique arcane-glyph aftertrail --
  -- small spinning glyphs that fade (see ArcaneSpark in effects.lua).
  if s.skin == 'spellblade' then
    self.orbit_a       = random:float(0, 2*math.pi)
    self.spell_t       = random:float(0, 6.28)
    self.spell_flash_t = 0
    self.t:every(0.05, function()
      if self.stuck or self.returning or self.mortar then return end
      ArcaneSpark{
        group = main.current.effects,
        x = self.x + random:float(-1, 1), y = self.y + random:float(-1, 1),
        color = self.color, rs = random:float(2, 3.5),
        alpha = 0.7, spin = random:float(-9, 9),
        duration = random:float(0.3, 0.5),
      }
    end)
  end

  -- Hammer skin (barbarian): the maul head tumbles as it flies -- start each one
  -- at a random angle so multiple barbarians don't spin in lockstep (see update
  -- for the spin, draw_hammer for the body).
  if s.skin == 'hammer' then
    self.hammer_a = random:float(0, 2*math.pi)
  end

  -- Lifebloom skin (cleric): a living flower. bloom_pulse drives the perpetual
  -- breathe-open, bloom_t bursts a full bloom on each cast (do_consecrate),
  -- orbit_a slowly turns the petals + seed crown. It sheds a fine SPORE trail --
  -- tiny particles puffed off and blown outward, fading (see SporeMote).
  if s.skin == 'lifebloom' then
    self.orbit_a     = random:float(0, 2*math.pi)
    self.bloom_t     = 0
    self.bloom_pulse = random:float(0, 6.28)
    self.t:every(0.06, function()
      if self.stuck or self.returning or self.mortar then return end
      for _ = 1, 2 do
        local ang = random:float(0, 2*math.pi)
        local sp  = random:float(10, 42)
        SporeMote{
          group = main.current.effects,
          x = self.x + random:float(-2, 2), y = self.y + random:float(-2, 2),
          color = self.color, vx = math.cos(ang)*sp, vy = math.sin(ang)*sp,
          rs = random:float(0.8, 1.7), alpha = random:float(0.45, 0.8),
          duration = random:float(0.4, 0.8),
        }
      end
    end)
  end

  -- Jester "Harlequin" skin: a bouncy motley orb in a spinning diamond-checker,
  -- crowned with a two-horned fool's cap whose bell tips wobble as it weaves. It
  -- sheds a steady drizzle of confetti (its trail) and a shimmering two-tone aura.
  --   jester_t        idle clock (bob + aura shimmer)
  --   cap_sway/_v     a damped pendulum so the bells lag the body's motion + jingle
  --   jester_weave_*  bends the flight path into a chaotic weave (see update)
  --   jester_cast_t   cap/body flash for a beat after each hex cast
  --   checker_a       slow spin of the harlequin motif
  --   jester_trail    sampled positions drawn as fading ghost-orbs
  if s.skin == 'jester' then
    self.jester_t            = random:float(0, 2*math.pi)
    self.cap_sway            = 0
    self.cap_sway_v          = 0
    self.jester_weave_base   = 3.0
    self.jester_weave_amp    = self.jester_weave_base
    self.jester_weave_t      = random:float(0, 2*math.pi)
    self.jester_cast_t       = 0
    self.checker_a           = random:float(0, 2*math.pi)
    self._jester_last_bounces = 0
    self.jester_trail        = {}
    self.t:every(0.05, function()
      if self.stuck or self.returning or self.mortar then
        self.jester_trail = {}
        return
      end
      table.insert(self.jester_trail, 1, {x = self.x, y = self.y})
      if #self.jester_trail > 5 then table.remove(self.jester_trail) end
      if random:bool(45) then
        JesterMote{group = main.current.effects, x = self.x + random:float(-2, 2), y = self.y,
                   color = self.color, vx = random:float(-20, 20), vy = random:float(-30, -6),
                   rs = random:float(1.0, 2.0), alpha = random:float(0.4, 0.7)}
      end
    end)
  end

  -- Bomber "Reactor Core" skin: a dark vented casing around a molten plasma core,
  -- with glowing vent seams that rotate and energy arcs crackling off the shell. It
  -- lumbers along venting heat-haze + plasma sparks; the core swells brighter as the
  -- next charge nears, then sinks in a recoil-squash on each plant.
  --   bomber_t        idle clock (core pulse + seam rotation + breathe)
  --   bomber_recoil_t downward recoil-squash for a beat after laying a charge
  --   bomber_fuse_t   counts toward stats.cd so the core telegraphs the next plant
  --   bomber_gravity  the downward "weight" lean that droops its arcs (see update)
  if s.skin == 'bomber' then
    self.bomber_t        = random:float(0, 2*math.pi)
    self.bomber_recoil_t = 0
    self.bomber_fuse_t   = 0
    self.bomber_gravity  = 25
    -- Dampened + heavy: it builds bounce-speed slowly and caps low, so it lumbers
    -- instead of pinballing (the opposite of the jester's fast, bouncy ramp).
    self.speed_mult_step = 1 + 0.22*(mods.charge or 1)
    self.speed_mult_max  = 2.4
    self.t:every(0.06, function()
      if self.stuck or self.returning or self.mortar then return end
      -- Heat-haze venting off the core.
      SmokePuff{group = main.current.effects, x = self.x + random:float(-2, 2), y = self.y - self.r_size*0.4,
                color = Color(self.color.r, self.color.g*0.7, self.color.b*0.4, 1), rs = random:float(1.2, 2.2),
                alpha = random:float(0.16, 0.30), vx = random:float(-10, 10), vy = random:float(-22, -10),
                duration = random:float(0.35, 0.6)}
      -- ...and the occasional brighter plasma spark.
      if random:bool(30) then
        SmokePuff{group = main.current.effects, x = self.x + random:float(-1, 1), y = self.y,
                  color = Color(yellow[0].r, yellow[0].g, yellow[0].b, 1), rs = random:float(0.7, 1.3),
                  alpha = random:float(0.5, 0.8), vx = random:float(-14, 14), vy = random:float(-24, -12),
                  duration = random:float(0.2, 0.4)}
      end
    end)
  end

  -- Engineer "Builder" skin: a fabricator drone -- a dark gear-core ringed with cog
  -- teeth that rotate, a glowing sensor "eye" lens that scans, and a mechanical glow.
  -- It hovers steadily, showering welding sparks, and spins up + flashes on each
  -- turret deploy.
  --   eng_t        idle clock (eye scan-pulse + aura breathe)
  --   eng_gear_a   cog-ring rotation (whips fast on a deploy)
  --   eng_deploy_t fabrication flash + recoil for a beat after deploying
  if s.skin == 'engineer' then
    self.eng_t        = random:float(0, 2*math.pi)
    self.eng_gear_a   = random:float(0, 2*math.pi)
    self.eng_deploy_t = 0
    -- Mildly dampened + steady (between the normal ramp and the bomber's heavy one).
    self.speed_mult_step = 1 + 0.35*(mods.charge or 1)
    self.speed_mult_max  = 3.0
    self.t:every(0.05, function()
      if self.stuck or self.returning or self.mortar then return end
      -- Grinding/welding sparks that shower off and fall.
      if random:bool(55) then
        SmokePuff{group = main.current.effects, x = self.x + random:float(-2, 2), y = self.y + random:float(-1, 2),
                  color = Color(yellow[0].r, yellow[0].g, yellow[0].b, 1), rs = random:float(0.6, 1.2),
                  alpha = random:float(0.5, 0.85), vx = random:float(-22, 22), vy = random:float(6, 28),
                  duration = random:float(0.22, 0.45)}
      end
    end)
  end

  -- Stormweaver "Tempest" skin: a ball of caged lightning. A white-hot nucleus
  -- inside the electric body, ringed by jagged arc-spokes that crackle (rebuilt
  -- on a timer so they writhe even at rest), a breathing static aura, and two
  -- electron sparks orbiting the core. On a discharge the core flares white and
  -- the spokes whip out (cast_flash_t).
  --   storm_t        idle clock (core pulse + aura breathe + orbit)
  --   arc_phase      slow rotation of the spoke ring
  --   cast_flash_t   core/spoke flare for a beat after each chain discharge
  --   storm_bolts    the jagged rim spokes, regenerated every tick to crackle
  -- It sheds a flickering StormSpark trail and rides a fast, bouncy, ERRATIC
  -- path: a slow-burn base that charges up hard on each bounce (the opposite of
  -- the bomber's dampened lumber), wobbling along a crackling zigzag.
  if s.skin == 'stormweaver' then
    self.storm_t             = random:float(0, 2*math.pi)
    self.arc_phase           = random:float(0, 2*math.pi)
    self.cast_flash_t        = 0
    self._storm_last_bounces = 0
    self.storm_bolts         = {}
    self.speed_mult_step = 1 + 0.7*(mods.charge or 1)   -- builds bounce-speed fast (zippy)
    self.speed_mult_max  = 4.2                           -- ...and uncaps high
    self.t:every(0.05, function()
      self:gen_storm_bolts()
      if self.stuck or self.returning or self.mortar then return end
      -- Trail/emission: a crackling spark sloughs off the body while it travels.
      local a = random:float(0, 2*math.pi)
      StormSpark{group = main.current.effects, x = self.x + random:float(-1, 1), y = self.y + random:float(-1, 1),
                 color = self.color, vx = math.cos(a)*random:float(8, 26), vy = math.sin(a)*random:float(8, 26),
                 alpha = random:float(0.4, 0.7)}
    end)
  end

  -- Cannon "Siege Mortar" skin: the ball as a heavy artillery piece. An iron base
  -- (the body) carries a thick barrel that swivels toward the nearest brick, recoils
  -- on each shot, and glows a reload ember at the muzzle that brightens as the cd
  -- fills. A heat-haze aura + a steady gunsmoke drizzle round it out.
  --   aim_a / aim_want    barrel angle (smoothed in update toward the sampled target)
  --   cannon_recoil_t     barrel kick + muzzle flash for a beat after firing
  --   cannon_t            idle clock (heat shimmer)
  --   cannon_gravity      heavy-lob droop added to its arcs (see active-motion)
  -- Movement: slow + dampened (builds bounce-speed slower than the bomber, caps low)
  -- and the shot recoils it backward -- a ponderous siege engine.
  if s.skin == 'cannon' then
    self.aim_a           = -math.pi/2
    self.aim_want        = -math.pi/2
    self.cannon_recoil_t = 0
    self.cannon_t        = random:float(0, 2*math.pi)
    self.cannon_gravity  = 32
    self.speed_mult_step = 1 + 0.18*(mods.charge or 1)
    self.speed_mult_max  = 2.2
    -- Retarget the barrel on a timer (cheap), like the crossbow turret.
    self.t:every(0.08, function()
      local arena = main.current
      if not arena or self.stuck or self.returning or self.mortar then return end
      local target = arena.get_nearest_brick and arena:get_nearest_brick(self.x, self.y)
      if target then self.aim_want = math.atan2(target.y - self.y, target.x - self.x) end
    end)
    -- Idle gunsmoke drizzle off the barrel.
    self.t:every(0.07, function()
      if self.stuck or self.returning or self.mortar then return end
      SmokePuff{group = main.current.effects, x = self.x + random:float(-2, 2), y = self.y - self.r_size*0.4,
                color = Color(0.30, 0.28, 0.26, 1), rs = random:float(1.2, 2.2), alpha = random:float(0.12, 0.22),
                vx = random:float(-6, 6), vy = random:float(-18, -6), duration = random:float(0.4, 0.7)}
    end)
  end

  self:set_as_circle(self.r_size, 'dynamic', 'ball')
  self.body:setBullet(true)
  self:set_fixed_rotation(true)
  self:set_restitution(1)
  self:set_friction(0)
  self:set_damping(0)
  self:set_angular_damping(0)
  self:set_mass(0.5)

  -- Pinball Lobber physics: balls obey gravity and travel slowly so they're
  -- easy to flip; low restitution + some friction makes them settle and roll
  -- off the flippers instead of pinging. (Bricks/walls keep their own higher
  -- restitution, so bricks still read as bumpers.) See pinball_update.
  if self:is_pinball() then
    local g = mods.sig or {}
    self.pb_gravity   = g.gravity   or 170
    self.pb_speed_cap = g.speed_cap or 620
    self:set_restitution(g.restitution or 0.12)
    self:set_friction(0.5)
    -- Real rolling: let the ball spin so it ROLLS down the angled bats toward
    -- the drain instead of statically sticking (a fixed-rotation ball sticks
    -- once surface friction exceeds the bat's slope).
    self:set_fixed_rotation(false)
  end

  -- Per-bounce ability cooldown for the on-bounce exceptions that need it
  -- (wizard, pyromancer). Used to limit fire rate when bouncing rapidly.
  self.ability_ready = true
  if s.bounce_cd then
    self.t:every(s.bounce_cd, function() self.ability_ready = true end)
  end

  -- Continuous timer-based attacks for the 12 non-exception heroes.
  self:setup_continuous_attack()

  -- Terrorist loadout: every ball self-detonates on a fuse, blasting its own
  -- element around it, then re-forms at the paddle (see terror_detonate).
  if mods.sig and mods.sig.fuse then
    self.t:every(mods.sig.fuse, function() self:terror_detonate() end)
  end

  -- Drop afterimage trail particles while the ball is moving above the
  -- speed-streak threshold. Empty/no-op otherwise.
  self.t:every(0.035, function() self:maybe_spawn_trail() end)

  -- Auto-launch on next frame.
  self.t:after(0, function() self:launch_from_paddle() end)
end


-- Toggle the ghost-through-bricks pierce mode on this specific ball. The
-- mask filter is read from the group's collision_tags at every call so it
-- stays correct even after the fixture is rebuilt by the big_ball powerup.
-- Idempotent: safe to call repeatedly with the same value.
function BallHero:set_piercing(on)
  on = on and true or false
  self.piercing = on
  if not (self.fixture and self.group) then return end
  local ball_tag  = self.group.collision_tags and self.group.collision_tags['ball']
  local brick_tag = self.group.collision_tags and self.group.collision_tags['brick']
  if not (ball_tag and brick_tag) then return end
  local normal = ball_tag.masks or {}
  if on then
    -- Add brick's category to this fixture's mask so Box2D filters out the
    -- ball-vs-brick contact entirely. The ball still collides with walls and
    -- the paddle normally because their categories aren't in the mask.
    self.fixture:setMask(brick_tag.category, unpack(normal))
  else
    -- Restore the default ball-tag mask (which still excludes ball-vs-ball).
    self.fixture:setMask(unpack(normal))
  end
end


function BallHero:maybe_spawn_trail()
  if self.stuck or self.returning or self.mortar then return end
  local mult = self.speed_mult or 1
  if mult < 1.3 then return end

  local fx = main.current.effects

  -- Tier 1 (always while mult >= 1.3): the regular colored aftershadow. Size,
  -- alpha and lifespan all scale with speed so 4× balls smear more visibly
  -- than 1.5× ones, but the hero's own colour stays readable.
  local base_rs       = self.r_size  * math.clamp(math.remap(mult, 1.3, 4.0, 0.85, 1.25), 0.85, 1.25)
  local base_alpha    = math.clamp(math.remap(mult, 1.3, 4.0, 0.35, 0.85), 0.35, 0.85)
  local base_duration = math.clamp(math.remap(mult, 1.3, 4.0, 0.22, 0.4),  0.22, 0.4)
  BallTrail{group = fx, x = self.x, y = self.y, color = self.color,
            rs = base_rs, alpha = base_alpha, duration = base_duration}

  -- Tier 2 (mult >= 2.5): NEON OVERDRIVE. A white-hot core particle sits on
  -- top of the coloured trail so the ball looks like it's burning through
  -- the arena. Core grows + brightens as the streak climbs toward the cap.
  if mult >= 2.5 then
    local neon = math.clamp(math.remap(mult, 2.5, 4.0, 0, 1), 0, 1)
    BallTrail{group = fx, x = self.x, y = self.y, color = Color(1, 1, 1, 1),
              rs = self.r_size*(0.45 + neon*0.45),
              alpha = 0.55 + neon*0.4,
              duration = 0.18 + neon*0.22}

    -- Tier 3 (mult >= ~3.25): saturated outer glow. We boost the hero's
    -- colour toward fully saturated to keep some identity instead of going
    -- pure white. Lingers longer than the core so it reads as an aftershadow.
    if neon > 0.5 then
      local c = self.color
      local glow = Color(
        math.min(1, c.r*1.8 + 0.2),
        math.min(1, c.g*1.8 + 0.2),
        math.min(1, c.b*1.8 + 0.2),
        1)
      BallTrail{group = fx, x = self.x, y = self.y, color = glow,
                rs = self.r_size*(1.0 + neon*0.6),
                alpha = 0.45*neon,
                duration = 0.32 + neon*0.3}
    end
  end
end


-- True for balls in a Pinball Lobber run — they use a different physics model
-- (gravity + a slow speed cap, they roll off the flippers, and they are
-- re-served from above on a drain instead of caught). See pinball_update /
-- pinball_serve and Paddle:flip_launch.
function BallHero:is_pinball()
  return self.run_mods and self.run_mods.signature == 'flippers'
end


-- Pinball Lobber per-frame physics: gravity pulls the ball down toward the
-- flippers and a soft speed cap keeps it slow and catchable. Used in place of
-- normalize_speed (which would force a constant speed and fight gravity).
function BallHero:pinball_update(dt)
  local vx, vy = self:get_velocity()
  if not vx then return end
  vy = vy + (self.pb_gravity or 170)*dt
  local cap = self.pb_speed_cap or 620
  local sp  = math.sqrt(vx*vx + vy*vy)
  if sp > cap then local k = cap/sp; vx, vy = vx*k, vy*k; sp = cap end
  self:set_velocity(vx, vy)
  -- Drive the speed-streak visuals off the ball's real speed, so a hard,
  -- well-placed flip glows and a slow drifting ball stays plain.
  self.speed_mult = math.clamp(sp/150, 1, self.speed_mult_max or 4)
end


-- The Lobber never catches a ball. A drained (or freshly-added) ball is
-- re-served by being DROPPED in from above the paddle, so the flippers have to
-- knock it back into play — there is no stick / aim / charge step.
function BallHero:pinball_serve()
  local arena = main.current
  if not (arena and arena.paddle) then return end
  self.returning       = false
  self.stuck           = false
  self.serving         = true   -- hand off to update_serving (a dragged respawn)
  self.speed_mult      = 1.0
  self.charge_dmg_mult = 1.0
  self.bounces         = 0
  if self.body then self.body:setActive(true) end
  self:set_piercing(arena.pierce_active == true)
  self.serve_off_x = random:float(-34, 34)
  self.serve_y     = math.clamp(arena.paddle.y - 200,
                                arena.y1 + self.r_size + 2, arena.paddle.y - 60)
  pop1:play{volume = 0.25, pitch = random:float(0.95, 1.1)}
end


-- Drag a drained ball back into play instead of teleporting it: a homing
-- "tractor" hauls it from the pit up to a serve point above the paddle, then
-- releases it into free-fall for the flippers to deal with. The target tracks
-- the paddle, so it always arrives above the current flipper position.
function BallHero:update_serving(dt)
  local arena = main.current
  if not (arena and arena.paddle) then return end
  local tx = math.clamp(arena.paddle.x + (self.serve_off_x or 0),
                        arena.x1 + self.r_size + 2, arena.x2 - self.r_size - 2)
  local ty = self.serve_y or (arena.paddle.y - 200)
  local dx, dy = tx - self.x, ty - self.y
  local d = math.sqrt(dx*dx + dy*dy)
  if d < 5 then
    self.serving = false
    self:set_velocity(random:float(-24, 24), 30)   -- let go into gravity
    self.spring:pull(0.2)
    return
  end
  local pull = math.min(820, 140 + d*4)
  self:set_velocity(dx/d*pull, dy/d*pull)
end


function BallHero:launch_from_paddle()
  local arena = main.current
  if not arena or not arena.paddle then return end
  -- Pinball Lobber: served from above the flippers, never launched off the paddle.
  if self:is_pinball() then self:pinball_serve() return end
  -- Mitosis daughter cell: it grew in at its parent's position, so don't yank
  -- it to the paddle — leave it where mitosis_on_kill placed it (one-shot flag).
  if self.mitosis_spawned then self.mitosis_spawned = nil; return end
  local px = arena.paddle.x
  local py = arena.paddle.y - arena.paddle.h/2 - self.r_size - 1
  self:set_position(px, py)
  self.speed_mult = 1.0
  self.bounces    = 0
  -- Inherit pierce from the active buff for this fresh launch.
  self:set_piercing(arena.pierce_active == true)
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


-- SNKRX assassin port (player.lua:587 + :2356). Every cd seconds with a brick
-- in the sensor, hurl a pierce-1000 knife at the CLOSEST one; on hit it makes
-- the target BLEED for bleed_dur seconds (dmg/2 normally, 4x dmg on a crit).
-- The rogue "assassination" crit (crit_chance%, +10% per level) also doubles
-- the strike's direct damage. The Shadowstalker juice is armed inside
-- shoot_assassin_knife. NOTE: this behavior is deliberately NOT in
-- RANGED_BEHAVIORS -- its cd is already the SNKRX 2s, and it applies the ranged
-- damage multiplier itself (via PROJECTILE_DMG_MULT in shoot_assassin_knife).
BEHAVIORS.assassinate = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    local crit_chance = (s.crit_chance or 25) + 10*(self.level - 1)
    local crit        = random:bool(crit_chance)
    local bleed_total = (crit and 4 or 0.5)*self:current_dmg()
    self:shoot_assassin_knife(s, crit, bleed_total)
  end, 0, nil, 'attack')
end


-- SNKRX scout port: throw a knife at the closest brick in range that chains
-- between random nearby targets (see Projectile:on_hit_brick). Level 3
-- doubles the chain count and adds the per-hop damage ramp.
BEHAVIORS.chain_knife = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    local extra = {
      chain          = (self.level >= 3) and 6 or (s.chain or 3),
      chain_dmg_ramp = (self.level >= 3) or nil,
    }
    self:shoot_knife(s.range, s.speed or 240, extra)
    self.throw_flick_t = 0.3   -- flicks the shuriken spin (see update/draw)
  end, 0, nil, 'attack')
end


-- SNKRX archer port: every cd seconds with a brick inside the sensor, loose
-- a bolt at the CLOSEST one with infinite pierce (see BallHero:shoot_bolt and
-- the wall_stick handling in projectile.lua). bolt_recoil_t drives the
-- turret kick + string snap in draw_crossbow.
BEHAVIORS.crossbow = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    self.bolt_recoil_t = 0.22
    self.spring:pull(0.2)
    self:shoot_bolt(s)
  end, 0, nil, 'attack')
end


-- SNKRX vulcanist port: every cd seconds, plant a Volcano at the midpoint
-- between this ball and the centre of the enemy mass (see cast_volcano).
-- SNKRX runs this on a plain 12s loop with no enemy gate; the cooldown's
-- active-check just stops a cast being wasted while the ball sits stuck on
-- the paddle — it fires the moment the ball is live again.
BEHAVIORS.volcano = function(self, s)
  self.t:cooldown(s.cd, function() return not (self.stuck or self.returning or self.mortar) end, function()
    self:cast_volcano(s)
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
        dmg    = self:current_dmg()*3.5*RANGED_DMG_MULT,
      }
    end)
    archer1:play{volume = 0.2, pitch = random:float(0.95, 1.05)}
  end, 0, nil, 'attack')
end


-- SNKRX spellblade port (player.lua:400 + :2013). Constant stream of spiraling,
-- all-piercing blade-shards fired in random directions -- a perpetual blade
-- nova. NOT in RANGED_BEHAVIORS: its tiny cd is the whole point, and it applies
-- its own (small) damage multiplier in shoot_blade. range = 9999 means it fires
-- whenever any brick is on the field; spell_flash_t whips the orbiting shards.
BEHAVIORS.blade_storm = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    self:shoot_blade(s)
    if self.stats.skin == 'spellblade' then self.spell_flash_t = 0.15 end
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


-- SNKRX swordsman port: every cd seconds with a brick in range, Cleave — a
-- rotated-square strike whose damage grows +15% per target hit (see
-- CleaveArea in effects.lua and BallHero:do_cleave below).
BEHAVIORS.cleave = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    self:do_cleave(s)
  end, 0, nil, 'attack')
end


-- The barbarian's Hammer Slam: the swordsman's Cleave logic, but bigger, slower
-- and reshaped as a hexagon shockwave (see BallHero:do_hammer_slam below).
BEHAVIORS.hammer_slam = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    self:do_hammer_slam(s)
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
    -- Routed through heal_hearts so the Vampire bar (1 heart = 20 units)
    -- and the normal heart counter share one code path.
    local healed = arena.heal_hearts and arena:heal_hearts(s.heal_amt) or 0
    if healed > 0 then
      heal1:play{volume = 0.35, pitch = random:float(0.95, 1.05)}
      FloatingText{group = arena.effects, x = self.x, y = self.y - 8,
        text = '+' .. s.heal_amt .. ' HP', color = green[0]}
    end
  end, 0, nil, 'heal')
end


-- Cleric rework: every cd seconds, plant a Consecrated Ground sigil at the
-- paddle -- a verdant zone that regenerates the player while the paddle sits in
-- it and burns bricks caught inside (see do_consecrate + ConsecratedGround in
-- effects.lua). Runs on a plain timer (a heal zone needs no target); skips while
-- the ball is stuck/returning so a fresh-launched cleric doesn't waste a cast.
BEHAVIORS.consecrate = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    self:do_consecrate(s)
  end, 0, nil, 'heal')
end


-- Plant the cleric's Consecrated Ground sigil at the paddle. The sigil owns the
-- regen + holy-damage ticks (see effects.lua); dmg is read live so charge / ally
-- buffs / loadout Dmg all apply to the holy burn. Also blooms the body (bloom_t).
function BallHero:do_consecrate(s)
  if self.stuck or self.returning or self.mortar then return end
  local arena = main.current
  if not (arena and arena.floor and arena.paddle) then return end
  self.bloom_t = 1.0   -- triggers the full flower-bloom burst (see draw_lifebloom)
  local rs = s.ground_rs or 64

  if random:bool(50) then
    -- Heal half: a pink flower planted at the paddle (paddle side of the red
    -- defense line) that regenerates HP while the paddle sits in it. Lives in
    -- the FLOOR layer so the paddle / balls draw on top of it.
    ConsecratedGround{
      group = arena.floor, x = arena.paddle.x, y = arena.paddle.y,
      rs = rs, duration = s.ground_duration or 6, heal_interval = s.heal_interval or 2.0,
      mode = 'heal', color = self.color, dmg = self:current_dmg()*(s.holy_mult or 0.6),
    }
  else
    -- Damage half: a red flower planted among the enemies (enemy side of the
    -- red line); its spinning blades deal damage. Drawn in effects so the red
    -- bloom reads clearly on top of the swarm.
    local line_y = (arena.breach_line_y and arena:breach_line_y()) or (arena.y1 + (arena.y2 - arena.y1)*0.5)
    local b  = arena.get_random_brick_within and arena:get_random_brick_within((arena.x1 + arena.x2)/2, (arena.y1 + line_y)/2, 9999)
    local tx = b and b.x or random:float(arena.x1 + rs, arena.x2 - rs)
    local ty = b and b.y or random:float(arena.y1 + rs, line_y - rs)
    ty = math.clamp(ty, arena.y1 + rs*0.5, line_y - rs*0.5)
    ConsecratedGround{
      group = arena.effects, x = tx, y = ty,
      rs = rs, duration = s.ground_duration or 6,
      mode = 'damage', color = self.color, dmg = self:current_dmg()*(s.blade_mult or 1.5),
    }
  end
  heal1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
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


-- Jester "Pandemonium" (SNKRX jester port; player.lua:525). Every s.cd seconds,
-- gated by a brick inside the s.range attack sensor (can_attack), HEX up to
-- s.curse_targets bricks inside the s.curse_radius wide sensor. The hex is a pure
-- mark -- it deals no damage on its own; a hexed brick that dies bursts into a
-- cross of 4 knives (see Brick:die / Brick:apply_jester_curse). At level 3 those
-- knives home + pierce twice, so kills chain. The knife damage is baked in here
-- as current_dmg * knife_mult so the explosion (in brick.lua) needs no hero ref.
BEHAVIORS.pandemonium = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    if self.stuck or self.returning then return end
    local arena  = main.current
    local bricks = arena:get_bricks_within(self.x, self.y, s.curse_radius or 128)
    table.shuffle(bricks)
    local n = math.min(s.curse_targets or 6, #bricks)
    if n <= 0 then return end
    local lvl3 = self.level >= 3
    local kdmg = self:current_dmg() * (s.knife_mult or 2.5)
    for i = 1, n do
      local b = bricks[i]
      if b.apply_jester_curse then
        b:apply_jester_curse(kdmg, s.curse_duration or 6, lvl3, self.color)
        arena_zap_line(arena, self.x, self.y, b.x, b.y, self.color)
      end
    end
    -- Cast juice: a mischievous squash, a chaotic weave flourish, a cap-flash and
    -- a ring of confetti so the hex reads as a gleeful flourish.
    self.spring:pull(0.45)
    self.jester_cast_t    = 0.3
    self.jester_weave_amp = (self.jester_weave_base or 3.0)*3
    for _ = 1, 14 do
      JesterMote{group = arena.effects, x = self.x, y = self.y, color = self.color,
                 vx = random:float(-70, 70), vy = random:float(-80, 20)}
    end
    buff1:play{volume = 0.35, pitch = random:float(0.95, 1.1)}
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


-- Bomber "Demoman" (SNKRX bomber port; player.lua:301 -> Bomb:3395). Every s.cd
-- seconds the bomber PLANTS a bomb at its own position (count of them, staggered
-- along its path). Each bomb detonates when a brick drifts within trigger_radius
-- or after its fuse, for a big AoE blast. Level 3 ("Demoman") doubles blast radius
-- + damage and the BombDrop adds a second aftershock. Damage is baked here as
-- current_dmg * blast_mult so the planted bomb needs no hero reference.
BEHAVIORS.bomb_drop = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    local lvl3  = self.level >= 3
    local count = s.count or 1
    for i = 1, count do
      arena.t:after((i-1)*0.15, function()
        if not (arena.main and arena.main.world) then return end
        local rad = (s.bomb_radius or 60) * (lvl3 and 2 or 1)
        local dmg = self:current_dmg() * (s.blast_mult or 2) * (lvl3 and 2 or 1)
        BombDrop{group = arena.effects, x = self.x, y = self.y, color = self.color,
                 dmg = dmg, radius = rad, fuse = s.fuse or 6,
                 trigger_radius = s.trigger_radius or 16, lvl3 = lvl3}
      end)
    end
    -- Cast juice: a heavy recoil as it expels the charge + a burst of plasma sparks;
    -- the core telegraph resets so it dims then re-swells toward the next plant.
    self.spring:pull(0.5)
    self.bomber_recoil_t = 0.32
    self.bomber_fuse_t   = 0
    for _ = 1, 7 do
      SmokePuff{group = arena.effects, x = self.x + random:float(-3, 3), y = self.y,
                color = Color(self.color.r, self.color.g, self.color.b, 1), rs = random:float(1.4, 2.8), alpha = 0.6,
                vx = random:float(-26, 26), vy = random:float(-26, -4), duration = random:float(0.3, 0.6)}
    end
    mine1:play{volume = 0.3, pitch = random:float(0.9, 1.0)}
  end, 0, nil, 'attack')
end


-- Engineer "Builder" (SNKRX engineer port; player.lua:409 -> Turret:3196). Every
-- s.cd seconds the engineer DEPLOYS turret(s) at its own position (a roaming
-- fabricator). Each turret aims at the nearest brick and fires bursts (see
-- AllyTurret). Level 3 ("Upgrade!!!") drops lvl3_count turrets per deploy and they
-- come pre-upgraded (+50% damage baked in here, +50% fire rate inside the turret).
BEHAVIORS.turret_drop = function(self, s)
  self.t:every(s.cd, function()
    if self.stuck or self.returning then return end
    local arena = main.current
    if not (arena and arena.main and arena.main.world) then return end
    local lvl3  = self.level >= 3
    local count = lvl3 and (s.lvl3_count or 2) or 1
    local tdmg  = self:current_dmg() * (s.turret_mult or 2.0) * (lvl3 and 1.5 or 1)
    for i = 1, count do
      local ox = (count > 1) and (i - (count + 1)/2)*18 or 0
      local px = math.clamp(self.x + ox, arena.x1 + 8, arena.x2 - 8)
      local py = math.clamp(self.y, arena.y1 + 10, arena.y2 - 24)
      AllyTurret{group = arena.effects, x = px, y = py, color = self.color,
                 lifetime = s.lifetime, burst_cd = s.turret_cd, burst_count = s.burst_count,
                 burst_gap = s.burst_gap, range = s.turret_range, dmg = tdmg,
                 shot_speed = s.shot_speed, upgraded = lvl3}
    end
    -- Deploy juice: a fabrication recoil + a spray of welding sparks.
    self.spring:pull(0.4)
    self.eng_deploy_t = 0.3
    for _ = 1, 6 do
      SmokePuff{group = arena.effects, x = self.x + random:float(-3, 3), y = self.y,
                color = Color(yellow[0].r, yellow[0].g, yellow[0].b, 1), rs = random:float(0.8, 1.6),
                alpha = 0.7, vx = random:float(-26, 26), vy = random:float(-6, 26), duration = random:float(0.25, 0.5)}
    end
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


-- Stormweaver chain lightning. Direct port of SNKRX's chain_infuse arc
-- (assets_from_SNKRX/player.lua:2370-2379): a strike forks to N nearby enemies,
-- each link drawn as a jagged bolt. SNKRX runs it as a passive infusing every
-- ally's hits; with no ally roster here, the stormweaver INITIATES -- it zaps the
-- nearest brick for full damage, then the bolt forks onward through the swarm.
-- links = base (+2 at lvl3) and radius doubles at lvl3 (mirrors SNKRX 64->128).
-- Hop damage uses a falloff of the ball's own damage instead of SNKRX's flat
-- 0.2x (there it piled onto a real hit; here the arc IS the attack). Each link
-- also briefly slows the brick -- an electric stun.
function BallHero:do_chain_lightning(s)
  if self.stuck or self.returning then return end
  local arena = main.current
  if not arena then return end
  local first = arena:get_nearest_brick_within(self.x, self.y, s.range or 122)
  if not first then return end

  local lvl3    = (self.level or 1) >= 3
  local links   = (s.links or 2) + (lvl3 and 2 or 0)
  local radius  = (s.chain_radius or 64)*(lvl3 and 2 or 1)
  local falloff = s.hop_falloff or 0.55
  local dmg     = self:current_dmg()
  local hit     = { [first.id] = true }

  -- Primary strike: full damage + a bolt from the ball to the first brick.
  first:take_damage(dmg, self.color)
  if first.apply_slow then first:apply_slow(0.6, 0.6) end
  LightningArc{group = arena.effects, x = self.x, y = self.y,
               x1 = self.x, y1 = self.y, x2 = first.x, y2 = first.y, color = self.color}

  -- Fork onward through the swarm (SNKRX player.lua:2370-2379).
  local src, hop_dmg = first, dmg
  for _ = 1, links do
    -- A random in-range brick we haven't struck yet this discharge
    -- (== SNKRX get_random_object_in_shape(..., infused_enemies_hit)).
    local pool, cands = arena:get_bricks_within(src.x, src.y, radius), {}
    for _, b in ipairs(pool) do if not hit[b.id] then cands[#cands + 1] = b end end
    if #cands == 0 then break end
    local dst = cands[random:int(1, #cands)]
    hit[dst.id] = true
    hop_dmg = hop_dmg*falloff
    dst:take_damage(hop_dmg, self.color)
    if dst.apply_slow then dst:apply_slow(0.6, 0.6) end
    LightningArc{group = arena.effects, x = src.x, y = src.y,
                 x1 = src.x, y1 = src.y, x2 = dst.x, y2 = dst.y, color = self.color}
    src = dst
  end

  -- Cast feedback: flare the body, pop the spring, discharge ring + crackle + thunder.
  self.cast_flash_t = 0.22
  self.spring:pull(0.16)
  TelegraphRing{group = arena.effects, x = self.x, y = self.y, radius = (s.range or 122)*0.5,
                color = self.color, duration = 0.18}
  for _ = 1, 5 do
    local a = random:float(0, 2*math.pi)
    StormSpark{group = arena.effects, x = self.x, y = self.y, color = self.color,
               vx = math.cos(a)*random:float(40, 110), vy = math.sin(a)*random:float(40, 110)}
  end
  thunder1:play{volume = 0.3, pitch = random:float(0.95, 1.1)}
end


BEHAVIORS.chain_lightning = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    self:do_chain_lightning(s)
  end, 0, nil, 'attack')
end


BEHAVIORS.cannon_shot = function(self, s)
  self.t:cooldown(s.cd, function() return self:can_attack(s.range) end, function()
    self:shoot_cannonball(s)
  end, 0, nil, 'attack')
end


-- Fire a heavy exploding cannonball at the nearest brick (SNKRX cannoneer,
-- player.lua:326). The shell flies slowly and DETONATES into a wide splash on
-- impact (the explosion lives in projectile.lua's cannon_explode). Firing kicks
-- the barrel into recoil, belches a muzzle flash + smoke, and shoves the BALL
-- backward along its heading -- a real cannon recoil that nudges its path.
function BallHero:shoot_cannonball(s)
  if self.stuck or self.returning then return end
  local arena  = main.current
  if not arena then return end
  local target = arena:get_nearest_brick_within(self.x, self.y, s.range or 150)
  if not target then return end

  local hx, hy = self.x, self.y
  local ang    = math.atan2(target.y - hy, target.x - hx)
  self.aim_want = ang   -- snap the barrel onto the shot
  -- Blast damage read live so charge / ally / loadout buffs apply per shell.
  local dmg     = self:current_dmg()*(s.blast_mult or 1.7)
  local bombard = ((self.level or 1) >= 3) and (s.bombard or 4) or 0
  local color   = self.color
  -- Box2D world is locked during collision callbacks; spawn the shell next frame.
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      Projectile{
        group        = arena.main,
        x = hx, y = hy, r = ang,
        type         = 'cannonball',
        dmg          = dmg,
        speed        = s.ball_speed or 150,
        blast_radius = s.blast_radius or 56,
        bombard      = bombard,
        color        = color,
      }
    end
  end)

  -- Recoil: kick the ball backward along its heading (normalize_speed restores
  -- the magnitude next frame, so the kick mostly shoves the heading off-axis).
  if self.body then
    local vx, vy = self:get_velocity()
    if vx then
      local kick = s.recoil or 90
      self:set_velocity(vx - math.cos(ang)*kick, vy - math.sin(ang)*kick)
    end
  end

  -- Muzzle feedback: recoil + flash timer, smoke from the muzzle, a pop + thud.
  self.cannon_recoil_t = 0.22
  self.spring:pull(0.12)
  local mx, my = hx + math.cos(ang)*self.r_size*2.2, hy + math.sin(ang)*self.r_size*2.2
  for _ = 1, 4 do
    SmokePuff{group = arena.effects, x = mx, y = my,
              color = Color(0.34, 0.32, 0.30, 1), rs = random:float(2, 4), alpha = random:float(0.3, 0.5),
              vx = math.cos(ang)*random:float(20, 60) + random:float(-10, 10),
              vy = math.sin(ang)*random:float(20, 60) + random:float(-10, 10),
              duration = random:float(0.35, 0.6)}
  end
  shoot1:play{volume = 0.3, pitch = random:float(0.7, 0.85)}
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
          dmg = (s.pet_dmg or 8)*(self.charge_dmg_mult or 1)*(self.buff_dmg_mult or 1)*(self.run_dmg_mult or 1),
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
-- doesn't bleed into contact damage on bounces. RANGED_DMG_MULT layers the
-- pace-tuning bonus on top: shots are 4x rarer, so each hits 2.5x harder.
local PROJECTILE_DMG_MULT = 3.5*RANGED_DMG_MULT
-- Spellblade fires a CONSTANT stream of piercing blades, so each shot is only a
-- fraction of a normal ranged hit (sheer volume + pierce make up the DPS, and
-- random spread wastes many shots). This is the spellblade's main balance knob.
local SPELLBLADE_DMG_MULT = 0.6*RANGED_DMG_MULT

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
  -- SNKRX plays one of two throw sounds at random for every knife thrower.
  _G[random:table{'scout1', 'scout2'}]:play{pitch = random:float(0.95, 1.05), volume = 0.35}
end


-- The assassin's bleed-knife (SNKRX assassin port). Unlike shoot_knife it
-- builds the Projectile directly so it can carry the crit flag and the bleed
-- payload (fire_projectile_at_nearest forwards neither). Targets the nearest
-- brick in range; pierce 1000 skewers the whole lane and every brick it punches
-- through starts bleeding (see projectile.lua / Brick:apply_bleed). Also arms
-- the Shadowstalker blink-lunge cross-slash (strike_a / assassin_strike_t).
function BallHero:shoot_assassin_knife(s, crit, bleed_total)
  if self.stuck or self.returning then return end
  local arena = main.current
  if not (arena and arena.main and arena.main.world) then return end
  local target = arena:get_nearest_brick_within(self.x, self.y, s.range)
  if not target then return end
  local hx, hy = self.x, self.y
  local r      = math.atan2(target.y - hy, target.x - hx)
  self.strike_a          = r
  self.assassin_strike_t = 0.26
  self.assassin_crit     = crit
  local dmg    = self:current_dmg()*PROJECTILE_DMG_MULT*(crit and 2 or 1)
  local color  = self.color
  local main_g = arena.main
  arena.t:after(0, function()
    if main_g and main_g.world then
      Projectile{
        group = main_g, x = hx, y = hy, r = r,
        type = 'knife', dmg = dmg, speed = s.speed or 320,
        pierce = s.pierce or 1000, color = color,
        crit = crit, bleed = bleed_total, bleed_dur = s.bleed_dur or 3,
      }
    end
  end)
  _G[random:table{'scout1', 'scout2'}]:play{pitch = random:float(0.95, 1.05), volume = 0.35}
end


-- The spellblade's spiraling blade-shard (SNKRX spellblade port, player.lua:400
-- + :2013). Fired in a RANDOM direction with pierce 1000; the projectile's
-- heading spins (orbit_vr, randomized cw/ccw) so it curls outward in a spiral
-- that opens up as the spin decays (see projectile.lua). Called as a constant
-- stream by BEHAVIORS.blade_storm; per-shot damage is intentionally small
-- (SPELLBLADE_DMG_MULT) since it fires ~10x a second and pierces everything.
function BallHero:shoot_blade(s)
  if self.stuck or self.returning then return end
  local arena = main.current
  if not (arena and arena.main and arena.main.world) then return end
  local ang    = random:float(0, 2*math.pi)
  local dir    = random:bool(50) and 1 or -1
  local x, y   = self.x, self.y
  local dmg    = self:current_dmg()*SPELLBLADE_DMG_MULT
  local color  = self.color
  local main_g = arena.main
  arena.t:after(0, function()
    if main_g and main_g.world then
      Projectile{
        group = main_g, x = x, y = y, r = ang,
        type = 'spellblade', dmg = dmg, speed = s.speed or 200,
        pierce = 1000, color = color, orbit_vr = dir*(s.orbit_vr or 6),
      }
    end
  end)
  -- The cast is near-constant, so keep its chime sparse and quiet.
  if random:bool(18) then wizard1:play{volume = 0.1, pitch = random:float(1.0, 1.2)} end
end


-- The archer's crossbow bolt: the exact SNKRX shot — closest brick in the
-- sensor, pierce 1000 (it never stops on a target), level-3 wall ricochet 3.
-- wall_stick makes the bolt bounce off / thunk into the arena walls instead
-- of silently expiring (projectile.lua handles both plus the WallArrow).
function BallHero:shoot_bolt(s)
  if self.stuck or self.returning then return end
  main.current:fire_projectile_at_nearest(self, {
    type = 'arrow', dmg = self:current_dmg()*PROJECTILE_DMG_MULT,
    speed = s.speed or 260, range = s.range, color = self.color,
    pierce = 1000, ricochet = (self.level >= 3) and 3 or 0, wall_stick = true,
  })
  archer1:play{pitch = random:float(0.95, 1.05), volume = 0.35}
end


function BallHero:melee_splash(radius, dmg)
  if self.stuck or self.returning then return end
  main.current:do_splash(self.x, self.y, radius, dmg*(self.charge_dmg_mult or 1), self.color)
  swordsman1:play{volume = 0.3, pitch = random:float(0.95, 1.05)}
end


-- Fire the swordsman's Cleave: shake + woosh + the CleaveArea strike (the
-- exact SNKRX attack — see effects.lua). Damage routes through current_dmg
-- so charge, ally buffs and the paddle loadout's Dmg stat all apply.
function BallHero:do_cleave(s)
  if self.stuck or self.returning or self.mortar then return end
  local arena = main.current
  if not arena then return end
  camera:shake(2, 0.5)
  self.spring:pull(0.3)
  self.cleave_flash_t = 0.25   -- whips the crescent into a full slash ring
  _G[random:table{'swordsman1', 'swordsman2'}]:play{pitch = random:float(0.9, 1.1), volume = 0.75}
  CleaveArea{
    group = arena.effects, x = self.x, y = self.y, r = self.face_a or 0,
    w = s.area or 96, color = self.color, dmg = self:current_dmg(), level = self.level,
  }
end


-- Fire the barbarian's Hammer Slam: a heavy version of do_cleave -- a big screen
-- shake, deep recoil, low-pitched swing, and a HexSlamArea (the Cleave strike
-- scaled up and reshaped into a hexagon shockwave; see effects.lua). Damage
-- routes through current_dmg so charge / ally buffs / loadout Dmg all apply.
function BallHero:do_hammer_slam(s)
  if self.stuck or self.returning or self.mortar then return end
  local arena = main.current
  if not arena then return end
  camera:shake(5, 0.45)
  self.spring:pull(0.5)
  self.slam_flash_t = 0.3   -- drives the maul-head recoil + impact aura in draw_hammer
  _G[random:table{'swordsman1', 'swordsman2'}]:play{pitch = random:float(0.7, 0.85), volume = 0.9}
  HexSlamArea{
    group = arena.effects, x = self.x, y = self.y, r = 0,
    w = s.area or 110, color = self.color, dmg = self:current_dmg(), level = self.level,
  }
end


-- Plant the vulcanist's Volcano (the exact SNKRX cast): target the midpoint
-- between this ball and the average position of every live enemy (arena
-- centre when nothing is alive), clamped into the arena so the eruptions
-- stay on screen. The Volcano itself owns the shake/sounds and the eruption
-- loop (see effects.lua); damage is read live off this ball every eruption
-- so charge, ally buffs and the paddle loadout's Dmg stat apply per tick.
function BallHero:cast_volcano(s)
  if self.stuck or self.returning or self.mortar then return end
  local arena = main.current
  if not (arena and arena.effects) then return end
  local x, y, n = 0, 0, 0
  for _, o in ipairs(arena.main.objects) do
    if not o.dead and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
      x, y, n = x + o.x, y + o.y, n + 1
    end
  end
  if n > 0 then
    x, y = x/n, y/n
  else
    x, y = (arena.x1 + arena.x2)/2, (arena.y1 + arena.y2)/2
  end
  x, y = (x + self.x)/2, (y + self.y)/2
  x = math.clamp(x, arena.x1 + 28, arena.x2 - 28)
  y = math.clamp(y, arena.y1 + 28, arena.y2 - 28)
  self.cast_flash_t = 0.4   -- all runes flash + the ring whips fast (draw)
  Volcano{group = arena.effects, x = x, y = y, color = self.color,
          parent = self, rs = s.volcano_rs or 24, area = s.area or 72,
          level = self.level, dmg_mult = RANGED_DMG_MULT}
end


function BallHero:update(dt)
  self:update_game_object(dt)

  local arena = main.current

  -- Mitosis: the grow-in (a budding daughter cell scaling up) and decay (a
  -- dying clone) timers advance every frame regardless of state, so the
  -- division + rot animation stays smooth. See begin_mitosis_grow/decay.
  if self.mitosis_grow_t then
    self.mitosis_grow_t = self.mitosis_grow_t + dt
    if self.mitosis_grow_t >= (self.mitosis_grow_dur or 0.35) then self.mitosis_grow_t = nil end
  end
  if self.mitosis_decay_t then
    self.mitosis_decay_t = self.mitosis_decay_t - dt
    if self.mitosis_decay_t <= 0 then self:mitosis_die(); return end
  end

  -- Crescent skin (swordsman): bank the slash arc into the travel direction
  -- with a smooth turn; while stuck it eases back to pointing up, ready for
  -- the launch. cleave_flash_t drives the full slash-ring flash in draw.
  if self.face_a then
    if (self.cleave_flash_t or 0) > 0 then
      self.cleave_flash_t = self.cleave_flash_t - dt
    end
    local want
    if self.stuck then
      want = -math.pi/2
    elseif not self.returning and not self.mortar and self.body then
      local vx, vy = self:get_velocity()
      if vx and (vx*vx + vy*vy) > 1 then want = math.atan2(vy, vx) end
    end
    if want then
      local diff = math.loop(want - self.face_a, 2*math.pi)
      if diff > math.pi then diff = diff - 2*math.pi end
      self.face_a = self.face_a + diff*math.min(1, 12*dt)
    end
  end

  -- Shuriken skin (scout): lazy idle spin that flicks fast for a beat each
  -- time a knife is thrown (throw_flick_t set in BEHAVIORS.chain_knife).
  if self.stats.skin == 'shuriken' then
    local speed = 2.5
    if (self.throw_flick_t or 0) > 0 then
      self.throw_flick_t = self.throw_flick_t - dt
      speed = 18
    end
    self.spin_a = (self.spin_a or 0) + speed*dt
  end

  -- Crossbow skin (archer): swivel the turret toward the latest target angle
  -- (aim_want, sampled on a timer in init) independently of the bouncing
  -- ball; while stuck it eases back to pointing up, ready for the launch.
  -- bolt_recoil_t (set on fire) drives the stock kick + string snap in draw.
  if self.stats.skin == 'crossbow' then
    if (self.bolt_recoil_t or 0) > 0 then
      self.bolt_recoil_t = self.bolt_recoil_t - dt
    end
    local want = self.stuck and -math.pi/2 or (self.aim_want or -math.pi/2)
    local diff = math.loop(want - (self.aim_a or 0), 2*math.pi)
    if diff > math.pi then diff = diff - 2*math.pi end
    self.aim_a = (self.aim_a or 0) + diff*math.min(1, 10*dt)
  end

  -- Rune-furnace skin (vulcanist): lazy ring spin, whipped fast for a beat
  -- each time a volcano is planted (cast_flash_t set in cast_volcano).
  if self.stats.skin == 'rune' then
    local speed = 0.8
    if (self.cast_flash_t or 0) > 0 then
      self.cast_flash_t = self.cast_flash_t - dt
      speed = 12
    end
    self.ring_a = (self.ring_a or 0) + speed*dt
  end

  -- Shadowstalker skin (assassin): advance the idle aura "breathe" clock and
  -- decay the per-throw strike flash (blink-lunge cross-slash; see draw_shadow).
  if self.stats.skin == 'shadow' then
    self.shadow_t = (self.shadow_t or 0) + dt
    if (self.assassin_strike_t or 0) > 0 then
      self.assassin_strike_t = self.assassin_strike_t - dt
    end
  end

  -- Spellblade skin: spin the orbiting blade-shards and advance the arcane
  -- pulse; the shards whip fast for a beat after each cast (spell_flash_t).
  if self.stats.skin == 'spellblade' then
    self.spell_t = (self.spell_t or 0) + dt
    local ospeed = 3.0
    if (self.spell_flash_t or 0) > 0 then
      self.spell_flash_t = self.spell_flash_t - dt
      ospeed = 15
    end
    self.orbit_a = (self.orbit_a or 0) + ospeed*dt
  end

  -- Hammer skin (barbarian): tumble the maul head (a slow heavy spin, whipped
  -- fast for a beat on each slam) and decay the slam flash (set in
  -- do_hammer_slam) that drives the pop + impact aura in draw_hammer.
  if self.stats.skin == 'hammer' then
    local hspeed = 2.5
    if (self.slam_flash_t or 0) > 0 then
      self.slam_flash_t = self.slam_flash_t - dt
      hspeed = 16
    end
    self.hammer_a = (self.hammer_a or 0) + hspeed*dt
  end

  -- Lifebloom skin (cleric): spin the wreath of leaves, advance the breathing
  -- pulse, and decay the bloom flash (set in do_consecrate).
  if self.stats.skin == 'lifebloom' then
    self.orbit_a     = (self.orbit_a or 0) + 1.1*dt
    self.bloom_pulse = (self.bloom_pulse or 0) + dt
    if (self.bloom_t or 0) > 0 then self.bloom_t = self.bloom_t - dt end
  end

  -- Jester skin: advance the idle clock, decay the cast flash, spin the checker,
  -- run the bell pendulum (so the cap's bells lag + jingle with motion), and react
  -- to bounces with a confetti pop + a weave flourish so every bounce feels
  -- springy. (The path-weave itself is applied below, in the active-motion block.)
  if self.stats.skin == 'jester' then
    self.jester_t  = (self.jester_t or 0) + dt
    self.checker_a = (self.checker_a or 0) + 0.8*dt
    if (self.jester_cast_t or 0) > 0 then self.jester_cast_t = self.jester_cast_t - dt end
    -- Bell pendulum: a damped spring driven by horizontal speed, so the bells
    -- swing out as the body weaves and keep jingling after it turns.
    local vx = 0
    if self.body then vx = self:get_velocity() or 0 end
    local drive = -vx*0.0016
    self.cap_sway_v = (self.cap_sway_v or 0) + (90*(drive - (self.cap_sway or 0)) - 7*(self.cap_sway_v or 0))*dt
    self.cap_sway   = (self.cap_sway or 0) + self.cap_sway_v*dt
    -- Bounce reaction: a pop of confetti + a bell jingle + a brief weave flourish.
    if (self.bounces or 0) ~= (self._jester_last_bounces or 0) then
      self._jester_last_bounces = self.bounces or 0
      self.cap_sway_v       = self.cap_sway_v + random:float(-6, 6)
      self.jester_weave_amp = math.max(self.jester_weave_amp or 0, (self.jester_weave_base or 3)*2)
      if main.current and not self.stuck and not self.returning then
        for _ = 1, 3 do
          JesterMote{group = main.current.effects, x = self.x, y = self.y, color = self.color,
                     rs = random:float(1.0, 2.0), alpha = random:float(0.4, 0.7)}
        end
      end
    end
  end

  -- Bomber skin: advance the idle clock, ramp the core telegraph toward the next
  -- plant, and decay the recoil-squash.
  if self.stats.skin == 'bomber' then
    self.bomber_t      = (self.bomber_t or 0) + dt
    self.bomber_fuse_t = math.min(self.stats.cd or 7, (self.bomber_fuse_t or 0) + dt)
    if (self.bomber_recoil_t or 0) > 0 then self.bomber_recoil_t = self.bomber_recoil_t - dt end
  end

  -- Engineer skin: advance the idle clock and the cog-ring rotation (whipped fast
  -- for a beat on each deploy), and decay the deploy flash.
  if self.stats.skin == 'engineer' then
    self.eng_t = (self.eng_t or 0) + dt
    local gspeed = 1.6
    if (self.eng_deploy_t or 0) > 0 then self.eng_deploy_t = self.eng_deploy_t - dt; gspeed = 10 end
    self.eng_gear_a = (self.eng_gear_a or 0) + gspeed*dt
  end

  -- Stormweaver skin: advance the idle clock + spoke-ring spin and decay the
  -- discharge flare. The spokes + sparks crackle on the init timer; here we just
  -- run the clocks the draw reads.
  if self.stats.skin == 'stormweaver' then
    self.storm_t   = (self.storm_t or 0) + dt
    self.arc_phase = (self.arc_phase or 0) + 1.4*dt
    if (self.cast_flash_t or 0) > 0 then self.cast_flash_t = self.cast_flash_t - dt end
  end

  -- Cannon skin (cannoneer): swivel the heavy barrel toward the latest target
  -- (eases back to up while stuck), advance the heat clock, decay the recoil
  -- kick + muzzle flash. The barrel turns a touch slower than the crossbow.
  if self.stats.skin == 'cannon' then
    self.cannon_t = (self.cannon_t or 0) + dt
    if (self.cannon_recoil_t or 0) > 0 then self.cannon_recoil_t = self.cannon_recoil_t - dt end
    local want = self.stuck and -math.pi/2 or (self.aim_want or -math.pi/2)
    local diff = math.loop(want - (self.aim_a or 0), 2*math.pi)
    if diff > math.pi then diff = diff - 2*math.pi end
    self.aim_a = (self.aim_a or 0) + diff*math.min(1, 8*dt)
  end

  if self.stuck then
    self:update_stuck(dt)
    return
  end

  if self.returning then
    self:update_return(dt)
    return
  end

  -- Pinball Lobber: a drained ball is being dragged back up to its serve point
  -- above the paddle (then released into free-fall) — see pinball_serve.
  if self.serving then
    self:update_serving(dt)
    return
  end

  -- Cannon loadout: the ball is out of plane on its mortar arc; physics is
  -- off and we integrate x/y/z manually until it has spent its impacts.
  if self.mortar then
    self:update_mortar(dt)
    return
  end

  if self:is_pinball() then
    self:pinball_update(dt)
  else
    self:normalize_speed()
  end

  -- Jester weave: bend the heading side to side so the ball weaves a restless,
  -- chaotic path -- its signature movement. Only the DIRECTION oscillates, and
  -- sin integrates to ~0 over a period, so there's no net spin and normalize_speed
  -- (magnitude only) never fights it. The amplitude flares on each hex cast / bounce
  -- then eases back to the resting weave.
  if self.stats.skin == 'jester' and self.body then
    self.jester_weave_t   = (self.jester_weave_t or 0) + 9*dt
    self.jester_weave_amp = (self.jester_weave_base or 3.0)
                          + ((self.jester_weave_amp or 3.0) - (self.jester_weave_base or 3.0))*(1 - math.min(1, 3*dt))
    local vx, vy = self:get_velocity()
    if vx and (vx ~= 0 or vy ~= 0) then
      local sp = math.sqrt(vx*vx + vy*vy)
      local na = math.atan2(vy, vx) + self.jester_weave_amp*math.sin(self.jester_weave_t)*dt
      self:set_velocity(math.cos(na)*sp, math.sin(na)*sp)
    end
  end

  -- Bomber heavy lean: add a gentle downward "weight" to its velocity each frame so
  -- its arcs droop like a heavy object (its signature lumbering trajectory).
  -- normalize_speed re-corrects the magnitude next frame, so only the heading sags.
  if self.stats.skin == 'bomber' and self.body then
    local vx, vy = self:get_velocity()
    if vx then self:set_velocity(vx, vy + (self.bomber_gravity or 25)*dt) end
  end

  -- Engineer hover: a gentle, regular perpendicular bob so it reads as a hovering
  -- drone holding a steady heading -- mechanical, not chaotic like the jester weave.
  if self.stats.skin == 'engineer' and self.body then
    local vx, vy = self:get_velocity()
    if vx and (vx ~= 0 or vy ~= 0) then
      local sp = math.sqrt(vx*vx + vy*vy)
      local na = math.atan2(vy, vx) + math.sin((self.eng_t or 0)*4)*0.6*dt
      self:set_velocity(math.cos(na)*sp, math.sin(na)*sp)
    end
  end

  -- Cannon heavy lob: a stronger downward "weight" than the bomber so its arcs sag
  -- like a hurled siege ball -- its signature ponderous trajectory. normalize_speed
  -- re-corrects the magnitude next frame, so only the heading droops.
  if self.stats.skin == 'cannon' and self.body then
    local vx, vy = self:get_velocity()
    if vx then self:set_velocity(vx, vy + (self.cannon_gravity or 32)*dt) end
  end

  -- Stormweaver erratic crackle: the heading stutters along a fast, sign-flipping
  -- wobble (a product of two out-of-phase sines -> chaotic but bounded + mean-zero,
  -- so it never drifts and -- being direction-only -- never fights normalize_speed).
  -- Reads as a nervous, arcing path rather than the jester's smooth weave. Each new
  -- bounce also scrambles the heading a touch and pops a crackle, so ricochets feel
  -- electric and unpredictable (its bouncy, static-discharge signature).
  if self.stats.skin == 'stormweaver' and self.body then
    local vx, vy = self:get_velocity()
    if vx and (vx ~= 0 or vy ~= 0) then
      local sp  = math.sqrt(vx*vx + vy*vy)
      local amp = self.stats.zigzag or 7.0
      local wob = math.sin((self.storm_t or 0)*23)*math.sin((self.storm_t or 0)*7.3 + 1.7)
      local na  = math.atan2(vy, vx) + amp*wob*dt
      self:set_velocity(math.cos(na)*sp, math.sin(na)*sp)
    end
    if (self.bounces or 0) ~= (self._storm_last_bounces or 0) then
      self._storm_last_bounces = self.bounces or 0
      local vx2, vy2 = self:get_velocity()
      if vx2 and (vx2 ~= 0 or vy2 ~= 0) then
        local sp2 = math.sqrt(vx2*vx2 + vy2*vy2)
        local na2 = math.atan2(vy2, vx2) + random:float(-1, 1)*(self.stats.bounce_scramble or 0.7)
        self:set_velocity(math.cos(na2)*sp2, math.sin(na2)*sp2)
      end
      self.spring:pull(0.08)
      for _ = 1, 3 do
        local a = random:float(0, 2*math.pi)
        StormSpark{group = main.current.effects, x = self.x, y = self.y, color = self.color,
                   vx = math.cos(a)*random:float(30, 80), vy = math.sin(a)*random:float(30, 80)}
      end
    end
  end

  -- Boomerang loadout: after any wall hit the ball curls back toward the
  -- paddle, damaging whatever it crosses on the way home. Velocity is only
  -- rotated (never re-scaled) so normalize_speed doesn't fight the turn.
  if self.boomerang_home and arena and arena.paddle then
    local vx, vy = self:get_velocity()
    local sp = math.sqrt(vx*vx + vy*vy)
    if sp > 1 then
      local p    = arena.paddle
      local cur  = math.atan2(vy, vx)
      local want = math.atan2(p.y - self.y, p.x - self.x)
      local diff = math.loop(want - cur, 2*math.pi)
      if diff > math.pi then diff = diff - 2*math.pi end
      local turn = (arena.run_mods and arena.run_mods.sig and arena.run_mods.sig.turn_rate) or 5
      local na   = cur + math.clamp(diff, -turn*dt, turn*dt)
      self:set_velocity(math.cos(na)*sp, math.sin(na)*sp)
    end
  end

  -- Cache the post-normalize velocity each frame so the pierce powerup can
  -- restore it inside the next collision callback (Box2D's reflection has
  -- already mangled the velocity by the time on_collision_enter fires).
  if self.body then
    self._last_vx, self._last_vy = self:get_velocity()
  end

  -- Ball fell into the pit (no bottom wall) — magnetic recall back to paddle.
  -- The Aegis wall normally makes this unreachable; if a ball ever tunnels
  -- past it the recall is the graceful fallback.
  if self.y > arena.y2 + 12 then
    self:start_return()
  end
end


-- Disable physics and lerp the ball back to a point just above the paddle.
-- The Pinball Lobber has no catch flow: it re-serves the ball from above the
-- flippers (pinball_serve) and keeps physics live instead.
function BallHero:start_return()
  -- ULTRAKILL: missing the paddle dings the combo meter. Wipe the per-ball
  -- chain counter too so the next launch starts fresh.
  local arena = main.current
  if arena and arena.on_ball_missed then arena:on_ball_missed(self) end
  self.bounces  = 0
  self:set_piercing(false)
  if self:is_pinball() then
    self:pinball_serve()
    return
  end
  self.returning = true
  self.boomerang_home = nil
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
      if not arena.no_speed_reset then self.speed_mult = 1.0 end
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
  self.boomerang_home   = nil
  self.stuck_offset_x   = random:float(-8, 8)
  -- Pinball flipper rig: snap the stuck spot onto one of the flippers so the
  -- ball never sits over the centre drain gap.
  local pad = main.current and main.current.paddle
  if pad and pad.flippers then
    local side = random:bool(50) and 1 or -1
    self.stuck_offset_x = side*((pad.flipper_gap or 8)/2 + 6)
  end
  -- The floor powerup sets arena.no_speed_reset so the streak survives any
  -- miss — even if a ball somehow slips past the temporary bottom wall, the
  -- accumulated speed_mult is preserved.
  if not (main.current and main.current.no_speed_reset) then
    self.speed_mult     = 1.0   -- missing the paddle wipes the speed streak
  end
  self.charge_time      = 0     -- fresh charge bar each time
  self.charge_dmg_mult  = 1.0   -- previous charge bonus is consumed
  self.bounces          = 0     -- chain starts over from the paddle
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
  -- Inherit pierce from the active buff each time we relaunch off the paddle.
  self:set_piercing(main.current and main.current.pierce_active == true)

  local launch_speed = self.base_speed*self.speed_mult
  self:set_velocity(math.cos(angle)*launch_speed, math.sin(angle)*launch_speed)
  self.spring:pull(0.3 + 0.2*charge_pct)
  if charge_pct > 0.6 then
    spawn_burst(main.current.effects, self.x, self.y, self.color, 6, 80, 160)
  end
  local arena = main.current
  arena.stuck_count = math.max(0, (arena.stuck_count or 0) - 1)
end


-- ----- Mitosis loadout: cell division -----
-- A live "cell" (hero ball) divides on a brick kill: a daughter cell grows out
-- of it (begin_mitosis_grow), the two diverge, and one of them — chosen at
-- random — is the non-viable daughter that decays and dies (begin_mitosis_decay
-- -> draw_mitosis_cell -> mitosis_die). Driven by BallPit:mitosis_on_kill.

function BallHero:mitosis_grow_factor()
  if not self.mitosis_grow_t then return 1 end
  local f = math.clamp(self.mitosis_grow_t/(self.mitosis_grow_dur or 0.35), 0, 1)
  return math.clamp(f*(2 - f), 0.05, 1)   -- ease-out so it pops into being
end


function BallHero:mitosis_decay_factor()
  if not (self.mitosis_decay_t and self.mitosis_decay_max) then return 1 end
  return math.clamp(self.mitosis_decay_t/self.mitosis_decay_max, 0, 1)
end


function BallHero:begin_mitosis_grow(dur)
  self.mitosis_grow_t   = 0
  self.mitosis_grow_dur = dur or 0.35
  self.spring:pull(0.45)
end


-- Mark this body as the non-viable daughter: it becomes a decaying cell and
-- dies when the countdown runs out.
function BallHero:begin_mitosis_decay(life)
  self.is_clone          = true
  self.mitosis_clone     = true
  self.mitosis_decay_max = life or 2.5
  self.mitosis_decay_t   = life or 2.5
end


-- The decaying cell ruptures: a small cytoplasm/spore burst, then it despawns.
function BallHero:mitosis_die()
  if self.dead then return end
  local arena = main.current
  local fx    = arena and arena.effects
  if fx then
    spawn_burst(fx, self.x, self.y, self.color, 6, 40, 90)
    for _ = 1, 4 do
      SporeMote{group = fx, x = self.x, y = self.y, color = self.color,
        vx = random:float(-45, 45), vy = random:float(-45, 45),
        rs = random:float(1, 2.4), alpha = 0.6, duration = random:float(0.3, 0.6)}
    end
  end
  if self.body then self.body:setActive(false) end
  self.dead = true
  if arena and arena.heroes then
    for i = #arena.heroes, 1, -1 do
      if arena.heroes[i] and arena.heroes[i].dead then table.remove(arena.heroes, i) end
    end
  end
end


-- Draw a Mitosis clone as a living cell: a translucent membrane around a
-- cytoplasm blob with a drifting nucleus. `grow` (0..1) scales it up as it buds
-- in; `decay` (1..0) shrinks + dulls it and ramps a death wobble, so the cell
-- visibly rots over its countdown before mitosis_die ruptures it.
function BallHero:draw_mitosis_cell(grow, decay)
  grow  = grow or 1
  decay = decay or 1
  local t  = love.timer.getTime()
  local c  = self.color
  local k  = decay
  local rs = self.r_size*grow*(0.55 + 0.45*k)
  if rs < 0.5 then return end
  local jit    = (1 - k)*1.8                 -- death wobble grows as it rots
  local px, py = self.x + math.sin(t*23)*jit, self.y + math.cos(t*19)*jit
  local cyto = Color(c.r, c.g, c.b, 0.40 + 0.30*k)
  local mem  = Color(c.r, c.g, c.b, 0.30 + 0.45*k)
  local nuc  = Color(c.r*0.5, c.g*0.5, c.b*0.5, 0.75*k + 0.15)
  graphics.circle(px, py, rs + 0.5, bg[-2])
  graphics.circle(px, py, rs, cyto)
  graphics.circle(px, py, rs + 1.2, mem, 1)            -- soft membrane ring
  graphics.circle(px + math.sin(t*3)*rs*0.2, py + math.cos(t*2.3)*rs*0.2, rs*0.4, nuc)
  if k < 0.3 then
    local f = 0.4 + 0.6*math.abs(math.sin(t*26))       -- flickering rupture halo
    graphics.circle(px, py, rs*1.35, Color(0.12, 0.12, 0.12, 0.4*f*(1 - k/0.3)), 1)
  end
end


function BallHero:draw()
  -- Cannon mortar: the ball is "out of the screen" — a ground shadow stays at
  -- (x, y) while the ball draws above it, scaled up with height, so the
  -- z-axis reads without real 3D.
  if self.mortar then
    local z  = self.z or 0
    local sa = math.clamp(0.5 - z/300, 0.12, 0.5)
    local sr = self.r_size*math.clamp(1 - z/260, 0.45, 1)
    graphics.circle(self.x, self.y, sr, Color(0, 0, 0, sa))
    local scale = 1 + z/140
    local dy    = z*0.9
    graphics.circle(self.x, self.y - dy, self.r_size*scale + 0.5, bg[-2])
    graphics.circle(self.x, self.y - dy, self.r_size*scale, self.color)
    graphics.circle(self.x - self.r_size*scale*0.3, self.y - dy - self.r_size*scale*0.3,
                    math.max(1, self.r_size*scale*0.35), fg[5])
    return
  end

  -- Mitosis decaying clone: drawn as a dividing/decaying cell (not the hero
  -- skin), wobbling harder as it dies — see draw_mitosis_cell.
  if self.mitosis_clone then
    self:draw_mitosis_cell(self:mitosis_grow_factor(), self:mitosis_decay_factor())
    if main.current.show_hero_labels then
      graphics.print_centered(self.character:sub(1, 3), pixul_font, self.x, self.y - self.r_size - 6, 0, 1, 1, 0, 0, fg[0])
    end
    return
  end

  -- Freshly-budded daughter cell: scale the whole body up from a point so it
  -- "grows" out of its parent (mitosis) instead of popping in.
  local grow = self:mitosis_grow_factor()
  if grow < 1 then graphics.push(self.x, self.y, 0, grow, grow) end

  self.spring:pull(0)
  local s = self.spring.x
  if self.stats.skin == 'crescent' then
    -- Swordsman: a banked crescent slash instead of the plain ball body.
    self:draw_crescent(s)
  elseif self.stats.skin == 'shuriken' then
    -- Scout: a spinning four-point throwing star.
    self:draw_shuriken(s)
  elseif self.stats.skin == 'crossbow' then
    -- Archer: the ball as a tower base with a crossbow turret on top.
    self:draw_crossbow(s)
  elseif self.stats.skin == 'rune' then
    -- Vulcanist: a rune-ringed furnace around a molten pupil.
    self:draw_rune_furnace(s)
  elseif self.stats.skin == 'shadow' then
    -- Assassin: a dark body wrapped in a breathing shadow aura, shedding inky
    -- smoke-clone afterimages; blink-lunges with a cross-slash on each throw.
    self:draw_shadow(s)
  elseif self.stats.skin == 'spellblade' then
    -- Spellblade: a bright arcane core orbited by spinning blade-shards.
    self:draw_spellblade(s)
  elseif self.stats.skin == 'hammer' then
    -- Barbarian: a heavy maul-head orb that pops + flares on each slam.
    self:draw_hammer(s)
  elseif self.stats.skin == 'lifebloom' then
    -- Cleric: a leaf-wreathed bud over a soft aura; blooms on each cast.
    self:draw_lifebloom(s)
  elseif self.stats.skin == 'jester' then
    -- Jester: a bouncy harlequin orb in a spinning diamond-checker, crowned with
    -- a bell-tipped fool's cap; shimmering motley aura, confetti, cap-flash on cast.
    self:draw_jester(s)
  elseif self.stats.skin == 'bomber' then
    -- Bomber: a dark vented reactor core around a molten plasma center; rotating
    -- vent seams, crackling energy arcs, core swells toward the next plant.
    self:draw_bomb(s)
  elseif self.stats.skin == 'engineer' then
    -- Engineer: a gear-core fabricator drone with a rotating cog ring + scanning
    -- sensor eye; spins up + flashes on each turret deploy.
    self:draw_engineer(s)
  elseif self.stats.skin == 'stormweaver' then
    -- Stormweaver: a caged-lightning orb -- a white-hot nucleus, crackling rim
    -- arcs and a breathing static aura; flares + discharges chain bolts on cast.
    self:draw_stormweaver(s)
  elseif self.stats.skin == 'cannon' then
    -- Cannoneer: an iron siege mortar -- heavy base + a swiveling barrel that
    -- recoils + muzzle-flashes on fire, with a reload ember and a heat-haze aura.
    self:draw_cannon(s)
  else
    graphics.circle(self.x, self.y, self.r_size + 0.5, bg[-2])
    graphics.circle(self.x, self.y, self.r_size*s, self.color)
    graphics.circle(self.x - self.r_size*0.3, self.y - self.r_size*0.3, math.max(1, self.r_size*0.35), fg[5])
  end

  if grow < 1 then graphics.pop() end

  if main.current.show_hero_labels then
    graphics.print_centered(self.character:sub(1, 3), pixul_font, self.x, self.y - self.r_size - 6, 0, 1, 1, 0, 0, fg[0])
  end

  -- Only the lead stuck ball renders its charge ring, so a paddle full of
  -- caught balls doesn't drown the player in overlapping rings.
  if self.stuck and main.current:lead_stuck_ball() == self then self:draw_charge() end
end


-- The swordsman's crescent-slash body: a frozen sword slash banked into its
-- travel direction, shedding fading arc afterimages behind it. Replaces the
-- plain ball circles in draw; the physics body underneath is still the same
-- r_size circle, so bounces are unchanged. The facing angle lives in update;
-- on cleave (cleave_flash_t) the crescent whips a full 360-degree slash ring.
function BallHero:draw_crescent(s)
  s = s or 1
  local rs = self.r_size
  local a  = self.face_a or -math.pi/2
  local c  = self.color

  -- Fading afterimages at the recently sampled positions (newest first).
  for i, p in ipairs(self.cres_trail or {}) do
    local alpha = (i == 1) and 0.3 or 0.14
    graphics.arc('open', p.x, p.y, rs*0.95, p.a - math.pi*0.45, p.a + math.pi*0.45,
                 Color(c.r, c.g, c.b, alpha), rs*0.7)
  end

  -- Main crescent: a thick coloured arc opening backward, with a thin steel
  -- edge just outside it and a bright tip dot at the leading point.
  graphics.arc('open', self.x, self.y, rs*0.95*s, a - math.pi*0.45, a + math.pi*0.45, c, rs*0.85)
  graphics.arc('open', self.x, self.y, rs*1.4*s, a - math.pi*0.38, a + math.pi*0.38, fg[0], 1.5)
  graphics.circle(self.x + math.cos(a)*rs*0.5, self.y + math.sin(a)*rs*0.5,
                  math.max(1, rs*0.22), fg[5])

  -- Cleave flash: an expanding, fading slash ring.
  if (self.cleave_flash_t or 0) > 0 then
    local k = math.clamp(self.cleave_flash_t/0.25, 0, 1)
    graphics.circle(self.x, self.y, rs*(1.6 + (1 - k)*1.4),
                    Color(c.r, c.g, c.b, 0.7*k), 2)
  end
end


-- Draw one four-point star as FOUR CONVEX KITES (centre -> notch -> tip ->
-- notch). LOVE's polygon fill only renders convex polygons — a single
-- concave 8-vertex star comes out mangled. Shared by the scout's body and
-- its ninja shadow-trail ghosts; the spin angle is baked into the vertices.
function BallHero:draw_star(x, y, angle, ro, ri, color)
  for i = 0, 3 do
    local a  = angle + i*math.pi/2
    local al = a - math.pi/4
    local ar = a + math.pi/4
    graphics.polygon({
      x, y,
      x + math.cos(al)*ri, y + math.sin(al)*ri,
      x + math.cos(a)*ro,  y + math.sin(a)*ro,
      x + math.cos(ar)*ri, y + math.sin(ar)*ri,
    }, color)
  end
end


-- The scout's bandit-shuriken body: a four-point throwing star with steel
-- tips spinning around a dark hub, dragging a ninja shadow-trail — fading,
-- shrinking ghost stars at its recently sampled positions. Replaces the
-- plain ball circles in draw; the physics body underneath is still the same
-- r_size circle. Spin angle lives in update (lazy idle spin, fast flick on
-- each knife throw).
function BallHero:draw_shuriken(s)
  s = s or 1
  local rs = self.r_size
  local ro = rs*2.0*s    -- outer point reach
  local ri = rs*0.75*s   -- inner notch radius
  local c  = self.color

  -- Ninja shadow-trail (newest first): darker, smaller, ghostlier copies.
  for i, p in ipairs(self.shuriken_trail or {}) do
    local k = 1 - (i - 1)*0.22
    local ghost = Color(c.r*0.45, c.g*0.45, c.b*0.45, 0.34 - (i - 1)*0.08)
    self:draw_star(p.x, p.y, p.a, ro*0.85*k, ri*0.85*k, ghost)
  end

  -- Star body + steel tip caps + dark hub.
  local a0 = self.spin_a or 0
  self:draw_star(self.x, self.y, a0, ro, ri, c)
  for i = 0, 3 do
    local a = a0 + i*math.pi/2
    graphics.line(self.x + math.cos(a)*ro*0.62, self.y + math.sin(a)*ro*0.62,
                  self.x + math.cos(a)*ro*0.95, self.y + math.sin(a)*ro*0.95, fg[0], 1.5)
  end
  graphics.circle(self.x, self.y, rs*0.6 + 0.5, bg[-2])
  graphics.circle(self.x, self.y, rs*0.55*s,
                  Color(self.color.r*0.55, self.color.g*0.55, self.color.b*0.55, 1))
  graphics.circle(self.x - rs*0.25, self.y - rs*0.25, math.max(1, rs*0.2), fg[5])
end


-- The archer's crossbow-tower body: the plain ball stays as the tower base,
-- with a compact crossbow turret (wood stock, steel limbs, string, loaded
-- bolt) drawn over it, rotated to aim_a — the turret physically points at
-- its next victim. The string cocks back and the bolt fades in as the attack
-- cooldown refills (read straight off the trigger), so a fully drawn string
-- means the shot is ready; an emerald aura ring brightens with it and pulses
-- once loaded. On fire (bolt_recoil_t) the stock kicks back with a muzzle
-- flash while the fresh cooldown naturally relaxes the string. The physics
-- body underneath is still the same r_size circle, so bounces are unchanged.
function BallHero:draw_crossbow(s)
  s = s or 1
  local rs = self.r_size
  local a  = self.aim_a or -math.pi/2
  local c  = self.color

  -- Cock progress 0..1 from the attack cooldown trigger.
  local prog = 1
  local tr   = self.t.triggers and self.t.triggers.attack
  if tr and tr.delay and tr.delay > 0 then
    prog = math.clamp(tr.timer/(tr.delay*(tr.multiplier or 1)), 0, 1)
  end

  -- Ghost afterimages of the whole tower (newest first): fading base circle
  -- plus a thin stock line along the sampled aim.
  for i, p in ipairs(self.bow_trail or {}) do
    local alpha = 0.26 - (i - 1)*0.08
    local k     = 1 - (i - 1)*0.18
    graphics.circle(p.x, p.y, rs*0.9*k, Color(c.r*0.5, c.g*0.5, c.b*0.5, alpha))
    graphics.line(p.x - math.cos(p.a)*rs*0.8*k, p.y - math.sin(p.a)*rs*0.8*k,
                  p.x + math.cos(p.a)*rs*1.1*k, p.y + math.sin(p.a)*rs*1.1*k,
                  Color(c.r*0.5, c.g*0.5, c.b*0.5, alpha), 1)
  end

  -- Emerald aura: a ring that brightens as the bolt loads, pulsing at full.
  local glow = 0.10 + 0.22*prog
  if prog >= 1 then
    glow = 0.32 + 0.12*math.sin(love.timer.getTime()*6)
  end
  graphics.circle(self.x, self.y, rs*1.55, Color(c.r, c.g, c.b, glow), 1.5)

  -- Tower base: the plain ball body.
  graphics.circle(self.x, self.y, rs + 0.5, bg[-2])
  graphics.circle(self.x, self.y, rs*s, c)
  graphics.circle(self.x - rs*0.3, self.y - rs*0.3, math.max(1, rs*0.35), fg[5])

  -- Crossbow turret, compact enough to sit on the ball (reach ~1.2 r_size).
  -- Drawn in a frame rotated to the aim; recoil slides everything backward
  -- along the stock for a beat after firing.
  graphics.push(self.x, self.y, a, s, s)
    local kick = 0
    if (self.bolt_recoil_t or 0) > 0 then
      kick = -(self.bolt_recoil_t/0.22)*rs*0.45
    end
    local x0 = self.x + kick   -- local frame: +x is the aim direction
    local y0 = self.y
    local fx = x0 + rs*1.15    -- front of the stock, where the limbs mount

    -- Wood stock with a dark outline, then the steel limbs sweeping back
    -- from the front mount, drawn as bent two-segment polylines.
    graphics.rectangle(x0 + rs*0.15, y0, rs*1.9, rs*0.5, 1, 1, Color(0.55, 0.42, 0.28, 1))
    graphics.rectangle(x0 + rs*0.15, y0, rs*1.9, rs*0.5, 1, 1, bg[-2], 1)
    graphics.polyline(fg[0], 1.2,
      fx, y0, fx - rs*0.18, y0 - rs*0.72, fx - rs*0.55, y0 - rs*1.15)
    graphics.polyline(fg[0], 1.2,
      fx, y0, fx - rs*0.18, y0 + rs*0.72, fx - rs*0.55, y0 + rs*1.15)

    -- String: from the limb tips back to the nock, which slides rearward
    -- with the cock progress (relaxed at the front right after firing).
    local nock_x = fx - rs*(0.18 + 1.05*prog)
    graphics.line(fx - rs*0.55, y0 - rs*1.15, nock_x, y0, Color(0.92, 0.95, 0.9, 0.9), 1)
    graphics.line(fx - rs*0.55, y0 + rs*1.15, nock_x, y0, Color(0.92, 0.95, 0.9, 0.9), 1)

    -- The bolt fades in on the rail as it loads; bright tip dot when ready.
    if prog > 0.1 then
      local tip_x = nock_x + rs*(0.9 + 0.75*prog)
      graphics.line(nock_x, y0, tip_x, y0, Color(c.r, c.g, c.b, 0.25 + 0.75*prog), 1.5)
      if prog >= 1 then
        graphics.circle(tip_x, y0, math.max(1, rs*0.18), fg[5])
      end
    end

    -- Muzzle flash right after loosing the bolt.
    if (self.bolt_recoil_t or 0) > 0 then
      local k = self.bolt_recoil_t/0.22
      graphics.circle(fx + rs*0.5, y0, rs*0.5*k, Color(1, 1, 1, 0.7*k))
    end
  graphics.pop()
end


-- The vulcanist's rune-furnace body: a ring of dark volcanic stone with 8
-- runes that ignite one by one as the volcano cooldown refills (read off the
-- attack trigger — all 8 lit means the next volcano is ready), around a
-- molten pupil that seethes brighter with charge. On cast (cast_flash_t) the
-- runes all flash white while the ring whips around fast, and an expanding
-- ember ring marks the moment. A molten afterimage trail drags behind it
-- while it flies — fading, shrinking ghost rings with ember runes, the
-- oldest dissolving into a rising smoke puff. The physics body underneath
-- is still the same r_size circle, so bounces are unchanged.
function BallHero:draw_rune_furnace(s)
  s = s or 1
  local rs = self.r_size
  local c  = self.color

  -- Charge progress 0..1 from the attack cooldown trigger.
  local prog = 1
  local tr   = self.t.triggers and self.t.triggers.attack
  if tr and tr.delay and tr.delay > 0 then
    prog = math.clamp(tr.timer/(tr.delay*(tr.multiplier or 1)), 0, 1)
  end

  -- Molten afterimages (newest first): fading, shrinking ghost copies of the
  -- furnace — ember glow disc, ghost stone ring, four dim runes at the
  -- sampled spin angle — with the oldest dissolving into a smoke puff.
  local trail = self.rune_trail or {}
  for i, p in ipairs(trail) do
    local k     = 1 - (i - 1)*0.18
    local alpha = 0.3 - (i - 1)*0.07
    graphics.circle(p.x, p.y, rs*1.05*k, Color(1, 0.6, 0.25, alpha*0.4))
    graphics.circle(p.x, p.y, rs*0.95*k, Color(c.r*0.55, c.g*0.4, c.b*0.4, alpha),
                    math.max(1, rs*0.35*k))
    for j = 0, 3 do
      local a = (p.a or 0) + j*math.pi/2
      graphics.line(p.x + math.cos(a)*rs*0.72*k, p.y + math.sin(a)*rs*0.72*k,
                    p.x + math.cos(a)*rs*1.15*k, p.y + math.sin(a)*rs*1.15*k,
                    Color(1, 0.55, 0.2, alpha), 1.3)
    end
    if i == #trail then
      graphics.circle(p.x, p.y - rs*0.8, math.max(1, rs*0.4*k),
                      Color(0.45, 0.4, 0.38, 0.18))
    end
  end

  -- Heat aura, swelling with charge; soft pulse at full.
  local glow = 0.08 + 0.2*prog
  if prog >= 1 then glow = 0.26 + 0.1*math.sin(love.timer.getTime()*5) end
  graphics.circle(self.x, self.y, rs*1.7, Color(c.r, c.g, c.b, glow))

  -- Stone ring + 8 runes around it. Lit runes count up with the charge and
  -- all flash white for a beat when the volcano goes down.
  graphics.circle(self.x, self.y, rs*0.95*s, Color(0.3, 0.24, 0.26, 1), rs*0.45)
  local lit = math.floor(prog*8 + 0.0001)
  for i = 0, 7 do
    local a = (self.ring_a or 0) + i*math.pi/4
    local col
    if (self.cast_flash_t or 0) > 0 then
      col = fg[0]
    elseif i < lit then
      col = orange[0]
    else
      col = Color(0.42, 0.33, 0.34, 1)
    end
    graphics.line(self.x + math.cos(a)*rs*0.72, self.y + math.sin(a)*rs*0.72,
                  self.x + math.cos(a)*rs*1.18*s, self.y + math.sin(a)*rs*1.18*s,
                  col, 1.6)
  end

  -- Molten pupil: hero-red core with an inner glow that seethes with charge.
  graphics.circle(self.x, self.y, rs*0.5 + 0.5, bg[-2])
  graphics.circle(self.x, self.y, rs*0.5*s, c)
  graphics.circle(self.x + rs*0.08, self.y - rs*0.08, rs*0.28*s,
                  Color(1, 0.72, 0.3, 0.35 + 0.6*prog))
  graphics.circle(self.x - rs*0.15, self.y - rs*0.18, math.max(1, rs*0.14), fg[5])

  -- Cast flash: an expanding, fading ember ring as the volcano is planted.
  if (self.cast_flash_t or 0) > 0 then
    local k = math.clamp(self.cast_flash_t/0.4, 0, 1)
    graphics.circle(self.x, self.y, rs*(1.4 + (1 - k)*1.6),
                    Color(1, 0.72, 0.3, 0.7*k), 2)
  end
end


-- The assassin's Shadowstalker body. The plain ball is wrapped in a soft
-- dark-purple shadow aura that "breathes" (slow sine on radius + alpha), trails
-- inky ghost-clones of itself that fade and drift up, and -- for a beat after
-- every knife throw (assassin_strike_t) -- blink-flickers, lunges toward the
-- victim (strike_a) and flashes a bright cross-slash (gold + wider on a crit).
-- The physics body underneath is the same r_size circle; bounces are unchanged.
function BallHero:draw_shadow(s)
  s = s or 1
  local rs = self.r_size
  local c  = self.color
  local bt = self.shadow_t or 0

  -- Inky smoke-clone afterimages (newest first): darker, ghostlier copies that
  -- rise and shrink with age so the ball reads as trailing smoke.
  for i, p in ipairs(self.shadow_trail or {}) do
    local k     = 1 - (i - 1)*0.16
    local rise  = (i - 1)*1.1
    local ghost = Color(c.r*0.4, c.g*0.35, c.b*0.5, 0.30 - (i - 1)*0.045)
    graphics.circle(p.x, p.y - rise, rs*0.92*k*s, ghost)
  end

  -- A strike flash 0..1 over the 0.26s after a throw; crits flare harder.
  local strike = math.clamp((self.assassin_strike_t or 0)/0.26, 0, 1)

  -- Breathing shadow aura: two soft concentric dark discs whose radius + alpha
  -- pulse slowly (the idle "breathe"). A strike briefly brightens the aura.
  local breathe = 0.5 + 0.5*math.sin(bt*2.2)
  local flare   = strike*(self.assassin_crit and 0.5 or 0.28)
  local aura_a  = 0.10 + 0.06*breathe + flare
  graphics.circle(self.x, self.y, rs*(2.4 + 0.35*breathe), Color(c.r*0.45, c.g*0.30, c.b*0.55, aura_a*0.6))
  graphics.circle(self.x, self.y, rs*(1.7 + 0.25*breathe), Color(c.r*0.70, c.g*0.45, c.b*0.80, aura_a))

  -- Blink-lunge: for the beat after a throw the body jumps toward the victim
  -- and flickers (alternating visible/dim), reading as a teleport-strike.
  local lunge = strike*rs*1.6
  local a     = self.strike_a or -math.pi/2
  local bx    = self.x + math.cos(a)*lunge
  local by    = self.y + math.sin(a)*lunge
  local blink = (strike > 0 and (math.floor(bt*40) % 2 == 0)) and 0.45 or 1

  -- Body.
  graphics.circle(bx, by, rs + 0.5, bg[-2])
  graphics.circle(bx, by, rs*s, Color(c.r, c.g, c.b, blink))
  graphics.circle(bx - rs*0.3, by - rs*0.3, math.max(1, rs*0.35), Color(fg[5].r, fg[5].g, fg[5].b, blink))

  -- Cross-slash: a bright X centered on the body, oriented to the strike, that
  -- snaps out then vanishes. Brighter, wider and gold on a crit.
  if strike > 0 then
    local len = rs*(2.2 + (self.assassin_crit and 1.4 or 0.7))*(0.5 + strike)
    local sc  = self.assassin_crit and Color(1, 0.9, 0.5, strike) or Color(1, 1, 1, strike*0.9)
    local w   = self.assassin_crit and 2 or 1.5
    for _, off in ipairs({math.pi/5, -math.pi/5}) do
      local sa = a + off
      graphics.line(bx - math.cos(sa)*len, by - math.sin(sa)*len,
                    bx + math.cos(sa)*len, by + math.sin(sa)*len, sc, w)
    end
  end
end


-- The jester's "Harlequin" body: a bouncy motley orb. A spinning ring of
-- alternating bright/body-hue diamonds (the harlequin checker) sits over a deep
-- shade base, crowned by a two-horned fool's cap whose bell tips swing on a
-- pendulum (cap_sway) and flash white on each hex cast (jester_cast_t). It bobs
-- on the idle clock, shimmers a two-tone aura, drags fading ghost-orbs and wears
-- a little grin. The physics body underneath is the same r_size circle.
function BallHero:draw_jester(s)
  s = s or 1
  local rs = self.r_size
  local c  = self.color
  local t  = self.jester_t or 0
  local cast = math.clamp((self.jester_cast_t or 0)/0.3, 0, 1)

  -- Two-tone motley palette: a bright harlequin tint and a deep shade of the hue.
  local light = Color(math.min(1, c.r*1.5 + 0.25), math.min(1, c.g*1.5 + 0.25), math.min(1, c.b*1.5 + 0.25), 1)
  local dark  = Color(c.r*0.45, c.g*0.40, c.b*0.50, 1)

  -- Trail: fading harlequin ghost-orbs (newest first).
  for i, p in ipairs(self.jester_trail or {}) do
    local k = 1 - (i - 1)*0.17
    graphics.circle(p.x, p.y, rs*0.85*k*s, Color(c.r, c.g, c.b, 0.22 - (i - 1)*0.035))
  end

  -- Shimmering motley aura: a soft disc whose hue flickers between the body colour
  -- and the bright motley on the idle clock, flaring on a cast.
  local shimmer = 0.5 + 0.5*math.sin(t*3.3)
  local aura_c  = Color(c.r + (light.r - c.r)*shimmer, c.g + (light.g - c.g)*shimmer,
                        c.b + (light.b - c.b)*shimmer, 0.12 + 0.06*shimmer + cast*0.2)
  graphics.circle(self.x, self.y, rs*(2.1 + 0.3*shimmer) + cast*3, aura_c)

  -- Idle bob (exaggerated for a beat on each cast); the cast also pops the scale.
  local bob    = math.sin(t*4)*0.8 + cast*rs*0.4
  local bx, by = self.x, self.y - bob
  local scale  = s*(1 + cast*0.25)

  -- Body orb (deep shade base).
  graphics.circle(bx, by, rs*scale + 0.5, bg[-2])
  graphics.circle(bx, by, rs*scale, dark)

  -- Harlequin motif: a slowly spinning ring of alternating diamonds (convex
  -- quads) around a centre pip, so the body reads as motley.
  local a0  = self.checker_a or 0
  local rad = rs*scale*0.52
  local pip = rs*scale*0.42
  for i = 0, 5 do
    local a  = a0 + i*math.pi/3
    local px = bx + math.cos(a)*rad
    local py = by + math.sin(a)*rad
    local col = (i % 2 == 0) and light or Color(c.r, c.g, c.b, 1)
    graphics.polygon({px, py - pip, px + pip, py, px, py + pip, px - pip, py}, col)
  end
  local cpip = rs*scale*0.5
  graphics.polygon({bx, by - cpip, bx + cpip, by, bx, by + cpip, bx - cpip, by}, light)

  -- Two-horned fool's cap with bell tips, leaning out from the crown and swinging
  -- on the pendulum (cap_sway). Each horn is a tapered triangle; the bells flash
  -- white for a beat after a cast.
  local sway   = self.cap_sway or 0
  local bell_c = (cast > 0) and Color(1, 1, 1, 1) or light
  for _, side in ipairs({-1, 1}) do
    local tip_a = -math.pi/2 + side*0.5 + sway
    local hl    = rs*scale*1.7
    local hx    = bx + math.cos(tip_a)*hl
    local hy    = by + math.sin(tip_a)*hl
    local rootx = bx + math.cos(-math.pi/2 + side*0.35)*rs*scale*0.7
    local rooty = by + math.sin(-math.pi/2 + side*0.35)*rs*scale*0.7
    local perp  = tip_a + math.pi/2
    local ww    = rs*scale*0.45
    local horn_c = (side < 0) and Color(c.r, c.g, c.b, 1) or light
    graphics.polygon({rootx + math.cos(perp)*ww, rooty + math.sin(perp)*ww,
                      rootx - math.cos(perp)*ww, rooty - math.sin(perp)*ww,
                      hx, hy}, horn_c)
    graphics.circle(hx, hy, rs*scale*0.34 + cast*1.2, bell_c)
  end

  -- A little white grin so it reads as a face.
  graphics.arc('open', bx, by + rs*scale*0.15, rs*scale*0.5, math.pi*0.15, math.pi*0.85, Color(1, 1, 1, 0.85), 1.5)
end


-- Rebuild the stormweaver's jagged rim spokes (called on the crackle timer in
-- init). Each spoke is a short midpoint-displaced fork springing from the body
-- rim outward, stored relative to centre and offset at draw time. They lengthen
-- while a discharge flare is active (cast_flash_t), so the cage of lightning
-- snaps wider on each cast.
function BallHero:gen_storm_bolts()
  local flare = math.clamp((self.cast_flash_t or 0)/0.22, 0, 1)
  local n     = 5
  self.storm_bolts = {}
  for i = 1, n do
    local a  = (self.arc_phase or 0) + (i - 1)*2*math.pi/n + random:float(-0.35, 0.35)
    local r0 = self.r_size*0.9
    local r1 = self.r_size*(1.5 + random:float(0, 0.7) + flare*1.4)
    local x0, y0 = math.cos(a)*r0, math.sin(a)*r0
    local x1, y1 = math.cos(a)*r1, math.sin(a)*r1
    local mx, my = (x0 + x1)/2, (y0 + y1)/2
    local k  = random:float(-r1*0.3, r1*0.3)
    mx = mx + math.cos(a + math.pi/2)*k
    my = my + math.sin(a + math.pi/2)*k
    self.storm_bolts[i] = {x0, y0, mx, my, x1, y1}
  end
end


-- The stormweaver's caged-lightning body: a breathing static aura, a ring of
-- crackling arc-spokes (rebuilt each tick in gen_storm_bolts), the electric
-- shell, a white-hot nucleus that pulses with the idle clock and flares to pure
-- white on each discharge (cast_flash_t), and two electron sparks orbiting the
-- core. Physics body underneath is the same r_size circle, so bounces are unchanged.
function BallHero:draw_stormweaver(s)
  s = s or 1
  local rs    = self.r_size
  local c     = self.color
  local t     = self.storm_t or 0
  local flare = math.clamp((self.cast_flash_t or 0)/0.22, 0, 1)
  local hot   = Color(math.min(1, c.r*0.4 + 0.6), math.min(1, c.g*0.4 + 0.6), math.min(1, c.b*0.3 + 0.7), 1)

  -- Static aura: a soft disc that breathes and flares on a discharge.
  local breathe = 0.5 + 0.5*math.sin(t*3.0)
  graphics.circle(self.x, self.y, rs*(1.8 + 0.25*breathe) + flare*9,
                  Color(c.r, c.g, c.b, 0.10 + 0.05*breathe + flare*0.22))

  -- Discharge ring: a bright ring snaps out + fades on each cast.
  if flare > 0.01 then
    graphics.circle(self.x, self.y, rs + 5 + (1 - flare)*26, Color(hot.r, hot.g, hot.b, flare*0.55), 2)
  end

  -- Crackling rim spokes (offset from centre to the body position), coloured glow
  -- with a hot inner streak on the first leg.
  local bcol = Color(c.r, c.g, c.b, 0.55 + flare*0.45)
  local ccol = Color(hot.r, hot.g, hot.b, 0.7 + flare*0.3)
  for _, b in ipairs(self.storm_bolts or {}) do
    graphics.line(self.x + b[1], self.y + b[2], self.x + b[3], self.y + b[4], bcol, 1.5)
    graphics.line(self.x + b[3], self.y + b[4], self.x + b[5], self.y + b[6], bcol, 1.5)
    graphics.line(self.x + b[1], self.y + b[2], self.x + b[3], self.y + b[4], ccol, 1)
  end

  -- Body shell + outline.
  graphics.circle(self.x, self.y, rs*s + 0.5, bg[-2])
  graphics.circle(self.x, self.y, rs*s, c)

  -- White-hot nucleus: pulses with the idle clock, swells + whitens on discharge.
  local core_r = rs*(0.38 + 0.10*math.sin(t*6.0)) + flare*rs*0.5
  graphics.circle(self.x, self.y, math.max(1, core_r), Color(hot.r, hot.g, hot.b, 0.9))
  graphics.circle(self.x, self.y, math.max(0.6, core_r*0.5), Color(1, 1, 1, 0.85 + flare*0.15))

  -- Two electron sparks orbiting the nucleus (extra emission + animation).
  for i = 0, 1 do
    local oa  = t*5.0 + i*math.pi
    local orr = rs*(0.95 + 0.15*math.sin(t*4 + i))
    graphics.circle(self.x + math.cos(oa)*orr, self.y + math.sin(oa)*orr, 1.1, Color(hot.r, hot.g, hot.b, 0.8))
  end
end


-- The cannoneer's siege-mortar body: a heavy iron base carrying a thick barrel
-- that swivels to the nearest brick (aim_a). A reload ember at the muzzle
-- brightens as the cooldown fills; on fire the barrel recoils backward along its
-- axis and a muzzle flash blooms (cannon_recoil_t). The physics body underneath is
-- the same r_size circle, so bounces are unchanged.
function BallHero:draw_cannon(s)
  s = s or 1
  local rs = self.r_size
  local a  = self.aim_a or -math.pi/2
  local c  = self.color

  -- Reload progress 0..1 from the attack cooldown trigger.
  local prog = 1
  local tr   = self.t.triggers and self.t.triggers.attack
  if tr and tr.delay and tr.delay > 0 then
    prog = math.clamp(tr.timer/(tr.delay*(tr.multiplier or 1)), 0, 1)
  end

  -- Heat-haze aura: brightens as the next shell loads, pulses when ready.
  local glow = 0.08 + 0.18*prog
  if prog >= 1 then glow = 0.28 + 0.12*math.sin(love.timer.getTime()*6) end
  graphics.circle(self.x, self.y, rs*1.7, Color(c.r, c.g, c.b, glow))

  -- Iron base (the ball body) with a coloured rim + metal highlight.
  graphics.circle(self.x, self.y, rs + 0.5, bg[-2])
  graphics.circle(self.x, self.y, rs*s, Color(0.26, 0.24, 0.26, 1))
  graphics.circle(self.x, self.y, rs*s, c, 1)
  graphics.circle(self.x - rs*0.32, self.y - rs*0.32, math.max(1, rs*0.3), fg[5])

  -- Barrel: a thick tube along the aim, sliding back into recoil on fire.
  graphics.push(self.x, self.y, a, s, s)
    local kick = 0
    if (self.cannon_recoil_t or 0) > 0 then kick = -(self.cannon_recoil_t/0.22)*rs*0.7 end
    local x0  = self.x + kick   -- local frame: +x is the aim direction
    local y0  = self.y
    local len = rs*2.0
    local bw  = rs*0.95
    -- Tube + dark outline.
    graphics.rectangle(x0 + len*0.5, y0, len, bw, 2, 2, Color(0.22, 0.20, 0.22, 1))
    graphics.rectangle(x0 + len*0.5, y0, len, bw, 2, 2, bg[-2], 1)
    -- Reinforcing band near the breech.
    graphics.rectangle(x0 + rs*0.5, y0, rs*0.35, bw + 1.5, 1, 1, Color(0.32, 0.30, 0.32, 1))
    -- Muzzle ring at the front.
    local mx = x0 + len
    graphics.circle(mx, y0, bw*0.6, Color(0.12, 0.11, 0.12, 1))
    graphics.circle(mx, y0, bw*0.6, c, 1)
    -- Muzzle flash on fire, or a reload ember glowing as the shell loads.
    local flash = math.clamp((self.cannon_recoil_t or 0)/0.22, 0, 1)
    if flash > 0.01 then
      graphics.circle(mx + rs*0.4, y0, rs*(0.5 + flash*1.2), Color(1, 0.85, 0.4, flash*0.9))
      graphics.circle(mx + rs*0.2, y0, rs*(0.3 + flash*0.6), Color(1, 1, 0.8, flash))
    else
      graphics.circle(mx, y0, 1.6, Color(1, 0.6 + 0.3*prog, 0.3, 0.4 + 0.5*prog))
    end
  graphics.pop()
end


-- The bomber's "Demoman" body: a heavy iron bomb-sphere with a tumbling iron band
-- + rivets, a glossy metal highlight and a lit fuse whose ember swells brighter as
-- the next charge nears (bomber_fuse_t -> stats.cd). It breathes heavily, sinks +
-- flattens in a recoil-squash for a beat after laying a bomb (bomber_recoil_t), and
-- glows a heat-haze danger aura. The physics body underneath is the same r_size circle.
-- The bomber's "reactor core" body: a dark vented casing with four glowing vent
-- seams rotating around a molten plasma core (orange -> yellow -> white-hot). It
-- pulses, crackles energy arcs off its shell, and swells brighter as the next
-- charge nears (bomber_fuse_t -> stats.cd); on each plant it sinks in a
-- recoil-squash (bomber_recoil_t). The physics body underneath is the same r_size
-- circle, so bounces are unchanged.
function BallHero:draw_bomb(s)
  s = s or 1
  local rs = self.r_size
  local c  = self.color
  local t  = self.bomber_t or 0
  local recoil = math.clamp((self.bomber_recoil_t or 0)/0.32, 0, 1)
  local fuse_k = math.clamp((self.bomber_fuse_t or 0)/(self.stats.cd or 7), 0, 1)
  local pulse  = 0.5 + 0.5*math.sin(t*5)

  -- Recoil sink + a slow heavy breathe.
  local breathe = 1 + 0.03*math.sin(t*2)
  local sc = s*(1 + recoil*0.18)*breathe
  local cx = self.x
  local by = self.y + recoil*rs*0.4

  -- Plasma aura that swells with the core pulse + toward the next plant.
  graphics.circle(cx, by, rs*(1.55 + 0.3*pulse)*sc + fuse_k*8,
                  Color(c.r, c.g*0.55, c.b*0.3, 0.10 + 0.06*pulse + fuse_k*0.12))

  -- Dark reactor casing.
  graphics.circle(cx, by, rs*sc + 1.5, bg[-2])
  graphics.circle(cx, by, rs*sc, Color(0.11, 0.10, 0.13, 1))

  -- Four glowing vent seams, slowly rotating; brighter with pulse + charge.
  local a0   = t*0.5
  local seam = Color(c.r, c.g*0.8, c.b*0.4, 0.5 + 0.3*pulse + fuse_k*0.2)
  for i = 0, 3 do
    local a = a0 + i*math.pi/2
    graphics.arc('open', cx, by, rs*0.78*sc, a + 0.3, a + 1.15, seam, 2.2)
  end

  -- Molten core: orange -> yellow -> white-hot, swelling with pulse + charge.
  graphics.circle(cx, by, rs*(0.5 + 0.12*pulse + fuse_k*0.12)*sc, Color(c.r, c.g, c.b, 0.92))
  graphics.circle(cx, by, rs*(0.30 + 0.10*pulse)*sc, Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.95))
  graphics.circle(cx, by, rs*0.14*sc, Color(1, 1, 1, 0.95))

  -- Energy arcs crackling off the shell (time-driven, no RNG; livelier as it charges).
  for i = 1, 2 do
    local seed = t*(7.3 + i*2.1) + i*2.0
    if math.sin(seed*3.1) > (0.35 - fuse_k*0.5) then
      local a  = seed
      local r1 = rs*0.6*sc
      local r2 = rs*(1.1 + 0.4*(0.5 + 0.5*math.sin(seed*5)))*sc
      graphics.line(cx + math.cos(a)*r1, by + math.sin(a)*r1,
                    cx + math.cos(a)*r2, by + math.sin(a)*r2,
                    Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.75), 1.5)
    end
  end
end


-- The engineer's "Builder" body: a fabricator drone -- a dark gear-core ringed with
-- rotating cog teeth around a glowing sensor "eye" lens that scans. A mechanical
-- glow aura breathes; the cog ring whips fast and the body flashes + pops for a beat
-- on each turret deploy (eng_deploy_t). Same r_size physics circle underneath.
function BallHero:draw_engineer(s)
  s = s or 1
  local rs = self.r_size
  local c  = self.color
  local t  = self.eng_t or 0
  local ga = self.eng_gear_a or 0
  local deploy = math.clamp((self.eng_deploy_t or 0)/0.3, 0, 1)
  local pulse  = 0.5 + 0.5*math.sin(t*4)
  local sc = s*(1 + deploy*0.18)

  -- Mechanical glow aura (flares on a deploy).
  graphics.circle(self.x, self.y, rs*(1.4 + 0.15*pulse)*sc + deploy*6,
                  Color(c.r, c.g*0.6, c.b*0.3, 0.08 + 0.05*pulse + deploy*0.18))

  -- Cog teeth ring: 8 stubby teeth radiating from the rim, rotating on ga.
  for i = 0, 7 do
    local a  = ga + i*math.pi/4
    local tr = rs*1.0*sc
    local tx = self.x + math.cos(a)*tr
    local ty = self.y + math.sin(a)*tr
    graphics.push(tx, ty, a, 1, 1)
      graphics.rectangle(tx, ty, rs*0.55*sc, rs*0.3*sc, 1, 1, Color(c.r*0.55, c.g*0.45, c.b*0.30, 1))
    graphics.pop()
  end

  -- Dark gear body + inner metal ring.
  graphics.circle(self.x, self.y, rs*sc + 1, bg[-2])
  graphics.circle(self.x, self.y, rs*sc, Color(0.15, 0.14, 0.16, 1))
  graphics.circle(self.x, self.y, rs*0.72*sc, Color(c.r*0.4, c.g*0.33, c.b*0.26, 1), 1.5)

  -- Central sensor eye/lens: a glowing orange core that scans (brightness pulse),
  -- white-hot on a deploy.
  graphics.circle(self.x, self.y, rs*(0.42 + 0.06*pulse)*sc, Color(c.r, c.g, c.b, 0.85 + deploy*0.15))
  graphics.circle(self.x, self.y, rs*0.24*sc, Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.95))
  graphics.circle(self.x, self.y, rs*0.11*sc, Color(1, 1, 1, 0.9))
end


-- The spellblade's body: a bright arcane core wrapped in a soft pulsing aura,
-- with three blade-shards orbiting it (orbit_a, whipped on each cast). It reads
-- as a little blade-mage orb; the shards telegraph the spiraling blades it
-- flings. The physics body underneath is the same r_size circle, so bounces
-- are unchanged.
function BallHero:draw_spellblade(s)
  s = s or 1
  local rs = self.r_size
  local c  = self.color
  local a  = self.orbit_a or 0
  local pulse = 0.5 + 0.5*math.sin((self.spell_t or 0)*3)
  local flash = math.clamp((self.spell_flash_t or 0)/0.15, 0, 1)

  -- Soft arcane aura that pulses (and flares on a cast).
  graphics.circle(self.x, self.y, rs*(2.0 + 0.25*pulse) + flash*2,
                  Color(c.r, c.g, c.b, 0.10 + 0.06*pulse + flash*0.15))

  -- Three orbiting blade-shards: a short blade drawn tangent to the orbit, with
  -- a bright tip. They sweep faster for a beat right after a cast.
  for i = 0, 2 do
    local ba   = a + i*2*math.pi/3
    local orad = rs*1.7
    local bx   = self.x + math.cos(ba)*orad
    local by   = self.y + math.sin(ba)*orad
    local ta   = ba + math.pi/2      -- tangent: the blade points along the orbit
    local bl   = 3 + flash*1.5
    graphics.line(bx - math.cos(ta)*bl, by - math.sin(ta)*bl,
                  bx + math.cos(ta)*bl, by + math.sin(ta)*bl, c, 1.5)
    graphics.circle(bx, by, 1.2, fg[5])
  end

  -- Core ball + white-hot arcane center.
  graphics.circle(self.x, self.y, rs + 0.5, bg[-2])
  graphics.circle(self.x, self.y, rs*s, c)
  graphics.circle(self.x, self.y, rs*0.45, Color(1, 1, 1, 0.6 + 0.25*pulse))
  graphics.circle(self.x - rs*0.3, self.y - rs*0.3, math.max(1, rs*0.3), fg[5])
end


-- The barbarian's body: a heavy double-headed maul that TUMBLES as it flies (a
-- slow iron tumble, whipped fast on each slam) -- a dark iron crossbar through a
-- glowing core with bright striking faces at both ends, so the spin reads at a
-- glance. On a Hammer Slam (slam_flash_t) it squash-pops bigger + flares an aura.
function BallHero:draw_hammer(s)
  s = s or 1
  local rs = self.r_size
  local c  = self.color
  local a  = self.hammer_a or 0
  local slam  = math.clamp((self.slam_flash_t or 0)/0.3, 0, 1)
  local scale = s*(1 + slam*0.3)

  -- Heavy impact aura on the slam.
  if slam > 0 then
    graphics.circle(self.x, self.y, rs*(1.8 + slam*1.4), Color(c.r, c.g, c.b, 0.20*slam))
  end

  -- Body orb (the maul-head core).
  graphics.circle(self.x, self.y, rs*scale + 1, bg[-2])
  graphics.circle(self.x, self.y, rs*scale, c)

  -- The heavy iron crossbar through the head, tumbling on `a`, with bright
  -- striking faces at both ends so the rotation is obvious.
  graphics.push(self.x, self.y, a, scale, scale)
    graphics.rectangle(self.x, self.y, rs*2.7, rs*0.8, 1, 1, Color(c.r*0.4, c.g*0.4, c.b*0.4, 1))
    graphics.rectangle(self.x - rs*1.2, self.y, rs*0.5, rs*1.3, 1, 1, fg[5])
    graphics.rectangle(self.x + rs*1.2, self.y, rs*0.5, rs*1.3, 1, 1, fg[5])
  graphics.pop()

  -- Bright core.
  graphics.circle(self.x, self.y, math.max(1, rs*0.35), fg[5])
end


-- Builds + fills one curled flower petal as a strip of convex quads (so the
-- hooked, overall-concave shape still renders under LOVE's convex-only polygon
-- fill). cx,cy = flower centre; a = petal base angle; L = length; W = max width;
-- hook = how hard the tip curls back sideways as it opens.
local function draw_flower_petal(cx, cy, a, L, W, hook, col)
  local SEG = 6
  local ca, sa = math.cos(a), math.sin(a)
  local lpx, lpy, rpx, rpy = {}, {}, {}, {}
  for i = 0, SEG do
    local u = i/SEG
    local mx, my = u*L, hook*L*u*u                 -- hooked centre-line
    local tx, ty = L, hook*L*2*u                   -- tangent
    local tl = math.sqrt(tx*tx + ty*ty); tx, ty = tx/tl, ty/tl
    local nx, ny = -ty, tx                         -- normal
    local w = (math.sin(u*math.pi))^0.8 * W*0.5    -- width taper (0 at base + tip)
    local axx, ayy = mx + nx*w, my + ny*w
    local bxx, byy = mx - nx*w, my - ny*w
    lpx[i+1] = cx + axx*ca - ayy*sa; lpy[i+1] = cy + axx*sa + ayy*ca
    rpx[i+1] = cx + bxx*ca - byy*sa; rpy[i+1] = cy + bxx*sa + byy*ca
  end
  for i = 1, SEG do
    graphics.polygon({lpx[i], lpy[i], rpx[i], rpy[i],
                      rpx[i+1], rpy[i+1], lpx[i+1], lpy[i+1]}, col)
  end
end


-- The cleric's Lifebloom body: a living flower. A ring of petals perpetually
-- breathes open -- curling their tips back as they spread -- around a green
-- heart with a gold seed-crown, over a soft mossy aura, and BURSTS into a full
-- bloom + pulse ring each time it casts Consecrated Ground (bloom_t). No
-- orbiting bits; the bloom itself is the motion. Physics body is unchanged.
function BallHero:draw_lifebloom(s)
  s = s or 1
  local rs = self.r_size
  local c  = self.color
  local leaf = Color(math.min(1, c.r*1.2 + 0.12), math.min(1, c.g*1.12 + 0.1), math.min(1, c.b*0.9), 1)

  -- Bloom amount: a gentle perpetual breathe-open, spiked to a full burst on a
  -- cast (cast = a 0->1->0 swell over the ~1s after bloom_t is set to 1).
  local breathe = 0.5 + 0.5*math.sin((self.bloom_pulse or 0)*1.4)
  local cast = math.sin(math.clamp(1 - (self.bloom_t or 0), 0, 1)*math.pi)
  local open = math.max(0.30 + breathe*0.32, cast)

  -- Soft mossy aura that breathes + flares on a bloom. [the pulse]
  graphics.circle(self.x, self.y, rs*(1.9 + 0.25*breathe) + open*10,
                  Color(c.r, c.g, c.b, 0.10 + 0.05*breathe + cast*0.16))

  -- Cast pulse ring: a bright ring that expands + fades on each full bloom.
  if cast > 0.01 then
    graphics.circle(self.x, self.y, rs + 6 + (1 - cast)*30, Color(leaf.r, leaf.g, leaf.b, cast*0.6), 2)
  end

  -- Petals: a wreath that unfurls and curls its tips back as `open` rises.
  local N = 7
  local L = rs*(0.7 + open*2.1)
  local W = rs*1.05
  local hook = 0.28 + open*0.55
  local spin = (self.orbit_a or 0)*0.35
  local pcol = Color(leaf.r, leaf.g, leaf.b, 0.45 + cast*0.3)
  for i = 0, N - 1 do
    draw_flower_petal(self.x, self.y, spin + i*2*math.pi/N, L, W, hook, pcol)
  end

  -- Body orb (the flower's heart) + bud.
  graphics.circle(self.x, self.y, rs*s + 0.5, bg[-2])
  graphics.circle(self.x, self.y, rs*s, c)
  graphics.circle(self.x, self.y, rs*0.5*s, leaf)

  -- Seed crown: little gold seeds that spread out of the heart as it opens.
  local sn = 7
  for i = 0, sn - 1 do
    local sa2 = i*2*math.pi/sn + (self.orbit_a or 0)*0.6
    local sr  = open*rs*0.55
    graphics.circle(self.x + math.cos(sa2)*sr, self.y + math.sin(sa2)*sr, 1.3,
                    Color(0.96, 0.9, 0.55, 0.5 + cast*0.5))
  end
  graphics.circle(self.x, self.y, math.max(1, rs*0.22), Color(0.96, 0.92, 0.6, 0.95))
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
  local ice = self.run_mods and self.run_mods.sig and self.run_mods.sig.ice
  if ice then
    -- Glacier: pucks on ice. Instead of snapping to the target speed, drift
    -- toward it a few percent per frame — launches and knocks leave lasting
    -- speed deviations that decay over ~a second, producing long glides.
    local k = 1 + (target/s - 1)*0.04
    self:set_velocity(vx*k, vy*k)
  elseif math.abs(s - target) > 12 then
    local k = target/s
    self:set_velocity(vx*k, vy*k)
  end
  vx, vy = self:get_velocity()
  -- Anti-horizontal floor. Halved on ice so shallow skimming paths survive.
  local floor_frac = ice and 0.075 or 0.15
  local bump_frac  = ice and 0.1   or 0.2
  if math.abs(vy) < target*floor_frac then
    local sign = vy >= 0 and 1 or -1
    self:set_velocity(vx, sign*target*bump_frac)
    self:normalize_speed()
  end
end


-- Called by BallPit on every ball-vs-brick collision. Contact damage always
-- happens; the four exception heroes also fire their on-bounce ability.
function BallHero:on_brick_hit(brick)
  local arena = main.current
  -- Pierce: ball is in its punch-through pass. No damage, no combo points,
  -- no on-bounce abilities (chain_lightning, big_splash, fire trail, etc.),
  -- no bounce-count increment. The ball glides through; the velocity restore
  -- in the BallPit collision callback handles the visual pass-through.
  -- Pierce ends when the ball bonks the top wall (see that callback).
  if self.piercing then return end
  -- Hive loadout: balls deal ZERO contact damage — every brick bounce spawns
  -- a maggot instead, and the combo meter is fed manually since we skip
  -- Brick:on_ball_contact (where it's normally awarded).
  local mods = self.run_mods
  if mods and mods.sig and mods.sig.contact_zero then
    self.bounces = (self.bounces or 0) + 1
    if arena and arena.on_brick_bounce then arena:on_brick_bounce(self, brick) end
    if arena and arena.hive_spawn_maggot then arena:hive_spawn_maggot(self) end
    return
  end
  -- Bump the chain counter BEFORE damage so Brick:on_ball_contact reads the
  -- post-increment value (a clean hit counts as the 1st bounce, not the 0th).
  self.bounces = (self.bounces or 0) + 1
  -- Bricks route damage through on_ball_contact so their Row can react to the
  -- knockback. Mobile enemies (critters, projectiles) just take damage.
  if brick.on_ball_contact then
    brick:on_ball_contact(self)
  else
    brick:take_damage(self.dmg, self.color)
  end

  -- Glacier loadout: every brick hit chills the struck block.
  if mods and mods.sig and mods.sig.ice and brick.apply_slow then
    brick:apply_slow(0.6, 1.5)
  end

  -- Fire-trail powerup: while active, every ball-on-brick contact also calls
  -- apply_burn on the target. EnemyCritter / EnemyProjectile are also tagged
  -- 'brick' for collision routing and expose a no-op apply_burn, so this is
  -- safe; only real Brick instances actually tick burn damage.
  if arena and arena.buffs and arena.buffs.fire_trail and brick.apply_burn then
    brick:apply_burn(self:current_dmg()*0.4, 2.0)
    if random:bool(25) then
      HitParticle{
        group = arena.effects,
        x = self.x + random:float(-3, 3),
        y = self.y - self.r_size,
        color = orange[0], v = 30, r = -math.pi/2, w = 2, duration = 0.3,
      }
    end
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


-- ----- Terrorist loadout: timed self-detonation -----

-- Blast the ball's own element in an AoE around it, then re-form at the
-- paddle. Deliberately NOT routed through start_return: re-forming is the
-- mechanic working as intended, so it must not eat the combo miss penalty.
-- The relaunch goes through launch_from_paddle, which resets speed_mult and
-- the chain counter — that reset is the glass-cannon cost of the blast.
function BallHero:terror_detonate()
  if self.stuck or self.returning or self.mortar or self.dead then return end
  local arena = main.current
  if not arena or arena.game_over then return end
  local sig    = (self.run_mods and self.run_mods.sig) or {}
  local radius = sig.blast_radius or 56
  local x, y   = self.x, self.y

  arena:do_splash(x, y, radius, self:current_dmg()*(sig.blast_mult or 2.2), self.color)
  -- Element carry-over: a Pyromancer ball makes a burn blast, a Cryomancer
  -- ball a freeze blast; everything else is the plain splash.
  local trigger = self.stats.on_bounce
  if trigger == 'burn' then
    arena:burn_area(x, y, radius, self:current_dmg()*1.5, 3)
  elseif trigger == 'slow' then
    arena:slow_in_area(x, y, radius, 0.5, 3)
  end
  explosion1:play{volume = 0.4, pitch = random:float(0.9, 1.05)}
  spawn_burst(arena.effects, x, y, self.color, 12, 80, 170)

  if self.body then self.body:setActive(false) end
  self.t:after(0.5, function()
    if self.dead then return end
    local a = main.current
    if not (a and a.paddle and self.body) then return end
    self.body:setActive(true)
    self:launch_from_paddle()
  end)
end


-- ----- Cannon loadout: the z-axis mortar -----

-- A charged ball (speed_mult past the launch threshold — the existing paddle
-- ramp IS the charge) fires "out of the screen": physics goes inactive (same
-- pattern as the pit-return recall, so z-flight ignores all 2D collisions)
-- and x/y/z are integrated by hand. Higher charge = faster up/down bounces
-- (constant apex: z_vel scales with charge, gravity with charge^2) and a
-- bigger splash per landing, with damage falloff from the impact centre.
function BallHero:start_mortar(hit_offset)
  if self.mortar then return end
  local arena = main.current
  if not arena then return end
  self.mortar = true
  self.boomerang_home = nil

  local cf = math.clamp((self.speed_mult or 1)/2, 0.6, 2.0)
  self.mortar_cf      = cf
  self.z              = 0
  self.z_vel          = 240*cf
  self.z_g            = 580*cf*cf
  self.mortar_bounces = 0
  self.mortar_max     = (arena.run_mods and arena.run_mods.sig and arena.run_mods.sig.impacts) or 4
  -- Edge hits steer the drop; a gentle climb pushes it up into the swarm.
  self.mortar_vx      = (hit_offset or 0)*60
  self.mortar_vy      = -(50 + 30*cf)

  -- Deactivating a body inside a Box2D contact callback is illegal (this is
  -- called from the paddle bounce), so defer it a frame.
  self.t:after(0, function()
    if self.body and self.mortar then self.body:setActive(false) end
  end)
  explosion1:play{volume = 0.25, pitch = 1.35}
  spawn_burst(main.current.effects, self.x, self.y, self.color, 8, 80, 160)
end


function BallHero:update_mortar(dt)
  local arena = main.current
  if not arena then return end

  -- Gentle homing toward the nearest brick so drops land among the swarm.
  -- Falls back to the boss on wave 10 (it isn't a Brick instance).
  local target = arena:get_nearest_brick(self.x, self.y)
  if not target and arena.boss and not arena.boss.dead then target = arena.boss end
  if target then
    local dx, dy = target.x - self.x, target.y - self.y
    local d = math.sqrt(dx*dx + dy*dy)
    if d > 4 then
      self.mortar_vx = self.mortar_vx + (dx/d)*40*dt
      self.mortar_vy = self.mortar_vy + (dy/d)*40*dt
    end
  end
  self.x = math.clamp(self.x + self.mortar_vx*dt, arena.x1 + self.r_size, arena.x2 - self.r_size)
  self.y = math.clamp(self.y + self.mortar_vy*dt, arena.y1 + self.r_size, arena.y2 - 20)
  if self.body then self.body:setPosition(self.x, self.y) end

  self.z_vel = self.z_vel - self.z_g*dt
  self.z     = math.max(0, self.z + self.z_vel*dt)

  if self.z <= 0 and self.z_vel < 0 then
    self.mortar_bounces = self.mortar_bounces + 1
    local mult   = self.speed_mult or 1
    local radius = 28 + 26*(mult - 1)
    arena:do_splash_falloff(self.x, self.y, radius, self:current_dmg()*3*mult, self.color)
    -- Feed the combo meter once per impact so mortar runs don't starve it.
    local b = arena:get_nearest_brick_within(self.x, self.y, radius)
    if b and arena.on_brick_bounce then arena:on_brick_bounce(self, b) end
    explosion1:play{volume = 0.35, pitch = random:float(0.85, 1.0)}

    if self.mortar_bounces >= self.mortar_max then
      self:land_mortar()
    else
      self.z_vel = 240*self.mortar_cf
    end
  end
end


-- The charge is consumed: speed_mult resets and the ball drops back into
-- normal 2D play (falling toward the paddle for the next ramp-up loop).
function BallHero:land_mortar()
  self.mortar     = false
  self.speed_mult = 1.0
  self.bounces    = 0
  if self.body then
    self.body:setActive(true)
    self.body:setPosition(self.x, self.y)
  end
  self:set_velocity(random:float(-30, 30), self.base_speed)
end
