-- A small helper that builds a Color with several lighter/darker variants
-- indexed from -10 .. 10. ramp[0] is the base color, ramp[-2] is darker,
-- ramp[5] is lighter, etc.
ColorRamp = Object:extend()
function ColorRamp:init(color, step)
  self.color = color
  self.step  = step or 0.025
  for i = -10, 10 do
    self[i] = self.color:clone():lighten(i*self.step)
  end
end


-- Initializes color palette, fonts and canvases used across BallPitX.
function shared_init()
  local palette = {
    white   = ColorRamp(Color(1, 1, 1, 1), 0.025),
    black   = ColorRamp(Color(0, 0, 0, 1), 0.025),
    bg      = ColorRamp(Color'#0c0c14', 0.025),
    fg      = ColorRamp(Color'#dadada', 0.025),
    fg_alt  = ColorRamp(Color'#b0a89f', 0.025),
    yellow  = ColorRamp(Color'#facf00', 0.025),
    orange  = ColorRamp(Color'#f07021', 0.025),
    blue    = ColorRamp(Color'#019bd6', 0.025),
    green   = ColorRamp(Color'#8bbf40', 0.025),
    red     = ColorRamp(Color'#e91d39', 0.025),
    purple  = ColorRamp(Color'#8e559e', 0.025),
    blue2   = ColorRamp(Color'#4778ba', 0.025),
    yellow2 = ColorRamp(Color'#f59f10', 0.025),
  }
  for name, color in pairs(palette) do
    _G[name] = color
    _G[name .. '_transparent']      = Color(color[0].r, color[0].g, color[0].b, 0.5)
    _G[name .. '_transparent_weak'] = Color(color[0].r, color[0].g, color[0].b, 0.25)
  end

  graphics.set_background_color(bg[0])
  graphics.set_color(fg[0])
  slow_amount = 1

  sfx = SoundTag()
  sfx.volume = 0.5
  music = SoundTag()
  music.volume = 0.4

  fat_font   = Font('FatPixelFont', 8)
  pixul_font = Font('PixulBrush', 8)

  background_canvas = Canvas(gw, gh)
  main_canvas       = Canvas(gw, gh, {stencil = true})
  shadow_canvas     = Canvas(gw, gh)
  shadow_shader     = Shader(nil, 'shadow.frag')

  -- Color lookup table — full hero roster. Used by BallHero:init to set ball
  -- tint and by BallPit:count_same_color_heroes for shade variation.
  character_colors = {
    vagrant     = fg[0],     swordsman   = yellow[0],  wizard      = blue[0],
    archer      = green[0],  scout       = red[0],     cleric      = green[0],
    bomber      = orange[0], stormweaver = blue[0],    cannoneer   = orange[0],
    spellblade  = blue[0],   engineer    = orange[0],  barbarian   = yellow[0],
    cryomancer  = blue[0],   pyromancer  = red[0],     jester      = red[0],
    assassin    = purple[0], psykino     = fg[0],      infestor    = orange[0],
    witch       = purple[0], gambler     = yellow2[0],
  }

  -- Draft pool: 20 balls, trimmed from the full 57-archetype SNKRX roster so
  -- every pick has a distinct effect. Includes every paddle loadout's
  -- starting heroes (paddles.lua start_balls) — those must stay in sync.
  hero_pool = {
    'vagrant', 'swordsman', 'wizard', 'archer', 'scout', 'cleric',
    'bomber', 'stormweaver', 'cannoneer', 'spellblade', 'engineer',
    'barbarian', 'cryomancer', 'pyromancer', 'jester', 'assassin',
    'psykino', 'infestor', 'witch', 'gambler',
  }
end


function shared_draw(draw_action)
  background_canvas:draw_to(function()
    graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, bg[0])
    -- Tiled background grid. Cell counts derive from gw/gh so the grid
    -- always covers the canvas if the game dimensions change.
    local cols = math.ceil(gw/15)
    local rows = math.ceil(gh/15)
    for i = 0, cols do
      for j = 0, rows do
        if (i + j) % 2 == 0 then
          graphics.rectangle2(i*15, j*15, 15, 15, nil, nil, bg[-1])
        end
      end
    end
  end)

  main_canvas:draw_to(function()
    draw_action()
  end)

  shadow_canvas:draw_to(function()
    graphics.set_color(white[0])
    shadow_shader:set()
    main_canvas:draw2(0, 0, 0, 1, 1)
    shadow_shader:unset()
  end)

  background_canvas:draw(0, 0, 0, sx, sy)
  shadow_canvas:draw(1.5*sx, 1.5*sy, 0, sx, sy)
  main_canvas:draw(0, 0, 0, sx, sy)
end
