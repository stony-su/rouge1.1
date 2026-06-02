-- BallPit: the combined Arkanoid / vampire-survivors gameplay loop.
-- Heroes are balls that bounce in the play area; enemy bricks drift downward
-- and damage the player if they reach the paddle line. Killing bricks drops
-- XP orbs; collecting enough levels the player up and lets them draft a new
-- ball-hero.

-- A static rectangle wall (invisible) used to bound the arena.
Wall = Object:extend()
Wall:implement(GameObject)
Wall:implement(Physics)
function Wall:init(args)
  self:init_game_object(args)
  self:set_as_rectangle(self.w, self.h, 'static', 'wall')
  self:set_restitution(1)
  self:set_friction(0)
end
function Wall:update(dt) self:update_game_object(dt) end
function Wall:draw() end


BallPit = Object:extend()
BallPit:implement(State)
BallPit:implement(GameObject)


-- Per-wave config: row cadence, row width, drift speed and the variant mix.
-- Variants come from SNKRX-master/enemies.lua (Seeker flags and boss subtypes).
-- Mix entries are {variant, weight} pairs that don't need to sum to 100.
local function wave_config(wave)
  -- Wave 10 is the boss wave. Returns a minimal config that disables the
  -- normal swarm spawner entirely; BallPit:start_wave detects `boss = true`
  -- and spawns the boss instead.
  if wave == 10 then
    return {
      boss               = true,
      swarm_interval     = 999,    -- effectively disables periodic spawns
      duration           = 999,    -- advance_wave is triggered by boss death
      swarm_rows_min     = 0, swarm_rows_max = 0,
      width_fraction_min = 0, width_fraction_max = 0,
      swarm_density      = 0,
      drift_speed        = 0,
      min_swarm_gap      = 0,
      mix                = {},
    }
  end

  local mix
  if wave <= 2 then
    mix = {{'seeker', 80}, {'speed_booster', 20}}
  elseif wave <= 4 then
    mix = {{'seeker', 50}, {'speed_booster', 15}, {'exploder', 15}, {'tank', 10}, {'sniper', 10}}
  elseif wave <= 6 then
    mix = {{'seeker', 25}, {'speed_booster', 10}, {'exploder', 12}, {'tank', 12}, {'headbutter', 12},
           {'shooter', 8}, {'sniper', 8}, {'spreader', 8}, {'burster', 5}}
  elseif wave <= 8 then
    mix = {{'seeker', 15}, {'exploder', 12}, {'tank', 12}, {'headbutter', 10}, {'shooter', 8},
           {'spawner', 8}, {'swarmer', 10}, {'sniper', 8}, {'spreader', 8}, {'burster', 5},
           {'arc_lobber', 4}}
  elseif wave == 9 then
    -- Pre-boss "warning" wave: every ranged variant is active, including the
    -- spiraler, so the player gets to taste what the boss will throw at them.
    mix = {{'seeker', 10}, {'tank', 10}, {'shooter', 8}, {'sniper', 10}, {'spreader', 10},
           {'spiraler', 8}, {'burster', 8}, {'arc_lobber', 8}, {'swarmer', 10}, {'forcer', 8},
           {'randomizer', 10}}
  else
    -- wave 11+ post-boss tier: hardest mix including all new ranged variants.
    mix = {{'seeker', 8}, {'tank', 12}, {'headbutter', 8}, {'shooter', 6}, {'spawner', 10},
           {'swarmer', 12}, {'forcer', 10}, {'randomizer', 8}, {'sniper', 10}, {'spreader', 10},
           {'spiraler', 10}, {'burster', 8}, {'arc_lobber', 8}}
  end
  -- All of these slide with wave number so the run gets progressively
  -- harder: more rows, wider swarms, shorter gap between spawns, and a
  -- shrinking minimum vertical gap between successive swarms (so they end
  -- up packed tightly at high waves).
  local min_rows = math.min(7, math.max(3, 3 + math.floor(wave/4)))
  local max_rows = math.min(7, math.max(min_rows, 3 + math.floor(wave/2)))
  local min_w    = math.min(0.80, 0.33 + 0.035*wave)
  local max_w    = math.min(1.00, math.max(min_w + 0.1, 0.55 + 0.045*wave))

  return {
    swarm_interval     = math.max(2.5, 6 - 0.35*wave),       -- spawn frequency ↑
    duration           = 25 + 2*wave,
    swarm_rows_min     = min_rows,
    swarm_rows_max     = max_rows,                            -- swarm size ↑
    width_fraction_min = min_w,
    width_fraction_max = max_w,
    swarm_density      = 0.88,
    -- Drift is scaled by the live arena height (relative to the original
    -- 228px playfield) so a taller map doesn't silently make swarms slower
    -- to reach the paddle. Keeps wave pressure consistent across resolutions.
    drift_speed        = (5 + 0.25*wave)*0.65*((gh - 42)/228),
    -- Vertical breathing room required between a new swarm and any existing
    -- swarm. Starts at 30px (about 2 brick-rows of clear space) and shrinks
    -- to 0 by wave 15, so late-game swarms can stack with no clearance.
    min_swarm_gap      = math.max(0, 30 - 2*wave),
    mix                = mix,
  }
end


function BallPit:init(name)
  self:init_state(name)
  self:init_game_object()

  -- Window-size options for the ESC settings menu. Each entry is a uniform
  -- scale applied to the fixed game canvas (gw x gh = 480 x 656), so the
  -- pixel dimensions are scale*480 x scale*656.
  self.scale_options = {
    {scale = 0.75, label = '0.75x  360 x 492'},
    {scale = 1.0,  label = '1x     480 x 656'},
    {scale = 1.25, label = '1.25x  600 x 820'},
    {scale = 1.5,  label = '1.5x   720 x 984'},
    {scale = 1.75, label = '1.75x  840 x 1148'},
    {scale = 2.0,  label = '2x     960 x 1312'},
  }
  self.settings_open = false
  self.settings_selected = 1
  for i, opt in ipairs(self.scale_options) do
    if math.abs(opt.scale - sx) < 0.01 then self.settings_selected = i; break end
  end
end


function BallPit:apply_scale_option(idx)
  local opt = self.scale_options[idx]
  if not opt then return end
  if math.abs(sx - opt.scale) < 0.01 then return end
  sx, sy = opt.scale, opt.scale
  ww, wh = sx*gw, sy*gh
  if state then state.sx, state.sy = sx, sy end
  love.window.setMode(ww, wh, {vsync = 1, msaa = msaa or 0})
  confirm1:play{volume = 0.4}
end


function BallPit:settings_option_under_mouse()
  local opt_w, opt_h = 200, 16
  local n = #self.scale_options
  local start_y = gh/2 - (n*opt_h)/2 + opt_h/2
  for i = 1, n do
    local oy = start_y + (i-1)*opt_h
    if mouse.x >= gw/2 - opt_w/2 and mouse.x <= gw/2 + opt_w/2
    and mouse.y >= oy - opt_h/2  and mouse.y <= oy + opt_h/2 then
      return i
    end
  end
  return nil
end


function BallPit:update_settings(dt)
  local hovered = self:settings_option_under_mouse()
  if hovered then
    if hovered ~= self.settings_selected then
      self.settings_selected = hovered
      ui_switch1:play{volume = 0.25}
    end
    if input.click.pressed then self:apply_scale_option(self.settings_selected) end
  end

  if input.aim_left.pressed or input.move_left.pressed then
    self.settings_selected = math.max(1, self.settings_selected - 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.aim_right.pressed or input.move_right.pressed then
    self.settings_selected = math.min(#self.scale_options, self.settings_selected + 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.confirm.pressed then self:apply_scale_option(self.settings_selected) end
end


function BallPit:draw_settings()
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0, 0, 0, 0.7))
  graphics.print_centered('SETTINGS', fat_font, gw/2, gh/2 - 90, 0, 1.4, 1.4, 0, 0, yellow[0])
  graphics.print_centered('window size', pixul_font, gw/2, gh/2 - 68, 0, 1, 1, 0, 0, fg[0])

  local opt_w, opt_h = 200, 16
  local n = #self.scale_options
  local start_y = gh/2 - (n*opt_h)/2 + opt_h/2
  for i, opt in ipairs(self.scale_options) do
    local oy = start_y + (i-1)*opt_h
    local selected = (i == self.settings_selected)
    local active   = math.abs(opt.scale - sx) < 0.01
    if selected then
      graphics.rectangle(gw/2, oy, opt_w, opt_h - 2, 2, 2, bg[-1])
      graphics.rectangle(gw/2, oy, opt_w, opt_h - 2, 2, 2, yellow[0], 1)
    end
    local label = opt.label .. (active and '   (current)' or '')
    local color = active and yellow[0] or fg[0]
    graphics.print_centered(label, pixul_font, gw/2, oy - 4, 0, 1, 1, 0, 0, color)
  end

  graphics.print_centered('arrows or mouse to choose, enter or click to apply',
    pixul_font, gw/2, gh/2 + 72, 0, 1, 1, 0, 0, fg_alt[0])
  graphics.print_centered('press ESC to close', pixul_font, gw/2, gh/2 + 86, 0, 1, 1, 0, 0, fg_alt[0])

  -- Hero roster lives below the close-hint, in the otherwise-empty bottom
  -- half of the settings overlay. Hovering a ball pops a name/level/ability
  -- tooltip so the player can audit what they've collected mid-run.
  self:draw_settings_heroes()
end


-- 8-per-row grid position helper. Each row is centered on its own contents,
-- so 1 hero is centered, 8 heroes span the full row width, and a partial
-- second row stays visually balanced under the first row.
function BallPit:hero_grid_pos(i)
  local n = #self.heroes
  local cell_w, cell_h = 22, 24
  local cols_per_row   = 8
  local row = math.floor((i-1)/cols_per_row)
  local col = (i-1) - row*cols_per_row
  local row_start_i = row*cols_per_row + 1
  local row_end_i   = math.min(n, (row+1)*cols_per_row)
  local row_items   = row_end_i - row_start_i + 1
  local start_x = gw/2 - (row_items*cell_w)/2 + cell_w/2
  local hx = start_x + col*cell_w
  local hy = gh/2 + 140 + row*cell_h
  return hx, hy
end


function BallPit:hero_under_mouse_in_settings()
  if not self.heroes then return nil end
  for i = 1, #self.heroes do
    local hx, hy = self:hero_grid_pos(i)
    if math.distance(mouse.x, mouse.y, hx, hy) <= 10 then return i end
  end
  return nil
end


function BallPit:draw_settings_heroes()
  if not self.heroes or #self.heroes == 0 then return end

  graphics.print_centered('HEROES', pixul_font, gw/2, gh/2 + 110, 0, 1, 1, 0, 0, fg[0])
  graphics.print_centered('hover a ball for level + ability', pixul_font, gw/2, gh/2 + 122, 0, 0.85, 0.85, 0, 0, fg_alt[0])

  local hovered_idx = self:hero_under_mouse_in_settings()

  for i, hero in ipairs(self.heroes) do
    local hx, hy = self:hero_grid_pos(i)
    local is_hover = (i == hovered_idx)

    -- Hovered icon gets a faint outer ring so the cursor focus is unmistakable.
    if is_hover then
      graphics.circle(hx, hy, 10, Color(hero.color.r, hero.color.g, hero.color.b, 0.35))
    end
    graphics.circle(hx, hy, 8, hero.color)
    graphics.circle(hx - 2, hy - 2, 2, fg[5])      -- highlight pip, matches upgrade-card style

    -- Level pips below the icon: 1-3 small dots.
    local lvl = hero.level or 1
    local dot_span = (lvl - 1) * 3
    for j = 1, lvl do
      local dx = hx - dot_span/2 + (j-1)*3
      graphics.circle(dx, hy + 11, 1, fg[0])
    end
  end

  -- Tooltip pinned under the grid. Anchored to the last row so it doesn't
  -- jump when the player levels up and a second row appears mid-session.
  if hovered_idx then
    local h = self.heroes[hovered_idx]
    local rows = math.ceil(#self.heroes/8)
    local tip_y = gh/2 + 140 + rows*24 + 4
    local tip = string.upper(h.character) .. '  lv ' .. (h.level or 1)
                .. '  -  ' .. self:hero_ability_blurb(h.character)
    graphics.print_centered(tip, pixul_font, gw/2, tip_y, 0, 1, 1, 0, 0, h.color)
  end
end


function BallPit:on_enter()
  self:reset_run()
  -- Pick a random music track on loop. The list is auto-discovered from
  -- assets/music/ at boot (see main.lua). If the folder is empty, songs
  -- will be empty and the music channel stays silent — gameplay is
  -- unaffected. Stop any previous instance so restarts don't stack
  -- tracks on top of each other.
  if self.song_instance then self.song_instance:stop() end
  if songs and #songs > 0 then
    local pick = songs[random:int(1, #songs)]
    self.song_instance = pick:play{volume = 0.45, loop = true}
  else
    self.song_instance = nil
  end
end


function BallPit:reset_run()
  if self.main then self.main:destroy() end
  if self.effects then self.effects:destroy() end
  if self.ui then self.ui:destroy() end

  self.main    = Group():set_as_physics_world(32, 0, 0, {'paddle', 'ball', 'brick', 'wall', 'xp', 'projectile', 'powerup'})
  self.swarms  = Group():no_camera()  -- controllers, no physics, no camera transform needed
  self.effects = Group()
  self.ui      = Group():no_camera()

  -- Collision matrix.
  self.main:disable_collision_between('ball', 'ball')
  self.main:disable_collision_between('xp', 'ball')
  self.main:disable_collision_between('xp', 'brick')
  self.main:disable_collision_between('xp', 'paddle')
  self.main:disable_collision_between('xp', 'projectile')
  self.main:disable_collision_between('xp', 'wall')
  self.main:disable_collision_between('xp', 'xp')
  self.main:disable_collision_between('projectile', 'paddle')
  self.main:disable_collision_between('projectile', 'ball')
  self.main:disable_collision_between('projectile', 'projectile')
  self.main:disable_collision_between('projectile', 'wall')
  self.main:disable_collision_between('brick', 'paddle')
  self.main:disable_collision_between('brick', 'brick')  -- adjacent bricks in a row touch
  self.main:disable_collision_between('brick', 'wall')   -- kinematic bricks don't react anyway
  self.main:disable_collision_between('paddle', 'wall')
  -- Powerup orbs bounce off the side/top walls so they stay in play (the
  -- bottom is open, so missed orbs still fall into the pit and despawn).
  -- They don't physically interact with anything else — paddle catches and
  -- tier-2 deflects are driven by the proximity check inside Powerup:update,
  -- not Box2D contacts.
  self.main:disable_collision_between('powerup', 'paddle')
  self.main:disable_collision_between('powerup', 'ball')
  self.main:disable_collision_between('powerup', 'brick')
  self.main:disable_collision_between('powerup', 'projectile')
  self.main:disable_collision_between('powerup', 'xp')
  self.main:disable_collision_between('powerup', 'powerup')

  -- Arena bounds.
  self.x1, self.y1 = 24, 18
  self.x2, self.y2 = gw - 24, gh - 24

  -- Static walls (left, right, top). The bottom is open — balls that miss
  -- the paddle fall into the pit and are pulled magnetically back to the
  -- paddle, where they stick for an aimed re-launch.
  local thick = 8
  self:spawn_wall(self.x1 - thick/2, (self.y1 + self.y2)/2, thick, self.y2 - self.y1 + thick)  -- left
  self:spawn_wall(self.x2 + thick/2, (self.y1 + self.y2)/2, thick, self.y2 - self.y1 + thick)  -- right
  self:spawn_wall((self.x1 + self.x2)/2, self.y1 - thick/2, self.x2 - self.x1 + thick, thick)  -- top

  -- Paddle.
  self.paddle = Paddle{group = self.main, x = gw/2, y = self.y2 - 14}

  -- Starting hero pool — player starts with two vagrants.
  self.heroes = {}
  self:add_hero('vagrant')
  self:add_hero('swordsman')

  -- Run state.
  self.player_hp     = 5
  self.player_hp_max = 5
  self.xp            = 0
  self.level         = 1
  self.xp_to_next    = 5
  self.wave          = 1
  self.wave_time     = 0
  self.boss          = nil
  self.boss_defeated = false
  self.score         = 0
  self.run_time      = 0
  self.paused        = false
  self.game_over     = false
  self.upgrade_pending = false
  self.upgrade_choices = nil
  self.upgrade_selected = 1
  self.show_hero_labels = false

  -- Stuck-ball aim state. While stuck_count > 0, paddle freezes and the
  -- left/right keys rotate aim_angle; SPACE launches every stuck ball.
  self.stuck_count = 0
  self.aim_angle   = -math.pi/2
  self.aim_speed   = math.pi*1.1   -- rad/s while holding left or right

  -- Admin cheats. Created once and preserved across reset_run so the operator
  -- doesn't lose their open log when they hit R to restart.
  self.god      = self.god or false
  self.terminal = self.terminal or Terminal(self)
  self.terminal.arena = self  -- re-point at the fresh arena state after reset

  -- Powerup state. `buffs` is a table keyed by powerup kind holding the
  -- {expires_at, restore} pair for every active timed effect. `fire_trail_until`
  -- and `no_speed_reset` are simple flags read from BallHero. `floor_wall` is
  -- a reference to the temporary bottom-wall spawned by the floor powerup so
  -- we can despawn it at wave end / on reset.
  self.buffs              = {}
  self.fire_trail_until   = 0
  self.no_speed_reset     = false
  self.floor_wall         = nil
  self.pierce_active      = false

  -- Powerup pity timer. Powerups no longer drop from individual bricks; they
  -- spawn on a periodic random roll instead, with a ramping pity multiplier
  -- so a long dry streak is impossible. Tuning:
  --   * Every `check_interval` seconds we roll for a spawn.
  --   * Base spawn chance is `base_chance`; each failed roll adds
  --     `pity_step` to the next check, capped at 100%.
  --   * On a successful spawn the streak counter resets to 0.
  -- With the values below the expected gap between powerups is ~14s and the
  -- maximum possible gap is ~30s (check_interval * 5). The wave-end tier-2
  -- in advance_wave is a separate guaranteed drop.
  self.powerup_pity = {
    timer          = 0,
    check_interval = 6,
    streak         = 0,
    base_chance    = 0.25,
    pity_step      = 0.20,
    tier2_chance   = 0.20,   -- on a spawn, this fraction roll the rare tier
  }

  self:start_wave()
end


function BallPit:spawn_wall(x, y, w, h)
  return Wall{group = self.main, x = x, y = y, w = w, h = h}
end


-- Returns the first currently-stuck hero in `self.heroes`, or nil if none.
-- Used by BallHero:draw so only one charge ring shows at a time even when
-- several balls are glued to the paddle together.
function BallPit:lead_stuck_ball()
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and h.stuck then return h end
  end
  return nil
end


-- Counts heroes already in play whose character uses the same base colour as
-- `character`. Comparison is on the colour value, not the character name, so
-- e.g. a wizard adds to the same-colour tally for a magician (both blue).
function BallPit:count_same_color_heroes(character)
  local base = character_colors[character] or fg[0]
  local n = 0
  for _, h in ipairs(self.heroes) do
    local hc = character_colors[h.character] or fg[0]
    if hc.r == base.r and hc.g == base.g and hc.b == base.b then
      n = n + 1
    end
  end
  return n
end


function BallPit:add_hero(character)
  local count = #self.heroes
  local x = self.paddle.x + (count - 1)*6
  local y = self.paddle.y - 14
  -- Count how many alive heroes already share this character's base colour,
  -- so the new ball gets a unique shade offset (and stays readable on screen
  -- + in the roster column on the left).
  local shade_offset = self:count_same_color_heroes(character)
  local hero = BallHero{
    group        = self.main,
    x            = x, y = y,
    character    = character,
    level        = 1,
    shade_offset = shade_offset,
  }
  hero.on_collision_enter = function(h, other, contact)
    if not other then return end
    if other.tag == 'brick' then
      h:on_brick_hit(other)
      h.spring:pull(0.22)
      -- Spark burst at the impact point, aimed back along the ball's incoming direction.
      local vx, vy = h:get_velocity()
      local impact_angle = math.atan2(-vy, -vx)
      spawn_bounce_sparks(self.effects, h.x, h.y, impact_angle, h.color)
      -- Pierce powerup: undo Box2D's bounce by restoring the velocity the
      -- ball had just before this collision. Deferred to next frame since
      -- the Box2D world is locked during the callback.
      if self.pierce_active and h._last_vx then
        local lvx, lvy = h._last_vx, h._last_vy
        self.t:after(0, function()
          if h.body and not h.dead then h:set_velocity(lvx, lvy) end
        end)
      end
    elseif other.tag == 'paddle' then
      other:on_ball_bounce(h)
    elseif other.tag == 'wall' then
      h.spring:pull(0.1)
      local vx, vy = h:get_velocity()
      spawn_bounce_sparks(self.effects, h.x, h.y, math.atan2(-vy, -vx), h.color)
      if random:bool(40) then bounce1:play{volume = 0.12, pitch = random:float(1.0, 1.1)} end
    end
  end
  table.insert(self.heroes, hero)
  return hero
end


function BallPit:start_wave()
  self.wave_cfg  = wave_config(self.wave)
  self.wave_time = 0

  -- Boss wave: skip the periodic swarm spawner entirely and spawn the boss
  -- directly. advance_wave for this wave is gated on boss_defeated being set
  -- by Boss:die (see BallPit:update).
  if self.wave_cfg.boss then
    self:spawn_boss()
    return
  end

  self.t:every(self.wave_cfg.swarm_interval, function()
    if self.paused or self.game_over or self.upgrade_pending then return end
    self:spawn_swarm()
  end, 0, nil, 'spawn_swarm')

  if self.wave == 1 and #self.swarms.objects == 0 then
    self:spawn_swarm(true)  -- force-spawn the first swarm so the screen isn't empty
  end
end


function BallPit:spawn_boss()
  local arena = self
  arena.t:after(0, function()
    if arena.main and arena.main.world then
      arena.boss = Boss{
        group = arena.main,
        x     = arena:arena_center_x(),
        y     = arena.y1 + 60,
      }
      Flash{group = arena.effects, x = gw/2, y = gh/2,
            color = red_transparent_weak, duration = 0.4}
    end
  end)
end


function BallPit:advance_wave()
  -- Guaranteed end-of-wave Tier-2 powerup drop. Spawned just inside the top
  -- of the arena so it's visible / catchable as the next wave starts. Fires
  -- on every wave clear, so slow runs still see at least one Tier-2 per wave.
  if Powerup then
    local t2 = Powerup.tier_2_kinds()
    if #t2 > 0 then
      local kind = t2[random:int(1, #t2)]
      local x    = self:arena_center_x() + random:float(-40, 40)
      local y    = self.y1 + 20
      self.t:after(0, function()
        if self.main and self.main.world then
          Powerup{group = self.main, x = x, y = y, kind = kind}
        end
      end)
    end
  end

  -- The "no-reset + floor" powerup lasts until the next wave starts. Tear
  -- down the temporary bottom wall + clear the flag here so the player has
  -- to re-earn the floor each wave.
  if self.floor_wall then
    self.floor_wall.dead = true
    self.floor_wall      = nil
    self.no_speed_reset  = false
  end

  -- The wave-end tier-2 drop above counts as the start-of-wave powerup; reset
  -- the pity counter so the very next pity roll doesn't immediately spawn a
  -- second powerup on top of it.
  if self.powerup_pity then
    self.powerup_pity.timer  = 0
    self.powerup_pity.streak = 0
  end

  self.wave = self.wave + 1
  self.t:cancel('spawn_swarm')
  self:start_wave()
end


function BallPit:roll_variant()
  local total = 0
  for _, entry in ipairs(self.wave_cfg.mix) do total = total + entry[2] end
  local roll = random:float(0, total)
  local cum = 0
  for _, entry in ipairs(self.wave_cfg.mix) do
    cum = cum + entry[2]
    if roll <= cum then return entry[1] end
  end
  return 'seeker'
end


-- Brick grid is centered on the arena and cell-sized at 22×14 (one brick +
-- one slot of gap). Snapping the swarm centre to a multiple of cell_w from the
-- arena centre keeps every brick at a deterministic (col, row) so the overlap
-- test is just an equality check.
local CELL_W, CELL_H = 22, 14


function BallPit:arena_center_x()
  return (self.x1 + self.x2)/2
end


function BallPit:snap_to_grid_x(x)
  local cx = self:arena_center_x()
  return cx + math.floor((x - cx)/CELL_W + 0.5)*CELL_W
end


-- Per-cell overlap check: walks every live brick in every live swarm and
-- bails if any of them shares a cell with the planned layout. The vertical
-- threshold is widened by `min_gap` so that early waves enforce a few rows
-- of empty space between successive swarms.
-- Per-cell overlap check: walks every live brick in every live swarm and
-- bails if any of them shares a grid cell with the planned layout. Each
-- entry may be a multi-cell brick now (2x2, L, T, etc.), so we expand both
-- sides to their full {x, y} per-cell footprint and compare cells to cells
-- — the brick centroid alone is no longer enough.
local function expand_to_cells(item, x_anchor, y_anchor)
  local cells_def = item.shape_cells or {{0,0}}
  local n = #cells_def
  local sum_cx, sum_cy = 0, 0
  for _, c in ipairs(cells_def) do sum_cx = sum_cx + c[1]; sum_cy = sum_cy + c[2] end
  local cx_c, cy_c = sum_cx/n, sum_cy/n
  local out = {}
  for _, c in ipairs(cells_def) do
    table.insert(out, {
      x = x_anchor + item.dx + (c[1] - cx_c) * CELL_W,
      y = y_anchor + item.dy + (c[2] - cy_c) * CELL_H,
    })
  end
  return out
end

function BallPit:can_place_layout(x_center, y_top, cells_layout, min_gap)
  min_gap = min_gap or 0
  local v_threshold = CELL_H - 1 + min_gap

  -- Build the new layout's full cell footprint once.
  local new_cells = {}
  for _, item in ipairs(cells_layout) do
    for _, p in ipairs(expand_to_cells(item, x_center, y_top)) do
      table.insert(new_cells, p)
    end
  end

  for _, swarm in ipairs(self.swarms.objects) do
    if swarm and not swarm.dead then
      for _, ec in ipairs(swarm.cells or {}) do
        local b = ec.brick
        if b and not b.dead then
          -- Use the swarm's logical centre (no knockback offset) so a
          -- transient spring oscillation doesn't unblock a cell.
          for _, ep in ipairs(expand_to_cells(ec, swarm.x_center, swarm.y_top)) do
            for _, np in ipairs(new_cells) do
              if math.abs(np.x - ep.x) < CELL_W - 1 and math.abs(np.y - ep.y) < v_threshold then
                return false
              end
            end
          end
        end
      end
    end
  end
  return true
end


-- Counts the live bricks in each horizontal third of the arena. Used to
-- bias new swarms toward the less-populated side.
function BallPit:zone_occupancy()
  local left, mid, right = 0, 0, 0
  local arena_w = self.x2 - self.x1
  for _, swarm in ipairs(self.swarms.objects) do
    if swarm and not swarm.dead then
      for _, cell in ipairs(swarm.cells or {}) do
        local b = cell.brick
        if b and not b.dead then
          local bx = swarm.x_center + cell.dx
          local rel = (bx - self.x1)/arena_w
          if     rel < 1/3 then left  = left  + 1
          elseif rel < 2/3 then mid   = mid   + 1
          else                  right = right + 1 end
        end
      end
    end
  end
  return left, mid, right
end


-- Pick an anchor x for a new swarm. Squared-inverse weights bias toward the
-- least-occupied third; the swarm is then constrained so it still fits inside
-- the arena given its width.
function BallPit:pick_swarm_anchor(width_fraction)
  local arena_w = self.x2 - self.x1
  local cx      = self:arena_center_x()
  if width_fraction >= 0.97 then return cx end
  local half_w = width_fraction*arena_w*0.5
  local min_cx = self.x1 + half_w + 4
  local max_cx = self.x2 - half_w - 4
  if max_cx < min_cx then return cx end

  local left, mid, right = self:zone_occupancy()
  local total = left + mid + right
  local w_left  = (total - left  + 1)^2
  local w_mid   = (total - mid   + 1)^2
  local w_right = (total - right + 1)^2

  local roll = random:float(0, w_left + w_mid + w_right)
  local anchor
  if     roll < w_left         then anchor = self.x1 + arena_w*0.25
  elseif roll < w_left + w_mid then anchor = cx
  else                              anchor = self.x1 + arena_w*0.75 end
  anchor = anchor + random:float(-CELL_W, CELL_W)
  return math.clamp(anchor, min_cx, max_cx)
end


function BallPit:spawn_swarm(force)
  local cfg            = self.wave_cfg
  local rows_count     = random:int(cfg.swarm_rows_min, cfg.swarm_rows_max)
  local width_fraction = random:float(cfg.width_fraction_min, cfg.width_fraction_max)
  local arena_w        = self.x2 - self.x1
  local max_cols       = math.max(2, math.floor(width_fraction*arena_w/CELL_W))

  -- Plan the per-row irregular layout once, then try a few anchor positions
  -- (zone-biased + snapped to grid) until we find one with no overlaps.
  local layout = Swarm.generate_cells(rows_count, max_cols, cfg.swarm_density, CELL_W, CELL_H)
  local y_top  = self.y1 + 8

  local x_center
  for attempt = 1, 8 do
    x_center = self:snap_to_grid_x(self:pick_swarm_anchor(width_fraction))
    if force or self:can_place_layout(x_center, y_top, layout, cfg.min_swarm_gap) then
      Swarm{
        group          = self.swarms,
        x_center       = x_center,
        y              = y_top,
        spacing_x      = CELL_W,
        spacing_y      = CELL_H,
        drift          = cfg.drift_speed,
        variant_picker = function() return self:roll_variant() end,
        cells_layout   = layout,
      }
      return
    end
  end
  -- All attempts blocked: skip this tick. Next interval will try again with a
  -- fresh layout once existing swarms have drifted further down.
end


function BallPit:update(dt)
  -- Terminal always ticks first, at real-time dt. The toggle key fires here
  -- regardless of pause / game-over / upgrade state, and while the terminal
  -- is open we suspend gameplay entirely (no physics, no swarm drift, no
  -- timer callbacks) so the operator can read and type in peace.
  --
  -- Two ways to toggle: the backtick / F1 key, or clicking the ADMIN button
  -- in the top-right of the HUD. The button click is checked here (before the
  -- early-return) so it works as both "open" and "close" — and so the click
  -- doesn't fall through to the upgrade-card hit-test or any future click
  -- consumers.
  if input.toggle_terminal.pressed then self.terminal:toggle() end
  if input.click.pressed and self:admin_button_hit() then
    self.terminal:toggle()
    -- Eat this click so it doesn't double up with anything else this frame.
    input.click.pressed = false
  end
  self.terminal:update(dt)
  if self.terminal.open then
    -- Still tick UI animations + effects so the screen doesn't look frozen;
    -- skip everything that advances world state.
    self.ui:update(dt)
    return
  end

  -- ESC toggles the settings overlay (window size). Checked after the
  -- terminal early-return so ESC is ignored while the operator is typing.
  if input.escape.pressed then
    self.settings_open = not self.settings_open
    ui_switch1:play{volume = 0.3}
  end
  if self.settings_open then
    self:update_settings(dt)
    return
  end

  -- Apply the game-speed cheat to everything that follows. Timers and the
  -- gameplay simulation get scaled by `s`; for s > 1 we sub-step the heavy
  -- bits to keep Box2D stable.
  local s = admin_speed or 1

  self.t:update(dt*s)

  if self.game_over then
    self.ui:update(dt*s)
    if input.restart.pressed then self:reset_run() end
    return
  end

  if self.upgrade_pending then
    self:update_upgrade(dt)
    self.effects:update(dt*s)
    self.ui:update(dt*s)
    return
  end

  local steps = 1
  local sdt   = dt*s
  if s > 1 then
    steps = math.min(20, math.max(1, math.floor(s + 0.5)))
    sdt   = dt*s/steps
  end

  for step = 1, steps do
    self.run_time  = self.run_time + sdt
    self.wave_time = self.wave_time + sdt

    -- Aim is adjustable whenever space is held OR a ball is stuck on the paddle.
    -- Holding space is the "auto-fire" mode: the aim line shows, arrow keys
    -- nudge the angle, and any stuck ball fires immediately (returning balls
    -- skip the stuck state entirely, see BallHero:update_return).
    local aim_active = self.stuck_count > 0 or input.launch.down
    if aim_active then
      if input.aim_left.down then
        self.aim_angle = math.max(self.aim_angle - self.aim_speed*sdt, -math.pi*0.92)
      end
      if input.aim_right.down then
        self.aim_angle = math.min(self.aim_angle + self.aim_speed*sdt, -math.pi*0.08)
      end
    end
    -- Launch-stuck-balls only fires once per real frame, not once per sub-step
    -- (otherwise the launch sound stacks and the same balls re-fire).
    if self.stuck_count > 0 and input.launch.down and step == steps then
      self:launch_stuck_balls()
    end

    self.main:update(sdt)
    self.swarms:update(sdt)
    self.effects:update(sdt)
    self.ui:update(sdt)

    -- Powerup buffs are time-based; tick them with the same sub-step dt so
    -- speed cheats and freeze cheats stay consistent across the rest of
    -- gameplay (game-speed × → buff timers also ×).
    self:tick_buffs(sdt)

    -- Powerup pity timer (random spawns replacing the old per-brick drop).
    self:tick_powerup_pity(sdt)

    -- Boss wave: short-circuit the duration check. advance_wave fires the
    -- moment the boss flips boss_defeated in its die().
    if self.wave_cfg.boss and self.boss_defeated then
      self.boss_defeated = false
      self.boss          = nil
      self:advance_wave()
    end

    -- Wave end → wave advance (purely time-based; leftover bricks roll into the next wave).
    if self.wave_time >= self.wave_cfg.duration then
      self:advance_wave()
    end
  end
end


function BallPit:draw()
  self.main:draw()
  self.effects:draw()
  if self.stuck_count > 0 or input.launch.down then self:draw_aim_line() end
  self.ui:draw()
  self:draw_hud()
  self:draw_buff_strip()

  if (admin_speed or 1) ~= 1 or self.god then
    local hint = ''
    if (admin_speed or 1) ~= 1 then hint = hint .. string.format('%.2fx ', admin_speed) end
    if self.god then hint = hint .. 'GOD ' end
    graphics.print(hint, pixul_font, gw - 92, 16, 0, 1, 1, 0, 0, red[0])
  end

  if self.upgrade_pending then self:draw_upgrade() end
  if self.game_over then self:draw_game_over() end
  if self.settings_open then self:draw_settings() end
  -- Terminal draws on top of everything so it stays readable over flashes,
  -- the upgrade dialog, and the game-over overlay.
  if self.terminal then self.terminal:draw() end
  -- Admin button is drawn LAST so it sits on top of every overlay (upgrade
  -- picker, game-over modal, terminal panel itself acting as a close button).
  -- Clicking it pauses the game and opens the command terminal.
  self:draw_admin_button()
end


function BallPit:draw_aim_line()
  local px = self.paddle.x
  local py = self.paddle.y - self.paddle.h/2 - 4
  local len = 36
  local ex = px + math.cos(self.aim_angle)*len
  local ey = py + math.sin(self.aim_angle)*len
  graphics.dashed_line(px, py, ex, ey, 3, 2, fg[0], 1)
  graphics.circle(ex, ey, 2, fg[0])
end


-- Admin button rect (canvas-space). Slotted into the empty corner between
-- the XP bar's right end (x ~ 446) and the canvas right edge (x = gw), on
-- the same y-row as the HP hearts. Stays clear of the playfield, the hero
-- roster column on the left, and the bottom HUD that may be clipped on
-- shorter monitors. Returns the centre + size of the rect.
function BallPit:admin_button_rect()
  local w, h = 28, 10
  local cx   = gw - w/2 - 2
  local cy   = self.y1 - 8         -- aligned with hearts + XP bar
  return cx, cy, w, h
end


function BallPit:admin_button_hit()
  local cx, cy, w, h = self:admin_button_rect()
  return mouse.x >= cx - w/2 and mouse.x <= cx + w/2
     and mouse.y >= cy - h/2 and mouse.y <= cy + h/2
end


function BallPit:draw_admin_button()
  local cx, cy, w, h = self:admin_button_rect()
  local hovered  = self:admin_button_hit()
  local active   = self.terminal and self.terminal.open
  local fill     = active and yellow[0] or (hovered and bg[2] or bg[-1])
  local border   = active and yellow[5] or (hovered and yellow[0] or fg_transparent_weak)
  local label_c  = active and bg[-2] or yellow[0]
  graphics.rectangle(cx, cy, w, h, 2, 2, fill)
  graphics.rectangle(cx, cy, w, h, 2, 2, border, 1)
  graphics.print_centered(active and 'CLOSE' or 'ADMIN', pixul_font, cx, cy - 4, 0, 1, 1, 0, 0, label_c)
end


function BallPit:draw_hud()
  -- Frame around playfield.
  graphics.rectangle((self.x1 + self.x2)/2, (self.y1 + self.y2)/2,
    self.x2 - self.x1, self.y2 - self.y1, 2, 2, fg_transparent_weak, 1)

  -- HP hearts.
  for i = 1, self.player_hp_max do
    local color = i <= self.player_hp and red[0] or bg[2]
    graphics.rectangle(self.x1 + 6 + (i-1)*10, self.y1 - 8, 6, 6, 1, 1, color)
  end

  -- XP bar.
  local bw = self.x2 - self.x1 - 70
  local bx = self.x1 + 60
  graphics.rectangle(bx + bw/2, self.y1 - 8, bw, 4, nil, nil, bg[-2])
  local pct = math.clamp(self.xp/self.xp_to_next, 0, 1)
  if pct > 0 then
    graphics.rectangle(bx + bw*pct/2, self.y1 - 8, bw*pct, 4, nil, nil, blue[0])
  end

  -- Level + wave + score.
  graphics.print('Lv ' .. self.level, pixul_font, self.x1 + 4, self.y2 + 4, 0, 1, 1, 0, 0, fg[0])
  graphics.print('Wave ' .. self.wave, pixul_font, (self.x1 + self.x2)/2 - 18, self.y2 + 4, 0, 1, 1, 0, 0, fg[0])
  graphics.print('Time ' .. math.floor(self.run_time), pixul_font, self.x2 - 50, self.y2 + 4, 0, 1, 1, 0, 0, fg[0])

  -- Hero roster: a vertical column tucked into the left margin (outside the
  -- play area), so it doesn't crowd the "Lv N" / wave / time row.
  local rx = math.max(8, self.x1 - 12)
  for i, hero in ipairs(self.heroes) do
    local ry = self.y1 + 14 + (i - 1)*8
    graphics.circle(rx, ry, 3, hero.color)
    graphics.circle(rx - 0.9, ry - 0.9, 1, fg[5])
  end
end


-- ----- Damage / upgrades / progression -----

function BallPit:on_brick_killed(brick)
  self.score = self.score + brick.xp_value*10
end


-- Used for single-enemy breaches (mobile critters that wander down past the paddle).
function BallPit:on_brick_breached(brick)
  -- Godmode swallows the hp loss but still plays the feedback so the operator
  -- can see what *would* have hit them.
  if not self.god then
    self.player_hp = self.player_hp - (brick.player_dmg or 1)
  end
  hit1:play{volume = 0.45, pitch = random:float(0.95, 1.05)}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = red_transparent_weak, duration = 0.08}
  spawn_burst(self.effects, brick.x, brick.y, red[0], 8, 60, 140)
  camera:shake(3, 0.2, 80)
  self.paddle.hfx:use('hit', 0.25, 200, 10)
  if self.player_hp <= 0 then self:trigger_game_over() end
end


-- Used when a whole Swarm reaches the paddle. HP loss scales with brick
-- count but is capped so a wide swarm doesn't insta-kill.
function BallPit:on_row_breached(swarm, brick_count)
  local dmg = math.min(3, 1 + math.floor(brick_count/4))
  if not self.god then
    self.player_hp = self.player_hp - dmg
  end
  hit1:play{volume = 0.5, pitch = random:float(0.9, 1.0)}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = red_transparent_weak, duration = 0.12}
  camera:shake(6 + brick_count*0.4, 0.4, 80)
  self.paddle.hfx:use('hit', 0.4, 200, 10)
  -- Burst at each surviving brick for a meaty visual. Swarms store bricks
  -- under .cells (each cell = {brick, dx, dy}) plus a single shared offset.
  for _, cell in ipairs(swarm.cells or {}) do
    if cell.brick and not cell.brick.dead then
      local bx = swarm.x_center + cell.dx + (swarm.x_offset or 0)
      local by = swarm.y_top    + cell.dy + (swarm.y_offset or 0)
      spawn_burst(self.effects, bx, by, red[0], 6, 60, 140)
    end
  end
  if self.player_hp <= 0 then self:trigger_game_over() end
end




function BallPit:gain_xp(amount)
  self.xp = self.xp + amount
  FloatingText{group = self.effects, x = self.paddle.x, y = self.paddle.y - 16, text = '+' .. amount, color = blue[0]}
  while self.xp >= self.xp_to_next do
    self.xp = self.xp - self.xp_to_next
    self:level_up()
  end
end


function BallPit:level_up()
  self.level      = self.level + 1
  self.xp_to_next = math.floor(self.xp_to_next * 1.35 + 1)
  level_up1:play{volume = 0.5}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = yellow_transparent_weak, duration = 0.15}
  camera:shake(3, 0.2, 90)
  self.paddle.hfx:use('hit', 0.3, 200, 10)
  self:offer_upgrades()
end


function BallPit:offer_upgrades()
  self.upgrade_pending = true
  self.upgrade_selected = 1
  local pool = {}
  for _, c in ipairs(hero_pool) do table.insert(pool, c) end
  table.shuffle(pool)
  self.upgrade_choices = {}
  for i = 1, 3 do
    local c = pool[i]
    local action = 'add'
    -- 35% chance to instead level up an existing hero of that type.
    local exists = false
    for _, h in ipairs(self.heroes) do if h.character == c and h.level < 3 then exists = true; break end end
    if exists and random:bool(35) then action = 'upgrade' end
    table.insert(self.upgrade_choices, {character = c, action = action})
  end
end


function BallPit:update_upgrade(dt)
  -- Mouse: hover over a card to select it, click to confirm.
  local hovered_card = self:upgrade_card_under_mouse()
  if hovered_card then
    if hovered_card ~= self.upgrade_selected then
      self.upgrade_selected = hovered_card
      ui_switch1:play{volume = 0.25}
    end
    if input.click.pressed then
      self:confirm_upgrade()
      return
    end
  end

  -- Keyboard: arrow keys move selection, Enter confirms.
  if input.aim_left.pressed then
    self.upgrade_selected = math.max(1, self.upgrade_selected - 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.aim_right.pressed then
    self.upgrade_selected = math.min(3, self.upgrade_selected + 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.confirm.pressed then
    self:confirm_upgrade()
  end
end


-- Hit-test the three upgrade cards against the mouse position; returns the
-- card index 1..3 or nil if the cursor is outside all of them.
function BallPit:upgrade_card_under_mouse()
  local card_w, card_h = 92, 110
  for i = 1, 3 do
    local cx = gw/2 + (i - 2)*110
    local cy = gh/2
    if mouse.x >= cx - card_w/2 and mouse.x <= cx + card_w/2
    and mouse.y >= cy - card_h/2 and mouse.y <= cy + card_h/2 then
      return i
    end
  end
  return nil
end


-- Apply whichever choice is currently selected and close the upgrade menu.
function BallPit:confirm_upgrade()
  local choice = self.upgrade_choices[self.upgrade_selected]
  if choice.action == 'upgrade' then
    for _, h in ipairs(self.heroes) do
      if h.character == choice.character and h.level < 3 then
        h.level = h.level + 1
        h.dmg = h.dmg * 1.4
        self:flash_hero_level_up(h)
        break
      end
    end
  else
    self:add_hero(choice.character)
  end
  confirm1:play{volume = 0.4}
  self.upgrade_pending = false
  self.upgrade_choices = nil
end


-- A brief visual confirmation that a specific hero just gained a level.
-- Used by the draft picker (BallPit:confirm_upgrade) and the "level random
-- balls" powerup (BallPit:apply_level_random). Pulses the ball, expands a
-- yellow telegraph ring out of it, drops a "+LVL" floating label, and
-- spawns a small burst of sparks.
function BallPit:flash_hero_level_up(hero)
  if not (hero and not hero.dead) then return end
  hero.spring:pull(0.35)
  TelegraphRing{
    group    = self.effects, x = hero.x, y = hero.y,
    radius   = hero.r_size*3.5, color = yellow[0], duration = 0.35,
  }
  spawn_burst(self.effects, hero.x, hero.y, yellow[0], 6, 70, 130)
  FloatingText{
    group = self.effects, x = hero.x, y = hero.y - hero.r_size - 4,
    text  = '+LVL ' .. (hero.level or 1), color = yellow[0],
  }
end


function BallPit:draw_upgrade()
  -- Dim background.
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0, 0, 0, 0.55))
  graphics.print_centered('LEVEL UP — pick a hero', fat_font, gw/2, 38, 0, 1, 1, 0, 0, yellow[0])
  graphics.print_centered('arrows or mouse to choose, enter or click to confirm', pixul_font, gw/2, 56, 0, 1, 1, 0, 0, fg[0])

  for i, choice in ipairs(self.upgrade_choices) do
    local cx = gw/2 + (i-2)*110
    local cy = gh/2
    local selected = (i == self.upgrade_selected)
    local card_w, card_h = 92, 110
    local border = selected and yellow[0] or fg_transparent_weak
    graphics.rectangle(cx, cy, card_w, card_h, 4, 4, bg[-1])
    graphics.rectangle(cx, cy, card_w, card_h, 4, 4, border, selected and 2 or 1)

    local color = character_colors[choice.character] or fg[0]
    graphics.circle(cx, cy - 18, 16, color)
    graphics.circle(cx - 5, cy - 23, 5, fg[5])
    graphics.print_centered(choice.character, pixul_font, cx, cy + 8, 0, 1, 1, 0, 0, fg[0])
    graphics.print_centered(choice.action == 'upgrade' and '+1 LEVEL' or 'NEW BALL', pixul_font, cx, cy + 24, 0, 1, 1, 0, 0,
      choice.action == 'upgrade' and yellow[0] or green[0])
    graphics.print_centered(self:hero_ability_blurb(choice.character), pixul_font, cx, cy + 40, 0, 0.8, 0.8, 0, 0, fg_alt[0])
  end
end


function BallPit:hero_ability_blurb(c)
  local blurbs = {
    -- Projectile shooters
    vagrant      = 'arrow shot',
    archer       = 'pierce arrow',
    outlaw       = 'fast arrow',
    sage         = 'slow arrow',
    blade        = 'short arrow',
    dual_gunner  = 'rapid arrow',
    hunter       = 'long range',
    lich         = 'chain ricochet',
    corruptor    = 'pierce x3',
    beastmaster  = 'crit shot',
    arcanist     = 'heavy pierce',
    merchant     = 'basic shot',

    -- Knives
    scout        = 'knife x3 bounce',
    thief        = 'knife x5 bounce',
    assassin     = 'fast pierce',

    -- Special projectiles
    spellblade   = 'random shot',
    barrager     = '3-shot burst',

    -- Melee splash
    swordsman    = 'splash strike',
    barbarian    = 'heavy splash',
    juggernaut   = 'splash+push',
    elementor    = 'wide splash',
    highlander   = 'rapid splash',
    miner        = 'dig splash',

    -- Random-target splash
    magician     = 'random splash',
    psychic      = 'mind splash',

    -- Healers
    cleric       = '+1 hp / 8s',
    priest       = '+2 hp / 12s',
    psykeeper    = '+1 hp / 10s',

    -- Curse / vulnerability
    launcher     = 'curse x4',
    jester       = 'curse x6',
    usurer       = 'curse + dot',
    silencer     = 'strong curse',
    bane         = 'big curse',

    -- DoT clouds
    plague_doctor = 'poison cloud',
    witch        = 'toxic cloud',

    -- Bomb drops
    saboteur     = 'drops 2 mines',
    bomber       = 'drops bomb',
    vulcanist    = 'volcano',

    -- Turret drops
    engineer     = 'drops turret',
    sentry       = 'fast turret',
    carver       = 'long turret',
    artificer    = 'rapid turrets',

    -- Force area
    psykino      = 'knockback',

    -- Ally damage buffs
    stormweaver  = '+50% ally dmg',
    warden       = '+30% ally dmg',

    -- Ally attack-speed buffs
    fairy        = '2x ally aspd',
    squire       = '1.5x ally aspd',

    -- Pet summons
    host         = 'pet / 4s',
    infestor     = '3 pets / 10s',
    illusionist  = '2 pets / 8s',

    -- Misc
    gambler      = 'lucky strikes',
    chronomancer = 'slow swarms',

    -- On-bounce specials
    wizard       = 'chain on hit',
    cryomancer   = 'freeze on hit',
    pyromancer   = 'burn on hit',
    cannoneer    = 'boom on hit',
    flagellant   = 'pulse on hit',
  }
  return blurbs[c] or 'ball-hero'
end


function BallPit:trigger_game_over()
  self.game_over = true
  self.t:cancel('spawn_brick')
  Flash{group = self.effects, x = gw/2, y = gh/2, color = Color(0, 0, 0, 0.4), duration = 0.4}
end


function BallPit:draw_game_over()
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0, 0, 0, 0.7))
  graphics.print_centered('GAME OVER', fat_font, gw/2, gh/2 - 24, 0, 1.4, 1.4, 0, 0, red[0])
  graphics.print_centered('Wave ' .. self.wave .. '   Score ' .. self.score, pixul_font, gw/2, gh/2, 0, 1, 1, 0, 0, fg[0])
  graphics.print_centered('press R to restart', pixul_font, gw/2, gh/2 + 16, 0, 1, 1, 0, 0, fg_alt[0])
end


-- ----- Ability helpers used by ball heroes -----

function BallPit:get_nearest_brick(x, y, exclude)
  local best, best_d = nil, 1e9
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead and (not exclude or o.id ~= exclude.id) then
      local d = math.distance(x, y, o.x, o.y)
      if d < best_d then best_d = d; best = o end
    end
  end
  return best
end


function BallPit:has_brick_within(x, y, range)
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead then
      if math.distance(x, y, o.x, o.y) <= range then return true end
    end
  end
  return false
end


function BallPit:get_nearest_brick_within(x, y, range)
  local best, best_d = nil, range
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead then
      local d = math.distance(x, y, o.x, o.y)
      if d <= best_d then best_d = d; best = o end
    end
  end
  return best
end


function BallPit:get_bricks_within(x, y, range)
  local out = {}
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead and math.distance(x, y, o.x, o.y) <= range then
      table.insert(out, o)
    end
  end
  return out
end


function BallPit:get_random_brick_within(x, y, range)
  local candidates = {}
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead and math.distance(x, y, o.x, o.y) <= range then
      table.insert(candidates, o)
    end
  end
  if #candidates == 0 then return nil end
  return candidates[random:int(1, #candidates)]
end


-- opts.range: optional, restrict targeting to bricks within range.
function BallPit:fire_projectile_at_nearest(hero, opts)
  local target
  if opts.range then
    target = self:get_nearest_brick_within(hero.x, hero.y, opts.range)
  else
    target = self:get_nearest_brick(hero.x, hero.y)
  end
  if not target then return end
  -- Defer to next frame: Box2D world is locked during collision callbacks.
  local hx, hy   = hero.x, hero.y
  local color    = opts.color or hero.color
  local r        = math.atan2(target.y - hy, target.x - hx)
  local main_g   = self.main
  self.t:after(0, function()
    if main_g and main_g.world then
      Projectile{
        group  = main_g,
        x      = hx, y = hy,
        r      = r,
        type   = opts.type,
        dmg    = opts.dmg,
        speed  = opts.speed,
        pierce = opts.pierce or 0,
        ricochet = opts.ricochet or 0,
        color  = color,
      }
    end
  end)
end


function BallPit:do_splash(x, y, radius, dmg, color)
  spawn_burst(self.effects, x, y, color, 10, 80, 160)
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead then
      if math.distance(x, y, o.x, o.y) <= radius then
        o:take_damage(dmg, color)
      end
    end
  end
  -- Expanding ring + screen shake scaled by blast radius.
  TelegraphRing{group = self.effects, x = x, y = y, radius = radius, color = color, duration = 0.2}
  local shake = math.clamp(radius/12, 1, 6)
  camera:shake(shake, 0.18, 90)
end


function BallPit:do_chain_lightning(x, y, dmg, chain_len, color)
  local hit_ids = {}
  local cx, cy = x, y
  local hit_any = false
  for i = 1, chain_len do
    local target
    local best_d = 80 + 30*i
    for _, o in ipairs(self.main.objects) do
      if o:is(Brick) and not o.dead and not hit_ids[o.id] then
        local d = math.distance(cx, cy, o.x, o.y)
        if d < best_d then best_d = d; target = o end
      end
    end
    if not target then break end
    hit_ids[target.id] = true
    hit_any = true

    -- Lightning line visual.
    local seg = Object:extend()
    seg:implement(GameObject)
    function seg:init(a) self:init_game_object(a); self.alpha = 1; self.t:tween(0.22, self, {alpha = 0}, math.linear, function() self.dead = true end) end
    function seg:update(dt) self:update_game_object(dt) end
    function seg:draw()
      graphics.line(self.x1, self.y1, self.x2, self.y2, Color(color.r, color.g, color.b, self.alpha), 2)
    end
    seg{group = self.effects, x1 = cx, y1 = cy, x2 = target.x, y2 = target.y, x = (cx+target.x)/2, y = (cy+target.y)/2}

    target:take_damage(dmg, color)
    spawn_burst(self.effects, target.x, target.y, color, 4, 60, 110)
    cx, cy = target.x, target.y
  end
  if hit_any then camera:shake(2, 0.1, 90) end
end


function BallPit:burn_area(x, y, radius, dps, duration)
  TelegraphRing{group = self.effects, x = x, y = y, radius = radius, color = orange[0], duration = 0.3}
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead then
      if math.distance(x, y, o.x, o.y) <= radius then
        o:apply_burn(dps, duration)
      end
    end
  end
end


function BallPit:slow_in_area(x, y, radius, factor, duration)
  TelegraphRing{group = self.effects, x = x, y = y, radius = radius, color = blue[0], duration = 0.3}
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead then
      if math.distance(x, y, o.x, o.y) <= radius then
        o:apply_slow(factor, duration)
      end
    end
  end
end


function BallPit:knockback_area(x, y, radius, force)
  TelegraphRing{group = self.effects, x = x, y = y, radius = radius, color = fg[0], duration = 0.2}
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead then
      local d = math.distance(x, y, o.x, o.y)
      if d <= radius and d > 0.5 then
        local ang = math.atan2(o.y - y, o.x - x)
        o:apply_impulse(math.cos(ang)*force, math.sin(ang)*force)
      end
    end
  end
  camera:shake(2, 0.1, 90)
end


-- Release every currently-stuck ball at self.aim_angle.
function BallPit:launch_stuck_balls()
  local launched = 0
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and h.stuck then
      h:launch_from_stuck(self.aim_angle)
      launched = launched + 1
    end
  end
  if launched > 0 then
    confirm1:play{volume = 0.4, pitch = random:float(0.95, 1.05)}
    self.aim_angle = -math.pi/2
  end
end


function BallPit:heal_player(amount)
  if amount and amount > 0 then
    local prev = self.player_hp
    self.player_hp = math.min(self.player_hp_max, self.player_hp + 1)
    if self.player_hp ~= prev then
      FloatingText{group = self.effects, x = self.paddle.x, y = self.paddle.y - 20, text = '+1 HP', color = green[0]}
    end
  end
end


-- ----- Powerups -----
--
-- Apply a powerup by name. Effects come in three flavours:
--   1. Instant (heal, freeze_wave, water_wave, level_random): no buff slot.
--   2. Timed buff (wide_paddle, big_ball, fire_trail, pierce, multi_ball):
--      stashed in self.buffs[kind] with an `expires_at` + `restore` pair;
--      tick_buffs counts down and calls restore on expiry. Stacking the same
--      buff while it's active extends the timer instead of stacking the
--      multiplier (so Wide Paddle twice = 15s + extension, not 2.56× width).
--   3. Wave-bounded (floor): cleared in advance_wave / reset_run, no timer.


-- Pity-timer driven powerup spawner. Called every sub-step from update;
-- accumulates real time and rolls for a spawn at fixed intervals. Each failed
-- roll bumps the chance for the next check (the "pity" ramp) so dry streaks
-- can't drag on forever — see the configuration in reset_run.
function BallPit:tick_powerup_pity(dt)
  if not Powerup then return end
  if self.upgrade_pending or self.game_over then return end
  local p = self.powerup_pity
  if not p then return end

  p.timer = p.timer + dt
  if p.timer < p.check_interval then return end
  p.timer = p.timer - p.check_interval

  local chance = math.min(1.0, p.base_chance + p.streak*p.pity_step)
  if random:float(0, 1) < chance then
    self:spawn_random_powerup()
    p.streak = 0
  else
    p.streak = p.streak + 1
  end
end


-- Pick a random tier (weighted toward tier-1) and a random kind within it,
-- then drop a Powerup near the top of the arena so it has time to fall to
-- the paddle. Used by the pity timer and exposed for admin / debugging use.
function BallPit:spawn_random_powerup()
  if not (Powerup and self.main and self.main.world) then return end

  local p = self.powerup_pity or {tier2_chance = 0.20}
  local kinds
  if random:float(0, 1) < (p.tier2_chance or 0.20) then
    kinds = Powerup.tier_2_kinds()
  else
    kinds = Powerup.tier_1_kinds()
  end
  if not kinds or #kinds == 0 then return end
  local kind = kinds[random:int(1, #kinds)]

  -- Spawn near the top of the arena, biased toward the centre so the orb is
  -- never wedged against a side wall on spawn. Random x within roughly the
  -- middle two-thirds of the arena.
  local arena_w = self.x2 - self.x1
  local x = self:arena_center_x() + random:float(-arena_w/3, arena_w/3)
  local y = self.y1 + 16

  self.t:after(0, function()
    if self.main and self.main.world then
      Powerup{group = self.main, x = x, y = y, kind = kind}
    end
  end)
end


function BallPit:apply_powerup(kind, x, y, color)
  local def = Powerup and Powerup.KINDS and Powerup.KINDS[kind]
  if not def then
    if self.terminal then self.terminal:log('unknown powerup: ' .. tostring(kind)) end
    return
  end

  -- Floating label so the player can read what they just caught.
  local px = (self.paddle and self.paddle.x) or gw/2
  local py = (self.paddle and self.paddle.y - 26) or gh/2
  FloatingText{group = self.effects, x = px, y = py, text = def.label:upper(), color = color or _G[def.color or 'fg'][0]}
  buff1:play{volume = 0.3, pitch = random:float(1.0, 1.1)}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = Color((color or fg[0]).r, (color or fg[0]).g, (color or fg[0]).b, 0.25), duration = 0.08}

  if kind == 'heal' then
    self:heal_player(1)

  elseif kind == 'wide_paddle' then
    self:apply_paddle_width_buff()

  elseif kind == 'big_ball' then
    self:apply_big_ball_buff()

  elseif kind == 'fire_trail' then
    self:apply_fire_trail_buff()

  elseif kind == 'freeze_wave' then
    self:apply_freeze_wave()

  elseif kind == 'water_wave' then
    self:apply_water_wave()

  elseif kind == 'multi_ball' then
    self:apply_multi_ball()

  elseif kind == 'pierce' then
    self:apply_pierce_buff()

  elseif kind == 'floor' then
    self:apply_floor()

  elseif kind == 'level_random' then
    self:apply_level_random()
  end
end


-- Tick every active buff. Called from BallPit:update with the sub-stepped dt.
function BallPit:tick_buffs(dt)
  for kind, b in pairs(self.buffs) do
    b.remaining = b.remaining - dt
    if b.remaining <= 0 then
      if b.restore then b.restore() end
      self.buffs[kind] = nil
    end
  end
end


-- Add or extend a timed buff. If a buff with this kind already exists, the
-- existing restore() is preserved (so we don't double-apply) and the timer
-- is bumped to whichever is longer.
function BallPit:add_or_extend_buff(kind, duration, on_apply, on_restore)
  local existing = self.buffs[kind]
  if existing then
    existing.remaining = math.max(existing.remaining, duration)
    return
  end
  if on_apply then on_apply() end
  self.buffs[kind] = {remaining = duration, restore = on_restore}
end


-- ----- Individual powerup effects -----

-- Helper: destroy the existing Box2D body+fixture and rebuild as a rectangle
-- at the same position. Used by paddle and any other body whose dimensions
-- need to change at runtime (Box2D doesn't allow live fixture resize).
local function rebuild_rect_body(obj, w, h, body_type, tag)
  local px, py = obj.x, obj.y
  if obj.destroy then obj:destroy() end
  obj.x, obj.y = px, py
  obj:set_as_rectangle(w, h, body_type, tag)
end


local function rebuild_circle_body(obj, r, body_type, tag)
  local px, py = obj.x, obj.y
  if obj.destroy then obj:destroy() end
  obj.x, obj.y = px, py
  obj:set_as_circle(r, body_type, tag)
end


function BallPit:apply_paddle_width_buff()
  local p = self.paddle
  if not p then return end
  self:add_or_extend_buff('wide_paddle', 15,
    function()
      p._orig_w = p._orig_w or p.w        -- stash once, restore to the original
      p.w = p._orig_w * 1.6
      rebuild_rect_body(p, p.w, p.h, 'kinematic', 'paddle')
      p:set_restitution(1)
      p.t:after(0, function() if p.body then p.body:setFixedRotation(true) end end)
    end,
    function()
      if p._orig_w then
        p.w = p._orig_w
        rebuild_rect_body(p, p.w, p.h, 'kinematic', 'paddle')
        p:set_restitution(1)
        p.t:after(0, function() if p.body then p.body:setFixedRotation(true) end end)
      end
    end)
end


local function resize_hero(h, new_r)
  if not (h.body and h.set_as_circle) then return end
  -- Cache state we need to restore after the body rebuild (Box2D doesn't
  -- carry velocity / activation / mass / restitution across a destroy+
  -- recreate).
  local vx, vy   = h:get_velocity()
  local was_active = h.body:isActive()

  -- Pull the position inward by the new radius so the rebuilt larger body
  -- doesn't spawn overlapping the side / top walls. Without this clamp a
  -- ball touching the left wall when big_ball applies gets ejected wildly
  -- (and sometimes tunnels out of the arena, which looks like the ball
  -- "vanishing" to the player).
  local arena = main.current
  if arena then
    h.x = math.clamp(h.x, arena.x1 + new_r + 1, arena.x2 - new_r - 1)
    h.y = math.clamp(h.y, arena.y1 + new_r + 1, arena.y2 + 40)  -- bottom is loose; falling balls handled elsewhere
  end

  h.r_size = new_r
  rebuild_circle_body(h, new_r, 'dynamic', 'ball')
  h.body:setBullet(true)
  h:set_fixed_rotation(true)
  h:set_restitution(1)
  h:set_friction(0)
  h:set_damping(0)
  h:set_angular_damping(0)
  h:set_mass(0.5)
  if vx and vy then h:set_velocity(vx, vy) end
  -- Stuck / returning balls have their body deactivated; the rebuild flips
  -- it back to active by default, which would let them drift off the paddle
  -- mid-charge. Restore the original active state.
  if not was_active then h.body:setActive(false) end
end


function BallPit:apply_big_ball_buff()
  self:add_or_extend_buff('big_ball', 12,
    function()
      for _, h in ipairs(self.heroes) do
        if h and not h.dead then
          h._orig_r_size = h._orig_r_size or h.r_size
          resize_hero(h, h._orig_r_size * 1.6)
        end
      end
    end,
    function()
      for _, h in ipairs(self.heroes) do
        if h and not h.dead and h._orig_r_size then
          resize_hero(h, h._orig_r_size)
        end
      end
    end)
end


function BallPit:apply_fire_trail_buff()
  self:add_or_extend_buff('fire_trail', 10,
    function() self.fire_trail_until = (self.run_time or 0) + 1e9 end,  -- gated by buff existence
    function() self.fire_trail_until = 0 end)
end


function BallPit:apply_freeze_wave()
  TelegraphRing{group = self.effects, x = gw/2, y = gh/2, radius = math.max(gw, gh)*0.6, color = blue[0], duration = 0.4}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = Color(blue[0].r, blue[0].g, blue[0].b, 0.25), duration = 0.18}
  for _, sw in ipairs(self.swarms.objects) do
    if sw and not sw.dead then
      sw._frozen_orig_drift = sw._frozen_orig_drift or sw.drift_speed
      sw.drift_speed        = 0
    end
  end
  self.t:after(5, function()
    for _, sw in ipairs(self.swarms.objects) do
      if sw and not sw.dead and sw._frozen_orig_drift then
        sw.drift_speed       = sw._frozen_orig_drift
        sw._frozen_orig_drift = nil
      end
    end
  end)
end


function BallPit:apply_water_wave()
  -- Visual: a phased WaterWave (see effects.lua) — a body of water surges
  -- from the paddle row up to the spawn line over `surge_dur`, *continuously*
  -- pulling every swarm it overlaps upward (so swarms ride the front instead
  -- of getting a one-time 30 px nudge). Then a `disperse_dur` phase fades
  -- the body, rains foam droplets, and crowns the wave with a final spray
  -- burst + ring so the effect doesn't vanish in a single frame.
  local surge_dur    = 0.65
  local disperse_dur = 0.55
  WaterWave{
    group        = self.effects,
    x = (self.x1 + self.x2)/2, y = self.y2,   -- centre point (used by GameObject)
    x1           = self.x1, x2 = self.x2,
    y_start      = self.y2 - 4,
    y_end        = self.y1 + 8,
    surge_dur    = surge_dur,
    disperse_dur = disperse_dur,
    color        = blue2[0],
  }

  -- Impact feedback at the moment of casting: a brief blue-tint flash on
  -- the whole arena, two stacked telegraph rings rising off the paddle row,
  -- and a meaty camera shake so the cast feels weighty before the wave
  -- even starts climbing.
  Flash{
    group = self.effects, x = gw/2, y = gh/2,
    color = Color(blue2[0].r, blue2[0].g, blue2[0].b, 0.32),
    duration = 0.18,
  }
  TelegraphRing{
    group = self.effects, x = gw/2, y = self.y2 - 6,
    radius = math.max(gw, gh)*0.55, color = fg[0], duration = 0.4,
  }
  TelegraphRing{
    group = self.effects, x = gw/2, y = self.y2 - 6,
    radius = math.max(gw, gh)*0.4, color = blue2[0], duration = 0.55,
  }
  -- Two secondary ripples that chase the wavefront. Re-timed to fire at
  -- ~1/3 and ~2/3 of the surge phase so each ring appears alongside the
  -- crest as it climbs, not after it's already dispersed.
  self.t:after(surge_dur*0.35, function()
    TelegraphRing{group = self.effects, x = gw/2, y = (self.y1 + self.y2)/2,
                  radius = math.max(gw, gh)*0.45, color = blue2[0], duration = 0.4}
  end)
  self.t:after(surge_dur*0.7, function()
    TelegraphRing{group = self.effects, x = gw/2, y = self.y1 + 24,
                  radius = math.max(gw, gh)*0.35, color = blue[0], duration = 0.4}
  end)
  -- One final shake on the disperse beat so the burst at the top of the
  -- arena gets its own jolt (the initial shake has already decayed by
  -- then).
  self.t:after(surge_dur, function()
    camera:shake(3, 0.25, 70)
  end)

  camera:shake(5, 0.35, 80)
  if frost1 then frost1:play{volume = 0.45, pitch = random:float(0.7, 0.85)} end
  if force1 then force1:play{volume = 0.35, pitch = random:float(0.85, 0.95)} end

  -- Slow buff. Snapshot the original drift on each live swarm so we restore
  -- exactly that value, even if the swarm later starts ramping. New swarms
  -- spawned during the slow window also get caught (we iterate again on
  -- expire to clean up any orphaned `_water_orig_drift` keys).
  for _, sw in ipairs(self.swarms.objects) do
    if sw and not sw.dead then
      sw._water_orig_drift = sw._water_orig_drift or sw.drift_speed
      sw.drift_speed       = sw._water_orig_drift * 0.4
    end
  end
  self.t:after(10, function()
    for _, sw in ipairs(self.swarms.objects) do
      if sw and not sw.dead and sw._water_orig_drift then
        sw.drift_speed       = sw._water_orig_drift
        sw._water_orig_drift = nil
      end
    end
  end)
end


function BallPit:apply_multi_ball()
  -- Snapshot the current hero list (so we don't iterate over clones we're
  -- adding). Cap clone count so the physics world doesn't choke.
  local snapshot = {}
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and not h.is_clone then table.insert(snapshot, h) end
  end
  local clone_cap = 16 - #snapshot
  if clone_cap <= 0 then return end

  local clones = {}
  for i = 1, math.min(clone_cap, #snapshot) do
    local src   = snapshot[i]
    local hero  = self:add_hero(src.character)
    hero.is_clone = true
    -- Match the source level so the clone is as strong as the original. The
    -- dmg field already includes per-level scaling from add_hero, so we only
    -- need to bump level (used by some ability handlers via self.level).
    hero.level  = src.level
    hero.dmg    = src.dmg
    table.insert(clones, hero)
  end
  -- Despawn clones after 12 s. Iterate the captured table, not self.heroes,
  -- so we only kill the clones we just spawned.
  self.t:after(12, function()
    for _, h in ipairs(clones) do
      if h and not h.dead then
        if h.body then h.body:setActive(false) end
        h.dead = true
      end
    end
    -- Compact self.heroes to drop the dead clone entries.
    for i = #self.heroes, 1, -1 do
      if self.heroes[i] and self.heroes[i].dead then
        table.remove(self.heroes, i)
      end
    end
  end)
end


function BallPit:apply_pierce_buff()
  -- We keep Box2D collisions ENABLED so the on_collision_enter callback still
  -- fires for damage. The "pass through" effect is achieved in the callback
  -- (in BallPit:add_hero) by restoring the pre-bounce velocity right after
  -- the contact resolves. See `pierce_active` consumers in `add_hero` and
  -- the velocity cache in `BallHero:update`.
  self:add_or_extend_buff('pierce', 8,
    function() self.pierce_active = true  end,
    function() self.pierce_active = false end)
end


function BallPit:apply_floor()
  if self.floor_wall then return end                 -- already up; one floor per wave
  local thick = 6
  local cx    = (self.x1 + self.x2)/2
  local cy    = self.y2 + thick/2 + 2                -- just below the paddle row
  local w     = self.x2 - self.x1 + thick
  self.floor_wall      = self:spawn_wall(cx, cy, w, thick)
  self.no_speed_reset  = true
  TelegraphRing{group = self.effects, x = cx, y = cy, radius = w*0.6, color = yellow2[0], duration = 0.45}
end


function BallPit:apply_level_random()
  local pool = {}
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and (h.level or 1) < 3 then table.insert(pool, h) end
  end
  if #pool == 0 then return end
  local n = math.min(#pool, random:int(1, 5))
  -- Fisher-Yates partial shuffle: pull n distinct entries off the front.
  for i = 1, n do
    local j = random:int(i, #pool)
    pool[i], pool[j] = pool[j], pool[i]
    local h = pool[i]
    h.level = (h.level or 1) + 1
    h.dmg   = h.dmg * 1.4
    self:flash_hero_level_up(h)
  end
  level_up1:play{volume = 0.4}
end


-- ----- Buff HUD strip -----
--
-- Tucked below the playfield, beneath the Lv/Wave/Time row. The header above
-- the playfield is too cramped to share with the HP/XP bar (and the ADMIN
-- button on the right) without the text bleeding into the hearts. Each active
-- buff renders as a coloured pill with its remaining seconds. Used to be a
-- debug log line; promoted to in-arena HUD so the player can plan around
-- expiries.
function BallPit:draw_buff_strip()
  local x = self.x1 + 2
  local y = self.y2 + 14
  local pad = 10
  for kind, b in pairs(self.buffs) do
    local def    = Powerup and Powerup.KINDS and Powerup.KINDS[kind]
    local color  = def and _G[def.color][0] or fg[0]
    local label  = (def and def.label or kind):upper() .. ' ' .. string.format('%.1f', math.max(0, b.remaining))
    local glyph_w = pixul_font:get_text_width(label) + 4
    graphics.rectangle(x + glyph_w/2, y + 3, glyph_w, 6, 1, 1, Color(color.r*0.4, color.g*0.4, color.b*0.4, 0.85))
    graphics.print(label, pixul_font, x + 2, y, 0, 1, 1, 0, 0, color)
    x = x + glyph_w + pad
  end
end
