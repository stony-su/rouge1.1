-- BallPit: the combined Arkanoid / vampire-survivors gameplay loop.
-- Heroes are balls that bounce in the play area; enemy bricks drift downward
-- and damage the player if they reach the paddle line. CLEARING A WAVE levels the
-- player up and lets them draft a new ball-hero -- one level, one draft, one wave.
-- (The Terrorist loadout is the exception: it keeps the old XP-orb economy, where
-- kills drop orbs and enough of them buy a level. See BallPit:uses_xp_orbs.)

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


-- Ranged variants fire EnemyProjectiles at the paddle. Two rules keep their
-- shots from blanketing the screen:
--   1. Gradual introduction -- one new ranged type per wave starting at wave 3,
--      in RANGED_ORDER below (ordered easiest-to-read pattern first), instead
--      of the old "dump four ranged types in at once at wave 5".
--   2. Low spawn share -- each ranged variant is layered onto the melee/utility
--      base mix at a small weight. The one introduced on the current wave gets
--      a brief spotlight weight so the player notices it; older ones settle to
--      a low maintenance weight.
--   3. Late-wave taper -- swarms keep growing wider/denser past wave 15 while the
--      ranged SHARE of the mix was flat, so the absolute number of shooters on
--      screen kept climbing until the arena was a bullet blanket. From
--      RANGED_TAPER_WAVE on -- the boss wave, after which every ranged variant
--      has long been unlocked and swarms are near their size cap -- every ranged
--      weight is thinned by RANGED_TAPER_STEP per wave (never below
--      RANGED_TAPER_FLOOR of its base), so their share
--      shrinks as the swarms grow and the shooter count flattens out.
local RANGED_ORDER       = {'shooter', 'sniper', 'spreader', 'burster', 'arc_lobber', 'spiraler'}
local RANGED_INTRO_WAVE  = 3    -- the first ranged variant unlocks on this wave
local RANGED_NEW_WEIGHT  = 2    -- weight for the variant introduced this wave (was 3; thinned again)
local RANGED_OLD_WEIGHT  = 0.8  -- weight for each ranged variant unlocked earlier (was 1.2; thinned again)
local RANGED_TAPER_WAVE  = 10   -- ranged weights start thinning from this wave on (was 15)
local RANGED_TAPER_STEP  = 0.08 -- fraction of the base weight shaved off per wave past it
local RANGED_TAPER_FLOOR = 0.4  -- floor: never thin below this fraction of the base weight


-- Appends the ranged variants unlocked by `wave` to `mix` (one new type per
-- wave from RANGED_INTRO_WAVE onward). The just-introduced type gets the
-- spotlight weight; once every type is unlocked nothing is "new" and they all
-- sit at the maintenance weight. No-op before the intro wave.
local function append_ranged(mix, wave)
  local new_idx  = wave - RANGED_INTRO_WAVE + 1      -- index introduced this wave
  local unlocked = math.clamp(new_idx, 0, #RANGED_ORDER)
  -- Late-wave taper (see above): shrink the ranged share as the swarms grow, so
  -- the shooter COUNT stops scaling with the wave past RANGED_TAPER_WAVE.
  local taper = 1
  if wave > RANGED_TAPER_WAVE then
    taper = math.clamp(1 - RANGED_TAPER_STEP*(wave - RANGED_TAPER_WAVE), RANGED_TAPER_FLOOR, 1)
  end
  for i = 1, unlocked do
    local w = (i == new_idx) and RANGED_NEW_WEIGHT or RANGED_OLD_WEIGHT
    table.insert(mix, {RANGED_ORDER[i], w*taper})
  end
end


-- The hard floor under the gap between swarm spawns, in seconds, no matter how
-- deep the run goes. Note this is a ceiling on the SPAWN ATTEMPT rate, not on the
-- arrival rate: a swarm still has to find a clear slot (BallPit:can_place_layout,
-- SWARM_GAP_MIN_ROWS), so once the field is packed the geometry, not this, is
-- what paces the wave.
local SWARM_INTERVAL_MIN = 0.9


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
      mix                = {},
    }
  end

  -- Melee/utility base mix per wave tier. Ranged variants are NOT listed here
  -- anymore -- append_ranged layers them in on top, gradually (see below).
  local mix
  if wave <= 2 then
    mix = {{'seeker', 80}, {'speed_booster', 20}}
  elseif wave <= 4 then
    mix = {{'seeker', 72}, {'speed_booster', 15}, {'exploder', 15}, {'tank', 10}}
  elseif wave <= 6 then
    mix = {{'seeker', 64}, {'speed_booster', 10}, {'exploder', 12}, {'tank', 12}, {'headbutter', 12}}
  elseif wave <= 8 then
    mix = {{'seeker', 56}, {'exploder', 12}, {'tank', 12}, {'headbutter', 10}}
  elseif wave == 9 then
    -- Pre-boss "warning" wave: by now every ranged variant has been introduced,
    -- so append_ranged layers in the full set -- a taste of what the boss throws.
    mix = {{'seeker', 38}, {'tank', 10}, {'forcer', 8}, {'randomizer', 10}}
  else
    -- wave 11+ post-boss tier: hardest melee/utility base; all ranged appended.
    mix = {{'seeker', 45}, {'tank', 12}, {'headbutter', 8},
           {'forcer', 10}, {'randomizer', 8}}
  end

  -- Layer ranged attackers on top of the melee/utility base above, introduced
  -- one new type per wave from wave 3 (see append_ranged / RANGED_ORDER).
  append_ranged(mix, wave)

  -- All of these slide with wave number so the run gets progressively
  -- harder: more rows, wider swarms, shorter gap between spawns, and a
  -- shrinking minimum vertical gap between successive swarms (so they end
  -- up packed tightly at high waves).
  local min_rows = math.min(7, math.max(3, 3 + math.floor(wave/4)))
  local max_rows = math.min(7, math.max(min_rows, 3 + math.floor(wave/2)))
  local min_w    = math.min(0.80, 0.33 + 0.035*wave)
  local max_w    = math.min(1.00, math.max(min_w + 0.1, 0.55 + 0.045*wave))

  -- Seconds between swarm spawns. Two terms, and the interval is whichever is
  -- LARGER:
  --   * a linear ramp that tightens through the early waves, and
  --   * a FLOOR that used to be a flat 2.5s -- from wave 10 on, every wave was
  --     spawning at exactly the same cadence as the one before it, so the run
  --     stopped getting denser and only got tougher per block. The floor now
  --     slides down with the wave too, bottoming out at 0.9s, so late waves keep
  --     compounding pressure instead of plateauing.
  -- Early waves are untouched: the ramp is the larger term until wave 10, which
  -- is where the old floor took over.
  local interval_floor = math.max(SWARM_INTERVAL_MIN, 2.5 - 0.08*wave)

  return {
    swarm_interval     = math.max(interval_floor, 6 - 0.35*wave), -- spawn frequency ↑
    duration           = 25 + 2*wave,
    swarm_rows_min     = min_rows,
    swarm_rows_max     = max_rows,                            -- swarm size ↑
    width_fraction_min = min_w,
    width_fraction_max = max_w,
    swarm_density      = 0.88,
    -- Drift is scaled by the live arena height (relative to the original
    -- 228px playfield) so a taller map doesn't silently make swarms slower
    -- to reach the paddle. Keeps wave pressure consistent across resolutions.
    drift_speed        = (5 + 0.25*wave)*0.5*((gh - 42)/228),
    -- (Vertical breathing room between swarms is no longer a per-wave constant.
    -- It is rolled fresh for every spawn -- see SWARM_GAP_MIN_ROWS below.)
    mix                = mix,
  }
end


-- ULTRAKILL-style combo system. Points come from chaining brick bounces;
-- balls falling into the pit take a heavy penalty.
--
-- What the rank PAYS OUT: climbing the ladder does not buff contact damage. It
-- makes every ball FASTER (speed_mult, folded into BallHero:normalize_speed) --
-- that is the whole payout now. The meter used to pay a second dividend in XP
-- (xp_mult, folded into gain_xp), which stopped meaning anything once levels came
-- from clearing waves rather than from collecting orbs; rather than leave a payout
-- that only one loadout could ever see, it was cut. The per-ball bounce chain
-- (bounce_dmg_mult) is a separate channel and still scales damage.
--
-- Rank entries are ordered low → high. `combo_rank_index` walks them from
-- the top so the highest threshold the current points crosses wins.
local COMBO_RANKS = {
  {label = 'D',      threshold =    0, speed_mult = 1.0,  color_key = 'fg_alt'},
  {label = 'C',      threshold =   50, speed_mult = 1.11, color_key = 'fg'    },
  {label = 'B',      threshold =  150, speed_mult = 1.21, color_key = 'yellow'},
  {label = 'A',      threshold =  300, speed_mult = 1.32, color_key = 'orange'},
  {label = 'S',      threshold =  500, speed_mult = 1.43, color_key = 'red'   },
  {label = 'SS',     threshold =  750, speed_mult = 1.54, color_key = 'red'   },
  {label = 'SSS',    threshold = 1100, speed_mult = 1.64, color_key = 'red'   },
  {label = 'FRENZY', threshold = 1500, speed_mult = 1.75, color_key = 'purple'},
}

-- Ranks at/above this index are the "hot streak" tiers — the meter grows a
-- crest, embers and a glow that scale from 0 at HOT_RANK to 1 at the top.
local COMBO_HOT_RANK = 5   -- S

-- Tunables. Gains are absolute; the idle bleed is PROPORTIONAL -- a fraction of
-- whatever you are currently holding, bled per idle second, exactly the shape
-- the pit-drop penalty already uses (miss_frac/miss_min). A hot bar therefore
-- costs more attention than a cold one: what you own is what you can lose.
--
-- The floor is not decoration. A pure percentage is exponential, so the tail
-- would asymptote at a point or two and never reach zero -- the meter would sit
-- at D forever with a sliver of fill and `streak`/`last_variant` would never
-- reset. DECAY_MIN is the rate below which the bleed stops scaling and goes
-- flat, which lands the tail on zero and keeps the low tiers moving.
--
-- Because the rank BANDS get wider as they climb (50/100/150/200/250/350/400)
-- while a flat rate does not, the old constant made the top of the ladder the
-- STICKIEST part of it -- 27 idle seconds to fall out of FRENZY against 3 to
-- fall out of C. Scaling the rate with the total inverts that: see the table
-- over tick_combo for what each tier now costs.
local COMBO_MISS_FRAC        = 0.25  -- fraction of current points lost per pit drop...
local COMBO_MISS_MIN         = 100   -- ...but never less than this
local COMBO_BASE_POINTS      = 10    -- baseline per brick bounce
local COMBO_VARIETY_BONUS    = 5     -- + this if hitting a different variant than last
local COMBO_STREAK_BONUS_CAP = 10    -- + min(streak, cap) per bounce
local COMBO_IDLE_GRACE       = 2     -- seconds with no bounces before decay starts
local COMBO_IDLE_DECAY_FRAC  = 0.04  -- fraction of the CURRENT total bled per idle second...
local COMBO_IDLE_DECAY_MIN   = 10    -- ...but never slower than this (points/sec)
local COMBO_BOUNCE_DMG_STEP  = 0.08  -- +8% damage per bounce on the same ball
local COMBO_BOUNCE_CAP       = 15    -- max bounces counted for damage scaling

-- Meter animation. The drawn bar never snaps: it chases the real point total
-- so every award slides left→right instead of popping in as a block. Rate is
-- proportional to the gap with a floor, so tiny bounces still visibly travel
-- and a big swing still catches up quickly.
local COMBO_BAR_CHASE    = 7     -- gap fraction closed per second
local COMBO_BAR_MIN_RATE = 55    -- ...but never slower than this (points/sec)
-- The "lost bar" ghost trails the fill front instead of receding at a fixed
-- speed: a fixed speed is either faster than the bar ever falls (so the tail
-- never shows) or slower (so it sticks). As a LAG it self-scales -- a pit drop
-- leaves a wide red tail, the slow idle bleed leaves a thin one. Value = the
-- fraction of the gap still remaining after one second.
local COMBO_GHOST_LAG    = 0.35
local COMBO_FX_MAX       = 48    -- hard cap on live meter particles

-- Meter layout. The rank label hangs BELOW the bar and is right-aligned on the
-- arena wall, so it reads as a badge stamped on the corner rather than a word
-- wedged between the XP bar and the meter. It is auto-fitted into LABEL_BOX px
-- (so 'D' and 'FRENZY' still occupy one fixed slot), and LABEL_TOP is where its
-- ink starts, measured down from the bar's centre line. draw_hud ends the XP
-- bar STRIP_W px short of the right edge -- now only enough to clear the bar
-- itself, since the label no longer shares that row.
local COMBO_LABEL_BOX = 54
local COMBO_LABEL_TOP = 10
local COMBO_STRIP_W   = 74
-- Both the bar and the rank badge sit this far in from the right arena wall.
-- One constant so they can never drift apart -- combo_meter_rect is the only
-- geometry source the bar, the badge and the particle emitters all read.
local COMBO_RIGHT_PAD = 5

-- Effective rank values: the equipped paddle's damage master file
-- (balance/<paddle>.lua, `combo.ranks`) can override every rank's threshold
-- and multipliers; the table above is the fallback and keeps labels/colors.
local function combo_rank_threshold(i)
  return BAL('combo.ranks.' .. i .. '.threshold', COMBO_RANKS[i].threshold)
end
local function combo_rank_speed_mult(i)
  return BAL('combo.ranks.' .. i .. '.speed_mult', COMBO_RANKS[i].speed_mult)
end
function BallPit:init(name)
  self:init_state(name)
  self:init_game_object()

  -- Window-size options for the ESC settings menu. Each entry is a uniform
  -- scale applied to the fixed game canvas (gw x gh = 480 x 656), so the
  -- pixel dimensions are scale*480 x scale*656.
  self.scale_options = {
    {scale = 0.75, label = '360 x 492'},
    {scale = 1.0,  label = '480 x 656'},
    {scale = 1.25, label = '600 x 820'},
    {scale = 1.5,  label = '720 x 984'},
    {scale = 1.75, label = '840 x 1148'},
    {scale = 2.0,  label = '960 x 1312'},
  }
  self.settings_open = false
  self.settings_selected = 1
  for i, opt in ipairs(self.scale_options) do
    if math.abs(opt.scale - sx) < 0.01 then self.settings_selected = i; break end
  end

  -- ----- Title screen (pinball backglass) -----
  --
  -- Set HERE, in init, and never in reset_run: the title is a boot screen, and
  -- a restart drops straight back into play (the run report has its own restart
  -- button rather than bouncing you through the title again).
  --
  -- The only moving parts are the logo assembling and, on start, the rule
  -- turning into the paddle. A backglass is printed art -- it does not have
  -- things drifting across it.
  self.title_open  = true
  self.title_t     = 0
  self.title_phase = 'idle'
  self.launch_t    = 0
  self.title_selected = 1
  -- Tutorial is a sub-page of the title, not a separate screen: it borrows the
  -- same glass and returns to the menu. (admin's terminal already guards on
  -- tutorial_open, so the debug console stays out of the way while it is up.)
  self.tutorial_open  = false
  self.tutorial_page  = 1
  self.tutorial_t     = 0
  self.tutorial_phase = 'idle'
  self.tutorial_anim  = 0
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


-- Commit the highlighted window-size row. update_settings calls this from BOTH
-- the mouse-click path and the confirm-key path, but it was never actually
-- defined -- so choosing any size threw
--   ballpit.lua: attempt to call method 'activate_settings_selection' (a nil value)
-- and took the frame down with it.
--
-- Applying is idempotent (apply_scale_option no-ops when the chosen scale is
-- already current), so confirming the row you are already on simply closes the
-- menu. ESC reopens it if you want to try another size.
function BallPit:activate_settings_selection()
  self:apply_scale_option(self.settings_selected)
  self.settings_open = false
end


function BallPit:settings_option_under_mouse()
  -- Same pitch draw_settings paints with, or the hit boxes creep out from
  -- under the rows they belong to as you go down the list.
  local opt_w, opt_h = 200, 18
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
  -- Hover priority: scale rows
  local hovered = self:settings_option_under_mouse()
  if hovered then
    if hovered ~= self.settings_selected then
      self.settings_selected = hovered
      ui_switch1:play{volume = 0.25}
    end
    if input.click.pressed then self:activate_settings_selection() end
  end

  if input.aim_left.pressed or input.move_left.pressed then
    self.settings_selected = math.max(1, self.settings_selected - 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.aim_right.pressed or input.move_right.pressed then
    self.settings_selected = math.min(#self.scale_options, self.settings_selected + 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.confirm.pressed then self:activate_settings_selection() end
end


function BallPit:draw_settings()
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0, 0, 0, 0.7))
  graphics.print_centered('SETTINGS', fat_font, gw/2, gh/2 - 90, 0, 1.4, 1.4, 0, 0, yellow[0])
  graphics.print_centered('window size', pixul_font, gw/2, gh/2 - 68, 0, 1, 1, 0, 0, fg[0])

  local opt_w, opt_h = 200, 18
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
    local color = active and yellow[0] or fg[0]
    graphics.print_centered(opt.label, pixul_font, gw/2, oy - 1, 0, 1, 1, 0, 0, color)
  end

  -- Hero roster lives below the window size options, in the otherwise-empty bottom
  -- half of the settings overlay. Hovering a ball pops a name/level/ability
  -- tooltip so the player can audit what they've collected mid-run.
  self:draw_settings_heroes()
end


-- Absolute y of the FIRST roster row, and the row pitch. The label, the grid
-- and the hover tooltip all anchor off these, so the block sits as one unit a
-- slim gap under the last window-size row instead of floating in the middle of
-- the empty bottom half. Deferred into a function because gh isn't defined yet
-- when this file is required.
local function hero_grid_top() return gh/2 + 88 end
local HERO_CELL_H = 24


-- 8-per-row grid position helper. Each row is centered on its own contents,
-- so 1 hero is centered, 8 heroes span the full row width, and a partial
-- second row stays visually balanced under the first row.
function BallPit:hero_grid_pos(i)
  local n = #self.heroes
  local cell_w, cell_h = 22, HERO_CELL_H
  local cols_per_row   = 8
  local row = math.floor((i-1)/cols_per_row)
  local col = (i-1) - row*cols_per_row
  local row_start_i = row*cols_per_row + 1
  local row_end_i   = math.min(n, (row+1)*cols_per_row)
  local row_items   = row_end_i - row_start_i + 1
  local start_x = gw/2 - (row_items*cell_w)/2 + cell_w/2
  local hx = start_x + col*cell_w
  local hy = hero_grid_top() + row*cell_h
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

  -- Sits just under the bottom window-size row (its box ends at gh/2 + 53), so
  -- the roster reads as the next section down rather than a detached island.
  graphics.print_centered('HEROES', pixul_font, gw/2, gh/2 + 68, 0, 1, 1, 0, 0, fg[0])

  local hovered_idx = self:hero_under_mouse_in_settings()

  for i, hero in ipairs(self.heroes) do
    local hx, hy = self:hero_grid_pos(i)
    local is_hover = (i == hovered_idx)

    -- Hovered icon gets a faint outer ring so the cursor focus is unmistakable.
    if is_hover then
      graphics.circle(hx, hy, 10, Color(hero.color.r, hero.color.g, hero.color.b, 0.35))
    end
    -- Live skin preview: the hero's real in-game body at roster scale.
    BallHero.draw_preview(hero.character, hx, hy, 5)

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
    self:draw_hero_tooltip(self.heroes[hovered_idx], #self.heroes)
  end
end


-- ----- Tutorial overlay -----
-- Removed - tutorial functionality has been deleted from the codebase.


function BallPit:on_enter()
  self:reset_run()
  -- Boot: the backglass is up. The run is built so the title's rule has a real
  -- paddle to aim at, but nothing may spawn into it and the paddle itself stays
  -- hidden until the rule lands on its spot (see finish_title).
  if self.title_open then
    self.t:cancel('spawn_swarm')
    self.t:cancel('spawn_brick')
    if self.paddle then self.paddle.hidden = true end
  end
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
  self.floor   = Group()   -- on-ground layer drawn UNDER main, so things like the cleric's heal sigil sit beneath the paddle/balls
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
  -- bottom is open). Paddle catches and tier-2 deflects are driven by the
  -- proximity check inside Powerup:update, not Box2D contacts.
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
  self.left_wall  = self:spawn_wall(self.x1 - thick/2, (self.y1 + self.y2)/2, thick, self.y2 - self.y1 + thick)  -- left
  self.right_wall = self:spawn_wall(self.x2 + thick/2, (self.y1 + self.y2)/2, thick, self.y2 - self.y1 + thick)  -- right
  -- Top wall is captured so the ball collision callback can recognise it and
  -- expire a ball's pierce state when it bonks the ceiling.
  self.top_wall = self:spawn_wall((self.x1 + self.x2)/2, self.y1 - thick/2, self.x2 - self.x1 + thick, thick)

  -- Paddle loadout (see paddles.lua / PADDLES.md). The selected paddle's
  -- stat multipliers are snapshotted into run_mods BEFORE the paddle and
  -- heroes spawn so both read them at init time.
  PADDLES.ensure_state()
  local pdef = PADDLES.get(state.selected_paddle)
  -- Load this paddle's damage master file (balance/<id>.lua) fresh from disk
  -- and overlay its loadout/signature numbers onto a COPY of the def, so
  -- every damage number below comes from the master file.
  Balance.set_paddle(pdef.id)
  pdef = Balance.effective_def(pdef)
  self.paddle_def = pdef
  self.run_mods = {
    ball = pdef.ball, charge = pdef.charge, aim = pdef.aim, dmg = pdef.dmg,
    xp = pdef.xp, combo = pdef.combo, xp_mode = pdef.xp_mode,
    hp_mode = pdef.hp_mode, signature = pdef.signature, sig = pdef.sig,
  }

  -- Paddle.
  self.paddle = Paddle{
    group = self.main, x = gw/2, y = self.y2 - 14,
    w = math.floor(36*pdef.size + 0.5), speed = 220*pdef.move,
    aim_mult = pdef.aim, color = _G[pdef.color_key][0],
    flippers = (pdef.signature == 'flippers') or nil,
    flipper_gap = pdef.sig.gap, flip_window = pdef.sig.flip_window,
    flipper_sig = pdef.sig,
    move_mode = (pdef.signature == 'glacier') and 'ice' or nil,
    paddle_skin = ({mitosis = 'mitosis', boomerang = 'boomerang', vampire = 'vampire', hive = 'hive', tesla = 'tesla', glacier = 'glacier', terrorist = 'terrorist', cannon = 'cannon', aegis = 'aegis'})[pdef.signature],
  }

  -- Pinball Lobber: damp the side/top walls so balls shed energy on a wall hit
  -- instead of pinging forever — part of the slower, gravity-bound feel. (Ball
  -- restitution is already low; Box2D mixes the two by taking the higher value,
  -- so the walls themselves have to come down for the bounce to soften.)
  if pdef.signature == 'flippers' then
    for _, w in ipairs({self.left_wall, self.right_wall, self.top_wall}) do
      if w and w.set_restitution then w:set_restitution(0.55) end
    end
  end

  -- Starting hero pool — the loadout decides the lineup (Twin Cast mirrors
  -- each one inside add_hero). seen_characters feeds the Mitosis regrow.
  self.heroes = {}
  self.seen_characters = {}
  -- Twin Cast (Binary Fusion): bonded pairs register here as they spawn, so
  -- this must exist before the starting heroes are added (add_hero fills it).
  self.twin_pairs = {}
  for _, c in ipairs(pdef.start_balls) do self:add_hero(c) end

  -- Run state. The Vampire's hp_mode 'bar' uses a 0-100 float (1 heart = 20
  -- units, see damage_player/heal_hearts) instead of discrete hearts.
  if pdef.hp_mode == 'bar' then
    self.player_hp     = 100
    self.player_hp_max = 100
  else
    self.player_hp     = pdef.hp
    self.player_hp_max = pdef.hp
  end
  -- Vampire blood-bar feedback state: a smoothed displayed fill, a heal-flash
  -- timer, and the in-flight lifesteal droplets (see the vampire_* helpers).
  self.hp_display     = self.player_hp
  self.hp_flash       = 0
  self.blood_droplets = {}
  self.run_kills     = 0
  self.xp            = 0
  self.xp_accumulator = 0  -- Terrorist: accumulates fractional passive XP before calling gain_xp
  self.level         = 1
  -- Scaling paddles: base cost of level 2 (was 5 — raised to slow the early
  -- level spam), tunable via the paddle's balance master file.
  self.xp_to_next    = (pdef.xp_mode == 'flat') and PADDLES.XP_FLAT or BAL('globals.xp_base', 8)
  self.wave          = 1
  -- Blank lockout clock. Set when the player eats a shot (see the blank in
  -- enemies.lua) and ticked down in update; while it is above zero no brick
  -- will fire (Brick:hold_fire), so the ranks can't immediately refill the
  -- space the blank just cleared.
  self.fire_lock_t   = 0
  self.wave_time     = 0
  -- Wave-track presentation state (see tick_wave_bar); rebuilt on first tick so
  -- a restart never inherits the last run's fill.
  self.wave_bar      = nil
  self.boss          = nil
  self.boss_defeated = false
  -- Set while wave 9 has elapsed but the arena still has live blocks; holds the
  -- boss wave from starting until everything is cleared (see BallPit:update).
  self.awaiting_boss = false
  self.score         = 0
  -- Highest combo rank this run reached, banked to the title stele on death.
  self.peak_rank_idx = 1
  -- Combo state. Persists across paddle bounces — only a ball falling into
  -- the pit (or extended idle time) reduces points. `streak` counts
  -- consecutive brick bounces across all balls; `last_variant` drives the
  -- variety bonus.
  --
  -- Everything from `display` down is PRESENTATION ONLY (see tick_combo /
  -- draw_combo_meter). `display` is the smoothed point total the bar actually
  -- draws, so a gain slides left→right instead of snapping; every rank-up
  -- effect fires off the DISPLAY crossing, keeping the juice in sync with
  -- what the player sees rather than with the instant the points landed.
  self.combo = {
    points        = 0,
    streak        = 0,
    idle_t        = 0,
    last_variant  = nil,
    bounces_total = 0,
    -- Cached payout for the current rank, refreshed once per frame in tick_combo
    -- and read every frame by every ball (BallHero:normalize_speed).
    speed_m       = 1,
    -- Presentation.
    display       = 0,    -- smoothed points the bar draws
    display_idx   = 1,    -- rank the drawn bar currently sits in
    pct           = 0,    -- 0..1 fill within display_idx
    ghost_pct     = 0,    -- lagging "just lost this" ghost segment
    gain_v        = 0,    -- 0..1 how hard the bar is currently filling
    drain         = 0,    -- 0..1 how hard the bar is currently bleeding
    heat          = 0,    -- 0..1 hot-streak intensity (S and above)
    flash         = 0,    -- tier break-through bar flash
    punch         = 0,    -- rank letter spring
    shock         = 0,    -- expanding break-through ring
    demote        = 0,    -- tier-loss pulse
    chip_pop      = 0,    -- newly-lit ladder chip pop
    ember_t       = 0,    -- ember spawn accumulator
    fx            = {},   -- live meter particles {x,y,vx,vy,t,life,r,c}
  }
  self.run_time      = 0
  self.paused        = false
  self.game_over     = false
  -- Death sequence: the beat between the killing blow and the run report.
  -- See trigger_game_over / update_death.
  self.dying         = false
  self.death_t       = 0
  self.upgrade_pending = false
  self.upgrade_choices = nil
  self.upgrade_selected = 1
  -- Number of upgrade pickers still owed after the one currently on screen.
  -- A single large XP gain can cross several level thresholds at once (see
  -- gain_xp); each owed level queues here and is drawn one after another as the
  -- player confirms each pick, instead of collapsing into a single picker.
  self.pending_levelups = 0
  self.show_hero_labels = false

  -- Stuck-ball aim state. While stuck_count > 0, paddle freezes and the
  -- left/right keys rotate aim_angle; SPACE launches every stuck ball.
  self.stuck_count = 0
  self.aim_angle   = -math.pi/2
  self.aim_speed   = math.pi*1.1   -- rad/s while holding left or right

  -- Powerup state. `buffs` is keyed by powerup kind holding {remaining,
  -- restore} pairs for active timed effects. `fire_trail_until` /
  -- `no_speed_reset` are simple flags read from BallHero. `floor_wall` is
  -- a reference to the temporary bottom-wall spawned by the floor powerup
  -- so we can despawn it at wave end / on reset.
  self.buffs            = {}
  self.fire_trail_until = 0
  self.no_speed_reset   = false
  self.floor_wall       = nil
  self.pierce_active    = false
  self.frozen           = false   -- freeze powerup: arena-wide deep freeze (gameplay + ice skins)
  self.frost_shards     = nil     -- pre-rolled edge ice-shard clusters for the frost overlay
  self.fire_active      = false   -- fire powerup: warm screen ambiance (visual only; no DoT)
  self.fire_flames      = nil     -- pre-rolled bottom-edge flame bases for the fire overlay

  -- Powerup pity timer. Powerups spawn on a periodic random roll with a
  -- ramping pity multiplier so dry streaks can't drag on forever.
  --   * Every `check_interval` seconds we roll for a spawn.
  --   * Base spawn chance is `base_chance`; each failed roll adds
  --     `pity_step` to the next check, capped at 100%.
  --   * On a successful spawn the streak counter resets to 0.
  -- The wave-end tier-2 in advance_wave is a separate guaranteed drop.
  -- Nerfed cadence (was 6s / 0.25 / 0.20 ≈ a powerup every ~14s — frequent
  -- enough to read as background noise): expected drop is now roughly every
  -- ~29s, so each catch is a real moment. BAL-tunable per paddle.
  self.powerup_pity = {
    timer          = 0,
    check_interval = BAL('powerups.check_interval', 9),
    streak         = 0,
    base_chance    = BAL('powerups.base_chance', 0.15),
    pity_step      = BAL('powerups.pity_step', 0.15),
    tier2_chance   = BAL('powerups.tier2_chance', 0.20),
  }

  -- The level-up ball ('level_random') spawns on its OWN timer, fully separate
  -- from the powerup pity roll above (and excluded from those pools via the
  -- `solo` flag in Powerup.KINDS). It drops on a randomized fixed-ish interval
  -- rather than the chance/streak model the regular powerups use.
  self.levelup_pity = {
    timer   = 0,
    -- First level-up ball ~30-45s in (was 20-30 — stretched alongside the
    -- harder XP curve so the orb doesn't leak free levels around it).
    next_at = random:float(BAL('powerups.level_orb_first_min', 30),
                           BAL('powerups.level_orb_first_max', 45)),
  }

  -- One-time signature setup for the selected paddle loadout (aegis brace
  -- state, mitosis regrow timer, phantom/tesla state). See paddles.lua.
  self.shop_selected = self.shop_selected or 1
  self:setup_signature()

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
-- e.g. a wizard adds to the same-colour tally for a cryomancer (both blue).
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


-- opts.no_mirror: skip the Twin Cast pair spawn (used by the mirror call
-- itself and by clone sources like apply_multi_ball / mitosis).
-- opts.clone: this ball is a temporary copy — don't record it as a drafted
-- character for the Mitosis regrow.
function BallPit:add_hero(character, opts)
  opts = opts or {}
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
    run_mods     = self.run_mods,
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
      -- Pierce: this specific ball is in its pierce flight. Undo Box2D's
      -- bounce off the brick by restoring the pre-collision velocity so the
      -- ball glides through. on_brick_hit already early-returned for this
      -- ball, so no damage / no combo / no on-bounce abilities fired.
      if h.piercing and h._last_vx then
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
      -- Boomerang loadout: any wall hit flags the ball to curl back home,
      -- damaging whatever it crosses on the return pass (see BallHero:update).
      if self.run_mods and self.run_mods.signature == 'boomerang' then
        h.boomerang_home = true
      end
      -- Top-wall hit ends pierce for this ball. The ball was passing through
      -- bricks while moving up; bouncing off the ceiling is the natural
      -- "now play normal — go ricochet through the bricks at the top".
      if other == self.top_wall and h.piercing then
        h:set_piercing(false)
        spawn_burst(self.effects, h.x, h.y, purple[0], 10, 80, 160)
        TelegraphRing{group = self.effects, x = h.x, y = h.y,
                      radius = 14, color = purple[0], duration = 0.25}
      end
    end
  end
  table.insert(self.heroes, hero)
  if self.seen_characters and not opts.clone then
    self.seen_characters[character] = true
  end
  -- Twin Cast loadout: every drafted hero arrives mirrored as a bonded pair
  -- (Binary Fusion). The mirror is registered as the hero's twin so the pair
  -- can orbit + fuse together (see BallPit:twincast_tick).
  if self.run_mods and self.run_mods.signature == 'twincast'
  and not opts.no_mirror and not opts.clone then
    local partner = self:add_hero(character, {no_mirror = true})
    self:twincast_register_pair(hero, partner)
  end
  return hero
end


-- Count the "blocks" still alive on screen: swarm bricks plus the brick-tagged
-- critters they spawn (EnemyCritter shares the 'brick' physics tag). Used to
-- gate the boss wave so it only starts on a fully cleared arena.
function BallPit:live_block_count()
  local n = 0
  if self.main and self.main.objects then
    for _, o in ipairs(self.main.objects) do
      if not o.dead and (o:is(Brick) or o:is(EnemyCritter)) then n = n + 1 end
    end
  end
  return n
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


-- ----- Boss-fight bumpers ---------------------------------------------------
--
-- The wave-10 arena is empty between the paddle and the boss, so a ball that
-- misses the core just falls all the way home. Bumpers surface periodically in
-- the band BELOW the boss's reach and kick balls back up at it (see
-- PinballBumper in effects.lua), which is what turns the fight into a rally.
--
-- BUMPER_CLEAR is the gap kept clear of the boss's own band and of the defense
-- line, so a bumper can never spawn somewhere the boss will fly through or
-- inside the paddle's dodge band.
local BUMPER_R          = 13
local BUMPER_INTERVAL   = {2.0, 3.2}   -- was {3.6, 5.4}
local BUMPER_MAX        = 4      -- alive at once
local BUMPER_LIFETIME   = 11
local BUMPER_CLEAR      = 18
local BUMPER_MIN_GAP    = 58     -- between two bumpers
local BUMPER_TRIES      = 14     -- placement attempts before giving up this tick

-- The vertical band a bumper may occupy. Boss:update clamps the boss to the TOP
-- HALF of the arena, so everything below that half -- plus the boss's own radius
-- and a margin -- is space it can never enter. The bottom stops short of the
-- defense line so a bumper never sits inside the paddle's dodge band.
function BallPit:bumper_band()
  local arena_h = self.y2 - self.y1
  local reach   = (self.boss and self.boss.r_outer) or 28
  return self.y1 + arena_h*0.5 + reach + BUMPER_CLEAR,
         self:breach_line_y() - BUMPER_CLEAR
end


function BallPit:live_bumpers()
  local n = 0
  for _, o in ipairs(self.floor.objects) do
    if o.is and o:is(PinballBumper) and not o.dead and not o.retiring then n = n + 1 end
  end
  return n
end


-- Place one bumper by rejection sampling: somewhere in the band, clear of the
-- other bumpers, and clear of the boss where it is RIGHT NOW as well -- the band
-- already excludes its path, but this costs nothing and covers the case of the
-- boss sitting at the very bottom of its travel as a bumper appears.
function BallPit:spawn_bumper()
  if not (self.boss and not self.boss.dead) then return end
  if self:live_bumpers() >= BUMPER_MAX then return end

  local top, bottom = self:bumper_band()
  if bottom - top < BUMPER_R*2 then return end

  for _ = 1, BUMPER_TRIES do
    local x = random:float(self.x1 + BUMPER_R + 8, self.x2 - BUMPER_R - 8)
    local y = random:float(top + BUMPER_R, bottom - BUMPER_R)
    local ok = true
    for _, o in ipairs(self.floor.objects) do
      if o.is and o:is(PinballBumper) and not o.dead
      and math.distance(x, y, o.x, o.y) < BUMPER_MIN_GAP then
        ok = false
        break
      end
    end
    if ok and math.distance(x, y, self.boss.x, self.boss.y)
             < (self.boss.r_outer or 28) + BUMPER_R + BUMPER_CLEAR then
      ok = false
    end
    if ok then
      PinballBumper{group = self.floor, x = x, y = y, rs = BUMPER_R,
                    color = yellow[0], lifetime = BUMPER_LIFETIME}
      return
    end
  end
end


-- Sink every live bumper. Called when the fight ends, so none is left standing
-- on an empty table after the boss is gone.
function BallPit:retire_bumpers()
  self.t:cancel('spawn_bumper')
  for _, o in ipairs(self.floor.objects) do
    if o.is and o:is(PinballBumper) and o.retire then o:retire() end
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
      -- Bumpers, from a beat after the boss lands so its arrival is uncluttered.
      arena.t:after(2.2, function()
        arena.t:every(BUMPER_INTERVAL, function()
          if arena.paused or arena.game_over or arena.upgrade_pending then return end
          arena:spawn_bumper()
        end, 0, nil, 'spawn_bumper')
      end)
    end
  end)
end


function BallPit:advance_wave()
  -- The fight is over (or the wave rolled on): take the table down.
  if self.retire_bumpers then self:retire_bumpers() end
  -- Guaranteed end-of-wave Tier-2 powerup drop. Spawned just inside the top
  -- of the arena so it's visible / catchable as the next wave starts.
  if Powerup then
    local t2 = Powerup.tier_2_kinds()
    if #t2 > 0 then
      local kind = t2[random:int(1, #t2)]
      local x    = self:arena_center_x() + random:float(-40, 40)
      local y    = self.y1 + 20
      self.t:after(0, function()
        -- By the time this deferred drop fires, start_wave has set the new
        -- wave_cfg; skip it entirely if we've just entered the boss wave, so no
        -- powerup appears during the boss fight. The post-boss clear still drops
        -- normally (wave 11 isn't a boss wave).
        if self.main and self.main.world and not (self.wave_cfg and self.wave_cfg.boss) then
          Powerup{group = self.main, x = x, y = y, kind = kind}
        end
      end)
    end
  end

  -- The floor runs on its own timer now (see apply_floor), but it never survives
  -- a wave boundary either: drop the wall AND the buff slot so the player has to
  -- re-earn the floor each wave.
  self:remove_floor()
  if self.buffs then self.buffs.floor = nil end

  -- CLEARING THE WAVE IS THE LEVEL. This is the whole progression loop for every
  -- loadout but the Terrorist (which is still on orbs -- see uses_xp_orbs). Paid
  -- here rather than in start_wave so it lands on the clear itself, and so the
  -- draft it opens covers the gap between waves instead of interrupting one.
  if not self:uses_xp_orbs() then self:level_up() end

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

-- Vertical breathing room a NEW swarm demands from every swarm already on the
-- field, in brick ROWS, rolled fresh for each spawn (see the spawner below).
-- Replaces a wave-scaled constant that decayed to 0 by wave 15 and let late
-- swarms stack flush into one unbroken wall; a per-swarm 0-3 row roll keeps a
-- readable seam without making the spacing uniform.
local SWARM_GAP_MIN_ROWS = 0
local SWARM_GAP_MAX_ROWS = 3


function BallPit:arena_center_x()
  return (self.x1 + self.x2)/2
end


function BallPit:snap_to_grid_x(x)
  local cx = self:arena_center_x()
  return cx + math.floor((x - cx)/CELL_W + 0.5)*CELL_W
end


-- Per-cell overlap check: walks every live brick in every live swarm and
-- bails if any of them shares a grid cell with the planned layout. Each
-- entry may be a multi-cell brick now (2x2, L, T, etc.), so we expand both
-- sides to their full {x, y} per-cell footprint and compare cells to cells
-- — the brick centroid alone is no longer enough. The vertical threshold is
-- widened by `min_gap` so that early waves enforce a few rows of empty
-- space between successive swarms.
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
          -- transient spring oscillation doesn't unblock a cell, and its
          -- SETTLED y (Swarm:place_y) so a swarm still gliding in already owns
          -- the slot it is heading for.
          for _, ep in ipairs(expand_to_cells(ec, swarm.x_center, swarm:place_y())) do
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
  -- Frozen by the freeze powerup: the arena is sealed -- no new swarms (not even
  -- the forced first-of-wave spawn) enter until it thaws.
  if self.frozen then return end
  local cfg            = self.wave_cfg
  local rows_count     = random:int(cfg.swarm_rows_min, cfg.swarm_rows_max)
  local width_fraction = random:float(cfg.width_fraction_min, cfg.width_fraction_max)
  local arena_w        = self.x2 - self.x1
  local max_cols       = math.max(2, math.floor(width_fraction*arena_w/CELL_W))

  -- Plan the per-row irregular layout once, then try a few anchor positions
  -- (zone-biased + snapped to grid) until we find one with no overlaps.
  local layout = Swarm.generate_cells(rows_count, max_cols, cfg.swarm_density, CELL_W, CELL_H)
  -- Where the top row SETTLES. Everything below -- the overlap test, the grid
  -- reservation -- is judged here, at the slot the swarm is claiming, not at the
  -- off-screen position it is built at.
  local y_top  = self.y1 + 8

  -- How far above the arena's top edge to build it, so the whole formation
  -- starts off screen and glides in (Swarm's entry glide). Deepest cell plus a
  -- row of clearance plus the gap down to the settle line: enough that the
  -- BOTTOM row is above the edge at spawn, so nothing pops into view.
  local deepest = 0
  for _, c in ipairs(layout) do if c.dy > deepest then deepest = c.dy end end
  local entry_dist = deepest + CELL_H + (y_top - self.y1) + 4

  -- Vertical clearance this swarm demands from the ones already on the field.
  -- Rolled once per spawn rather than per anchor attempt, so all 8 tries below
  -- are judged against the same requirement (see SWARM_GAP_MIN_ROWS).
  local min_gap = random:int(SWARM_GAP_MIN_ROWS, SWARM_GAP_MAX_ROWS)*CELL_H

  local x_center
  for attempt = 1, 8 do
    x_center = self:snap_to_grid_x(self:pick_swarm_anchor(width_fraction))
    if force or self:can_place_layout(x_center, y_top, layout, min_gap) then
      Swarm{
        group          = self.swarms,
        x_center       = x_center,
        y              = y_top,
        entry_dist     = entry_dist,
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
  -- Title: the arena is BUILT but wholly frozen behind the backglass -- self.t
  -- is not ticked either, so no wave timer, powerup pity or spawn can fire into
  -- the world the rule is about to drop into. Handled ahead of everything else
  -- for exactly that reason.
  if self.title_open then
    if input.escape.pressed then
      self.settings_open = not self.settings_open
      ui_switch1:play{volume = 0.3}
    end
    if self.settings_open then self:update_settings(dt) return end
    if self.tutorial_open then
      self:update_tutorial(dt)
      self.ui:update(dt)
      return
    end
    self:update_title(dt)
    self.ui:update(dt)
    return
  end

  self.t:update(dt)

  -- Page transitions run ahead of every early return below: a restart's gate
  -- has to keep animating after game_over has already been cleared, and the
  -- reset itself happens on the frame the shutters are shut (paddles.lua).
  self:tick_page_gate(dt)

  -- ESC toggles the settings overlay at any time (including from game-over
  -- and the level-up upgrade screen). While open, all other game updates
  -- are frozen.
  if input.escape.pressed then
    self.settings_open = not self.settings_open
    ui_switch1:play{volume = 0.3}
  end
  if self.settings_open then
    self:update_settings(dt)
    return
  end

  if self.game_over then
    self.ui:update(dt)
    -- The game-over overlay doubles as the paddle shop (see paddles.lua).
    self:update_shop(dt)
    if input.restart.pressed then self:begin_page_gate('restart') end
    return
  end

  -- Dying: the board is FROZEN (main / swarms deliberately not updated) while
  -- the wreck animates, so the only thing still moving is the thing that just
  -- failed. Effects and the UI keep running so the death plays out; the page
  -- gate is driven above every early return, so its shutters animate too.
  if self.dying then
    self:update_death(dt)
    self.effects:update(dt)
    self.ui:update(dt)
    return
  end

  if self.upgrade_pending then
    self:update_upgrade(dt)
    self.effects:update(dt)
    self.ui:update(dt)
    return
  end

  self.run_time  = self.run_time + dt
  self.wave_time = self.wave_time + dt
  if (self.fire_lock_t or 0) > 0 then self.fire_lock_t = self.fire_lock_t - dt end

  -- Terrorist loadout: passive XP gain over time. Gains a percentage of the
  -- current level's XP requirement per second, scaled to level up every ~6.5 seconds
  -- of passive gain. Updates every frame for smooth, continuous progress.
  if self.run_mods and self.run_mods.signature == 'terrorist' then
    local xp_pct_per_sec = self.run_mods.sig.passive_xp_pct or 0.1538  -- ~15.38% per sec = 6.5 sec per level
    local xp_gain = self.xp_to_next * xp_pct_per_sec * dt
    self.xp_accumulator = (self.xp_accumulator or 0) + xp_gain
    -- Grant XP in smaller chunks (every 0.1 XP accumulated) for smoother visual feedback
    while self.xp_accumulator >= 0.1 do
      self:gain_xp(1)
      self.xp_accumulator = self.xp_accumulator - 1.0
    end
  end

  -- Vampire loadout: HP is a continuously draining bar — stop killing and
  -- you die. Sits below the overlay early-returns above, so the drain
  -- auto-pauses in menus / the upgrade picker / game over.
  if self.run_mods and self.run_mods.hp_mode == 'bar' then
    self.player_hp = self.player_hp - (self.run_mods.sig.drain or 2)*dt
    if self.player_hp <= 0 then
      self.player_hp = 0
      self:trigger_game_over()
      return
    end
    self:update_vampire(dt)
  end

  -- Phantom loadout: E drops a ghost-paddle anchor / teleports back to it.
  if self.run_mods and self.run_mods.signature == 'phantom' and input.blink.pressed then
    self:phantom_blink()
  end

  -- Terrorist loadout: E detonates every ball currently near a block.
  if self.run_mods and self.run_mods.signature == 'terrorist' and input.blink.pressed then
    self:terror_manual_detonate()
  end

  -- Aegis loadout: E (or click) raises the shield for a sustained window —
  -- balls and bullets turned while it's up are parried (see Paddle:start_brace).
  if self.run_mods and self.run_mods.signature == 'aegis'
  and (input.blink.pressed or input.click.pressed) then
    self.paddle:start_brace()
  end

  -- Aim is adjustable whenever space is held OR a ball is stuck on the paddle.
  -- Holding space is the "auto-fire" mode: the aim line shows, arrow keys
  -- nudge the angle, and any stuck ball fires immediately (returning balls
  -- skip the stuck state entirely, see BallHero:update_return).
  -- The Pinball Lobber has no stick/aim/launch flow at all (balls are served
  -- from above and flipped, arrows are the flippers), so SPACE is dead there.
  local pinball_rig = self.run_mods and self.run_mods.signature == 'flippers'
  local aim_active = (self.stuck_count > 0 or input.launch.down) and not pinball_rig
  if aim_active then
    if input.aim_left.down then
      self.aim_angle = math.max(self.aim_angle - self.aim_speed*dt, -math.pi*0.92)
    end
    if input.aim_right.down then
      self.aim_angle = math.min(self.aim_angle + self.aim_speed*dt, -math.pi*0.08)
    end
  end
  if self.stuck_count > 0 and input.launch.down then
    self:launch_stuck_balls()
  end

  self.main:update(dt)
  self.swarms:update(dt)
  self.effects:update(dt)
  self.floor:update(dt)
  self.ui:update(dt)

  -- Powerup buffs (timed effects) + pity-timer driven random spawns.
  self:tick_buffs(dt)
  self:tick_powerup_pity(dt)
  self:tick_levelup_pity(dt)
  self:tick_combo(dt)
  self:tick_wave_bar(dt)
  self:tesla_tick(dt)    -- Tesla: persistent conduction web pulses (no-op otherwise)
  self:glacier_tick(dt)  -- Glacier: lay slick ice patches on the rink (no-op otherwise)
  self:twincast_tick(dt) -- Twin Cast: orbit/charge/fuse the bonded pairs (no-op otherwise)
  self:aegis_tick(dt)    -- Aegis: bulwark meter idle bleed (no-op otherwise)

  -- Wave advance. Three cases:
  --   * Boss wave (10): never advances on time -- only once the boss is dead
  --     (it flips boss_defeated in Boss:die). This is what makes wave 10 end
  --     strictly on boss defeat.
  --   * Wave 9 -> 10: once wave 9's timer is up, hold the boss wave until every
  --     block on screen is cleared, so the boss never spawns onto a half-full
  --     arena. New swarm spawns are stopped while we drain.
  --   * Any other wave: plain time-based advance (leftover bricks roll over).
  if self.wave_cfg.boss then
    if self.boss_defeated then
      self.boss_defeated = false
      self.boss          = nil
      self:advance_wave()
    end
  elseif self.wave_time >= self.wave_cfg.duration then
    if self.wave == 9 then
      if not self.awaiting_boss then
        self.awaiting_boss = true
        self.t:cancel('spawn_swarm')   -- stop adding blocks while the arena drains
      end
      if self:live_block_count() == 0 then
        self.awaiting_boss = false
        self:advance_wave()
      end
    else
      self:advance_wave()
    end
  end

  if input.launch.pressed then
    -- Tap launch to release any still-attached balls.
    -- Hero update handles this internally; nothing else to do here.
  end
end


-- ----- Title screen ---------------------------------------------------------
--
-- A pinball BACKGLASS: a solid panel behind a printed bezel, a symmetrical
-- sunburst crest, the marquee, and a rule under it. One ink colour in two
-- tints -- signwriting, not a colour wheel -- and nothing glows or drifts.
--
-- The rule under the title is the piece that matters: on start it does not fade
-- out, it SHRINKS AND DROPS INTO THE PADDLE. The arena behind the glass is
-- already built (on_enter), with the real paddle hidden, so the rule can be
-- aimed at that paddle's exact spawn point and width. It lands, the run is
-- rebuilt, and the paddle that appears is the rule -- same place, same size.
local TITLE_TEXT    = 'RICO RITE'
local TITLE_STAGGER = 0.055
local TITLE_DROP    = 0.34
local TITLE_DELAY   = 0.16       -- facade is up before the first letter lands
local TITLE_SETTLE  = TITLE_DELAY + TITLE_STAGGER*(#TITLE_TEXT - 1) + TITLE_DROP
local TITLE_SCALE   = 2.0
local TITLE_Y       = 0.285      -- fractions of screen height
local RULE_Y        = 0.365
local RULE_HALF     = 96         -- rule half-width at rest
local LAUNCH_DUR    = 1.05       -- rule -> paddle

-- The whole screen is these five values. Deep panel, a slightly lifted inlay,
-- gold ink with a bronze tint for the quiet strokes, and a warm off-white for
-- text that has to be read rather than admired.
local GLASS_DEEP   = Color(0.055, 0.045, 0.085, 1)
local GLASS_PANEL  = Color(0.086, 0.072, 0.125, 1)
local INK_GOLD     = Color(0.93, 0.78, 0.38, 1)
local INK_BRONZE   = Color(0.55, 0.42, 0.22, 1)
local INK_PALE     = Color(0.88, 0.85, 0.79, 1)
local INK_GOLD_DIM = Color(0.72, 0.60, 0.30, 1)


-- ----- The facade -----------------------------------------------------------
--
-- The two margins either side of the marquee are ~120px of nothing each, and
-- the band under the plates is another 200. One idea fills all three: the glass
-- is a carved FACADE. A pediment over an entablature, two fluted columns
-- carrying it, a stepped base under the lot, and the run records cut into a
-- stele between the columns.
--
-- Same five inks as the rest of the print. All the depth is keylines -- no
-- gradients, no light source, nothing that could not be screened onto glass.
-- Coordinates are absolute canvas values: gw/gh are not bound until engine_run,
-- so nothing at file scope may reference them.
local FAC_M         = 44    -- pediment / cornice inset from the canvas edge
local PED_APEX_Y    = 28
local PED_BASE_Y    = 74
local ENTAB_Y       = 74    -- cornice rule; the pediment sits on it
local DENTIL_Y      = 79
local DENTIL_H      = 7
local ARCH_Y        = 88    -- rule closing the entablature under the dentils
local COL_INSET     = 83    -- column centre line, in from the canvas edge
local COL_TOP       = 88    -- top of the abacus; meets the architrave
local COL_SHAFT_TOP = 112
local COL_SHAFT_BOT = 546
local COL_BOT       = 562   -- bottom of the plinth
local COL_HALF      = 16    -- shaft half-width at the base
local STYLO_Y       = 566   -- top step of the crepidoma
local STELE_CY      = 462
local STELE_W       = 216
local STELE_H       = 160


-- Shaft half-width at `ty` (0 at the shaft top, 1 at its bottom). A column is
-- not a rectangle: it tapers toward the top and carries a slight outward swell
-- -- entasis -- around the middle. Both are tiny here (2.5px and 0.5px), which
-- is the point: you should not be able to name what makes it look right.
local function col_half(ty)
  return COL_HALF*(0.84 + 0.16*ty + math.sin(ty*math.pi)*0.035)
end


-- One column: five bronze flutes between two gold arrises, every strip sampled
-- down the entasis curve so the swell actually reads. Capital and base are
-- struck as flat plates, the way the bezel is. `a` fades the whole thing in.
local function draw_column(cx, gold, bronze, a)
  local yt, yst, ysb = COL_TOP, COL_SHAFT_TOP, COL_SHAFT_BOT
  local sw = col_half(0)          -- shaft width where the echinus hands over

  -- Capital: abacus slab over a flared echinus, closed by a bead necking.
  graphics.rectangle(cx, yt + 4, 46, 8, 1, 1, bronze(0.18*a))
  graphics.rectangle(cx, yt + 4, 46, 8, 1, 1, gold(0.75*a), 1)
  local ech = {cx - 23, yt + 8, cx + 23, yt + 8, cx + sw, yst, cx - sw, yst}
  graphics.polygon(ech, bronze(0.16*a))
  graphics.polygon(ech, gold(0.5*a), 1)
  graphics.line(cx - sw, yst + 2, cx + sw, yst + 2, bronze(0.8*a), 1)

  -- Shaft. The engine draws with line_style "rough", so a near-vertical line
  -- snaps to whole pixel columns: sample often enough that the taper steps in
  -- small increments rather than in three visible jogs. graphics.polyline
  -- hands a flat table straight to love.graphics.line, so no unpacking here.
  local SEG = 14
  local function strip(u, color)
    local p = {}
    for i = 0, SEG do
      local ty = i/SEG
      p[#p + 1] = cx + col_half(ty)*u
      p[#p + 1] = yst + (ysb - yst)*ty
    end
    graphics.polyline(color, 1, p)
  end
  for k = -2, 2 do strip(k/2.6, bronze(0.5*a)) end
  strip(-1, gold(0.7*a))
  strip( 1, gold(0.7*a))

  -- Base: torus over a plinth, each a shade wider than the thing above it.
  graphics.rectangle(cx, ysb + 4,     42, 7, 2, 2, bronze(0.18*a))
  graphics.rectangle(cx, ysb + 4,     42, 7, 2, 2, gold(0.6*a), 1)
  graphics.rectangle(cx, COL_BOT - 4, 48, 9, 1, 1, bronze(0.16*a))
  graphics.rectangle(cx, COL_BOT - 4, 48, 9, 1, 1, gold(0.55*a), 1)
end


-- Cornice, dentil row, architrave. `dy` lets the crown settle down onto the
-- columns during the entrance.
local function draw_entablature(gold, bronze, a, dy)
  local x1, x2 = FAC_M, gw - FAC_M
  -- The cornice overhangs its own span, the way a real one throws a shadow.
  graphics.line(x1 - 5, ENTAB_Y + dy,     x2 + 5, ENTAB_Y + dy,     gold(0.8*a), 1)
  graphics.line(x1,     ENTAB_Y + 3 + dy, x2,     ENTAB_Y + 3 + dy, bronze(0.7*a), 1)
  -- Dentils: the row of small blocks that makes a cornice read as carved
  -- rather than drawn. Counted, then centred, so the run is symmetrical.
  local step  = 11
  local n     = math.floor(((x2 - 12) - (x1 + 12))/step) + 1
  local start = gw/2 - (n - 1)*step/2
  local y     = DENTIL_Y + DENTIL_H/2 + dy
  for i = 0, n - 1 do
    graphics.rectangle(start + i*step, y, 3, DENTIL_H, nil, nil, bronze(0.6*a))
  end
  graphics.line(x1, ARCH_Y + dy, x2, ARCH_Y + dy, bronze(0.5*a), 1)
end


-- The gable, its tympanum mark, and the three acroteria pips.
local function draw_pediment(gold, bronze, a, dy)
  local x1, x2 = FAC_M, gw - FAC_M
  local cx     = gw/2
  local ay, by = PED_APEX_Y + dy, PED_BASE_Y + dy
  graphics.polyline(gold(0.85*a),   1, {x1, by, cx, ay, x2, by})
  graphics.polyline(bronze(0.75*a), 1, {x1 + 13, by - 3, cx, ay + 8, x2 - 13, by - 3})
  -- Tympanum mark: a ball over a rule -- the game's own emblem, stated once.
  -- The stele echoes it at the bottom and that is the whole of it.
  graphics.circle(cx, by - 22, 4, gold(0.9*a))
  graphics.line(cx - 11, by - 12, cx + 11, by - 12, bronze(0.9*a), 1)
  -- Acroteria, using the same 3px pips the bezel corners already carry.
  graphics.rectangle(cx, ay - 3, 4, 4, nil, nil, gold(0.9*a))
  graphics.rectangle(x1, by - 2, 4, 4, nil, nil, gold(0.8*a))
  graphics.rectangle(x2, by - 2, 4, 4, nil, nil, gold(0.8*a))
end


-- Three receding steps, widest at the bottom: the columns have to land on
-- something or they read as hanging in the panel.
local function draw_crepidoma(gold, bronze, a)
  graphics.line(FAC_M - 2,  STYLO_Y,      gw - FAC_M + 2,  STYLO_Y,      gold(0.7*a), 1)
  graphics.line(FAC_M - 8,  STYLO_Y + 5,  gw - FAC_M + 8,  STYLO_Y + 5,  bronze(0.7*a), 1)
  graphics.line(FAC_M - 14, STYLO_Y + 10, gw - FAC_M + 14, STYLO_Y + 10, bronze(0.5*a), 1)
end


-- The four inscribed lines. Values come from the persistent record table that
-- finish_game_over writes; before the first death every one of them is a dash
-- rather than a zero, so an untouched stele reads as UNCUT instead of as a
-- record of bad runs.
local function title_record_rows()
  local r    = (state and state.records) or {}
  local runs = r.runs or 0
  local function cut(v, prefix)
    if runs <= 0 or not v or v <= 0 then return '--' end
    return (prefix or '') .. tostring(v)
  end
  local rank = '--'
  if runs > 0 and r.best_rank and COMBO_RANKS[r.best_rank] then
    rank = COMBO_RANKS[r.best_rank].label
  end
  return {
    {'FURTHEST',   cut(r.best_wave, 'WAVE ')},
    {'BEST SCORE', cut(r.best_score)},
    {'PEAK RANK',  rank},
    {'RITES',      cut(runs)},
  }
end


-- The stele: the run records cut into the wall between the columns. Its face is
-- GLASS_DEEP -- darker than the panel around it -- so it reads as recessed into
-- the glass rather than as one more plate lying on top of it.
local function draw_stele(gold, bronze, pale, a)
  local cx, top = gw/2, STELE_CY - STELE_H/2
  graphics.rectangle(cx, STELE_CY, STELE_W, STELE_H, 3, 3,
                     Color(GLASS_DEEP.r, GLASS_DEEP.g, GLASS_DEEP.b, 0.85*a))
  graphics.rectangle(cx, STELE_CY, STELE_W,     STELE_H,     3, 3, gold(0.6*a),   1)
  graphics.rectangle(cx, STELE_CY, STELE_W - 9, STELE_H - 9, 2, 2, bronze(0.7*a), 1)

  graphics.print_centered('RECORDS', pixul_font, cx, top + 16, 0, 1, 1, 0, 0, gold(0.95*a))
  graphics.line(cx - 54, top + 28, cx + 54, top + 28, bronze(0.8*a), 1)
  for _, s in ipairs({-1, 1}) do
    graphics.rectangle(cx + s*62, top + 28, 3, 3, nil, nil, gold(0.85*a))
  end

  local y = top + 44
  for _, row in ipairs(title_record_rows()) do
    graphics.print(row[1], pixul_font, cx - STELE_W/2 + 20, y, 0, 1, 1, 0, 0, pale(0.7*a))
    -- Values are set flush RIGHT so the column of them lines up the way an
    -- inscription's does. Measured rather than guessed -- get_text_width folds
    -- the font's tracking in, which a character count would miss.
    local w = pixul_font:get_text_width(row[2])
    graphics.print(row[2], pixul_font, cx + STELE_W/2 - 20 - w, y, 0, 1, 1, 0, 0, gold(0.95*a))
    y = y + 21
  end

  graphics.circle(cx, top + 138, 3, bronze(0.9*a))
  graphics.line(cx - 11, top + 146, cx + 11, top + 146, bronze(0.7*a), 1)
end


-- ---- dust ------------------------------------------------------------------
-- Fourteen specks drifting down the panel. Seeded on first use rather than at
-- file scope, because `random` is not bound until engine_run either; wrapped
-- forever after, since the title screen is never rebuilt.
local TITLE_MOTES = nil
local function title_motes()
  if TITLE_MOTES then return TITLE_MOTES end
  TITLE_MOTES = {}
  for i = 1, 14 do
    TITLE_MOTES[i] = {
      x  = random:float(28, gw - 28), y  = random:float(28, gh - 28),
      vx = random:float(-2.5, 2.5),   vy = random:float(3, 9),
      r  = random:float(0.6, 1.5),    a  = random:float(0.10, 0.26),
      p  = random:float(0, math.pi*2),
    }
  end
  return TITLE_MOTES
end


-- Drift: down, with a slow sway. Slow enough that you only notice it once you
-- have stopped reading -- the room is old, not haunted.
local function update_title_motes(dt)
  for _, m in ipairs(title_motes()) do
    m.p = m.p + dt*0.6
    m.y = m.y + m.vy*dt
    m.x = m.x + (m.vx + math.sin(m.p)*3)*dt
    if m.y > gh - 24 then m.y, m.x = 24, random:float(28, gw - 28) end
    if     m.x < 24      then m.x = gw - 24
    elseif m.x > gw - 24 then m.x = 24 end
  end
end



-- The two plates under the rule. Geometry FIRST, read by both the hit test and
-- the draw, so a plate can never be painted somewhere it cannot be clicked.
function BallPit:title_buttons()
  return {
    {id = 'play',     label = 'PLAY',     x = gw/2, y = gh*0.455, w = 132, h = 24},
    {id = 'tutorial', label = 'TUTORIAL', x = gw/2, y = gh*0.520, w = 132, h = 24},
  }
end


function BallPit:title_button_under_mouse()
  for i, b in ipairs(self:title_buttons()) do
    if mouse.x >= b.x - b.w/2 and mouse.x <= b.x + b.w/2
    and mouse.y >= b.y - b.h/2 and mouse.y <= b.y + b.h/2 then return b, i end
  end
  return nil
end


function BallPit:title_select(delta)
  local n = #self:title_buttons()
  local s = ((self.title_selected or 1) - 1 + delta) % n + 1
  if s ~= self.title_selected then
    self.title_selected = s
    ui_switch1:play{volume = 0.25}
  end
end


function BallPit:title_activate()
  local b = self:title_buttons()[self.title_selected or 1]
  if not b then return end
  if b.id == 'play' then
    self:start_title_launch()
  else
    self.tutorial_open  = true
    self.tutorial_page  = 1
    self.tutorial_t     = 0
    self.tutorial_phase = 'in'
    self.tutorial_anim  = 0
    ui_switch1:play{volume = 0.3}
  end
end


function BallPit:update_title(dt)
  self.title_t = (self.title_t or 0) + dt
  update_title_motes(dt)

  if self.title_phase == 'launch' then
    self.launch_t = (self.launch_t or 0) + dt
    if self.launch_t >= LAUNCH_DUR then self:finish_title() end
    return
  end

  -- Hover picks; W/S and the arrows move; SPACE / ENTER commit. A click only
  -- counts ON a plate -- a stray click in the margin used to start the run,
  -- which is not what a menu with two choices on it should do.
  local hovered, idx = self:title_button_under_mouse()
  if hovered and idx ~= self.title_selected then
    self.title_selected = idx
    ui_switch1:play{volume = 0.25}
  end
  if input.move_up.pressed   or input.aim_left.pressed  then self:title_select(-1) end
  if input.move_down.pressed or input.aim_right.pressed then self:title_select(1)  end
  if input.confirm.pressed or input.launch.pressed
  or (input.click.pressed and hovered) then
    self:title_activate()
  end
end


-- Begin the transformation. Everything the rule needs to become is read off the
-- REAL paddle: on_enter built the run before the glass went up and the title
-- branch freezes it, so that paddle is sitting untouched at its spawn point --
-- which is exactly where the rule has to end up for the hand-off to read as one
-- object rather than a swap.
function BallPit:start_title_launch()
  if self.title_phase == 'launch' then return end
  self.title_phase = 'launch'
  self.launch_t    = 0
  local p = self.paddle
  self.launch_to_x = (p and p.x) or gw/2
  self.launch_to_y = (p and p.y) or (self.y2 - 14)
  self.launch_to_w = (p and p.w) or 36
  self.launch_to_h = (p and p.h) or 4
  mine1:play{volume = 0.45, pitch = 0.72}
end


-- The rule has landed. Rebuild the run so play starts clean; the fresh paddle
-- spawns at the point the rule just came to rest on, at the width it just
-- shrank to, so the glass lifting reveals the same object that fell.
function BallPit:finish_title()
  self.title_open  = false
  self.title_phase = 'idle'
  self:reset_run()
  -- Struck AFTER the rebuild, so it survives into the first frame of play.
  local p = self.paddle
  if p then
    TelegraphRing{group = self.effects, x = p.x, y = p.y, radius = 44,
                  color = INK_GOLD, duration = 0.30}
    spawn_burst(self.effects, p.x, p.y, INK_GOLD, 14, 70, 190)
  end
  spawn1:play{volume = 0.45}
  camera:shake(3, 0.18, 90)
end


-- Rule geometry for the current frame: where it is, how wide, how thick. At
-- rest it is the keyline under the title; mid-launch it is on its way to being
-- the paddle. One function so the drawn rule and the landing point can never
-- disagree.
function BallPit:title_rule_pose()
  local cx, cy = gw/2, gh*RULE_Y
  local half, th = RULE_HALF, 2
  if self.title_phase ~= 'launch' then return cx, cy, half, th, 0 end
  -- Held briefly, then eased in and out of the drop: it leaves reluctantly and
  -- arrives softly, which is what makes it read as being placed rather than
  -- dropped.
  local k = math.clamp(((self.launch_t or 0) - 0.14)/0.74, 0, 1)
  local e = (k < 0.5) and (2*k*k) or (1 - ((-2*k + 2)^2)/2)
  local to_half = (self.launch_to_w or 36)/2
  local to_th   = (self.launch_to_h or 4)
  -- Squash on arrival: a hair wider and flatter as it seats, settling back.
  local land = math.clamp((k - 0.86)/0.14, 0, 1)
  local sq   = math.sin(land*math.pi)*0.18
  return cx  + ((self.launch_to_x or cx) - cx)*e,
         cy  + ((self.launch_to_y or cy) - cy)*e,
         (half + (to_half - half)*e)*(1 + sq),
         (th   + (to_th   - th)*e)*(1 - sq*0.5),
         k
end


function BallPit:draw_title()
  local t = self.title_t or 0
  local launching = (self.title_phase == 'launch')
  local k = launching and math.clamp((self.launch_t or 0)/LAUNCH_DUR, 0, 1) or 0
  -- The glass itself lifts over the back half of the launch, so the arena is
  -- already showing by the time the rule seats into it.
  local glass = launching and (1 - math.clamp((k - 0.55)/0.42, 0, 1)) or 1
  -- Everything printed on the glass goes first and fast -- the rule is the only
  -- thing that survives the transition, so nothing else may compete with it.
  local ink = launching and (1 - math.clamp(k/0.34, 0, 1)) or 1
  -- Torch flicker: ONE scalar, multiplied into the GOLD ink only. Two detuned
  -- sines so the period is never countable, and shallow enough (~2%) that it
  -- reads as a warm room rather than as an animation.
  local lume = 1 + 0.022*math.sin(t*1.7) + 0.012*math.sin(t*4.3 + 1.1)

  -- ---- the panel -----------------------------------------------------------
  if glass > 0.001 then
    graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil,
                       Color(GLASS_DEEP.r, GLASS_DEEP.g, GLASS_DEEP.b, glass))
    -- Inlay: a slightly lifted field inside the bezel. Flat fill, no gradient,
    -- no light -- the depth comes from the keylines, the way a printed glass
    -- gets it.
    local m = 16
    graphics.rectangle(gw/2, gh/2, gw - m*2, gh - m*2, 3, 3,
                       Color(GLASS_PANEL.r, GLASS_PANEL.g, GLASS_PANEL.b, glass))
  end

  if ink > 0.001 then
    local function gold(a)   return Color(INK_GOLD.r,   INK_GOLD.g,   INK_GOLD.b,   math.min(a*ink*lume, 1)) end
    local function bronze(a) return Color(INK_BRONZE.r, INK_BRONZE.g, INK_BRONZE.b, a*ink) end
    local function pale(a)   return Color(INK_PALE.r,   INK_PALE.g,   INK_PALE.b,   a*ink) end

    -- ---- bezel: double keyline with deco corner brackets --------------------
    local m = 16
    graphics.rectangle(gw/2, gh/2, gw - m*2,     gh - m*2,     3, 3, gold(0.55), 1)
    graphics.rectangle(gw/2, gh/2, gw - m*2 - 6, gh - m*2 - 6, 2, 2, bronze(0.75), 1)
    local bx1, by1 = m + 3, m + 3
    local bx2, by2 = gw - m - 3, gh - m - 3
    for _, c in ipairs({{bx1, by1, 1, 1}, {bx2, by1, -1, 1},
                        {bx1, by2, 1, -1}, {bx2, by2, -1, -1}}) do
      local x, y, sx, sy = c[1], c[2], c[3], c[4]
      graphics.line(x, y + sy*14, x + sx*14, y + sy*14, gold(0.8), 1)
      graphics.line(x + sx*14, y, x + sx*14, y + sy*14, gold(0.8), 1)
      graphics.rectangle(x + sx*5, y + sy*5, 3, 3, nil, nil, gold(0.9))
    end

    -- ---- dust --------------------------------------------------------------
    -- Drawn here, under the facade, so a speck never crosses a keyline.
    for _, m in ipairs(title_motes()) do
      graphics.circle(m.x, m.y, m.r, bronze(m.a))
    end

    -- ---- the facade --------------------------------------------------------
    -- Columns and steps come up first; the crown then SETTLES onto them from
    -- above. Stone descends -- nothing here floats into place.
    local base_k  = math.clamp(t/0.30, 0, 1)
    local crown_k = math.clamp((t - 0.18)/0.34, 0, 1)
    if base_k > 0 then
      draw_column(COL_INSET,      gold, bronze, base_k)
      draw_column(gw - COL_INSET, gold, bronze, base_k)
      draw_crepidoma(gold, bronze, base_k)
    end
    if crown_k > 0 then
      local dy = -9*(1 - crown_k)^3
      draw_entablature(gold, bronze, crown_k, dy)
      draw_pediment(gold, bronze, crown_k, dy)
    end

    -- ---- crest: a static sunburst behind the marquee ------------------------
    local cx, cy = gw/2, gh*TITLE_Y
    -- The crest breathes: +/-2px on a slow sine. It is the only thing on the
    -- glass that moves without a reason to, and even at full stretch the apex
    -- stays clear of the architrave above it.
    local breath = math.sin(t*0.9)*2
    for i = -7, 7 do
      local a  = -math.pi/2 + i*0.135
      local r1 = 54 + (math.abs(i) % 2)*10
      local r2 = r1 + 30 - math.abs(i)*1.6 + breath
      graphics.line(cx + math.cos(a)*r1, cy + math.sin(a)*r1,
                    cx + math.cos(a)*r2, cy + math.sin(a)*r2,
                    bronze(0.5 - math.abs(i)*0.03), 1)
    end
    graphics.arc('open', cx, cy, 50, math.pi*1.12, math.pi*1.88, gold(0.45), 1)
    graphics.arc('open', cx, cy, 46, math.pi*1.12, math.pi*1.88, bronze(0.7), 1)

    -- ---- the marquee: one ink, letters set one at a time ---------------------
    local n, widths, total = #TITLE_TEXT, {}, 0
    for i = 1, n do
      widths[i] = fat_font:get_text_width(TITLE_TEXT:sub(i, i))
      total     = total + widths[i]
    end
    local x = gw/2 - (total*TITLE_SCALE)/2
    for i = 1, n do
      local ch = TITLE_TEXT:sub(i, i)
      local lk = math.clamp((t - TITLE_DELAY - (i - 1)*TITLE_STAGGER)/TITLE_DROP, 0, 1)
      if lk > 0 and ch ~= ' ' then
        local e = 1 - (1 - lk)*(1 - lk)*(1 - lk)
        local y = gh*TITLE_Y - 46*(1 - e)
        -- Struck twice: a bronze plate offset down-right, gold face over it.
        -- Reads as embossed signwriting without a single glow.
        graphics.print(ch, fat_font, x + 2, y + 2, 0, TITLE_SCALE, TITLE_SCALE, 0, 0, bronze(0.9*lk))
        graphics.print(ch, fat_font, x,     y,     0, TITLE_SCALE, TITLE_SCALE, 0, 0, gold(lk))
      end
      x = x + widths[i]*TITLE_SCALE
    end

    -- ---- the menu plates ----------------------------------------------------
    local pk = math.clamp((t - TITLE_SETTLE)/0.45, 0, 1)
    if pk > 0 then
      for i, b in ipairs(self:title_buttons()) do
        local on = (i == (self.title_selected or 1))
        -- The selected plate is filled and gold-edged; the other is a bronze
        -- keyline. Selection is a change of WEIGHT, not of colour, so the
        -- scheme stays one scheme.
        if on then
          graphics.rectangle(b.x, b.y, b.w, b.h, 2, 2, gold(0.16))
          -- Deco pointers either side, the way a backglass marks its live line.
          for _, s in ipairs({-1, 1}) do
            local dx = b.x + s*(b.w/2 + 9)
            graphics.polygon({dx - s*4, b.y - 4, dx + s*3, b.y, dx - s*4, b.y + 4}, gold(0.9*pk))
          end
        end
        graphics.rectangle(b.x, b.y, b.w, b.h, 2, 2, on and gold(0.95*pk) or bronze(0.9*pk), 1)
        graphics.print_centered(b.label, pixul_font, b.x, b.y, 0, 1, 1, 0, 0,
                                on and gold(pk) or pale(pk*0.7))
      end
      draw_stele(gold, bronze, pale, pk)
      graphics.print_centered('ESC   SETTINGS',
                              pixul_font, gw/2, gh*0.895, 0, 1, 1, 0, 0, bronze(pk*0.9))
      -- Ground line. The facade stands ON something, so this runs the full
      -- width of the crepidoma rather than stopping under the plates.
      graphics.line(40, gh*0.925, gw - 40, gh*0.925, bronze(pk*0.6), 1)
    end
  end

  -- ---- the rule ------------------------------------------------------------
  -- Drawn last and never faded: it is the one element that leaves the glass and
  -- becomes part of the game.
  local rx, ry, rhalf, rth = self:title_rule_pose()
  local settle = math.clamp((t - TITLE_SETTLE + 0.2)/0.4, 0, 1)
  if settle > 0 then
    local w = rhalf*2*(launching and 1 or settle)
    -- Explicit inks, not the ink() helpers above: those live inside the
    -- glass-fade block and are scoped to it, and the rule must NOT fade with
    -- the rest of the print -- it is the one element that leaves the glass.
    graphics.rectangle(rx, ry + 1, w, rth, 1, 1, INK_BRONZE)
    graphics.rectangle(rx, ry,     w, rth, 1, 1, INK_GOLD)
    -- Deco caps: small diamonds at each end while it is still a keyline. They
    -- retract as it becomes a paddle, so nothing ornamental survives into play.
    local caps = launching and (1 - math.clamp(((self.launch_t or 0) - 0.14)/0.4, 0, 1)) or 1
    if caps > 0.01 then
      for _, s in ipairs({-1, 1}) do
        local dx = rx + s*(rhalf + 7)
        graphics.polygon({dx, ry - 4, dx + 4, ry, dx, ry + 4, dx - 4, ry},
                         Color(INK_GOLD.r, INK_GOLD.g, INK_GOLD.b, caps))
      end
    end
  end
end


-- ----- Tutorial ---------------------------------------------------------
--
-- Opened from the title's TUTORIAL button. A prototype reference for the whole
-- game, written as PAGES OF ROWS rather than prose: every entry is a short
-- label and the one line that explains it, so a player can find the thing they
-- are looking for by scanning instead of reading. Navigated with the PREV /
-- BACK / NEXT buttons, the arrow or A/D keys, or the mouse.
--
-- Content is deliberately exhaustive -- controls, every enemy family, every
-- powerup tier, the combo ladder, the boss, the loadouts -- because the point
-- of the prototype is to find out which of it a player actually needs.
local TUTORIAL_PAGES = {
  {title = 'CONTROLS', rows = {
    {'A / D',      'move the paddle left and right'},
    {'W / S',      'lift and lower it inside the dodge band'},
    {'LEFT/RIGHT', 'aim a ball that is stuck to the paddle'},
    {'SPACE',      'launch a stuck ball -- hold to see the aim line'},
    {'E',          'the signature power of your paddle loadout'},
    {'MOUSE 1',    'confirm menu choices'},
    {'ENTER',      'confirm a draft card'},
    {'R',          'restart the run from the game-over screen'},
    {'ESC',        'settings (window size)'},
  }},

  {title = 'THE LINE', rows = {
    {'RED DOTS',   'the defense line above your paddle'},
    {'A BREACH',   'is a block crossing it -- that costs you HP'},
    {'THE COST',   'scales with how big the swarm was'},
    {'RETALIATION','a breach sets off a shockwave in return'},
    {'IT SWEEPS',  'up the arena, damaging and shoving every swarm'},
    {'SO',         'losing a heart also buys you room'},
  }},

  {title = 'LEVELS', rows = {
    {'CLEAR A WAVE', 'and you gain a level -- one per wave'},
    {'A LEVEL',    'opens the three-card draft'},
    {'THE BAR',    'up top fills as the wave runs down'},
    {'WAVE 10',    'the boss: it fills as the boss bleeds'},
    {'LEVEL ORBS', 'a powerup that levels your BALLS instead'},
    {'TERRORIST',  'that loadout levels on XP orbs instead'},
  }},

  {title = 'COMBO METER', rows = {
    {'POINTS',     'from chaining block hits without missing'},
    {'RANKS',      'D, C, B, A, S, SS, SSS, FRENZY'},
    {'IT PAYS',    'faster balls -- not raw damage'},
    {'IT BLEEDS',  'idle time drains a fraction of what you hold'},
    {'SO',         'a hot meter costs more attention than a cold one'},
    {'DROPPING',   'a ball into the pit takes a heavy cut'},
  }},

  {title = 'POWERUPS (1/2)', rows = {
    {'THEY DROP',  'on a timer and at the end of every wave'},
    {'TIER 1',     'catch it with the paddle -- instant effect'},
    {'TIER 2',     'DEFLECT it with the paddle to arm it, then catch'},
    {'HEAL',       'restores hearts'},
    {'WIDE',       'a bigger paddle -- and shots pass through you'},
    {'BIG BALL',   'oversized, heavier-hitting balls'},
  }},

  {title = 'POWERUPS (2/2)', rows = {
    {'MULTI BALL', 'more balls in play at once'},
    {'PIERCE',     'balls punch through instead of bouncing off'},
    {'FIRE TRAIL', 'balls leave burning ground behind them'},
    {'FREEZE',     'the whole arena stops for a few seconds'},
    {'WATER WAVE', 'a surge that shoves every swarm back up'},
    {'FLOOR',      'a temporary floor -- no ball can fall out'},
    {'LEVEL ORB',  'levels several random balls at once'},
  }},

  {title = 'ENEMIES (1/2)', rows = {
    {'SEEKER',     'the basic block -- drifts and breaches'},
    {'TANK',       'slow, very high HP'},
    {'BOOSTER',    'speeds up its whole row'},
    {'EXPLODER',   'chain-detonates its neighbours on death'},
    {'HEADBUTTER', 'lunges down the screen in bursts'},
    {'FORCER',     'shoves your balls away from it'},
    {'RANDOMIZER', 'scrambles the direction of what it touches'},
  }},

  {title = 'ENEMIES (2/2)', rows = {
    {'SHOOTER',    'plain aimed shots'},
    {'SNIPER',     'a single fast, long-range shot'},
    {'SPREADER',   'a fan of shots at once'},
    {'BURSTER',    'a rapid string of them'},
    {'ARC LOBBER', 'a shot that curves down onto you'},
    {'SPIRALER',   'a rotating spray'},
    {'CRITTERS',   'small enemies that walk down at the paddle'},
  }},

  {title = 'WAVES & BOSS', rows = {
    {'WAVES',      'each one is longer, wider and denser'},
    {'WAVE 10',    'THE PRISM CORE -- the boss'},
    {'PHASES',     'three, each faster and with new attacks'},
    {'ITS SHOTS',  'some are unbreakable -- those cannot be parried'},
    {'ON DEATH',   'three paddle levels and five ball levels'},
    {'WAVE 11+',   'the hardest tier, forever'},
  }},

  {title = 'LOADOUTS', rows = {
    {'PADDLES',    'thirteen of them, each rewriting a core verb'},
    {'STATS',      'size, speed, damage, XP rate all differ'},
    {'SIGNATURE',  'each has one power, usually on E'},
    {'AEGIS',      'raise a shield -- parried shots fly back at them'},
    {'PINBALL',    'two flippers instead of a bar'},
    {'PHANTOM',    'drop an anchor, blink back to it'},
    {'UNLOCK',     'them in the shop after a run'},
  }},
}


-- Buttons are geometry FIRST: hit-testing and drawing both read this, so a
-- button can never be drawn somewhere it cannot be clicked.
function BallPit:tutorial_buttons()
  local y = gh*0.885
  return {
    {id = 'prev',  label = '<  PREV', x = gw*0.23, y = y, w = 92, h = 22},
    {id = 'close', label = 'BACK',    x = gw*0.50, y = y, w = 82, h = 22},
    {id = 'next',  label = 'NEXT  >', x = gw*0.77, y = y, w = 92, h = 22},
  }
end


function BallPit:tutorial_button_under_mouse()
  for _, b in ipairs(self:tutorial_buttons()) do
    if mouse.x >= b.x - b.w/2 and mouse.x <= b.x + b.w/2
    and mouse.y >= b.y - b.h/2 and mouse.y <= b.y + b.h/2 then return b end
  end
  return nil
end


function BallPit:tutorial_go(delta)
  local n = #TUTORIAL_PAGES
  local p = math.clamp((self.tutorial_page or 1) + delta, 1, n)
  if p ~= self.tutorial_page then
    self.tutorial_page = p
    self.tutorial_t    = 0     -- restart the row stagger: a turn SETS a page
    ui_switch1:play{volume = 0.3}
  end
end


-- Enter / exit timing. The panel does not appear and disappear -- it is racked
-- in and pulled out, which is what stops it reading as a dialog box dropped on
-- top of the machine.
local TUT_IN  = 0.26
local TUT_OUT = 0.20


-- 0 -> 1 racking in, 1 while it is up, 1 -> 0 pulling out. Note it reaches
-- EXACTLY 1 at rest, so the drawn buttons and the hit test agree while the
-- page is actually interactive (input is ignored during both transitions).
function BallPit:tutorial_anim_k()
  local a = self.tutorial_anim or 0
  if self.tutorial_phase == 'in' then
    local p = math.clamp(a/TUT_IN, 0, 1)
    return 1 - (1 - p)*(1 - p)*(1 - p)
  elseif self.tutorial_phase == 'out' then
    local p = math.clamp(a/TUT_OUT, 0, 1)
    return 1 - p*p
  end
  return 1
end


function BallPit:close_tutorial()
  if self.tutorial_phase == 'out' then return end
  self.tutorial_phase = 'out'
  self.tutorial_anim  = 0
  ui_switch1:play{volume = 0.3}
end


function BallPit:update_tutorial(dt)
  self.tutorial_t    = (self.tutorial_t or 0) + dt
  self.tutorial_anim = (self.tutorial_anim or 0) + dt

  -- Input is deliberately dead through both transitions: the panel is moving,
  -- so what is under the cursor is not what will be under it a frame later.
  if self.tutorial_phase == 'in' then
    if self.tutorial_anim >= TUT_IN then
      self.tutorial_phase, self.tutorial_anim = 'idle', 0
    end
    return
  elseif self.tutorial_phase == 'out' then
    if self.tutorial_anim >= TUT_OUT then
      self.tutorial_open  = false
      self.tutorial_phase = 'idle'
    end
    return
  end

  local hovered = self:tutorial_button_under_mouse()
  self.tutorial_hover = hovered and hovered.id or nil
  if hovered and input.click.pressed then
    if     hovered.id == 'prev'  then self:tutorial_go(-1)
    elseif hovered.id == 'next'  then self:tutorial_go(1)
    else   self:close_tutorial() end
    return
  end

  if input.move_left.pressed  or input.aim_left.pressed  then self:tutorial_go(-1) end
  if input.move_right.pressed or input.aim_right.pressed then self:tutorial_go(1)  end
  -- SPACE / ENTER page forward, and close out of the last page, so the whole
  -- thing can be read on one key without ever reaching for the mouse.
  if input.launch.pressed or input.confirm.pressed then
    if (self.tutorial_page or 1) >= #TUTORIAL_PAGES then
      self:close_tutorial()
    else
      self:tutorial_go(1)
    end
  end
end


function BallPit:draw_tutorial()
  local page = TUTORIAL_PAGES[self.tutorial_page or 1]
  if not page then return end
  local t = self.tutorial_t or 0

  -- Racked in / pulled out (see tutorial_anim_k). The ground is faded but NOT
  -- scaled -- scaling a full-screen fill would open a gap at the edges and show
  -- the arena through it. Everything printed on the panel is scaled about the
  -- centre instead, and the alpha multiplier carries the fade through every
  -- layer below without threading it into each colour by hand.
  local k = self:tutorial_anim_k()
  if k <= 0.005 then return end
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil,
                     Color(GLASS_DEEP.r, GLASS_DEEP.g, GLASS_DEEP.b, k))
  local prev_alpha = graphics.alpha_mult
  graphics.alpha_mult = prev_alpha*k
  local s = 0.90 + 0.10*k
  graphics.push(gw/2, gh/2, 0, s, s)

  local m = 16
  graphics.rectangle(gw/2, gh/2, gw - m*2,     gh - m*2,     3, 3, GLASS_PANEL)
  graphics.rectangle(gw/2, gh/2, gw - m*2,     gh - m*2,     3, 3, INK_GOLD_DIM, 1)
  graphics.rectangle(gw/2, gh/2, gw - m*2 - 6, gh - m*2 - 6, 2, 2, INK_BRONZE, 1)

  -- Header: page title over a rule, with the page count opposite.
  graphics.print_centered(page.title, fat_font, gw/2, gh*0.105, 0, 1.25, 1.25, 0, 0, INK_GOLD)
  graphics.line(gw*0.14, gh*0.145, gw*0.86, gh*0.145, INK_BRONZE, 1)
  graphics.print_centered(string.format('%d / %d', self.tutorial_page or 1, #TUTORIAL_PAGES),
                          pixul_font, gw/2, gh*0.165, 0, 1, 1, 0, 0, INK_BRONZE)

  -- Rows: label column in gold, explanation in pale. Two columns, never a
  -- paragraph -- the whole point is that it can be scanned.
  local y = gh*0.225
  for i, row in ipairs(page.rows) do
    -- Rows fade up in sequence, so a page turn reads as a page being SET.
    local k = math.clamp((t - (i - 1)*0.035)/0.18, 0, 1)
    if k > 0 then
      graphics.print(row[1], pixul_font, gw*0.10, y, 0, 1, 1, 0, 0,
                     Color(INK_GOLD.r, INK_GOLD.g, INK_GOLD.b, k))
      graphics.print(row[2], pixul_font, gw*0.36, y, 0, 1, 1, 0, 0,
                     Color(INK_PALE.r, INK_PALE.g, INK_PALE.b, k*0.92))
    end
    y = y + gh*0.052
  end

  -- Buttons. Disabled ends are drawn dimmed rather than hidden, so the shape
  -- of the row never moves as you page through.
  local n = #TUTORIAL_PAGES
  for _, b in ipairs(self:tutorial_buttons()) do
    local dead = (b.id == 'prev' and (self.tutorial_page or 1) <= 1)
              or (b.id == 'next' and (self.tutorial_page or 1) >= n)
    local hot  = (self.tutorial_hover == b.id) and not dead
    local edge = dead and INK_BRONZE or (hot and INK_GOLD or INK_GOLD_DIM)
    local face = dead and Color(INK_BRONZE.r, INK_BRONZE.g, INK_BRONZE.b, 0.55)
                       or (hot and INK_GOLD or INK_PALE)
    if hot then
      graphics.rectangle(b.x, b.y, b.w, b.h, 2, 2,
                         Color(INK_GOLD.r, INK_GOLD.g, INK_GOLD.b, 0.14))
    end
    graphics.rectangle(b.x, b.y, b.w, b.h, 2, 2, edge, 1)
    graphics.print_centered(b.label, pixul_font, b.x, b.y, 0, 1, 1, 0, 0, face)
  end

  graphics.pop()
  graphics.alpha_mult = prev_alpha
end


-- Clip the play field to the arena's TOP EDGE for the duration of `draw_fn`.
--
-- Swarms now glide in from ABOVE that edge (see the entry glide in swarm.lua),
-- and the band above it is not spare canvas -- it is the HUD, where the
-- progression bar and the combo meter live. Without a clip an arriving formation
-- would slide straight over the readouts. With it, a swarm emerges from behind
-- the frame, which is what it is doing.
--
-- The scissor is in canvas space, so it does NOT follow camera shake: during a
-- shake the clip line holds while the contents move under it. At the 1-3px the
-- shake actually uses that reads as the cabinet's frame staying put.
function BallPit:clip_to_arena(draw_fn)
  love.graphics.setScissor(0, self.y1, gw, gh - self.y1)
  draw_fn()
  love.graphics.setScissor()
end


function BallPit:draw()
  self.floor:draw()
  self:clip_to_arena(function() self.main:draw() end)
  self:draw_hop_layer()
  self.effects:draw()
  if self.frozen then self:draw_frost_overlay() end
  if self.fire_active then self:draw_fire_overlay() end
  if (self.stuck_count > 0 or input.launch.down)
  and not (self.run_mods and self.run_mods.signature == 'flippers') then self:draw_aim_line() end
  if self.run_mods and self.run_mods.signature == 'terrorist' then self:draw_terror_prompt() end
  self.ui:draw()
  self:draw_hud()
  self:draw_buff_strip()

  if self.upgrade_pending then self:draw_upgrade() end
  if self.game_over then self:draw_game_over() end
  if self.title_open then
    if self.tutorial_open then self:draw_tutorial() else self:draw_title() end
  end
  if self.settings_open then self:draw_settings() end
  -- Last of all: the transition shutters close over whatever is on screen,
  -- including live play (that is what a restart parts them onto).
  self:draw_page_gate()
end


-- Cannon loadout: hopping balls are AIRBORNE — draw them (plus their ground
-- shadow) in a pass AFTER the whole main group, so they layer OVER the bricks
-- they fly across instead of being covered by swarm cells drawn later in
-- group insertion order. BallHero:draw skips its normal body draw while
-- hopping; BallHero:draw_hop is the deferred draw.
function BallPit:draw_hop_layer()
  if not self.heroes then return end
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and h.hopping and h.draw_hop then h:draw_hop() end
  end
end


function BallPit:draw_aim_line()
  -- Every paddle traces its real predicted path now; how FAR it sees comes
  -- from its balance master file: aim.path_base px at level 1, growing by
  -- aim.path_per_level px per level gained. The Terrorist's file carries its
  -- original full 1300px sight with no growth, so it plays untouched.
  local budget = BAL('aim.path_base', 110)
               + BAL('aim.path_per_level', 10)*((self.level or 1) - 1)
  if budget <= 0 then return end
  self:draw_aim_trajectory(budget)
end


-- Nearest ray hit along (dx,dy) from (x,y) against every live block's AABB,
-- inflated by the ball radius r (slab test). Returns the hit distance and
-- the axis of the face crossed ('x' or 'y'), or nil when nothing is hit.
-- Used by draw_aim_trajectory so the preview bounces off blocks like the
-- real ball, not just the walls.
local function nearest_block_hit(arena, x, y, dx, dy, r)
  local best_t, best_axis = math.huge, nil
  for _, o in ipairs(arena.main.objects) do
    if not o.dead and o:is(Brick) then
      local hw, hh = (o.w or 12)/2 + r, (o.h or 12)/2 + r
      local tmin, tmax, axis = -math.huge, math.huge, nil
      local ok = true
      if math.abs(dx) < 1e-9 then
        if x < o.x - hw or x > o.x + hw then ok = false end
      else
        local t1, t2 = (o.x - hw - x)/dx, (o.x + hw - x)/dx
        if t1 > t2 then t1, t2 = t2, t1 end
        if t1 > tmin then tmin, axis = t1, 'x' end
        if t2 < tmax then tmax = t2 end
      end
      if ok then
        if math.abs(dy) < 1e-9 then
          if y < o.y - hh or y > o.y + hh then ok = false end
        else
          local t1, t2 = (o.y - hh - y)/dy, (o.y + hh - y)/dy
          if t1 > t2 then t1, t2 = t2, t1 end
          if t1 > tmin then tmin, axis = t1, 'y' end
          if t2 < tmax then tmax = t2 end
        end
      end
      if ok and tmax >= tmin and tmin > 1e-3 and tmin < best_t then
        best_t, best_axis = tmin, axis
      end
    end
  end
  return best_t, best_axis
end


-- Trace the launch ray, reflecting it off the three solid walls AND every
-- live block (both inset/inflated by the ball radius), drawing a dashed
-- segment per leg with a dot at each bounce — pale for walls, yellow for
-- blocks — until it descends back to the paddle's launch height, runs out of
-- bounces, or spends the `max_total` length budget (the paddle's aim sight,
-- see draw_aim_line). The trace stops AT the launch line so it never draws
-- behind/below the paddle (where the ball would just be caught).
function BallPit:draw_aim_trajectory(max_total)
  local px = self.paddle.x
  local py = self.paddle.y - self.paddle.h/2 - 4
  -- Use a live ball's radius for the wall inset so the preview matches reality.
  local r = 6
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and h.r_size then r = h.r_size; break end
  end
  local lx, rx = self.x1 + r, self.x2 - r
  local ty     = self.y1 + r
  local by     = py                      -- stop once it returns to the paddle line

  local dx, dy = math.cos(self.aim_angle), math.sin(self.aim_angle)
  local x, y   = px, py
  local total, MAX_TOTAL = 0, max_total or 1300
  -- Blocks consume bounce slots too now, so the cap is a bit roomier than
  -- the old walls-only 5; the length budget is the real limiter.
  local MAX_BOUNCES = 8

  for _ = 0, MAX_BOUNCES do
    -- Nearest positive intersection with each boundary along (dx, dy).
    local t_best, side = math.huge, nil
    if dx > 1e-6      then local t = (rx - x)/dx; if t > 1e-4 and t < t_best then t_best, side = t, 'x' end
    elseif dx < -1e-6 then local t = (lx - x)/dx; if t > 1e-4 and t < t_best then t_best, side = t, 'x' end end
    if dy < -1e-6     then local t = (ty - y)/dy; if t > 1e-4 and t < t_best then t_best, side = t, 'y' end end
    if dy > 1e-6      then local t = (by - y)/dy; if t > 1e-4 and t < t_best then t_best, side = t, 'bottom' end end
    -- Blocks: the ball reflects off bricks in flight, so the preview must too.
    local bt, baxis = nearest_block_hit(self, x, y, dx, dy, r)
    if baxis and bt < t_best then
      t_best, side = bt, (baxis == 'x') and 'brick_x' or 'brick_y'
    end
    if not side then break end

    local seg, clipped = t_best, false
    if total + seg > MAX_TOTAL then seg = MAX_TOTAL - total; clipped = true end
    local nx, ny = x + dx*seg, y + dy*seg
    graphics.dashed_line(x, y, nx, ny, 3, 3, fg[0], 1)
    x, y, total = nx, ny, total + seg

    if clipped then break end
    if side == 'bottom' then graphics.circle(x, y, 2.5, red[0]); break end
    -- Bounce: mark it + reflect the direction. Block bounces get a yellow
    -- dot so the player can tell "off a brick" from "off a wall" at a glance.
    if side == 'brick_x' or side == 'brick_y' then
      graphics.circle(x, y, 2.5, Color(yellow[0].r, yellow[0].g, yellow[0].b, 0.9))
    else
      graphics.circle(x, y, 2.5, Color(fg[0].r, fg[0].g, fg[0].b, 0.85))
    end
    if side == 'x' or side == 'brick_x' then dx = -dx else dy = -dy end
  end
  graphics.circle(px, py, 2, fg[0])
end


-- Terrorist: a pulsing detonator symbol prompt over the paddle whenever at
-- least one ball is armed (near a block), so the detonate beat reads clearly.
-- The symbol is a circular button with an "E" inside radiating explosion lines.
-- Moved down slightly from the paddle so it doesn't overlap with other UI.
function BallPit:draw_terror_prompt()
  local n = 0
  for _, h in ipairs(self.heroes) do if h and not h.dead and h.terror_armed then n = n + 1 end end
  if n == 0 then return end
  local a = 0.6 + 0.4*math.sin(love.timer.getTime()*8)
  local col = Color(1, 0.4, 0.2, a)

  -- Draw the detonator symbol: circle with E and radiating explosion lines
  -- Positioned slightly left of center for better visual balance
  local cx, cy = self.paddle.x - 10, self.paddle.y + 16
  local r = 7

  -- Outer circle (button)
  graphics.circle(cx, cy, r, col, 1.5)

  -- Letter E in the center
  graphics.print('E', pixul_font, cx - 3, cy - 4, 0, 0.85, 0.85, 0, 0, col)

  -- Radiating explosion lines (4 diagonal spikes)
  for i = 0, 3 do
    local angle = math.pi/4 + i*math.pi/2
    local x1 = cx + math.cos(angle) * (r + 1)
    local y1 = cy + math.sin(angle) * (r + 1)
    local x2 = cx + math.cos(angle) * (r + 4)
    local y2 = cy + math.sin(angle) * (r + 4)
    graphics.line(x1, y1, x2, y2, col, 1.5)
  end

  -- Count display
  graphics.print_centered('x' .. n, pixul_font, self.paddle.x + 10, self.paddle.y + 16, 0, 1, 1, 0, 0, col)
end


-- ===== Vampire loadout: blood bar + lifesteal droplets =====

-- The blood bar's screen rect: left x, centre y, width, height. Longer than the
-- old 64px stub so the 0-100 pool reads with real precision. Shared by the draw,
-- the droplet target and the XP-bar offset so they always line up.
function BallPit:blood_bar_rect()
  return self.x1 + 6, self.y1 - 8, 104, 7
end


-- Where lifesteal droplets fly to: the live surface of the blood (the fill
-- front), so they look like they top the pool up where it meets air.
function BallPit:blood_bar_target()
  local x, yc, w = self:blood_bar_rect()
  local pct = math.clamp((self.hp_display or self.player_hp)/self.player_hp_max, 0, 1)
  return x + w*pct, yc
end


-- Lifesteal: a kill sprays a few blood droplets from the kill point. They
-- scatter, then home to the blood bar and top it up on arrival (update_vampire
-- -> vampire_absorb).
function BallPit:vampire_spawn_blood(x, y, amount)
  self.blood_droplets = self.blood_droplets or {}
  local n = 3
  for _ = 1, n do
    table.insert(self.blood_droplets, {
      x = x + random:float(-4, 4), y = y + random:float(-4, 4),
      vx = random:float(-70, 70), vy = random:float(-100, -30),
      amount = amount/n, scatter = random:float(0.10, 0.22),
      r = random:float(1.6, 2.8), tint = random:float(0.8, 1.0), t = 0,
    })
  end
end


-- Per-frame: smooth the displayed fill toward the real HP, decay the heal
-- flash, and fly the droplets to the bar. Driven from the drain block so it
-- shares the menu / upgrade-picker auto-pause.
function BallPit:update_vampire(dt)
  self.hp_display = self.hp_display or self.player_hp
  self.hp_display = self.hp_display + (self.player_hp - self.hp_display)*math.min(1, 12*dt)
  self.hp_flash   = math.max(0, (self.hp_flash or 0) - dt*2.5)
  local list = self.blood_droplets
  if not (list and #list > 0) then return end
  local tx, ty = self:blood_bar_target()
  for i = #list, 1, -1 do
    local d = list[i]
    d.t = d.t + dt
    if d.t < d.scatter then
      d.vy = d.vy + 320*dt
      d.x, d.y = d.x + d.vx*dt, d.y + d.vy*dt
    else
      local dx, dy = tx - d.x, ty - d.y
      local dist = math.sqrt(dx*dx + dy*dy)
      if dist < 5 then
        self:vampire_absorb(d.amount)
        table.remove(list, i)
      else
        local sp = math.min(560, 170 + dist*5)
        d.x, d.y = d.x + (dx/dist)*sp*dt, d.y + (dy/dist)*sp*dt
      end
    end
  end
end


-- A droplet reaches the bar: top up the pool and kick the heal flash.
function BallPit:vampire_absorb(amount)
  self.player_hp = math.min(self.player_hp_max, self.player_hp + amount)
  self.hp_flash  = 1
end


-- The fancy blood bar: a dark vial holding a sloshing red pool with a wavy
-- meniscus, rising bubbles, a glass specular streak, a low-HP danger pulse and a
-- heal-flash glow. Draws the in-flight lifesteal droplets on top.
function BallPit:draw_blood_bar()
  local x, yc, w, h = self:blood_bar_rect()
  local t  = love.timer.getTime()
  local cx = x + w/2
  graphics.rectangle(cx, yc, w + 4, h + 4, (h + 4)/2, (h + 4)/2, Color(0.12, 0.02, 0.03, 1))  -- casing
  graphics.rectangle(cx, yc, w, h, h/2, h/2, bg[-2])                                           -- empty vial
  local pct = math.clamp((self.hp_display or self.player_hp)/self.player_hp_max, 0, 1)
  if pct > 0 then
    local fw  = math.max(h, w*pct)
    local fcx = x + fw/2
    local low = (pct < 0.25) and (0.55 + 0.45*math.sin(t*11)) or 1
    local base = Color(0.5*low, 0.02, 0.05, 1)
    local lite = Color(math.min(1, 0.85*low), 0.12, 0.14, 1)
    graphics.rectangle(fcx, yc, fw, h, h/2, h/2, base)
    graphics.rectangle(fcx, yc - h*0.16, fw, h*0.42, h*0.2, h*0.2, lite)   -- upper volume band
    for i = 1, 3 do                                                        -- rising bubbles
      local bx = x + (i/4)*fw
      local by = yc + h*0.3 - ((t*8 + i*3) % (h*1.2))
      graphics.circle(bx, by, 0.8, Color(1, 0.5, 0.5, 0.4))
    end
    local front = x + fw                                                   -- wavy meniscus
    for i = -1, 1 do
      graphics.circle(front + math.sin(t*6 + i*1.7)*1.1, yc + i*(h*0.24), h*0.34, lite)
    end
    local fl = self.hp_flash or 0                                          -- heal flash + splash ring
    if fl > 0 then
      graphics.rectangle(fcx, yc, fw + 3, h + 3, (h + 3)/2, (h + 3)/2, Color(1, 0.55, 0.55, 0.5*fl), 1)
      graphics.circle(front, yc, h*(0.6 + (1 - fl)*1.4), Color(1, 0.6, 0.6, 0.5*fl), 1)
    end
  end
  graphics.rectangle(cx, yc - h*0.3, w*0.96, 1, nil, nil, Color(1, 1, 1, 0.16))                -- glass streak
  graphics.polygon({x - 1, yc - 2.5, x + 2, yc - 2.5, x + 0.5, yc + 2}, Color(1, 1, 1, 0.85))  -- fang/drop marker

  if self.blood_droplets then                                              -- in-flight lifesteal droplets
    for _, d in ipairs(self.blood_droplets) do
      graphics.circle(d.x, d.y + 0.6, d.r, Color(0.2, 0, 0, 0.35))
      graphics.circle(d.x, d.y, d.r, Color(0.7*d.tint, 0.04, 0.06, 1))
      graphics.circle(d.x - d.r*0.3, d.y - d.r*0.3, math.max(0.5, d.r*0.4), Color(1, 0.6, 0.6, 0.8))
    end
  end
end


-- ----- Wave progress bar ----------------------------------------------------
--
-- The strip between the HP readout and the combo meter. It began life as an XP
-- bar and still fills with XP on the orb loadouts -- but for every other paddle
-- the next draft is bought by CLEARING THE WAVE (see advance_wave), so what it
-- actually reports is "how far through this wave am I". It is drawn as that:
--
--   WAVE 3  [####|####|##  |    |    |    |    ]  >>
--
-- Three things do the talking, and none of them are things an XP tube does:
--   * a LABEL naming what is being counted (and changing when that changes --
--     BOSS on wave 10, CLEAR while wave 9 drains, LV on the orb loadouts, which
--     really are still filling with XP and should not pretend otherwise),
--   * NOTCHES cutting the track into chunks, so it answers "how much of this
--     wave is behind me" instead of "how full is a bar", and each chunk lands
--     as a visible tick when the fill crosses it,
--   * an END MARKER for what finishing it gets you -- chevrons for the next
--     wave, a boss diamond when the boss is what is waiting (wave 9's drain and
--     the boss fight itself).
local WAVE_BAR_H     = 7    -- track height, matching the Vampire vial's
local WAVE_BAR_SEGS  = 10   -- notches on a timed wave
local WAVE_BOSS_SEGS = 3    -- ...one per boss phase on the boss wave
local WAVE_LABEL_GAP = 7    -- px between the label and the track
local WAVE_END_W     = 15   -- reserved at the right for the end-of-wave marker


-- What the bar is measuring, as a fraction, plus the mode driving it and how
-- many notches the track should be cut into. Modes:
--   'xp'   orb loadouts (Terrorist): the level is still bought with orbs, so
--          the bar stays an XP bar and its label says so.
--   'boss' wave 10: the wave ends on the boss's DEATH, not on a clock (its
--          duration is a placeholder 999), so the honest measure of progress is
--          the boss's missing HP -- cut into its three phases.
--   'time' every other wave: the wave clock, which is what pays the draft.
-- Pure read of state, so the tick and the draw can both call it freely.
function BallPit:wave_progress()
  if self:uses_xp_orbs() then
    return math.clamp(self.xp/self.xp_to_next, 0, 1), 'xp', WAVE_BAR_SEGS
  end
  if self.wave_cfg and self.wave_cfg.boss then
    local b = self.boss
    if b and not b.dead and (b.max_hp or 0) > 0 then
      return math.clamp(1 - b.hp/b.max_hp, 0, 1), 'boss', WAVE_BOSS_SEGS
    end
    return (self.boss_defeated and 1 or 0), 'boss', WAVE_BOSS_SEGS
  end
  -- Wave 9 holds past its timer while the arena drains before the boss; the
  -- clamp parks the bar full there, which is exactly what is happening.
  return math.clamp(self.wave_time/((self.wave_cfg and self.wave_cfg.duration) or 1), 0, 1),
         'time', WAVE_BAR_SEGS
end


-- Per-frame animation state for the wave track. Kept out of the draw (same
-- contract as tick_combo) so the bar animates identically however often draw
-- runs, and so the notch ticks fire exactly once each.
function BallPit:tick_wave_bar(dt)
  local w = self.wave_bar
  if not w then
    w = {disp = 0, vel = 0, flash = 0, pop = 0, seg = 0, seg_pop = 0, wave = self.wave}
    self.wave_bar = w
  end
  local pct, _, segs = self:wave_progress()

  -- A new wave (or, on the orb loadouts, a fresh level) empties the track. Snap
  -- rather than let the chase run backwards: the track restarting from nothing
  -- is the clearest "that one is behind you" this HUD has.
  if self.wave ~= w.wave or pct < w.disp - 0.25 then
    w.wave, w.disp, w.seg = self.wave, 0, 0
    w.flash, w.pop = 1, 1
  end

  local prev = w.disp
  w.disp = w.disp + (pct - w.disp)*math.min(1, 9*dt)
  -- Fill velocity, normalised and decayed: drives the leading-edge glow, so a
  -- burst of boss damage lights the front up while the slow wave clock does not.
  local rate = (w.disp - prev)/math.max(dt, 0.0001)
  w.vel = math.clamp(math.max(w.vel - dt*2.2, math.min(1, rate*4)), 0, 1)

  -- Notch crossings pop, so every completed chunk of the wave lands as an event
  -- instead of sliding by.
  local seg = math.floor(w.disp*segs)
  if seg > w.seg then w.seg, w.seg_pop = seg, 1 end

  w.flash   = math.max(0, w.flash   - dt*2.2)
  w.pop     = math.max(0, w.pop     - dt*2.5)
  w.seg_pop = math.max(0, w.seg_pop - dt*3.0)
end


-- Paints the wave track. `x0` is where the strip may start (past whatever width
-- the HP readout took) and `x1` where it must stop (the combo meter's reserve).
-- Reads ONLY state pre-computed by tick_wave_bar, so it stays a pure painter.
function BallPit:draw_wave_bar(x0, x1)
  local w = self.wave_bar
  if not w then return end
  local _, mode, segs = self:wave_progress()
  local t  = love.timer.getTime()
  local cy = self.y1 - 8
  local h  = WAVE_BAR_H

  -- ---- label ----
  -- Names what the track is counting, and changes with the state so it is never
  -- just a second copy of the "Wave N" readout on the bottom row.
  local label, lcol = 'WAVE ' .. self.wave, fg_alt[0]
  if mode == 'xp' then
    label, lcol = 'LV ' .. self.level, blue[0]
  elseif mode == 'boss' then
    label, lcol = 'BOSS', red[0]
  elseif self.awaiting_boss then
    label, lcol = 'CLEAR', yellow[0]
  end
  local lw = pixul_font:get_text_width(label)
  local ls = 1 + 0.22*w.pop
  -- print_centered scales about the centre, so the centre comes off the LIVE
  -- scale: a wave-change pop then grows rightward from a pinned left edge
  -- instead of swelling back over the hearts.
  graphics.print_centered(label, pixul_font, x0 + lw*ls/2, cy, 0, ls, ls, 0, 0, lcol)

  -- ---- track ----
  -- Width is measured off the UNSCALED label so a popping label cannot shove
  -- the track sideways.
  local tx0 = x0 + lw + WAVE_LABEL_GAP
  local tw  = (x1 - WAVE_END_W) - tx0
  if tw < 24 then return end
  local cx  = tx0 + tw/2
  graphics.rectangle(cx, cy, tw + 4, h + 4, (h + 4)/2, (h + 4)/2, Color(0, 0, 0, 0.45))  -- casing
  graphics.rectangle(cx, cy, tw, h, h/2, h/2, bg[-2])                                    -- empty track

  -- ---- fill ----
  local base
  if mode == 'xp' then
    base = blue[0]
  elseif mode == 'boss' then
    -- The live boss tint, so the track shifts red -> orange -> purple with the
    -- phase it is counting down.
    base = (self.boss and self.boss.color) or red[0]
  else
    base = yellow2[0]
  end
  local fw = tw*w.disp
  if fw > 0.5 then
    fw = math.max(h*0.6, fw)                                       -- keep the cap round
    graphics.rectangle(tx0 + fw/2, cy, fw, h, h/2, h/2, base)
    graphics.rectangle(tx0 + fw/2, cy - h*0.22, fw, h*0.34, 1, 1,  -- glassy upper band
                       Color(math.min(1, base.r + 0.3), math.min(1, base.g + 0.3),
                             math.min(1, base.b + 0.3), 0.5))

    -- Marching chevrons: the wave is always travelling toward its end. Clipped
    -- by only drawing the ones that sit fully inside the fill.
    local period = 10
    local sx = tx0 - period + ((t*22) % period)
    while sx < tx0 + fw do
      if sx - 2 > tx0 and sx + 3 < tx0 + fw then
        graphics.polyline(Color(1, 1, 1, 0.15), 1,
                          sx - 2, cy - h/2 + 1, sx + 2, cy, sx - 2, cy + h/2 - 1)
      end
      sx = sx + period
    end

    -- Leading edge: a bright cap, glowing harder the faster the track is moving.
    graphics.rectangle(tx0 + fw - 1, cy, 2, h, 1, 1, Color(1, 1, 1, 0.35 + 0.5*w.vel))
    graphics.circle(tx0 + fw, cy, 1.4 + 2.2*w.vel,
                    Color(base.r, base.g, base.b, 0.3 + 0.4*w.vel))
  end

  -- ---- notches ----
  -- Cut across the whole track, over the fill, so the bar reads as N chunks of
  -- wave rather than one continuous tube. The notch the fill has just passed
  -- flashes -- the per-chunk tick a smooth bar could never give.
  for i = 1, segs - 1 do
    local nx = tx0 + tw*i/segs
    graphics.line(nx, cy - h/2 + 1, nx, cy + h/2 - 1, Color(0, 0, 0, 0.6), 1)
    if i == w.seg and w.seg_pop > 0.01 then
      graphics.line(nx, cy - h/2 - 2, nx, cy + h/2 + 2, Color(1, 1, 1, w.seg_pop), 1)
    end
  end
  graphics.rectangle(cx, cy, tw, h, h/2, h/2,                      -- rim, drawn over the cuts
                     Color(fg_alt[0].r, fg_alt[0].g, fg_alt[0].b, 0.22), 1)

  -- ---- end-of-wave marker ----
  -- What finishing the track gets you, parked past its right end and brightening
  -- as the fill closes on it.
  local mx   = tx0 + tw + 7
  local near = math.clamp((w.disp - 0.55)/0.45, 0, 1)
  if mode == 'boss' or (mode ~= 'xp' and self.wave == 9) then
    local p = 0.55 + 0.45*math.sin(t*5)
    local a = 0.35 + 0.65*p*(0.35 + 0.65*near)
    graphics.polygon({mx, cy - 5, mx + 4, cy, mx, cy + 5, mx - 4, cy},
                     Color(red[0].r, red[0].g, red[0].b, a))
    graphics.circle(mx, cy, 1.2, Color(1, 1, 1, a))
  else
    local a = 0.25 + 0.6*near
    for i = 0, 1 do
      local ox = mx - 3 + i*4
      graphics.polyline(Color(fg_alt[0].r, fg_alt[0].g, fg_alt[0].b, a), 1,
                        ox - 2, cy - 3.5, ox + 1.5, cy, ox - 2, cy + 3.5)
    end
  end

  -- ---- wave-change flash ----
  if w.flash > 0.01 then
    graphics.rectangle(cx, cy, tw + 4, h + 4, (h + 4)/2, (h + 4)/2,
                       Color(1, 1, 1, 0.45*w.flash))
  end
end


function BallPit:draw_hud()
  -- Playfield frame, open at the TOP. Drawn as one polyline down the left
  -- side, across the bottom and back up the right, so the three solid edges
  -- read as a channel the balls live in while the top stays uncapped -- the
  -- combo meter and the HP/XP strip sit on that top edge, and a line through
  -- them boxed the whole screen in.
  graphics.polyline(fg_transparent_weak, 1,
                    {self.x1, self.y1, self.x1, self.y2,
                     self.x2, self.y2, self.x2, self.y1})

  -- Red dotted "defense line" at the top of the paddle's dodge band. Any enemy
  -- that crosses it costs the player HP (see breach_line_y consumers), so it
  -- doubles as a readable danger boundary and keeps the swarm action off the
  -- very bottom of the screen. A gentle pulse marks it as a live threat line.
  local line_y = self:breach_line_y()
  local pulse  = 0.35 + 0.15*math.sin(love.timer.getTime()*4)
  graphics.dashed_line(self.x1 + 1, line_y, self.x2 - 1, line_y, 5, 4,
                       Color(red[0].r, red[0].g, red[0].b, pulse), 1)

  -- HP readout: hearts normally; the Vampire loadout renders its draining
  -- 0-100 bar instead.
  local hp_bar_mode = self.run_mods and self.run_mods.hp_mode == 'bar'
  if hp_bar_mode then
    self:draw_blood_bar()
  else
    -- Each paddle draws its own themed life glyphs — see HEART_STYLES /
    -- draw_themed_hearts (and the Aegis steel halves) in paddles.lua.
    self:draw_themed_hearts()
  end

  -- Wave progress track. Starts past however wide the HP readout is (Aegis runs
  -- 7 hearts, the Vampire blood bar is longer still) and stops COMBO_STRIP_W
  -- short of the right edge to reserve the combo meter block (label + bar +
  -- chips). See draw_wave_bar for what it measures and why it is a wave track
  -- rather than the XP tube it used to be.
  local hb_x, _, hb_w = self:blood_bar_rect()
  local bx = hp_bar_mode and (hb_x + hb_w + 14) or (self.x1 + 20 + self.player_hp_max*10)
  self:draw_wave_bar(bx, self.x2 - COMBO_STRIP_W)

  self:draw_combo_meter()

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
  -- Meta currency: every block kill banks one into the persistent wallet
  -- (spent in the post-death paddle shop; saved to disk in trigger_game_over).
  self.run_kills = (self.run_kills or 0) + 1
  if state then state.wallet = (state.wallet or 0) + 1 end

  local mods = self.run_mods
  if mods then
    -- Vampire lifesteal: kills spray blood droplets that fly from the kill to
    -- the blood bar and top it up on arrival (see vampire_spawn_blood) — the
    -- refill is shown travelling in, not just ticking up.
    if mods.hp_mode == 'bar' then
      self:vampire_spawn_blood(brick.x, brick.y, mods.sig.heal_per_kill or 3)
    end
    -- Mitosis: each kill splits off a short-lived clone ball.
    if mods.signature == 'mitosis' then self:mitosis_on_kill() end
  end
end


-- ----- Combo meter -----

-- Rank for an arbitrary point total. Walks the ladder from the top so the
-- highest threshold crossed wins. Used for BOTH the live rank (real points,
-- drives the payouts) and the DRAWN rank (smoothed points, drives the juice).
local function combo_index_for(points)
  local idx = 1
  for i = #COMBO_RANKS, 1, -1 do
    if points >= combo_rank_threshold(i) then
      idx = i
      break
    end
  end
  return idx
end


function BallPit:combo_rank_index()
  return combo_index_for((self.combo and self.combo.points) or 0)
end


-- What a rank pays out. Damage is deliberately NOT on this list any more: the
-- meter buys TEMPO (every ball moves faster) and PROGRESSION (every XP pickup
-- is worth more), so a hot run feels quicker and levels harder instead of just
-- printing bigger numbers. Both are cached once per frame by tick_combo --
-- BallHero:normalize_speed reads the speed one every frame for every ball, so
-- these have to stay O(1).
function BallPit:combo_speed_mult()
  return (self.combo and self.combo.speed_m) or 1
end


-- Per-ball bounce damage scaling. Capped so a single perfectly-chained ball
-- can't trivialise a wave on its own. This is the ONLY damage channel the
-- combo system still owns -- it is per-ball chain length, not meter rank.
function BallPit:bounce_dmg_mult(bounces)
  local n = math.min(bounces or 0, BAL('combo.bounce_cap', COMBO_BOUNCE_CAP))
  return 1 + n*BAL('combo.bounce_dmg_step', COMBO_BOUNCE_DMG_STEP)
end


-- Called from Brick:on_ball_contact after damage is applied. Awards points
-- with a small variety + streak bonus. Points are read off the combo meter
-- HUD -- there's deliberately no per-bounce floating "+N".
--
-- Note it does NOT fire the rank-up feedback: tick_combo does that when the
-- DRAWN bar reaches the threshold, so the break-through lands on the frame the
-- player actually sees the meter fill rather than a beat ahead of it.
function BallPit:on_brick_bounce(ball, brick)
  local c = self.combo
  if not c then return end
  c.idle_t = 0

  c.streak = (c.streak or 0) + 1
  local streak_bonus  = math.min(c.streak, BAL('combo.streak_bonus_cap', COMBO_STREAK_BONUS_CAP))
  local variety_bonus = 0
  if brick.variant_name and c.last_variant and brick.variant_name ~= c.last_variant then
    variety_bonus = BAL('combo.variety_bonus', COMBO_VARIETY_BONUS)
  end
  c.last_variant  = brick.variant_name or c.last_variant
  c.bounces_total = c.bounces_total + 1
  -- The loadout's Combo stat scales gain AND bleed (see on_ball_missed /
  -- tick_combo) — high-combo paddles run a hotter, riskier meter.
  local cm = (self.run_mods and self.run_mods.combo) or 1
  c.points = c.points + (BAL('combo.base_points', COMBO_BASE_POINTS) + streak_bonus + variety_bonus)*cm
end


-- Flat combo award from non-bounce sources (the Aegis bullet-parry refund).
-- Skips the streak/variety bookkeeping; the loadout Combo stat still scales it.
function BallPit:add_combo_points(pts)
  local c = self.combo
  if not c or not pts or pts <= 0 then return end
  c.idle_t = 0
  local cm = (self.run_mods and self.run_mods.combo) or 1
  c.points = c.points + pts*cm
end


-- Called from BallHero:start_return — a ball just fell into the pit. Wipes the
-- streak and subtracts a proportional penalty (a drop costs the same FRACTION
-- of the bar at every rank, floored so early drops still register). The
-- demotion pulse comes from tick_combo when the drawn bar falls back through.
function BallPit:on_ball_missed(ball)
  local c = self.combo
  if not c or c.points <= 0 then return end
  local cm = (self.run_mods and self.run_mods.combo) or 1
  local penalty  = math.max(BAL('combo.miss_min', COMBO_MISS_MIN),
                            BAL('combo.miss_frac', COMBO_MISS_FRAC)*c.points*cm)
  c.points       = math.max(0, c.points - penalty)
  c.streak       = 0
  c.last_variant = nil
end


-- Rank advancement feedback. Fired by tick_combo off the DRAWN bar, so it is
-- exactly in step with the fill reaching the end of its track: the bar flashes
-- white, the letter springs, a hoop expands off it and sparks shear along the
-- meter, over a level-up SFX pitched up per rank. Still deliberately
-- HUD-local -- no screen flash, no giant floating rank letter.
function BallPit:on_combo_rank_up(new_idx)
  local c = self.combo
  if c then
    c.flash    = 1
    c.punch    = 1
    c.shock    = 1
    c.chip_pop = 1
    self:combo_burst(new_idx)
  end
  if level_up1 then
    level_up1:play{volume = 0.35, pitch = 0.85 + new_idx*0.06}
  end
  if new_idx >= COMBO_HOT_RANK then camera:shake(2 + new_idx*0.4, 0.2, 80) end
end


-- The drawn bar fell back through a threshold. Deliberately quieter than the
-- promotion: a red pulse across the meter and a small shake, no sound.
function BallPit:on_combo_rank_down(new_idx)
  local c = self.combo
  if c then
    c.demote = 1
    c.punch  = 0.55
  end
  camera:shake(2, 0.15, 80)
end


-- Meter geometry, shared by tick_combo_fx and draw_combo_meter so particles
-- spawn exactly on the bar. draw_hud reserves this strip by ending the XP bar
-- at x2 - COMBO_STRIP_W.
-- Returns: rank-label RIGHT edge x, bar centre y, bar left x, bar width, bar
-- height, rank-label ink TOP y. The label is right-aligned on the wall and
-- hangs under the bar, so it anchors by its right edge, not by its centre.
function BallPit:combo_meter_rect()
  local bx1 = self.x2 - 3 - COMBO_RIGHT_PAD
  local bw  = 60
  local bx0 = bx1 - bw
  local cy  = self.y1 + 2
  return self.x2 - COMBO_RIGHT_PAD, cy, bx0, bw, 6, cy + COMBO_LABEL_TOP
end


-- Debug hook (admin terminal `combo <tier>`): jam the meter to a named or
-- numbered rank. Only the point total is set -- tick_combo derives the rank,
-- the payouts and every bit of presentation from it on the next frame, so
-- this cannot desync the meter from the multipliers it is advertising.
-- Returns the index and label it landed on, or nil for an unknown tier.
function BallPit:set_combo_rank(which)
  local idx = tonumber(which)
  if not idx then
    local want = string.upper(tostring(which))
    for i, r in ipairs(COMBO_RANKS) do
      if r.label == want then idx = i break end
    end
  end
  idx = idx and math.floor(idx)
  if not idx or not COMBO_RANKS[idx] then return nil end
  if not self.combo then return nil end
  self.combo.points = combo_rank_threshold(idx)
  self.combo.idle_t = 0
  return idx, COMBO_RANKS[idx].label
end


-- HUD-local particle push. These are a plain list on self.combo drawn inside
-- draw_combo_meter, NOT effects-group entities: the meter lives in canvas
-- space and must not inherit the arena camera's shake/offset.
function BallPit:combo_add_fx(x, y, vx, vy, life, r, col)
  local fx = self.combo and self.combo.fx
  if not fx or #fx >= COMBO_FX_MAX then return end
  fx[#fx + 1] = {x = x, y = y, vx = vx, vy = vy, t = 0, life = life, r = r, c = col}
end


-- Sparks thrown along the whole bar when a tier breaks.
function BallPit:combo_burst(idx)
  local c = self.combo
  if not c then return end
  local _, cy, bx0, bw = self:combo_meter_rect()
  local col = _G[COMBO_RANKS[idx].color_key][0]
  for i = 1, 14 do
    local a  = random:float(-math.pi, 0)          -- upward fan
    local sp = random:float(20, 70)
    self:combo_add_fx(bx0 + random:float(0, bw), cy + random:float(-2, 2),
                      math.cos(a)*sp, math.sin(a)*sp,
                      random:float(0.25, 0.5), random:float(0.5, 1.2),
                      (i % 3 == 0) and Color(1, 1, 1, 1) or col)
  end
end


-- Advance + retire meter particles, and emit the two ambient streams: embers
-- lifting off a hot (S+) bar, and cinders shearing off the leading edge while
-- the bar bleeds down. Both are what makes the constant decay legible without
-- having to read the number.
function BallPit:tick_combo_fx(dt)
  local c  = self.combo
  local fx = c.fx
  for i = #fx, 1, -1 do
    local p = fx[i]
    p.t  = p.t + dt
    p.x  = p.x + p.vx*dt
    p.y  = p.y + p.vy*dt
    p.vy = p.vy + 40*dt
    if p.t >= p.life then table.remove(fx, i) end
  end

  local _, cy, bx0, bw = self:combo_meter_rect()
  local front = bx0 + bw*c.pct
  local col   = _G[COMBO_RANKS[c.display_idx].color_key][0]

  -- Hot streak: the higher the tier, the more embers lift off the fill.
  if c.heat > 0.01 then
    c.ember_t = c.ember_t + dt*(4 + 26*c.heat)
    while c.ember_t >= 1 do
      c.ember_t = c.ember_t - 1
      self:combo_add_fx(bx0 + random:float(0, math.max(2, bw*c.pct)), cy + random:float(-2, 2),
                        random:float(-6, 6), random:float(-26, -12),
                        random:float(0.3, 0.6), random:float(0.4, 0.9), col)
    end
  end

  -- Bleeding: cinders shear backwards off the receding front and fall away.
  if c.drain > 0.4 and c.pct > 0.01 then
    c.ember_t = c.ember_t + dt*14*c.drain
    while c.ember_t >= 1 do
      c.ember_t = c.ember_t - 1
      self:combo_add_fx(front, cy + random:float(-2, 2),
                        random:float(-14, -4), random:float(4, 16),
                        random:float(0.2, 0.4), random:float(0.4, 0.8),
                        Color(col.r, col.g, col.b, 1))
    end
  end
end


-- Per-frame combo bookkeeping: the constant idle bleed, the cached rank
-- payouts, the smoothed bar, and every scrap of meter animation state. Called
-- from BallPit:update below the overlay early-returns, so the meter freezes
-- with the game in menus / the upgrade picker.
function BallPit:tick_combo(dt)
  local c = self.combo
  if not c then return end

  -- ---- points: PROPORTIONAL bleed ----
  -- The idle rate is a fraction of what you are currently holding, floored so
  -- the tail still lands on zero. A FRENZY bar bleeds 60/sec, a C bar 10/sec,
  -- so the meter costs attention in proportion to what it is paying out.
  --
  -- Seconds of silence (past the grace) to fall one whole tier:
  --      FRENZY  7.8   SSS  9.6   SS 10.1   S 12.8
  --      A      14.6   B   10.0   C   5.0
  -- ...against 26.7 / 23.3 / 16.7 / 13.3 / 10.0 / 6.7 / 3.3 under the old flat
  -- rate. Same ladder, but holding the top of it is now the expensive part.
  c.idle_t = c.idle_t + dt
  local bleeding = false
  if c.idle_t > BAL('combo.idle_grace', COMBO_IDLE_GRACE) and c.points > 0 then
    local cm = (self.run_mods and self.run_mods.combo) or 1
    -- cm (the paddle's combo stat) scales the bleed as well as the gain, so a
    -- combo-heavy loadout runs the whole economy hot in both directions.
    local rate = math.max(BAL('combo.idle_decay_min',  COMBO_IDLE_DECAY_MIN),
                          BAL('combo.idle_decay_frac', COMBO_IDLE_DECAY_FRAC)*c.points)
    c.points = math.max(0, c.points - rate*cm*dt)
    bleeding = true
    if c.points <= 0 then
      c.streak       = 0
      c.last_variant = nil
    end
  end

  -- ---- cached payouts, read off the LIVE rank ----
  local idx = combo_index_for(c.points)
  c.speed_m = combo_rank_speed_mult(idx)

  -- ---- the drawn bar chases the real total ----
  -- Rate = a fraction of the remaining gap with a floor under it, so a
  -- 15-point bounce still takes a visible beat to travel and a 400-point drop
  -- still sweeps back down smoothly. This is what turns every award into
  -- continuous left-to-right motion instead of the bar teleporting a block wider.
  local prev_disp = c.display
  local diff = c.points - c.display
  if diff ~= 0 then
    local step = math.max(BAL('combo.bar_min_rate', COMBO_BAR_MIN_RATE),
                          math.abs(diff)*BAL('combo.bar_chase', COMBO_BAR_CHASE))*dt
    if math.abs(diff) <= step then c.display = c.points
    else c.display = c.display + (diff > 0 and step or -step) end
  end
  local rate_now = (c.display - prev_disp)/math.max(dt, 1e-5)

  -- ---- rank crossings, off the DRAWN bar ----
  local prev_idx = c.display_idx or 1
  local disp_idx = combo_index_for(c.display)
  if     disp_idx > prev_idx then self:on_combo_rank_up(disp_idx)
  elseif disp_idx < prev_idx then self:on_combo_rank_down(disp_idx) end
  c.display_idx = disp_idx
  -- Peak for the record stele, taken off the DRAWN bar so what gets carved is
  -- the rank the player actually saw light up.
  self.peak_rank_idx = math.max(self.peak_rank_idx or 1, disp_idx)

  -- ---- fill fraction within the drawn tier, plus the lagging ghost tail ----
  local lo = combo_rank_threshold(disp_idx)
  if disp_idx < #COMBO_RANKS then
    local hi = combo_rank_threshold(disp_idx + 1)
    c.pct = math.clamp((c.display - lo)/math.max(1, hi - lo), 0, 1)
  else
    c.pct = 1
  end
  if disp_idx ~= prev_idx then
    c.ghost_pct = c.pct                    -- tier changed: don't streak across it
  elseif c.pct >= c.ghost_pct then
    c.ghost_pct = c.pct                    -- gaining: the ghost rides the front
  else
    c.ghost_pct = math.max(c.pct, math.lerp_dt(BAL('combo.ghost_lag', COMBO_GHOST_LAG),
                                               dt, c.ghost_pct, c.pct))
  end

  -- ---- animation channels ----
  -- gain_v / drain are the meter's two "live" looks: a hot comet front while
  -- filling, an eroding front + red ghost tail while bleeding.
  local gain_target  = (rate_now > 2) and math.clamp(rate_now/260, 0.25, 1) or 0
  local drain_target = (bleeding or rate_now < -2) and 1 or 0
  c.gain_v = math.lerp_dt(0.0008, dt, c.gain_v, gain_target)
  c.drain  = math.lerp_dt(0.05,   dt, c.drain,  drain_target)
  -- Hot streak ramps 0 below COMBO_HOT_RANK up to 1 at the top of the ladder.
  local hot = math.clamp((idx - COMBO_HOT_RANK + 1)/(#COMBO_RANKS - COMBO_HOT_RANK + 1), 0, 1)
  c.heat = math.lerp_dt(0.2, dt, c.heat, hot)

  c.flash    = math.max(0, c.flash    - dt*4.0)
  c.punch    = math.max(0, c.punch    - dt*3.2)
  c.shock    = math.max(0, c.shock    - dt*2.2)
  c.demote   = math.max(0, c.demote   - dt*3.0)
  c.chip_pop = math.max(0, c.chip_pop - dt*3.0)

  self:tick_combo_fx(dt)
end


-- Compact HUD at the top-right of the canvas, sharing the strip with the HP
-- hearts (left) and XP bar (middle). Rendered by draw_hud.
--
-- Reads ONLY state pre-computed by tick_combo (pct / ghost_pct / heat / gain_v
-- / drain / flash / punch / shock / demote / fx), so it stays a pure painter
-- and the meter animates identically no matter how often draw runs.
--
-- Layout:  [====== fill bar ======]
--          [.. tier ladder chips ..]
--                       [rank label]   <- right-aligned on the arena wall
function BallPit:draw_combo_meter()
  local c = self.combo
  if not c then return end
  local idx  = c.display_idx or 1
  local rank = COMBO_RANKS[idx]
  local base = _G[rank.color_key][0]
  local t    = love.timer.getTime()

  local lrx, cy, bx0, bw, bh, lty = self:combo_meter_rect()
  local cx  = bx0 + bw/2

  -- Bleeding dims the whole meter, so "I'm losing it" reads before you've
  -- parsed the bar length.
  local dim = 1 - 0.28*c.drain
  local col = Color(base.r*dim, base.g*dim, base.b*dim, 1)

  -- ---- hot-streak underglow (S and up) ----
  if c.heat > 0.01 then
    -- Wraps the BAR ONLY. The rank label sits on its own row underneath and is
    -- deliberately outside the glow, so the tier letter stays a clean badge
    -- instead of a word sitting inside a lit box.
    local pulse = 0.5 + 0.5*math.sin(t*7)
    graphics.rectangle(cx, cy, bw + 8, bh + 10, 5, 5,
                       Color(col.r, col.g, col.b, 0.09 + 0.15*c.heat*pulse))
  end

  -- ---- rank label ----
  -- Auto-fit: 'D' and 'FRENZY' have to live in the same COMBO_LABEL_BOX, so the
  -- scale comes off the measured glyph width instead of a hardcoded number.
  local lw  = math.max(1, fat_font:get_text_width(rank.label))
  local lsc = math.min(1.15, COMBO_LABEL_BOX/lw)
  local pop = 1 + 0.55*c.punch*c.punch                          -- promotion spring
  local wob = (c.heat > 0.01) and (1 + 0.05*c.heat*math.sin(t*9)) or 1
  -- Hard ceiling so even a springing 'FRENZY' can't grow out of its slot.
  local ls  = math.min(lsc*pop*wob, (COMBO_LABEL_BOX + 10)/lw)
  -- print_centered scales about the centre, so the centre is derived from the
  -- LIVE scale every frame: that pins the label's right edge on the wall and
  -- makes a promotion spring grow leftward instead of over it. Vertically the
  -- anchor is the ink TOP -- fat_font at size 8 paints 3..22px below its draw
  -- origin and print_centered lifts by font.h/2 (20), so ink_top = y - 17*s --
  -- which keeps the gap under the tier chips identical at every scale.
  local lx  = lrx - lw*ls/2
  local ly  = lty + 17*ls

  if c.heat > 0.01 then                                          -- heat halo
    for i = 1, 2 do
      local hs = ls*(1 + 0.10*i)
      graphics.print_centered(rank.label, fat_font, lx, lty + 17*hs, 0, hs, hs, 0, 0,
                              Color(col.r, col.g, col.b, 0.16*c.heat/i))
    end
  end
  local lcol = col
  if c.demote > 0.01 then
    lcol = Color(math.lerp(c.demote, col.r, red[0].r),
                 math.lerp(c.demote, col.g, red[0].g),
                 math.lerp(c.demote, col.b, red[0].b), 1)
  end
  graphics.print_centered(rank.label, fat_font, lx, ly, 0, ls, ls, 0, 0, lcol)
  if c.flash > 0.01 then
    graphics.print_centered(rank.label, fat_font, lx, ly, 0, ls, ls, 0, 0, Color(1, 1, 1, c.flash))
  end
  if c.shock > 0.01 then                                         -- break-through hoop
    -- Centred on the label's INK centre (ink_top + half the 19px ink height).
    graphics.circle(lx, lty + 9.5*ls, 5 + 20*(1 - c.shock),
                    Color(col.r, col.g, col.b, c.shock*0.7), 1)
  end

  -- ---- track ----
  graphics.rectangle(cx, cy, bw, bh, bh/2, bh/2, bg[-2])
  graphics.rectangle(cx, cy, bw, bh, bh/2, bh/2,
                     Color(col.r, col.g, col.b, 0.22 + 0.2*c.heat), 1)

  local fw = bw*c.pct

  -- Ghost tail: the slice the bar just lost, held a beat behind the live front
  -- so a drop / the idle bleed reads as "that much was taken off you" instead
  -- of the bar quietly being shorter than it was.
  if c.ghost_pct > c.pct + 0.005 then
    local gwx = bw*(c.ghost_pct - c.pct)
    graphics.rectangle(bx0 + fw + gwx/2, cy, gwx, bh - 2, 1, 1,
                       Color(red[0].r, red[0].g, red[0].b, 0.45))
  end

  if fw > 0.5 then
    graphics.rectangle(bx0 + fw/2, cy, fw, bh, bh/2, bh/2, col)
    graphics.rectangle(bx0 + fw/2, cy - bh*0.22, fw, bh*0.34, 1, 1,   -- glassy upper band
                       Color(math.min(1, col.r + 0.35), math.min(1, col.g + 0.35),
                             math.min(1, col.b + 0.35), 0.5))

    -- Scrolling energy stripes: the fill always LOOKS like it is flowing
    -- left to right, and it flows faster the hotter the streak / the harder the
    -- bar is filling. Clipped by only drawing stripes fully inside the fill.
    local period = 11
    local sa     = 0.10 + 0.22*c.heat + 0.18*c.gain_v
    local sx     = bx0 - period + ((t*(26 + 90*c.heat + 60*c.gain_v)) % period)
    while sx < bx0 + fw do
      if sx - 2 > bx0 and sx + 4 < bx0 + fw then
        graphics.polygon({sx - 2, cy + bh/2, sx + 2, cy - bh/2,
                          sx + 4, cy - bh/2, sx,     cy + bh/2}, Color(1, 1, 1, sa))
      end
      sx = sx + period
    end

    -- Leading edge: a bright cap plus, while the bar is actually travelling, a
    -- comet smear behind it -- the motion cue that says gains are sliding in.
    local fxx = bx0 + fw
    graphics.rectangle(fxx - 1, cy, 2, bh, 1, 1, Color(1, 1, 1, 0.45 + 0.55*c.gain_v))
    graphics.circle(fxx, cy, 1.6 + 2.4*c.gain_v,
                    Color(col.r, col.g, col.b, 0.35 + 0.4*c.gain_v))
    if c.gain_v > 0.05 then
      graphics.rectangle(fxx - 5, cy, 10, bh - 3, 1, 1, Color(1, 1, 1, 0.20*c.gain_v))
    end
  end

  -- ---- one-shot overlays ----
  if c.flash > 0.01 then
    graphics.rectangle(cx, cy, bw + 2, bh + 2, bh/2, bh/2, Color(1, 1, 1, 0.5*c.flash))
  end
  if c.demote > 0.01 then
    graphics.rectangle(cx, cy, bw + 2, bh + 2, bh/2, bh/2,
                       Color(red[0].r, red[0].g, red[0].b, 0.4*c.demote), 1)
  end
  if c.drain > 0.4 then                                          -- bleeding rim pulse
    graphics.rectangle(cx, cy, bw + 2, bh + 2, bh/2, bh/2,
                       Color(red[0].r, red[0].g, red[0].b,
                             0.25*c.drain*(0.5 + 0.5*math.sin(t*7))), 1)
  end

  -- ---- tier ladder chips ----
  -- Where you sit on the whole ladder, which the single-tier fill bar can't
  -- say on its own. The chip for the current tier pops on a break-through.
  local n   = #COMBO_RANKS
  local cw  = 4
  local gp  = (bw - n*cw)/(n - 1)
  local cyy = cy + bh/2 + 3
  for i = 1, n do
    local ccol = _G[COMBO_RANKS[i].color_key][0]
    local a    = (i <= idx) and 0.95 or 0.18
    local h    = 2
    if i == idx then h = 2 + 2*c.chip_pop; a = 1 end
    graphics.rectangle(bx0 + cw/2 + (i - 1)*(cw + gp), cyy, cw, h, 0.5, 0.5,
                       Color(ccol.r, ccol.g, ccol.b, a))
  end

  -- ---- particles ----
  for _, p in ipairs(c.fx) do
    local k = 1 - p.t/p.life
    graphics.circle(p.x, p.y, p.r*k, Color(p.c.r, p.c.g, p.c.b, k))
  end
end


-- The y of the red "defense line" at the top of the paddle's dodge band. It is
-- both the breach boundary -- enemies that cross it cost the player HP (see the
-- swarm and critter breach checks) -- and what draw_hud renders as the red
-- dotted line. Falls back to a fixed offset if the paddle isn't built yet.
function BallPit:breach_line_y()
  -- Fallback = dodge band (120, see paddle.lua DODGE_BAND_UP) + 14px spawn
  -- offset, matching paddle.top_reach.
  return (self.paddle and self.paddle.top_reach) or (self.y2 - 134)
end


-- Used for single-enemy breaches (mobile critters that wander down past the paddle).
function BallPit:on_brick_breached(brick)
  self:damage_player(brick.player_dmg or 1)
  hit1:play{volume = 0.45, pitch = random:float(0.95, 1.05)}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = red_transparent_weak, duration = 0.08}
  spawn_burst(self.effects, brick.x, brick.y, red[0], 8, 60, 140)
  camera:shake(3, 0.2, 80)
  self.paddle.hfx:use('hit', 0.25, 200, 10)
  if self.player_hp <= 0 then self:trigger_game_over() end
end


-- Used when a whole Swarm reaches the paddle. HP loss scales with brick
-- count but is capped so a wide swarm doesn't insta-kill.
-- Breach retaliation. Taking HP from a swarm sets off a repulsion blast at the
-- breach line (BreachShockwave, effects.lua): every swarm it sweeps over loses
-- BREACH_NOVA_HP_FRAC of each brick's MAX HP and is shoved BREACH_SHOVE_DIST back
-- up the screen. Losing hearts is the worst thing that happens in a run, so a
-- breach buys a genuine reset -- the field comes off you and you get a window to
-- recover -- instead of one breach compounding straight into the next.
local BREACH_NOVA_HP_FRAC = 0.5
local BREACH_SHOVE_DIST   = 4*CELL_H   -- four brick rows of ground given back


function BallPit:on_row_breached(swarm, brick_count)
  local dmg = math.min(3, 1 + math.floor(brick_count/4))
  self:damage_player(dmg)
  hit1:play{volume = 0.5, pitch = random:float(0.9, 1.0)}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = red_transparent_weak, duration = 0.12}
  camera:shake(6 + brick_count*0.4, 0.4, 80)
  self.paddle.hfx:use('hit', 0.4, 200, 10)
  -- The retaliation blast (see BREACH_NOVA_HP_FRAC above). Spawned from the
  -- breach line so it reads as coming off the paddle, and it applies its damage
  -- + shove progressively as it sweeps, not instantly here.
  BreachShockwave{
    group   = self.effects,
    x1      = self.x1, x2 = self.x2,
    y_start = self:breach_line_y(), y_end = self.y1,
    color   = red[0],
    hp_frac = BREACH_NOVA_HP_FRAC,
    shove   = BREACH_SHOVE_DIST,
  }
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




-- XP. Reachable only on a loadout that still runs the orb economy -- the
-- Terrorist (see uses_xp_orbs); every other paddle levels on wave clears and
-- never calls this. The loadout's XP stat scales every gain. Rounded, never
-- below 1.
function BallPit:gain_xp(amount)
  amount = math.max(1, math.floor(amount*((self.run_mods and self.run_mods.xp) or 1) + 0.5))
  self.xp = self.xp + amount
  FloatingText{group = self.effects, x = self.paddle.x, y = self.paddle.y - 16, text = '+' .. amount, color = blue[0]}
  while self.xp >= self.xp_to_next do
    self.xp = self.xp - self.xp_to_next
    self:level_up()
  end
end


-- Does this run still level on XP ORBS? Only the Terrorist does.
--
-- Every other loadout levels on the WAVE CLOCK -- one level per wave cleared,
-- granted in advance_wave -- so blocks drop nothing, there is no XP to chase
-- across the arena, and the draft arrives on a rhythm the player can plan around
-- instead of whenever enough gems happened to fall within reach of the paddle.
--
-- The Terrorist is left on orbs because its whole loop is built out of them: it
-- auto-collects field-wide, levels on a FLAT curve, gains XP passively over time,
-- and every level auto-arms a ball instead of opening a draft (see
-- terror_auto_levelup). Wave-paced levelling would flatten all of that into the
-- same cadence every other paddle has.
--
-- Read by: the three orb drops (Brick:die, EnemyCritter:die, Boss:die), the wave
-- clear in advance_wave, and the HUD bar in draw_hud.
function BallPit:uses_xp_orbs()
  return (self.run_mods and self.run_mods.signature == 'terrorist') or false
end


function BallPit:level_up()
  self.level = self.level + 1
  -- Terrorist loadout: FLAT XP — every level costs the same, so the curve
  -- never runs away from you (slow opener, out-levels hard late).
  if not (self.run_mods and self.run_mods.xp_mode == 'flat') then
    -- Harder curve (was *1.35 + 1): a steeper multiplier plus a level-sized
    -- kicker, so the opening levels stop flying by. Tunable via the balance
    -- master files (globals.xp_curve_mult / globals.xp_base).
    self.xp_to_next = math.floor(self.xp_to_next*BAL('globals.xp_curve_mult', 1.5) + self.level)
  end
  level_up1:play{volume = 0.5}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = yellow_transparent_weak, duration = 0.15}
  camera:shake(3, 0.2, 90)
  self.paddle.hfx:use('hit', 0.3, 200, 10)
  -- If a picker is already open (e.g. one big XP pickup crossed several levels
  -- in gain_xp's loop), queue this level so it gets its own picker after the
  -- current pick is confirmed; otherwise open one now. See confirm_upgrade.
  if self.upgrade_pending then
    self.pending_levelups = self.pending_levelups + 1
  else
    self:offer_upgrades()
  end
end


function BallPit:offer_upgrades()
  -- Terrorist: no draft screen — the player shouldn't stop to pick a card every
  -- level when balls are expendable munitions. Auto-arm a random ball instead
  -- and leave upgrade_pending false so play never freezes.
  if self.run_mods and self.run_mods.signature == 'terrorist' then
    self:terror_auto_levelup()
    return
  end
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


-- Terrorist's draftless level-up: every level instantly arms a fresh random
-- ball (the player wants ammo, not menu time, since detonations spend balls).
-- Once the field is crowded it levels an existing ball instead so the screen
-- doesn't drown in orbs. Never opens a picker / sets upgrade_pending.
function BallPit:terror_auto_levelup()
  local TERROR_BALL_CAP = 14
  local live = 0
  for _, h in ipairs(self.heroes) do if h and not h.dead then live = live + 1 end end

  if live < TERROR_BALL_CAP then
    local c    = hero_pool[random:int(1, #hero_pool)]
    local hero = self:add_hero(c)
    FloatingText{group = self.effects, x = self.paddle.x, y = self.paddle.y - 24,
                 text = '+' .. c:sub(1, 4):upper(), color = yellow[0]}
    if hero then self:flash_hero_level_up(hero) end
  else
    local pool = {}
    for _, h in ipairs(self.heroes) do
      if h and not h.dead and (h.level or 1) < 3 then pool[#pool + 1] = h end
    end
    if #pool > 0 then
      local h = pool[random:int(1, #pool)]
      h.level = (h.level or 1) + 1
      h.dmg   = h.dmg * (1 + BAL('globals.level_dmg_growth', 0.4))
      self:flash_hero_level_up(h)
    end
  end
  confirm1:play{volume = 0.35}
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
    -- Twin Cast: heroes come in mirrored pairs, so a level-up pick levels two
    -- matching balls instead of one.
    local to_level = (self.run_mods and self.run_mods.signature == 'twincast') and 2 or 1
    for _, h in ipairs(self.heroes) do
      if h.character == choice.character and h.level < 3 then
        h.level = h.level + 1
        h.dmg = h.dmg * (1 + BAL('globals.level_dmg_growth', 0.4))
        to_level = to_level - 1
        if to_level <= 0 then break end
      end
    end
  else
    self:add_hero(choice.character)
  end
  confirm1:play{volume = 0.4}
  -- More levels were earned than pickers shown so far: immediately open the
  -- next one instead of closing, so a multi-level XP gain yields one picker per
  -- level. offer_upgrades rebuilds a fresh draft and keeps upgrade_pending set.
  if self.pending_levelups > 0 then
    self.pending_levelups = self.pending_levelups - 1
    self:offer_upgrades()
  else
    self.upgrade_pending = false
    self.upgrade_choices = nil
  end
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

    -- Live skin preview: the hero's exact in-game body (BallHero.draw_preview
    -- -> draw_skin), scaled up to card size.
    BallHero.draw_preview(choice.character, cx, cy - 18, 11)
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
    archer       = 'skewer bolt',

    -- Knives
    scout        = 'chaining knife',

    -- Special projectiles
    spellblade   = 'random shot',

    -- Cleave
    swordsman    = 'cleave +15%/hit',

    -- Melee splash
    barbarian    = 'heavy splash',

    -- Healers
    cleric       = '+1 hp / 8s',

    -- Curse / vulnerability
    jester       = 'curse x6',

    -- DoT clouds
    witch        = 'toxic cloud',

    -- Bomb drops
    bomber       = 'drops bomb',

    -- Turret drops
    engineer     = 'drops turret',

    -- Force area
    psykino      = 'knockback',

    -- Chain lightning
    stormweaver  = 'chain lightning',

    -- Hive / locust swarm
    infestor     = 'locust swarm',

    -- Misc
    gambler      = 'lucky strikes',

    -- Volcano
    vulcanist    = 'plants volcano',

    -- Cannon (ranged AoE)
    cannoneer    = 'cannon blast',

    -- On-bounce specials
    wizard       = 'chain on hit',
    cryomancer   = 'freeze on hit',
    pyromancer   = 'burn on hit',
  }
  return blurbs[c] or 'ball-hero'
end


-- Detailed hero ability progression data for the tooltip UI.
-- Each entry has: description (what the ability does), and tier-specific bonuses.
function BallPit:get_hero_ability_data(c)
  local data = {
    vagrant = {
      desc = 'Fires arrows at nearby enemies',
      tiers = {
        {dmg_mult = 1.0, special = ''},
        {dmg_mult = 1.4, special = '+40% damage'},
        {dmg_mult = 1.8, special = '+80% damage'},
      }
    },
    archer = {
      desc = 'Piercing bolts that skewer entire lanes',
      tiers = {
        {dmg_mult = 1.0, special = 'Infinite pierce'},
        {dmg_mult = 1.4, special = '+40% damage'},
        {dmg_mult = 1.8, special = '+80% damage, 3 ricochets'},
      }
    },
    scout = {
      desc = 'Throws chaining knives between targets',
      tiers = {
        {dmg_mult = 1.0, special = '3 chains'},
        {dmg_mult = 1.4, special = '+40% damage'},
        {dmg_mult = 1.8, special = '+80% damage, 6 chains, +25% dmg/hop'},
      }
    },
    spellblade = {
      desc = 'Spiraling blade storm in all directions',
      tiers = {
        {dmg_mult = 1.0, special = 'Constant stream'},
        {dmg_mult = 1.4, special = '+40% damage'},
        {dmg_mult = 1.8, special = '+80% damage'},
      }
    },
    swordsman = {
      desc = 'Melee cleave that stacks power per hit',
      tiers = {
        {dmg_mult = 1.0, special = '+15% damage per target hit'},
        {dmg_mult = 1.4, special = '+40% base damage'},
        {dmg_mult = 1.8, special = '+80% base damage, 2x multiplier'},
      }
    },
    barbarian = {
      desc = 'Massive hexagonal hammer slam',
      tiers = {
        {dmg_mult = 1.0, special = '+15% damage per target'},
        {dmg_mult = 1.4, special = '+40% damage, +30% area'},
        {dmg_mult = 1.8, special = '+80% damage, +60% area, 2x multiplier'},
      }
    },
    cleric = {
      desc = 'Plants healing sigil at paddle position',
      tiers = {
        {dmg_mult = 1.0, special = '1 HP every 2s, 6s duration'},
        {dmg_mult = 1.4, special = '+40% holy damage'},
        {dmg_mult = 1.8, special = '+80% holy damage, blade bombard'},
      }
    },
    jester = {
      desc = 'Curses enemies; hexed kills explode into knives',
      tiers = {
        {dmg_mult = 1.0, special = '1.4x vulnerability, 6s curse'},
        {dmg_mult = 1.4, special = '+40% knife damage'},
        {dmg_mult = 1.8, special = '+80% damage, homing + pierce knives'},
      }
    },
    witch = {
      desc = 'Spawns toxic clouds that damage over time',
      tiers = {
        {dmg_mult = 1.0, special = 'DoT cloud'},
        {dmg_mult = 1.4, special = '+40% damage'},
        {dmg_mult = 1.8, special = '+80% damage'},
      }
    },
    bomber = {
      desc = 'Drops explosive bombs on enemies',
      tiers = {
        {dmg_mult = 1.0, special = 'Area explosion'},
        {dmg_mult = 1.4, special = '+40% damage, +20% radius'},
        {dmg_mult = 1.8, special = '+80% damage, +40% radius'},
      }
    },
    engineer = {
      desc = 'Deploys auto-firing turrets',
      tiers = {
        {dmg_mult = 1.0, special = 'Turret damage scales with hero'},
        {dmg_mult = 1.4, special = '+40% turret damage'},
        {dmg_mult = 1.8, special = '+80% turret damage'},
      }
    },
    psykino = {
      desc = 'Psychic force pushes enemies away',
      tiers = {
        {dmg_mult = 1.0, special = 'Knockback'},
        {dmg_mult = 1.4, special = '+40% damage, +25% range'},
        {dmg_mult = 1.8, special = '+80% damage, +50% range'},
      }
    },
    stormweaver = {
      desc = 'Lightning chains between multiple enemies',
      tiers = {
        {dmg_mult = 1.0, special = 'Chain lightning'},
        {dmg_mult = 1.4, special = '+40% damage, more chains'},
        {dmg_mult = 1.8, special = '+80% damage, max chains'},
      }
    },
    infestor = {
      desc = 'Summons locust swarms that attack enemies',
      tiers = {
        {dmg_mult = 1.0, special = 'Locust swarm'},
        {dmg_mult = 1.4, special = '+40% damage'},
        {dmg_mult = 1.8, special = '+80% damage'},
      }
    },
    gambler = {
      desc = 'Random chance to crit for massive damage',
      tiers = {
        {dmg_mult = 1.0, special = '15% crit chance'},
        {dmg_mult = 1.4, special = '+40% damage, 20% crit'},
        {dmg_mult = 1.8, special = '+80% damage, 25% crit, multi-cast'},
      }
    },
    vulcanist = {
      desc = 'Plants erupting volcanoes that deal area damage',
      tiers = {
        {dmg_mult = 1.0, special = 'Area damage over time'},
        {dmg_mult = 1.4, special = '+40% damage'},
        {dmg_mult = 1.8, special = '+80% damage'},
      }
    },
    cannoneer = {
      desc = 'Fires explosive cannon shots',
      tiers = {
        {dmg_mult = 1.0, special = 'Area explosion'},
        {dmg_mult = 1.4, special = '+40% damage, +20% radius'},
        {dmg_mult = 1.8, special = '+80% damage, +40% radius'},
      }
    },
    wizard = {
      desc = 'Each bounce chains lightning to nearby foes',
      tiers = {
        {dmg_mult = 1.0, special = 'On-bounce lightning'},
        {dmg_mult = 1.4, special = '+40% damage, 4 links'},
        {dmg_mult = 1.8, special = '+80% damage, 5 links'},
      }
    },
    cryomancer = {
      desc = 'Freezes and slows enemies on contact',
      tiers = {
        {dmg_mult = 1.0, special = '40% slow, 3s duration'},
        {dmg_mult = 1.4, special = '+40% damage, 4s slow'},
        {dmg_mult = 1.8, special = '+80% damage, 5s slow'},
      }
    },
    pyromancer = {
      desc = 'Burns enemies on contact for damage over time',
      tiers = {
        {dmg_mult = 1.0, special = 'Burn DoT on bounce'},
        {dmg_mult = 1.4, special = '+40% damage'},
        {dmg_mult = 1.8, special = '+80% damage, stronger burn'},
      }
    },
  }
  return data[c] or {
    desc = 'A powerful ball-hero',
    tiers = {
      {dmg_mult = 1.0, special = ''},
      {dmg_mult = 1.4, special = '+40% damage'},
      {dmg_mult = 1.8, special = '+80% damage'},
    }
  }
end


-- Greedy word wrap against a PIXEL budget rather than a character count, so a
-- line can never overrun its panel just because the font or the scale changed.
-- A word wider than the budget gets its own line instead of being dropped.
local function wrap_to_width(text, font, scale, max_w)
  local lines, line = {}, nil
  for word in tostring(text or ''):gmatch('%S+') do
    local try = line and (line .. ' ' .. word) or word
    if (not line) or font:get_text_width(try)*scale <= max_w then
      line = try
    else
      lines[#lines + 1] = line
      line = word
    end
  end
  if line then lines[#lines + 1] = line end
  return lines
end


-- Hover card for one roster hero: name + level, what the ability does, and the
-- three upgrade tiers side by side.
--
-- Everything here is laid out from MEASURED text: the copy is wrapped to the
-- panel's inner width and the panel's height is then computed from how many
-- lines that produced, so no line can spill past the frame or collide with the
-- row under it however long the ability text is.
--
-- EVERY line draws at scale 1.0. The brush fonts are 2x pixel faces (two-pixel
-- strokes at size 8); the old 0.7/0.55 draws put those strokes on 1.4 and 1.1
-- pixels and the filter turned them to grey. Native scale costs width, which
-- is why the panel is 380 wide now and the mono font carries -1 tracking
-- (shared.lua) -- together those land the copy at roughly the line count the
-- shrunken version had, but legible.
--
-- Vertical arithmetic: pixul ink runs y .. y+9 below a `print` origin, and
-- print_centered lifts by font.h/2 = 6.5 at scale 1.0. So an INK TOP of `k`
-- means drawing at k + 6.5, and every offset below is written that way.
function BallPit:draw_hero_tooltip(hero, total_heroes)
  local rows = math.ceil(total_heroes/8)
  local data = self:get_hero_ability_data(hero.character)
  local lvl  = hero.level or 1

  local pw   = 380                                   -- 300 before the copy grew
  local px0  = gw/2 - pw/2
  local py   = hero_grid_top() + rows*HERO_CELL_H + 10
  local tw   = pw/3                                  -- one tier column
  local LP   = 11                                    -- line pitch (9px ink + 2)

  -- Wrap first, size the panel second.
  local desc = wrap_to_width(data.desc, pixul_mono_font, 1, pw - 24)
  local spec, spec_rows = {}, 0
  for tier = 1, 3 do
    spec[tier] = wrap_to_width(data.tiers[tier].special, pixul_mono_font, 1, tw - 10)
    spec_rows  = math.max(spec_rows, #spec[tier])
  end
  local ty = py + 24 + #desc*LP + 6                   -- top of the tier columns
  local ph = (ty - py) + 31 + math.max(1, spec_rows)*LP + 6

  graphics.rectangle(gw/2, py + ph/2, pw, ph, 4, 4, bg[-2])
  graphics.rectangle(gw/2, py + ph/2, pw, ph, 4, 4,
                     Color(hero.color.r, hero.color.g, hero.color.b, 0.6), 1)

  -- Header + rule.
  graphics.print_centered(string.upper(hero.character) .. '  LEVEL ' .. lvl,
                          pixul_font, gw/2, py + 13.5, 0, 1, 1, 0, 0, hero.color)
  graphics.line(px0 + 10, py + 20, px0 + pw - 10, py + 20, Color(1, 1, 1, 0.12), 1)

  for i, line in ipairs(desc) do
    -- ink top py + 24, then one pitch per line
    graphics.print_centered(line, pixul_mono_font, gw/2, py + 30.5 + (i - 1)*LP,
                            0, 1, 1, 0, 0, fg_alt[0])
  end

  -- Tier columns. Hairline separators so three stacks of copy don't read as
  -- one paragraph.
  for i = 1, 2 do
    graphics.line(px0 + i*tw, ty - 4, px0 + i*tw, py + ph - 6, Color(1, 1, 1, 0.10), 1)
  end

  for tier = 1, 3 do
    local tx         = px0 + (tier - 0.5)*tw
    local is_current = (tier == lvl)
    local is_open    = (tier <= lvl)
    local tcol = is_current and yellow[0] or (is_open and fg[0] or fg[-2])

    -- ink top ty + 0
    graphics.print_centered((tier == 1 and 'I') or (tier == 2 and 'II') or 'III',
                            pixul_font, tx, ty + 6.5, 0, 1, 1, 0, 0, tcol)

    -- clear of the numeral's ink (ends ty + 9)
    if is_current then      graphics.circle(tx, ty + 14, 2.5, yellow[0])
    elseif is_open then     graphics.circle(tx, ty + 14, 2,   fg[-1])
    else                    graphics.circle(tx, ty + 14, 1.5, fg[-3], 1) end

    -- ink top ty + 18
    local pct = math.floor((data.tiers[tier].dmg_mult - 1.0)*100)
    graphics.print_centered(pct > 0 and ('+' .. pct .. '%') or 'BASE',
                            pixul_font, tx, ty + 24.5, 0, 1, 1, 0, 0,
                            is_open and (is_current and yellow[0] or green[0]) or fg[-3])

    -- ink top ty + 31
    local scol = is_open and fg_alt[0] or fg[-3]
    for i, line in ipairs(spec[tier]) do
      graphics.print_centered(line, pixul_mono_font, tx, ty + 37.5 + (i - 1)*LP,
                              0, 1, 1, 0, 0, scol)
    end
  end
end


-- How long the wreck gets before the shutters start closing on it. Tuned to
-- land while the debris is still falling rather than after it has settled --
-- the transition should interrupt the death, not wait politely for it.
local DEATH_DUR = 1.25


-- The killing blow. This no longer jumps straight to the run report: it starts
-- the DEATH SEQUENCE -- the paddle breaks apart over a frozen board (see the
-- dying branch in update), and when that has played the page gate closes and
-- finish_game_over swaps the page behind the shutters.
--
-- Idempotent: several damage paths can reach zero HP on the same frame, and
-- without the guard each would spawn its own wreck and stack its own stinger.
function BallPit:trigger_game_over()
  if self.dying or self.game_over then return end
  self.dying   = true
  self.death_t = 0
  self.t:cancel('spawn_brick')
  local p = self.paddle
  if p then
    p.destroyed = true          -- Paddle:draw hands over to the wreck
    PaddleDeath{group = self.effects, x = p.x, y = p.y, w = p.w, h = p.h,
                color = p.color or fg[0]}
  end
end


-- Drive the death beat, then hand off to the shutters. begin_page_gate is
-- itself guarded against a second call, and 'death' is handled in
-- tick_page_gate (paddles.lua), which runs finish_game_over at full cover.
function BallPit:update_death(dt)
  self.death_t = (self.death_t or 0) + dt
  if self.death_t >= DEATH_DUR and not self.gate then
    self:begin_page_gate('death')
  end
end


-- Swap to the run report. Called from behind the closed shutters, so nothing
-- here is ever seen to happen.
function BallPit:finish_game_over()
  self.dying     = false
  self.game_over = true
  -- Land on the run-report screen; the shop is one button deeper (paddles.lua).
  self.go_screen   = 'over'
  self.go_selected = 1
  -- Bank the run's kills to disk and pre-select the equipped card for when
  -- the player opens the shop.
  PADDLES.ensure_state()
  -- Cut the run into the title stele. Every field is a high-water mark except
  -- `runs`, which just counts -- so a bad run still adds a rite to the tally.
  local rec = state.records
  rec.runs       = rec.runs + 1
  rec.best_wave  = math.max(rec.best_wave,  self.wave or 0)
  rec.best_score = math.max(rec.best_score, self.score or 0)
  rec.best_rank  = math.max(rec.best_rank,  self.peak_rank_idx or 1)
  self.shop_selected = 1
  for i, id in ipairs(PADDLES.order) do
    if id == state.selected_paddle then self.shop_selected = i; break end
  end
  system.save_state()
end


function BallPit:draw_game_over()
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0, 0, 0, 0.7))
  graphics.print_centered('GAME OVER', fat_font, gw/2, gh/2 - 24, 0, 1.4, 1.4, 0, 0, red[0])
  graphics.print_centered('Wave ' .. self.wave .. '   Score ' .. self.score, pixul_font, gw/2, gh/2, 0, 1, 1, 0, 0, fg[0])
  graphics.print_centered('press R to restart', pixul_font, gw/2, gh/2 + 16, 0, 1, 1, 0, 0, fg_alt[0])
end


-- ----- Ability helpers used by ball heroes -----

-- An enemy still gliding into the arena is not a target yet. It is off screen
-- (the play field is clipped at the top edge -- see clip_to_arena), so a shot
-- aimed at one would fly up and vanish into the ceiling, and an ability would
-- spend itself on something the player cannot see. Anything not riding a swarm
-- -- critters, the boss -- is always in play.
local function targetable(o)
  return not (o.swarm and o.swarm.entering and o.swarm:entering())
end


function BallPit:get_nearest_brick(x, y, exclude)
  local best, best_d = nil, 1e9
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead and targetable(o) and (not exclude or o.id ~= exclude.id) then
      local d = math.distance(x, y, o.x, o.y)
      if d < best_d then best_d = d; best = o end
    end
  end
  return best
end


function BallPit:has_brick_within(x, y, range)
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead and targetable(o) then
      if math.distance(x, y, o.x, o.y) <= range then return true end
    end
  end
  return false
end


-- Like has_brick_within but counts ANY enemy (block, critter, or boss) — used
-- by the Terrorist to decide whether a ball is "armed" (close enough to blow).
function BallPit:terror_has_enemy_within(x, y, range)
  for _, o in ipairs(self.main.objects) do
    if not o.dead and targetable(o) and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
      if math.distance(x, y, o.x, o.y) <= range then return true end
    end
  end
  return false
end


-- Terrorist: the detonation radius — also the arm range. Grows with the run
-- level so late-game blasts cover more ground (and balls arm from further out),
-- capped by blast_radius_max so it never engulfs the whole arena. Shared by the
-- blast itself (terror_detonate), the per-ball armed check, and the E gate.
function BallPit:terror_blast_radius()
  local sig   = (self.run_mods and self.run_mods.sig) or {}
  local scale = 1 + ((self.level or 1) - 1)*(sig.blast_radius_per_level or 0.05)
  return math.min((sig.blast_radius or 78)*scale, sig.blast_radius_max or 150)
end


-- Terrorist: E pressed. Detonate every ball that is in play AND near an enemy
-- (armed); balls that aren't close don't blow, so the player keeps them. Each
-- detonation consumes its ball (terror_detonate). Iterate a snapshot because
-- the detonations mutate self.heroes mid-loop.
function BallPit:terror_manual_detonate()
  local arm = self:terror_blast_radius()
  -- Slam the paddle's detonator plunger on every press, hit or whiff (see
  -- Paddle:draw_terrorist_paddle).
  if self.paddle then self.paddle.plunger_at = love.timer.getTime() end
  local snapshot = {}
  for _, h in ipairs(self.heroes) do snapshot[#snapshot + 1] = h end
  local any = false
  for _, h in ipairs(snapshot) do
    if h and not h.dead and not h.stuck and not h.returning and not h.mortar then
      if self:terror_has_enemy_within(h.x, h.y, arm) then
        h:terror_detonate()
        any = true
      end
    end
  end
  -- Nothing in range: a soft click so the press still registers as "no target".
  if not any and pop1 then pop1:play{volume = 0.2, pitch = 0.6} end
end


function BallPit:get_nearest_brick_within(x, y, range)
  local best, best_d = nil, range
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead and targetable(o) then
      local d = math.distance(x, y, o.x, o.y)
      if d <= best_d then best_d = d; best = o end
    end
  end
  return best
end


-- Nearest ANY enemy -- block, critter or boss -- within range. get_nearest_brick_within
-- above only sees Bricks, so anything targeting through it goes blind on the boss
-- wave (nothing but the Boss is on the field). Used by the engineer's deployed
-- turrets, which otherwise stood idle through the whole fight.
function BallPit:get_nearest_enemy_within(x, y, range)
  local best, best_d = nil, range
  for _, o in ipairs(self.main.objects) do
    if not o.dead and targetable(o) and (o:is(Brick) or o:is(EnemyCritter) or o:is(Boss)) then
      local d = math.distance(x, y, o.x, o.y)
      if d <= best_d then best_d = d; best = o end
    end
  end
  return best
end


function BallPit:get_bricks_within(x, y, range)
  local out = {}
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead and targetable(o) and math.distance(x, y, o.x, o.y) <= range then
      table.insert(out, o)
    end
  end
  return out
end


function BallPit:get_random_brick_within(x, y, range)
  local candidates = {}
  for _, o in ipairs(self.main.objects) do
    if o:is(Brick) and not o.dead and targetable(o) and math.distance(x, y, o.x, o.y) <= range then
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
        chain  = opts.chain or 0,
        chain_dmg_ramp = opts.chain_dmg_ramp,
        wall_stick = opts.wall_stick,
        proj_scale = opts.proj_scale,
        max_hp_frac = opts.max_hp_frac,
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

    -- Lightning visual: a real jagged bolt (LightningArc -- coloured glow, hot
    -- core, stray forks) that re-rolls its path over its short life so the
    -- whole chain flickers like one strike. Jag amplitude scales with hop
    -- length so short hops stay tight and long ones whip.
    local hop_len = math.distance(cx, cy, target.x, target.y)
    LightningArc{group = self.effects, x1 = cx, y1 = cy, x2 = target.x, y2 = target.y,
                 color = color, w = 2.5, duration = 0.22, gens = 4,
                 offset = math.clamp(hop_len*0.14, 5, 14), flicker = true}

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
    -- heal_hearts handles the Vampire bar conversion (1 heart = 20 units).
    local healed = self:heal_hearts(1)
    if healed > 0 then
      FloatingText{group = self.effects, x = self.paddle.x, y = self.paddle.y - 20, text = '+1 HP', color = green[0]}
    end
  end
end


-- ----- Powerups -----
--
-- Apply a powerup by name. Effects come in three flavours:
--   1. Instant (heal, water_wave, level_random): no buff slot.
--   2. Timed buff (wide_paddle, big_ball, fire_trail, freeze_wave, pierce, multi_ball,
--      floor):
--      stashed in self.buffs[kind] with a `remaining` + `restore` pair;
--      tick_buffs counts down and calls restore on expiry. Stacking the same
--      buff while it's active extends the timer instead of stacking the
--      multiplier.
--      The floor is additionally wave-bounded: advance_wave / reset_run clear it
--      early even if its timer has not run out.


-- A brief visual confirmation that a specific hero just gained a level.
-- Used by the "level random balls" powerup.
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


-- Pity-timer driven powerup spawner. Accumulates real time and rolls for a
-- spawn at fixed intervals; each failed roll bumps the chance for the next
-- check so dry streaks can't drag on forever.
function BallPit:tick_powerup_pity(dt)
  if not Powerup then return end
  if self.upgrade_pending or self.game_over then return end
  -- No powerups during the boss wave (wave 10): the fight should be dodged on
  -- its own terms, not trivialised by mid-fight pickups.
  if self.wave_cfg and self.wave_cfg.boss then return end
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
-- the paddle.
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

  local arena_w = self.x2 - self.x1
  local x = self:arena_center_x() + random:float(-arena_w/3, arena_w/3)
  local y = self.y1 + 16

  self.t:after(0, function()
    if self.main and self.main.world then
      Powerup{group = self.main, x = x, y = y, kind = kind}
    end
  end)
end


-- Dedicated spawn cadence for the level-up ball, independent of the regular
-- powerup pity timer. Fires every `next_at` seconds, then re-rolls the gap.
function BallPit:tick_levelup_pity(dt)
  if not Powerup then return end
  if self.upgrade_pending or self.game_over then return end
  -- No level-up balls during the boss wave either (see tick_powerup_pity).
  if self.wave_cfg and self.wave_cfg.boss then return end
  local p = self.levelup_pity
  if not p then return end

  p.timer = p.timer + dt
  if p.timer < p.next_at then return end
  p.timer   = 0
  p.next_at = random:float(BAL('powerups.level_orb_gap_min', 36),
                           BAL('powerups.level_orb_gap_max', 54))   -- gap until the next level-up ball (was 24-36)
  self:spawn_levelup_powerup()
end


-- Drop a single level-up ball near the top of the arena. Skipped (and retried
-- next interval) if every ball-hero is already max level, so the player never
-- has to chase a powerup that would do nothing.
function BallPit:spawn_levelup_powerup()
  if not (Powerup and self.main and self.main.world) then return end

  local has_target = false
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and (h.level or 1) < 3 then has_target = true; break end
  end
  if not has_target then return end

  local arena_w = self.x2 - self.x1
  local x = self:arena_center_x() + random:float(-arena_w/3, arena_w/3)
  local y = self.y1 + 16
  self.t:after(0, function()
    if self.main and self.main.world then
      Powerup{group = self.main, x = x, y = y, kind = 'level_random'}
    end
  end)
end


function BallPit:apply_powerup(kind, x, y, color, amount)
  local def = Powerup and Powerup.KINDS and Powerup.KINDS[kind]
  if not def then return end

  -- Floating label so the player can read what they just caught.
  local px = (self.paddle and self.paddle.x) or gw/2
  local py = (self.paddle and self.paddle.y - 26) or gh/2
  FloatingText{group = self.effects, x = px, y = py, text = def.label:upper(), color = color or _G[def.color or 'fg'][0]}
  buff1:play{volume = 0.3, pitch = random:float(1.0, 1.1)}
  Flash{group = self.effects, x = gw/2, y = gh/2, color = Color((color or fg[0]).r, (color or fg[0]).g, (color or fg[0]).b, 0.25), duration = 0.08}

  if     kind == 'heal'         then self:heal_player(1)
  elseif kind == 'wide_paddle'  then self:apply_paddle_width_buff()
  elseif kind == 'big_ball'     then self:apply_big_ball_buff()
  elseif kind == 'fire_trail'   then self:apply_fire_trail_buff()
  elseif kind == 'freeze_wave'  then self:apply_freeze_wave()
  elseif kind == 'water_wave'   then self:apply_water_wave()
  elseif kind == 'multi_ball'   then self:apply_multi_ball()
  elseif kind == 'pierce'       then self:apply_pierce_buff()
  elseif kind == 'floor'        then self:apply_floor()
  elseif kind == 'level_random' then self:apply_level_random(amount)
  end
end


-- Tick every active buff. Called from BallPit:update.
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
  -- Pinball Lobber: the rig is a two-fixture body that rebuild_rect_body
  -- would flatten into a plain rectangle — rescale the whole rig instead.
  if p.flippers then
    self:add_or_extend_buff('wide_paddle', 15,
      function() p:build_flipper_rig(1.6); p.phased = true  end,
      function() p:build_flipper_rig(1);   p.phased = false end)
    return
  end
  self:add_or_extend_buff('wide_paddle', 15,
    function()
      -- Phased: for the buff's duration the paddle is intangible to DAMAGE
      -- (see BallPit:damage_player) and draws at a ghost alpha to show it.
      -- Balls still bounce off it normally -- only the HP channel is off.
      p.phased  = true
      p._orig_w = p._orig_w or p.w
      p.w = p._orig_w * 1.6
      rebuild_rect_body(p, p.w, p.h, 'kinematic', 'paddle')
      p:set_restitution(1)
      p.t:after(0, function() if p.body then p.body:setFixedRotation(true) end end)
    end,
    function()
      p.phased = false
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
  local vx, vy   = h:get_velocity()
  local was_active = h.body:isActive()

  local arena = main.current
  if arena then
    h.x = math.clamp(h.x, arena.x1 + new_r + 1, arena.x2 - new_r - 1)
    h.y = math.clamp(h.y, arena.y1 + new_r + 1, arena.y2 + 40)
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
  -- The fixture was rebuilt, so the Pinball Lobber's roll-not-bounce surface
  -- props (low restitution + friction) have to be re-applied.
  if h.is_pinball and h:is_pinball() then
    local g = (h.run_mods and h.run_mods.sig) or {}
    h:set_restitution(g.restitution or 0.12)
    h:set_friction(0.5)
    h:set_fixed_rotation(false)   -- keep real rolling after the fixture rebuild
  end
  if vx and vy then h:set_velocity(vx, vy) end
  if not was_active then h.body:setActive(false) end
  -- The fixture was destroyed and recreated, so any per-fixture filter
  -- state (e.g. the pierce ghost-mode mask) needs to be re-applied.
  if h.set_piercing then h:set_piercing(h.piercing) end
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


-- Fire (timed buff). While it's up the arena gets a warm fiery ambiance (a
-- screen overlay of flames licking up from the floor), and any block the player
-- ignites by hitting it with a ball burns down to black ash via a burn DoT.
-- The burn itself is applied on ball contact in BallHero (gated on this buff);
-- this function only drives the timer + the ambiance flag (self.fire_active).
-- No screen-wide drain -- fire damages only the blocks the balls actually hit.
function BallPit:apply_fire_trail_buff()
  local ember = Color(1.0, 0.55, 0.15, 1)

  self:add_or_extend_buff('fire_trail', 18,       -- seconds of fire
    function()
      self.fire_active = true
      self:spawn_fire_flames()
    end,
    function()
      self.fire_active = false
      self.fire_flames = nil
    end)

  -- One-shot cast burst, replayed on every catch (even when extending the
  -- timer): a fiery flash, two expanding rings, a shake and a sound. The old
  -- per-brick ember sparkle on every block on screen is gone -- it dated from
  -- when fire damaged all blocks; now it only burns the blocks the balls hit.
  Flash{group = self.effects, x = gw/2, y = gh/2,
        color = Color(red[0].r, red[0].g, red[0].b, 0.30), duration = 0.22}
  TelegraphRing{group = self.effects, x = gw/2, y = gh/2,
                radius = math.max(gw, gh)*0.62, color = red[0], duration = 0.45}
  TelegraphRing{group = self.effects, x = gw/2, y = gh/2,
                radius = math.max(gw, gh)*0.42, color = ember, duration = 0.55}
  camera:shake(4, 0.3, 80)
  if fire1 then fire1:play{volume = 0.5, pitch = random:float(0.85, 1.0)} end
end


-- Pre-roll a stable row of flame bases along the BOTTOM screen edge for
-- draw_fire_overlay. Each base has a fixed x + half-width + nominal height; the
-- live height + sway derive from the clock so the flames lick upward without any
-- per-frame random. The buff's restore() clears the list.
function BallPit:spawn_fire_flames()
  local list = {}
  local n = 22
  for i = 1, n do
    list[#list + 1] = {
      x     = (i - 0.5)*gw/n + random:float(-7, 7),
      w     = random:float(10, 18),      -- base half-width
      h     = random:float(50, 110),     -- nominal flame height
      speed = random:float(6, 11),       -- flicker speed
      seed  = random:float(0, math.pi*2),
    }
  end
  self.fire_flames = list
end


-- Full-screen fire ambiance while the buff is live: a heat wash strongest along
-- the floor, a warm edge vignette, and a row of flame tongues (outer red, inner
-- orange, yellow core) licking up from the BOTTOM screen edge -- no dots/embers.
-- Intensity eases out over the final 0.8s so the burn-out is visible.
function BallPit:draw_fire_overlay()
  local b = self.buffs and self.buffs.fire_trail
  if not b then return end
  local intensity = math.min(1, math.max(0, b.remaining)/0.8)
  local time      = love.timer.getTime()

  -- Bottom-weighted heat wash: 6 stacked full-width bands, hottest along the floor.
  for i = 1, 6 do
    local a  = 0.085 * (1 - (i - 1)/6) * intensity
    local cy = gh - (gh/6)*(i - 0.5)
    graphics.rectangle(gw/2, cy, gw, gh/6, nil, nil, Color(1.0, 0.30, 0.07, a))
  end

  -- Warm edge vignette: stacked translucent bands fading inward from each side.
  local th = 6
  for i = 1, 5 do
    local a   = 0.12 * (1 - (i - 1)/5) * intensity
    local off = (i - 1)*th + th/2
    local c   = Color(1.0, 0.48, 0.14, a)
    graphics.rectangle(gw/2,     off,      gw, th, nil, nil, c)
    graphics.rectangle(gw/2,     gh - off, gw, th, nil, nil, c)
    graphics.rectangle(off,      gh/2,     th, gh, nil, nil, c)
    graphics.rectangle(gw - off, gh/2,     th, gh, nil, nil, c)
  end

  -- Flame tongues licking up from the bottom edge: three layered triangles each
  -- (red base, orange mid, yellow core), waving + flickering in height. No dots.
  if self.fire_flames then
    for _, f in ipairs(self.fire_flames) do
      local flick = 0.7 + 0.3*math.sin(time*f.speed + f.seed)
      local sway  = math.sin(time*3 + f.seed)*7
      local h     = f.h * flick * intensity
      local tipx  = f.x + sway
      graphics.polygon({f.x - f.w,      gh, f.x + f.w,      gh, tipx,           gh - h},
                       Color(0.85, 0.15, 0.07, 0.42*intensity))
      graphics.polygon({f.x - f.w*0.62, gh, f.x + f.w*0.62, gh, f.x + sway*0.7, gh - h*0.66},
                       Color(1.0, 0.48, 0.12, 0.44*intensity))
      graphics.polygon({f.x - f.w*0.32, gh, f.x + f.w*0.32, gh, f.x + sway*0.4, gh - h*0.42},
                       Color(1.0, 0.82, 0.24, 0.40*intensity))
    end
  end
end


-- Deep Freeze (timed buff). For its whole duration the arena ices over: no new
-- swarms spawn (spawn_swarm bails on self.frozen), every live brick holds
-- position (Swarm:update gates its drift on self.frozen) and stops acting
-- (Brick:hold_fire + the behaviour casts check self.frozen), and a frost screen
-- overlay + per-brick ice-cube skins render while it lasts. Restoring just
-- clears the flag, so drift / spawns / fire resume on their own at thaw.
function BallPit:apply_freeze_wave()
  local ice = Color(0.85, 0.94, 1.0, 1)

  self:add_or_extend_buff('freeze_wave', 6,        -- seconds of full deep-freeze
    function()
      self.frozen = true
      self:spawn_frost_shards()
    end,
    function()
      self.frozen       = false
      self.frost_shards = nil
    end)

  -- One-shot cast burst, replayed on every catch (even when extending the
  -- timer): a frost flash, two expanding rings, a shake, a sound, and a sparkle
  -- of ice shards on each brick the wave catches.
  Flash{group = self.effects, x = gw/2, y = gh/2,
        color = Color(blue[0].r, blue[0].g, blue[0].b, 0.30), duration = 0.22}
  TelegraphRing{group = self.effects, x = gw/2, y = gh/2,
                radius = math.max(gw, gh)*0.62, color = blue[0], duration = 0.45}
  TelegraphRing{group = self.effects, x = gw/2, y = gh/2,
                radius = math.max(gw, gh)*0.42, color = ice, duration = 0.55}
  camera:shake(4, 0.3, 80)
  if frost1 then frost1:play{volume = 0.5, pitch = random:float(0.7, 0.85)} end

  for _, sw in ipairs(self.swarms.objects) do
    if sw and not sw.dead then
      for _, cell in ipairs(sw.cells or {}) do
        if cell.brick and not cell.brick.dead then
          spawn_burst(self.effects, cell.brick.x, cell.brick.y, ice, 3, 20, 60)
        end
      end
    end
  end
end


-- Pre-roll jagged ice shards rooted on all four screen edges, each pointing
-- INWARD, for draw_frost_overlay. Each stores its base point, the inward normal
-- (nx,ny) + along-edge tangent (tx,ty), a length and half-width. Rolled once on
-- cast (stable, no crawl); the centre is left clear. frost_dur is stashed so the
-- draw can compute the grow-in without a magic number.
function BallPit:spawn_frost_shards()
  self.frost_dur = 6   -- must match the freeze_wave buff duration above
  local list = {}
  -- edge: 1=top 2=bottom 3=left 4=right. n = inward normal, t = along-edge tangent.
  local function add(edge, along, len, halfw)
    local x, y, nx, ny, tx, ty
    if     edge == 1 then x, y, nx, ny, tx, ty = along, 0,   0,  1, 1, 0
    elseif edge == 2 then x, y, nx, ny, tx, ty = along, gh,  0, -1, 1, 0
    elseif edge == 3 then x, y, nx, ny, tx, ty = 0, along,   1,  0, 0, 1
    else                  x, y, nx, ny, tx, ty = gw, along, -1,  0, 0, 1 end
    list[#list + 1] = {x = x, y = y, nx = nx, ny = ny, tx = tx, ty = ty,
                       len = len, halfw = halfw}
  end
  local nh = 12
  for i = 1, nh do
    local along = (i - 0.5)*gw/nh + random:float(-8, 8)
    add(1, along, random:float(20, 48), random:float(5, 11))
    add(2, along, random:float(20, 48), random:float(5, 11))
  end
  local nv = 14
  for i = 1, nv do
    local along = (i - 0.5)*gh/nv + random:float(-8, 8)
    add(3, along, random:float(18, 40), random:float(5, 10))
    add(4, along, random:float(18, 40), random:float(5, 10))
  end
  self.frost_shards = list
end


-- Full-screen frost while the freeze buff is live: a cold blue wash plus jagged
-- ICE SHARDS crystallizing inward from all four screen edges -- no dots. Shards
-- grow in over the first ~0.5s and the whole effect eases out over the final
-- 0.8s (the thaw). Each shard is a filled triangle plus white glint edges.
function BallPit:draw_frost_overlay()
  local b = self.buffs and self.buffs.freeze_wave
  if not b then return end
  local intensity = math.min(1, math.max(0, b.remaining)/0.8)
  local grow      = math.clamp(((self.frost_dur or 6) - b.remaining)/0.5, 0, 1)

  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil,
                     Color(0.52, 0.78, 1.0, 0.14*intensity))

  if self.frost_shards then
    for _, s in ipairs(self.frost_shards) do
      local L = s.len * grow * intensity
      local ax, ay     = s.x - s.tx*s.halfw, s.y - s.ty*s.halfw
      local bx, by     = s.x + s.tx*s.halfw, s.y + s.ty*s.halfw
      local tipx, tipy = s.x + s.nx*L,       s.y + s.ny*L
      graphics.polygon({ax, ay, bx, by, tipx, tipy}, Color(0.82, 0.93, 1.0, 0.55*intensity))
      graphics.line(ax, ay, tipx, tipy, Color(1.0, 1.0, 1.0, 0.50*intensity), 1)
      graphics.line(bx, by, tipx, tipy, Color(0.70, 0.88, 1.0, 0.32*intensity), 1)
    end
  end
end


function BallPit:apply_water_wave()
  local surge_dur    = 0.65
  local disperse_dur = 0.55
  WaterWave{
    group        = self.effects,
    x = (self.x1 + self.x2)/2, y = self.y2,
    x1           = self.x1, x2 = self.x2,
    y_start      = self.y2 - 4,
    y_end        = self.y1 + 8,
    surge_dur    = surge_dur,
    disperse_dur = disperse_dur,
    color        = blue2[0],
  }

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
  self.t:after(surge_dur*0.35, function()
    TelegraphRing{group = self.effects, x = gw/2, y = (self.y1 + self.y2)/2,
                  radius = math.max(gw, gh)*0.45, color = blue2[0], duration = 0.4}
  end)
  self.t:after(surge_dur*0.7, function()
    TelegraphRing{group = self.effects, x = gw/2, y = self.y1 + 24,
                  radius = math.max(gw, gh)*0.35, color = blue[0], duration = 0.4}
  end)
  self.t:after(surge_dur, function()
    camera:shake(3, 0.25, 70)
  end)

  camera:shake(5, 0.35, 80)
  if frost1 then frost1:play{volume = 0.45, pitch = random:float(0.7, 0.85)} end
  if force1 then force1:play{volume = 0.35, pitch = random:float(0.85, 0.95)} end

  -- Slow buff on every live swarm, restored after 10s.
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
  local snapshot = {}
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and not h.is_clone then table.insert(snapshot, h) end
  end
  local clone_cap = 16 - #snapshot
  if clone_cap <= 0 then return end

  local clones = {}
  for i = 1, math.min(clone_cap, #snapshot) do
    local src   = snapshot[i]
    -- no_mirror: Twin Cast must not double the doubles past the cap.
    local hero  = self:add_hero(src.character, {no_mirror = true, clone = true})
    hero.is_clone = true
    hero.level  = src.level
    hero.dmg    = src.dmg
    -- Mark it as a copy and scale it in. is_copy drives the dashed ring that
    -- tells copies apart from the real balls for the whole 12s; begin_copy_in
    -- is the arrival animation (see BallHero:copy_scale).
    hero:begin_copy_in(0.3)
    table.insert(clones, hero)
  end
  -- Wind them down rather than deleting them. The copies used to be killed
  -- outright on this frame -- setActive(false) + dead on the same tick -- so
  -- half a full field blinked out between two frames and read as a bug. Each
  -- copy now collapses over copy_out and removes ITSELF at the end
  -- (BallHero:copy_expire, which also compacts the roster).
  self.t:after(12, function()
    for _, h in ipairs(clones) do
      if h and not h.dead and h.begin_copy_out then h:begin_copy_out(0.45) end
    end
  end)
end


function BallPit:apply_pierce_buff()
  -- Box2D collisions stay ENABLED so the on_collision_enter callback still
  -- fires for damage. The "pass through" effect is achieved in the callback
  -- by restoring the pre-bounce velocity right after the contact resolves.
  self:add_or_extend_buff('pierce', 8,
    function() self.pierce_active = true  end,
    function() self.pierce_active = false end)
end


-- How long the floor stays up. It used to be purely wave-bounded -- torn down in
-- advance_wave and nowhere else -- which on a long wave (and especially the boss
-- wave, which only ends on the boss's death) left the pit sealed for minutes,
-- far longer than any other powerup and with no countdown anywhere to say so.
-- It is a timed buff like the rest now, so it shows in the buff strip and reads
-- honestly; the wave-end teardown stays as a hard cap on top of the timer.
local FLOOR_DUR = 12


-- Tear the temporary bottom wall down. Idempotent -- the buff timer, the wave
-- advance and reset_run can all reach it.
function BallPit:remove_floor()
  if self.floor_wall then self.floor_wall.dead = true end
  self.floor_wall     = nil
  self.no_speed_reset = false
end


function BallPit:apply_floor()
  self:add_or_extend_buff('floor', FLOOR_DUR,
    function()
      local thick = 6
      local cx    = (self.x1 + self.x2)/2
      local cy    = self.y2 + thick/2 + 2
      local w     = self.x2 - self.x1 + thick
      self.floor_wall     = self:spawn_wall(cx, cy, w, thick)
      self.no_speed_reset = true
      TelegraphRing{group = self.effects, x = cx, y = cy, radius = w*0.6, color = yellow2[0], duration = 0.45}
    end,
    function() self:remove_floor() end)
end


function BallPit:apply_level_random(amount)
  local pool = {}
  for _, h in ipairs(self.heroes) do
    if h and not h.dead and (h.level or 1) < 3 then table.insert(pool, h) end
  end
  if #pool == 0 then return end
  -- `amount` is the bounce-earned level count from the powerup (1-5); fall back to
  -- a fresh roll if applied without one (e.g. the admin terminal). Capped by how
  -- many heroes can still take a level so we never promise more than we deliver.
  local n = math.min(#pool, amount or random:int(1, 5))
  for i = 1, n do
    local j = random:int(i, #pool)
    pool[i], pool[j] = pool[j], pool[i]
    local h = pool[i]
    h.level = (h.level or 1) + 1
    h.dmg   = h.dmg * (1 + BAL('globals.level_dmg_growth', 0.4))
    self:flash_hero_level_up(h)
  end
  level_up1:play{volume = 0.4}
end


-- ----- Buff HUD strip -----
--
-- Tucked below the playfield, beneath the Lv/Wave/Time row. The header above
-- the playfield is too cramped to share with the HP/XP bar without the text
-- bleeding into the hearts. Each active buff renders as a coloured pill with
-- its remaining seconds.
function BallPit:draw_buff_strip()
  if not self.buffs then return end
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
