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


-- Ranged variants fire EnemyProjectiles at the paddle. Two rules keep their
-- shots from blanketing the screen:
--   1. Gradual introduction -- one new ranged type per wave starting at wave 3,
--      in RANGED_ORDER below (ordered easiest-to-read pattern first), instead
--      of the old "dump four ranged types in at once at wave 5".
--   2. Low spawn share -- each ranged variant is layered onto the melee/utility
--      base mix at a small weight. The one introduced on the current wave gets
--      a brief spotlight weight so the player notices it; older ones settle to
--      a low maintenance weight.
local RANGED_ORDER      = {'shooter', 'sniper', 'spreader', 'burster', 'arc_lobber', 'spiraler'}
local RANGED_INTRO_WAVE = 3   -- the first ranged variant unlocks on this wave
local RANGED_NEW_WEIGHT = 3   -- weight for the variant introduced this wave (was 5; -40% to thin ranged spawns)
local RANGED_OLD_WEIGHT = 1.2 -- weight for each ranged variant unlocked earlier (was 2; -40%)


-- Appends the ranged variants unlocked by `wave` to `mix` (one new type per
-- wave from RANGED_INTRO_WAVE onward). The just-introduced type gets the
-- spotlight weight; once every type is unlocked nothing is "new" and they all
-- sit at the maintenance weight. No-op before the intro wave.
local function append_ranged(mix, wave)
  local new_idx  = wave - RANGED_INTRO_WAVE + 1      -- index introduced this wave
  local unlocked = math.clamp(new_idx, 0, #RANGED_ORDER)
  for i = 1, unlocked do
    local w = (i == new_idx) and RANGED_NEW_WEIGHT or RANGED_OLD_WEIGHT
    table.insert(mix, {RANGED_ORDER[i], w})
  end
end


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
    drift_speed        = (5 + 0.25*wave)*0.5*((gh - 42)/228),
    -- Vertical breathing room required between a new swarm and any existing
    -- swarm. Starts at 30px (about 2 brick-rows of clear space) and shrinks
    -- to 0 by wave 15, so late-game swarms can stack with no clearance.
    min_swarm_gap      = math.max(0, 30 - 2*wave),
    mix                = mix,
  }
end


-- ULTRAKILL-style combo system. Points come from chaining brick bounces;
-- balls falling into the pit take a heavy penalty. Damage paid out by every
-- brick hit is multiplied by the current rank's multiplier plus a per-ball
-- bounce-count bonus, so the longer you keep a ball alive without dropping
-- it, the harder it hits.
--
-- Rank entries are ordered low → high. `combo_rank_index` walks them from
-- the top so the highest threshold the current points crosses wins.
local COMBO_RANKS = {
  {label = 'D',         threshold =    0, mult = 1.0, color_key = 'fg_alt'},
  {label = 'C',         threshold =   50, mult = 1.2, color_key = 'fg'    },
  {label = 'B',         threshold =  150, mult = 1.5, color_key = 'yellow'},
  {label = 'A',         threshold =  300, mult = 1.9, color_key = 'orange'},
  {label = 'S',         threshold =  500, mult = 2.4, color_key = 'red'   },
  {label = 'SS',        threshold =  750, mult = 3.0, color_key = 'red'   },
  {label = 'SSS',       threshold = 1100, mult = 3.5, color_key = 'red'   },
  {label = 'FRENZY', threshold = 1500, mult = 4.0, color_key = 'purple'},
}

-- Tunables. All point values are absolute (not percentages of current).
local COMBO_PENALTY_MISS     = 150   -- subtract when a ball falls into the pit
local COMBO_BASE_POINTS      = 10    -- baseline per brick bounce
local COMBO_VARIETY_BONUS    = 5     -- + this if hitting a different variant than last
local COMBO_STREAK_BONUS_CAP = 10    -- + min(streak, cap) per bounce
local COMBO_IDLE_GRACE       = 2     -- seconds with no bounces before decay starts
local COMBO_IDLE_DECAY       = 20    -- points/sec subtracted after grace expires
local COMBO_BOUNCE_DMG_STEP  = 0.08  -- +8% damage per bounce on the same ball
local COMBO_BOUNCE_CAP       = 15    -- max bounces counted for damage scaling


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
  self.tutorial_open = false
  self.tutorial_page = 1
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
  local tut_idx = #self.scale_options + 1

  -- Hover priority: scale rows first, then the HOW TO PLAY button below them.
  local hovered = self:settings_option_under_mouse()
  if not hovered and self:tutorial_button_under_mouse() then hovered = tut_idx end
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
    self.settings_selected = math.min(tut_idx, self.settings_selected + 1)
    ui_switch1:play{volume = 0.3}
  end
  if input.confirm.pressed then self:activate_settings_selection() end
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

  -- HOW TO PLAY button: selectable as the row just past the last scale option.
  local tut_on = (self.settings_selected == #self.scale_options + 1)
  graphics.rectangle(gw/2, gh/2 + 60, 200, 16, 3, 3, bg[-1])
  graphics.rectangle(gw/2, gh/2 + 60, 200, 16, 3, 3, tut_on and green[0] or fg_transparent_weak, tut_on and 2 or 1)
  graphics.print_centered('HOW TO PLAY', pixul_font, gw/2, gh/2 + 56, 0, 1, 1, 0, 0, tut_on and green[0] or fg[0])

  graphics.print_centered('arrows or mouse to choose, enter or click to select',
    pixul_font, gw/2, gh/2 + 80, 0, 1, 1, 0, 0, fg_alt[0])
  graphics.print_centered('press ESC to close', pixul_font, gw/2, gh/2 + 92, 0, 1, 1, 0, 0, fg_alt[0])

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


-- ----- Tutorial overlay -----
-- Opened from the ESC settings menu (HOW TO PLAY button) and layered on top
-- of it. A small paged "how to play" guide: each page pairs a few lines of
-- text with a diagram drawn from the same primitives the live game uses, so
-- the visuals match what the player sees in the arena. Gameplay is frozen
-- while it's up, exactly like the settings overlay.

-- Small filled arrowhead pointing 'left' / 'right' / 'up' / 'down'.
local function tut_arrow(x, y, size, dir, color)
  local s = size
  local v
  if dir == 'left' then
    v = {x - s, y, x + s*0.6, y - s, x + s*0.6, y + s}
  elseif dir == 'right' then
    v = {x + s, y, x - s*0.6, y - s, x - s*0.6, y + s}
  elseif dir == 'up' then
    v = {x, y - s, x - s, y + s*0.6, x + s, y + s*0.6}
  else
    v = {x, y + s, x - s, y - s*0.6, x + s, y - s*0.6}
  end
  graphics.polygon(v, color)
end

local TUTORIAL_PAGES = {
  {
    heading = 'CONTROLS',
    visual  = 'controls',
    lines = {
      'A and D slide the paddle, W and S dodge',
      'hold SPACE to aim, release to launch',
      'LEFT and RIGHT arrows fine-tune the aim',
    },
  },
  {
    heading = 'BREAK THE BLOCKS',
    visual  = 'bricks',
    lines = {
      'enemy blocks drift down from the top',
      'bounce ball-heroes into them to break them',
      'if a block reaches the paddle you lose a heart',
    },
  },
  {
    heading = 'COLLECT XP',
    visual  = 'xp',
    lines = {
      'broken blocks drop XP orbs - sweep them up',
      'fill the bar to level up and draft a hero',
      'more heroes means more balls in play',
    },
  },
  {
    heading = 'COMBO METER',
    visual  = 'combo',
    lines = {
      'chain block hits to climb the rank ladder',
      'higher rank means a bigger damage bonus',
      'dropping a ball in the pit resets the streak',
    },
  },
  {
    heading = 'POWERUPS',
    visual  = 'powerups',
    lines = {
      'catch falling powerups for buffs',
      'glowing orbs - bounce once, then catch',
      'survive the waves - wave 10 is the BOSS',
    },
  },
}

-- Shared geometry for the tutorial nav arrows, used by both the hit-test and
-- the draw so they stay aligned. cy matches the diagram panel centre below.
local TUT_PANEL_CY = 210
local TUT_ARROW_X  = 52


function BallPit:activate_settings_selection()
  if self.settings_selected == #self.scale_options + 1 then
    self:open_tutorial()
  else
    self:apply_scale_option(self.settings_selected)
  end
end


function BallPit:open_tutorial()
  self.tutorial_open = true
  self.tutorial_page = 1
  confirm1:play{volume = 0.4}
end


function BallPit:tutorial_button_under_mouse()
  local bx, by, bw, bh = gw/2, gh/2 + 60, 200, 16
  return mouse.x >= bx - bw/2 and mouse.x <= bx + bw/2
     and mouse.y >= by - bh/2 and mouse.y <= by + bh/2
end


function BallPit:tutorial_arrow_under_mouse()
  if self.tutorial_page > 1
     and math.distance(mouse.x, mouse.y, TUT_ARROW_X, TUT_PANEL_CY) <= 18 then
    return 'prev'
  end
  if self.tutorial_page < #TUTORIAL_PAGES
     and math.distance(mouse.x, mouse.y, gw - TUT_ARROW_X, TUT_PANEL_CY) <= 18 then
    return 'next'
  end
  return nil
end


function BallPit:tutorial_set_page(p)
  p = math.clamp(p, 1, #TUTORIAL_PAGES)
  if p ~= self.tutorial_page then
    self.tutorial_page = p
    ui_switch1:play{volume = 0.3}
  end
end


function BallPit:update_tutorial(dt)
  local n = #TUTORIAL_PAGES

  -- ESC backs out to the settings menu it was opened from.
  if input.escape.pressed then
    self.tutorial_open = false
    ui_switch1:play{volume = 0.3}
    return
  end

  -- Mouse: click the side arrows to page through.
  local hovered = self:tutorial_arrow_under_mouse()
  if hovered and input.click.pressed then
    self:tutorial_set_page(self.tutorial_page + (hovered == 'next' and 1 or -1))
  end

  -- Keyboard: left/right page; SPACE or ENTER advances, and closes the
  -- tutorial once it's stepped past the final page.
  if input.aim_left.pressed or input.move_left.pressed then
    self:tutorial_set_page(self.tutorial_page - 1)
  end
  if input.aim_right.pressed or input.move_right.pressed then
    self:tutorial_set_page(self.tutorial_page + 1)
  end
  if input.launch.pressed or input.confirm.pressed then
    if self.tutorial_page < n then
      self:tutorial_set_page(self.tutorial_page + 1)
    else
      self.tutorial_open = false
      ui_switch1:play{volume = 0.3}
    end
  end
end


function BallPit:draw_tutorial()
  local n    = #TUTORIAL_PAGES
  local page = TUTORIAL_PAGES[self.tutorial_page]

  -- Near-opaque backdrop so the frozen arena behind doesn't distract.
  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0.04, 0.04, 0.08, 0.93))

  graphics.print_centered('HOW TO PLAY', fat_font, gw/2, 50, 0, 1.4, 1.4, 0, 0, yellow[0])
  graphics.print_centered(page.heading, pixul_font, gw/2, 72, 0, 1, 1, 0, 0, fg[0])

  -- Diagram panel.
  local cx, cy, pw, ph = gw/2, TUT_PANEL_CY, 304, 200
  graphics.rectangle(cx, cy, pw, ph, 4, 4, bg[-2])
  graphics.rectangle(cx, cy, pw, ph, 4, 4, fg_transparent_weak, 1)
  self:draw_tutorial_diagram(page.visual, cx, cy, pw, ph)

  -- Body text under the panel.
  for i, line in ipairs(page.lines) do
    graphics.print_centered(line, pixul_font, gw/2, 338 + (i-1)*18, 0, 1, 1, 0, 0, fg_alt[0])
  end

  -- Prev / next arrows, hidden at the ends.
  local hovered = self:tutorial_arrow_under_mouse()
  if self.tutorial_page > 1 then
    tut_arrow(TUT_ARROW_X, cy, 12, 'left', hovered == 'prev' and yellow[0] or fg[0])
  end
  if self.tutorial_page < n then
    tut_arrow(gw - TUT_ARROW_X, cy, 12, 'right', hovered == 'next' and yellow[0] or fg[0])
  end

  -- Page dots.
  for i = 1, n do
    local dx = gw/2 - (n-1)*7/2 + (i-1)*7
    graphics.circle(dx, 410, 2.5, i == self.tutorial_page and yellow[0] or bg[3])
  end

  -- Footer hint.
  local tip = (self.tutorial_page < n)
    and 'SPACE or arrows to navigate   -   ESC to close'
    or  'SPACE to finish   -   ESC to close'
  graphics.print_centered(tip, pixul_font, gw/2, 444, 0, 1, 1, 0, 0, fg_alt[0])
end


-- Each branch draws a small illustration centred in the panel (cx, cy) with
-- half-extents up to ~100px, using the same shapes/colors as the real game.
function BallPit:draw_tutorial_diagram(tag, cx, cy, w, h)
  if tag == 'controls' then
    local pad_y = cy + 46
    -- aim line up-left from the stuck ball
    graphics.dashed_line(cx, pad_y - 8, cx - 46, cy - 54, 4, 3, fg_transparent, 1)
    graphics.circle(cx - 46, cy - 54, 2, fg[0])
    -- paddle + a ball stuck on it, ready to launch
    graphics.rectangle(cx, pad_y, 46, 5, 2, 2, fg[0])
    graphics.rectangle(cx, pad_y - 2.5, 46, 1, nil, nil, fg[5])
    graphics.circle(cx, pad_y - 8, 5, yellow[0])
    graphics.circle(cx - 1.6, pad_y - 9.6, 1.6, fg[5])
    -- A / D horizontal movement
    tut_arrow(cx - 80, pad_y, 7, 'left', fg[0])
    graphics.print_centered('A', pixul_font, cx - 64, pad_y, 0, 1, 1, 0, 0, fg[0])
    tut_arrow(cx + 80, pad_y, 7, 'right', fg[0])
    graphics.print_centered('D', pixul_font, cx + 64, pad_y, 0, 1, 1, 0, 0, fg[0])
    -- W / S vertical dodge, set up-right so it clears the aim line
    tut_arrow(cx + 74, cy - 40, 6, 'up', fg_alt[0])
    tut_arrow(cx + 74, cy - 8, 6, 'down', fg_alt[0])
    graphics.dashed_line(cx + 74, cy - 32, cx + 74, cy - 16, 3, 3, fg_alt_transparent, 1)
    graphics.print_centered('W S', pixul_font, cx + 98, cy - 24, 0, 1, 1, 0, 0, fg_alt[0])

  elseif tag == 'bricks' then
    -- a row of enemy blocks near the top, one mid-break
    local cols = {red[0], orange[0], blue[0], green[0]}
    local by = cy - 56
    for i = 1, 4 do
      local bx = cx - 33 + (i - 1)*22
      if i == 2 then
        graphics.rectangle(bx, by, 18, 10, 2, 2, Color(cols[i].r, cols[i].g, cols[i].b, 0.35))
        for a = 0, 5 do
          local ang = a*math.pi/3
          graphics.line(bx + math.cos(ang)*7, by + math.sin(ang)*7,
                        bx + math.cos(ang)*12, by + math.sin(ang)*12, cols[i], 1)
        end
      else
        graphics.rectangle(bx, by, 18, 10, 2, 2, cols[i])
        graphics.rectangle(bx, by - 4, 18, 2, nil, nil, fg[5])
      end
    end
    -- drift-down hint arrows above the row
    for i = 0, 2 do
      tut_arrow(cx - 22 + i*22, by - 18, 5, 'down', fg_alt_transparent)
    end
    -- paddle + ball trajectory bouncing up into the breaking block
    local pad_y = cy + 64
    graphics.rectangle(cx, pad_y, 40, 5, 2, 2, fg[0])
    graphics.dashed_line(cx, pad_y - 4, cx + 34, cy + 6, 4, 3, fg_transparent, 1)
    graphics.dashed_line(cx + 34, cy + 6, cx - 11, by + 6, 4, 3, fg_transparent, 1)
    graphics.circle(cx + 34, cy + 6, 4, yellow[0])
    graphics.circle(cx + 34 - 1.3, cy + 6 - 1.3, 1.3, fg[5])

  elseif tag == 'xp' then
    -- a just-broken block at the top
    graphics.rectangle(cx, cy - 60, 18, 10, 2, 2, Color(red[0].r, red[0].g, red[0].b, 0.3))
    -- three XP orbs (blue / green / yellow, matching the in-game tiers)
    local orbs = {{cx - 22, cy - 34, 3,   blue[0]},
                  {cx,      cy - 28, 3.5, green[0]},
                  {cx + 22, cy - 38, 4,   yellow[0]}}
    local pad_y = cy + 52
    for _, o in ipairs(orbs) do
      graphics.dashed_line(o[1], o[2], cx, pad_y - 6, 3, 4, fg_alt_transparent, 1)
    end
    for _, o in ipairs(orbs) do
      graphics.circle(o[1], o[2], o[3] + 0.5, bg[-2])
      graphics.circle(o[1], o[2], o[3], o[4])
      graphics.circle(o[1] - o[3]*0.3, o[2] - o[3]*0.3, math.max(0.5, o[3]*0.3), fg[5])
    end
    -- paddle sweeping the orbs in
    graphics.rectangle(cx, pad_y, 40, 5, 2, 2, fg[0])
    -- XP bar filling toward a level
    local barw = 150
    graphics.rectangle(cx, cy + 70, barw, 5, nil, nil, bg[-2])
    graphics.rectangle(cx - barw/2 + barw*0.62/2, cy + 70, barw*0.62, 5, nil, nil, blue[0])
    graphics.print_centered('XP', pixul_font, cx - barw/2 - 10, cy + 70, 0, 1, 1, 0, 0, fg_alt[0])

  elseif tag == 'combo' then
    -- big rank readout, styled like the live combo meter
    graphics.print_centered('S', fat_font, cx - 26, cy - 44, 0, 2.2, 2.2, 0, 0, red[0])
    graphics.print_centered('x2.4', pixul_font, cx + 18, cy - 44, 0, 1, 1, 0, 0, red[0])
    local barw = 90
    graphics.rectangle(cx, cy - 24, barw, 3, nil, nil, bg[-2])
    graphics.rectangle(cx - barw/2 + barw*0.7/2, cy - 24, barw*0.7, 3, nil, nil, red[0])
    graphics.print_centered('D  C  B  A  S  SS  SSS', pixul_font, cx, cy - 8, 0, 0.85, 0.85, 0, 0, fg_alt[0])
    -- a chain of bounces among three blocks
    local pts = {{cx - 56, cy + 46}, {cx - 14, cy + 22}, {cx + 30, cy + 48}, {cx + 60, cy + 24}}
    for i = 1, #pts - 1 do
      graphics.dashed_line(pts[i][1], pts[i][2], pts[i+1][1], pts[i+1][2], 4, 3, yellow_transparent, 1)
    end
    local blk = {{cx - 14, cy + 22, orange[0]}, {cx + 30, cy + 48, blue[0]}, {cx + 60, cy + 24, green[0]}}
    for _, b in ipairs(blk) do graphics.rectangle(b[1], b[2], 16, 9, 2, 2, b[3]) end
    graphics.circle(pts[1][1], pts[1][2], 4, yellow[0])

  elseif tag == 'powerups' then
    -- left: a tier-2 powerup that must be deflected, then caught
    local ox, oy = cx - 66, cy - 26
    graphics.circle(ox, oy, 11, Color(green[0].r, green[0].g, green[0].b, 0.3))
    graphics.circle(ox, oy, 9, green[0])
    graphics.circle(ox, oy, 11, green[0], 1)
    graphics.print_centered('M', pixul_font, ox, oy, 0, 1, 1, 0, 0, bg[-2])
    local pdy = cy + 30
    graphics.rectangle(ox, pdy, 32, 5, 2, 2, fg[0])
    tut_arrow(ox, (oy + pdy)/2, 6, 'up', green[0])
    graphics.print_centered('bounce', pixul_font, ox, pdy + 14, 0, 0.85, 0.85, 0, 0, fg_alt[0])
    graphics.print_centered('then catch', pixul_font, ox, pdy + 24, 0, 0.85, 0.85, 0, 0, fg_alt[0])
    -- right: the boss
    local bx2, by2 = cx + 66, cy - 16
    graphics.rectangle(bx2, by2, 48, 34, 6, 6, purple[0])
    graphics.rectangle(bx2, by2, 48, 34, 6, 6, purple[5], 1)
    graphics.circle(bx2 - 10, by2 - 4, 3, red[0])
    graphics.circle(bx2 + 10, by2 - 4, 3, red[0])
    graphics.rectangle(bx2, by2 + 9, 22, 3, 1, 1, red_transparent)
    graphics.print_centered('BOSS - wave 10', pixul_font, bx2, by2 + 34, 0, 0.9, 0.9, 0, 0, red[0])
  end
end


function BallPit:on_enter()
  self:reset_run()
  -- Play a random Kubbi - Ember track on loop. Stop any previous instance so
  -- restarts don't stack tracks on top of each other.
  if self.song_instance then self.song_instance:stop() end
  local pick = random:table{song1, song2, song3, song4, song5}
  self.song_instance = pick:play{volume = 0.45, loop = true}
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
    paddle_skin = ({mitosis = 'mitosis', boomerang = 'boomerang'})[pdef.signature],
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
  self.run_kills     = 0
  self.xp            = 0
  self.level         = 1
  self.xp_to_next    = (pdef.xp_mode == 'flat') and PADDLES.XP_FLAT or 5
  self.wave          = 1
  self.wave_time     = 0
  self.boss          = nil
  self.boss_defeated = false
  -- Set while wave 9 has elapsed but the arena still has live blocks; holds the
  -- boss wave from starting until everything is cleared (see BallPit:update).
  self.awaiting_boss = false
  self.score         = 0
  -- Combo state. Persists across paddle bounces — only a ball falling into
  -- the pit (or extended idle time) reduces points. `streak` counts
  -- consecutive brick bounces across all balls; `last_variant` drives the
  -- variety bonus.
  self.combo = {
    points        = 0,
    streak        = 0,
    idle_t        = 0,
    last_variant  = nil,
    bounces_total = 0,
  }
  self.run_time      = 0
  self.paused        = false
  self.game_over     = false
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
  self.powerup_pity = {
    timer          = 0,
    check_interval = 6,
    streak         = 0,
    base_chance    = 0.25,
    pity_step      = 0.20,
    tier2_chance   = 0.20,
  }

  -- The level-up ball ('level_random') spawns on its OWN timer, fully separate
  -- from the powerup pity roll above (and excluded from those pools via the
  -- `solo` flag in Powerup.KINDS). It drops on a randomized fixed-ish interval
  -- rather than the chance/streak model the regular powerups use.
  self.levelup_pity = {
    timer   = 0,
    next_at = random:float(20, 30),   -- first level-up ball lands ~20-30s in
  }

  -- One-time signature setup for the selected paddle loadout (aegis bottom
  -- wall, mitosis regrow timer, phantom/tesla state). See paddles.lua.
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
  -- Twin Cast loadout: every drafted hero arrives mirrored as a pair.
  if self.run_mods and self.run_mods.signature == 'twincast'
  and not opts.no_mirror and not opts.clone then
    self:add_hero(character, {no_mirror = true})
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

  -- The floor powerup lasts until the next wave starts. Tear down the
  -- temporary bottom wall and clear the flag here so the player has to
  -- re-earn the floor each wave.
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
  self.t:update(dt)

  -- ESC toggles the settings overlay at any time (including from game-over
  -- and the level-up upgrade screen). While open, all other game updates
  -- are frozen.
  -- The how-to-play overlay opens from the settings menu and layers on top of
  -- it. Handle it before the ESC toggle below so its own ESC backs out to the
  -- settings menu instead of flipping the whole settings overlay off.
  if self.tutorial_open then
    self:update_tutorial(dt)
    return
  end

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
    if input.restart.pressed then self:reset_run() end
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
  end

  -- Phantom loadout: E drops a ghost-paddle anchor / teleports back to it.
  if self.run_mods and self.run_mods.signature == 'phantom' and input.blink.pressed then
    self:phantom_blink()
  end

  -- Aim is adjustable whenever space is held OR a ball is stuck on the paddle.
  -- Holding space is the "auto-fire" mode: the aim line shows, arrow keys
  -- nudge the angle, and any stuck ball fires immediately (returning balls
  -- skip the stuck state entirely, see BallHero:update_return).
  local aim_active = self.stuck_count > 0 or input.launch.down
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


function BallPit:draw()
  self.floor:draw()
  self.main:draw()
  self.effects:draw()
  if self.frozen then self:draw_frost_overlay() end
  if self.fire_active then self:draw_fire_overlay() end
  if self.stuck_count > 0 or input.launch.down then self:draw_aim_line() end
  self.ui:draw()
  self:draw_hud()
  self:draw_buff_strip()

  if self.upgrade_pending then self:draw_upgrade() end
  if self.game_over then self:draw_game_over() end
  if self.settings_open and not self.tutorial_open then self:draw_settings() end
  if self.tutorial_open then self:draw_tutorial() end
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


function BallPit:draw_hud()
  -- Frame around playfield.
  graphics.rectangle((self.x1 + self.x2)/2, (self.y1 + self.y2)/2,
    self.x2 - self.x1, self.y2 - self.y1, 2, 2, fg_transparent_weak, 1)

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
    local hbw, hbh = 64, 6
    local hbx = self.x1 + 6
    graphics.rectangle(hbx + hbw/2, self.y1 - 8, hbw, hbh, 1, 1, bg[-2])
    local hpct = math.clamp(self.player_hp/self.player_hp_max, 0, 1)
    if hpct > 0 then
      graphics.rectangle(hbx + hbw*hpct/2, self.y1 - 8, hbw*hpct, hbh, 1, 1, red[0])
    end
  else
    for i = 1, self.player_hp_max do
      local color = i <= self.player_hp and red[0] or bg[2]
      graphics.rectangle(self.x1 + 6 + (i-1)*10, self.y1 - 8, 6, 6, 1, 1, color)
    end
  end

  -- XP bar. Starts past however wide the HP readout is (Aegis runs 7 hearts)
  -- and leaves a ~70px strip on the right for the combo meter.
  local bx = hp_bar_mode and (self.x1 + 80) or (self.x1 + 20 + self.player_hp_max*10)
  local bw = (self.x2 - 80) - bx
  graphics.rectangle(bx + bw/2, self.y1 - 8, bw, 4, nil, nil, bg[-2])
  local pct = math.clamp(self.xp/self.xp_to_next, 0, 1)
  if pct > 0 then
    graphics.rectangle(bx + bw*pct/2, self.y1 - 8, bw*pct, 4, nil, nil, blue[0])
  end

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
    -- Vampire lifesteal: kills refill the draining bar.
    if mods.hp_mode == 'bar' then
      self.player_hp = math.min(self.player_hp_max,
                                self.player_hp + (mods.sig.heal_per_kill or 3))
    end
    -- Mitosis: each kill splits off a short-lived clone ball.
    if mods.signature == 'mitosis' then self:mitosis_on_kill() end
  end
end


-- ----- Combo meter -----

function BallPit:combo_rank_index()
  local idx = 1
  for i = #COMBO_RANKS, 1, -1 do
    if self.combo.points >= COMBO_RANKS[i].threshold then
      idx = i
      break
    end
  end
  return idx
end


function BallPit:combo_mult()
  return COMBO_RANKS[self:combo_rank_index()].mult
end


-- Per-ball bounce damage scaling. Capped so a single perfectly-chained ball
-- can't trivialise a wave on its own. Combines multiplicatively with the
-- combo multiplier in Brick:on_ball_contact.
function BallPit:bounce_dmg_mult(bounces)
  local n = math.min(bounces or 0, COMBO_BOUNCE_CAP)
  return 1 + n*COMBO_BOUNCE_DMG_STEP
end


-- Called from Brick:on_ball_contact after damage is applied. Awards points
-- with a small variety + streak bonus and triggers the rank-up SFX/shake if
-- a threshold was crossed. Points are read off the combo meter HUD -- there's
-- deliberately no per-bounce floating "+N" anymore.
function BallPit:on_brick_bounce(ball, brick)
  local c = self.combo
  if not c then return end
  c.idle_t = 0
  local prev_idx = self:combo_rank_index()

  c.streak = (c.streak or 0) + 1
  local streak_bonus  = math.min(c.streak, COMBO_STREAK_BONUS_CAP)
  local variety_bonus = 0
  if brick.variant_name and c.last_variant and brick.variant_name ~= c.last_variant then
    variety_bonus = COMBO_VARIETY_BONUS
  end
  c.last_variant  = brick.variant_name or c.last_variant
  c.bounces_total = c.bounces_total + 1
  -- The loadout's Combo stat scales gain AND bleed (see on_ball_missed /
  -- tick_combo) — high-combo paddles run a hotter, riskier meter.
  local cm = (self.run_mods and self.run_mods.combo) or 1
  local gained = (COMBO_BASE_POINTS + streak_bonus + variety_bonus)*cm
  c.points = c.points + gained

  local new_idx = self:combo_rank_index()
  if new_idx > prev_idx then self:on_combo_rank_up(new_idx) end
end


-- Rank advancement feedback: a level-up SFX (pitched up per rank) plus a
-- small camera shake at higher ranks for that ULTRAKILL "you're cooking"
-- feeling. The centre-screen flash and big floating rank letter were removed
-- as too bright/noisy -- the combo meter HUD (draw_combo_meter) is the only
-- persistent rank readout now.
function BallPit:on_combo_rank_up(new_idx)
  if level_up1 then
    level_up1:play{volume = 0.35, pitch = 0.85 + new_idx*0.06}
  end
  if new_idx >= 5 then camera:shake(2 + new_idx*0.4, 0.2, 80) end
end


-- Called from BallHero:start_return — a ball just fell into the pit. Wipes
-- the streak and subtracts a flat penalty. If the penalty drops the rank,
-- adds a small shake so the demotion isn't silent.
function BallPit:on_ball_missed(ball)
  local c = self.combo
  if not c or c.points <= 0 then return end
  local prev_idx = self:combo_rank_index()
  local cm = (self.run_mods and self.run_mods.combo) or 1
  c.points       = math.max(0, c.points - COMBO_PENALTY_MISS*cm)
  c.streak       = 0
  c.last_variant = nil

  if self:combo_rank_index() < prev_idx then
    camera:shake(2, 0.15, 80)
  end
end


function BallPit:tick_combo(dt)
  local c = self.combo
  if not c then return end
  c.idle_t = c.idle_t + dt
  if c.idle_t > COMBO_IDLE_GRACE and c.points > 0 then
    local cm = (self.run_mods and self.run_mods.combo) or 1
    c.points = math.max(0, c.points - COMBO_IDLE_DECAY*cm*dt)
    if c.points <= 0 then
      c.streak       = 0
      c.last_variant = nil
    end
  end
end


-- Compact HUD at the top-right of the canvas, sharing the strip with the
-- HP hearts (left) and XP bar (middle). Rendered by draw_hud.
function BallPit:draw_combo_meter()
  local c    = self.combo
  if not c then return end
  local idx  = self:combo_rank_index()
  local rank = COMBO_RANKS[idx]
  local col  = _G[rank.color_key][0]

  -- Anchor the meter just inside the right edge of the canvas. Width is
  -- reserved by shrinking the XP bar in draw_hud.
  local cx = self.x2 - 32
  local cy = self.y1 - 10

  -- Rank letter pulses subtly on S+ to give the meter some "life" at the
  -- top of the ladder.
  local scale = (idx >= 5) and (1 + 0.08*math.sin(love.timer.getTime()*8)) or 1
  graphics.print_centered(rank.label, fat_font, cx, cy, 0, scale, scale, 0, 0, col)

  -- Multiplier label sits to the right of the rank letter.
  graphics.print_centered(string.format('x%.1f', rank.mult), pixul_font,
                          cx + 22, cy, 0, 1, 1, 0, 0, col)

  -- Progress bar to the next rank (full at ULTRAKILL).
  local bar_w = 56
  local bar_y = cy + 6
  graphics.rectangle(cx + 4, bar_y, bar_w, 2, nil, nil, bg[-2])
  local pct
  if idx == #COMBO_RANKS then
    pct = 1
  else
    local next_t = COMBO_RANKS[idx + 1].threshold
    local prev_t = rank.threshold
    pct = math.clamp((c.points - prev_t) / (next_t - prev_t), 0, 1)
  end
  if pct > 0 then
    graphics.rectangle(cx + 4 - bar_w/2 + bar_w*pct/2, bar_y,
                       bar_w*pct, 2, nil, nil, col)
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
function BallPit:on_row_breached(swarm, brick_count)
  local dmg = math.min(3, 1 + math.floor(brick_count/4))
  self:damage_player(dmg)
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
  -- The loadout's XP stat scales every gain (rounded, never below 1).
  amount = math.max(1, math.floor(amount*((self.run_mods and self.run_mods.xp) or 1) + 0.5))
  self.xp = self.xp + amount
  FloatingText{group = self.effects, x = self.paddle.x, y = self.paddle.y - 16, text = '+' .. amount, color = blue[0]}
  while self.xp >= self.xp_to_next do
    self.xp = self.xp - self.xp_to_next
    self:level_up()
  end
end


function BallPit:level_up()
  self.level = self.level + 1
  -- Terrorist loadout: FLAT XP — every level costs the same, so the curve
  -- never runs away from you (slow opener, out-levels hard late).
  if not (self.run_mods and self.run_mods.xp_mode == 'flat') then
    self.xp_to_next = math.floor(self.xp_to_next * 1.35 + 1)
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
    -- Twin Cast: heroes come in mirrored pairs, so a level-up pick levels two
    -- matching balls instead of one.
    local to_level = (self.run_mods and self.run_mods.signature == 'twincast') and 2 or 1
    for _, h in ipairs(self.heroes) do
      if h.character == choice.character and h.level < 3 then
        h.level = h.level + 1
        h.dmg = h.dmg * 1.4
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
    archer       = 'skewer bolt',

    -- Knives
    scout        = 'chaining knife',
    assassin     = 'fast pierce',

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

    -- Ally damage buffs
    stormweaver  = '+50% ally dmg',

    -- Pet summons
    infestor     = '3 pets / 10s',

    -- Misc
    gambler      = 'lucky strikes',

    -- Volcano
    vulcanist    = 'plants volcano',

    -- On-bounce specials
    wizard       = 'chain on hit',
    cryomancer   = 'freeze on hit',
    pyromancer   = 'burn on hit',
    cannoneer    = 'boom on hit',
  }
  return blurbs[c] or 'ball-hero'
end


function BallPit:trigger_game_over()
  self.game_over = true
  self.t:cancel('spawn_brick')
  Flash{group = self.effects, x = gw/2, y = gh/2, color = Color(0, 0, 0, 0.4), duration = 0.4}
  -- Bank the run's kills to disk and open the paddle shop on the equipped
  -- card (the game-over overlay IS the shop — see paddles.lua).
  PADDLES.ensure_state()
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
        chain  = opts.chain or 0,
        chain_dmg_ramp = opts.chain_dmg_ramp,
        wall_stick = opts.wall_stick,
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
--   2. Timed buff (wide_paddle, big_ball, fire_trail, freeze_wave, pierce, multi_ball):
--      stashed in self.buffs[kind] with a `remaining` + `restore` pair;
--      tick_buffs counts down and calls restore on expiry. Stacking the same
--      buff while it's active extends the timer instead of stacking the
--      multiplier.
--   3. Wave-bounded (floor): cleared in advance_wave / reset_run, no timer.


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
  p.next_at = random:float(24, 36)   -- gap until the next level-up ball
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
      function() p:build_flipper_rig(1.6) end,
      function() p:build_flipper_rig(1) end)
    return
  end
  self:add_or_extend_buff('wide_paddle', 15,
    function()
      p._orig_w = p._orig_w or p.w
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
    table.insert(clones, hero)
  end
  self.t:after(12, function()
    for _, h in ipairs(clones) do
      if h and not h.dead then
        if h.body then h.body:setActive(false) end
        h.dead = true
      end
    end
    for i = #self.heroes, 1, -1 do
      if self.heroes[i] and self.heroes[i].dead then
        table.remove(self.heroes, i)
      end
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


function BallPit:apply_floor()
  if self.floor_wall then return end
  local thick = 6
  local cx    = (self.x1 + self.x2)/2
  local cy    = self.y2 + thick/2 + 2
  local w     = self.x2 - self.x1 + thick
  self.floor_wall      = self:spawn_wall(cx, cy, w, thick)
  self.no_speed_reset  = true
  TelegraphRing{group = self.effects, x = cx, y = cy, radius = w*0.6, color = yellow2[0], duration = 0.45}
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
    h.dmg   = h.dmg * 1.4
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
