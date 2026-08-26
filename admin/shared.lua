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


-- ----- Enemy feedback knobs -------------------------------------------------
--
-- Enemy feedback is qualitatively different from the player's: it is CONSTANT
-- and it comes from many bodies at once -- a late wave can field a dozen
-- shooters plus a headbutting rank -- so per-event juice tuned at the strength
-- the player's one-at-a-time abilities use stacks into a permanent tremor and a
-- wall of noise instead of reading as individual impacts. The player's own hits
-- deliberately keep their full punch; that is the payoff.
--
-- Both helpers take each call site's ORIGINAL, unscaled values, so the relative
-- weight and character of every enemy event stays intact (a sniper's crack still
-- differs from a lobber's thump) and the numbers still document intent. Tune the
-- four constants to move all enemy shake / all enemy fire together.

ENEMY_SHAKE_MULT      = 0.5    -- amplitude scale
ENEMY_SHAKE_DUR_MULT  = 0.75   -- duration scale (a long weak shake is a tremor)
ENEMY_SFX_VOL_MULT    = 0.45   -- quieter
ENEMY_SFX_PITCH_MULT  = 0.78   -- and pitched down, which is what reads as muted
-- Weapon FIRE takes a further cut on top of the shared scale. It is by far the
-- most repeated enemy sound -- 14 of the ~23 enemy call sites, and a late wave
-- fires several per second from many bodies at once -- so the shot sample has to
-- sit lower than one-off casts and deaths or it becomes the bed of the whole mix
-- rather than an event in it. Casts/deaths keep the shared level above.
ENEMY_SHOT_VOL_MULT   = 0.45

-- Screen shake from an enemy source: their bullets landing, their casts, their
-- death effects.
function enemy_shake(amount, duration, frequency)
  camera:shake((amount or 2)*ENEMY_SHAKE_MULT,
               (duration or 0.2)*ENEMY_SHAKE_DUR_MULT, frequency)
end

-- ANY sound an enemy makes: weapon fire, ability casts, deaths. Same treatment
-- for all of them -- different enemies doing different things all contribute to
-- the same wall of noise, so they share one pair of knobs.
function enemy_fx_sound(snd, volume, pitch)
  if not snd then return end
  snd:play{volume = (volume or 0.3)*ENEMY_SFX_VOL_MULT,
           pitch  = (pitch  or 1.0)*ENEMY_SFX_PITCH_MULT}
end

-- Enemy weapon fire specifically (bricks and the boss alike), which carries the
-- extra ENEMY_SHOT_VOL_MULT cut on top of the shared enemy scale.
function enemy_shot_sound(volume, pitch)
  enemy_fx_sound(shoot1, (volume or 0.2)*ENEMY_SHOT_VOL_MULT, pitch)
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
  -- Monospaced cut of the same brush face, used for running prose (the hero
  -- ability tooltip, the shop's loadout copy).
  --
  -- Two things make this face legible or not, and both are settled here rather
  -- than at the call sites:
  --
  --  * SCALE. The brush is a 2x pixel font -- every stroke is exactly two
  --    pixels thick at size 8. Drawn at 0.7 those strokes land on 1.4 pixels
  --    and LOVE's linear filter smears them into grey mush, which is why the
  --    copy read as fuzzy. Everything drawn in this font therefore draws at
  --    scale 1.0, on the pixel grid the glyphs were cut for.
  --
  --  * TRACKING. The mono cut pads every glyph out to a 10px cell even though
  --    the widest ink is 8px, so at native scale the letters float apart. -1
  --    closes that to a single-pixel gutter -- the same rhythm the
  --    proportional cut ships with -- while keeping the even grid that makes
  --    a block of small copy scannable. Font:get_text_width folds tracking in,
  --    so measured layout (wrapping, centring, right-alignment) is unaffected.
  --
  -- Net: ~9px per character at scale 1.0, against ~7px for the old 0.7 draw --
  -- a third wider, and every stroke a real pixel.
  pixul_mono_font = Font('PixulBrush-Mono', 8, -1)

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
    psykino     = fg[0],     infestor    = green[0],
    witch       = purple[0], gambler     = yellow2[0],  vulcanist   = red[0],
  }

  -- Draft pool: 20 balls, trimmed from the full 57-archetype SNKRX roster so
  -- every pick has a distinct effect. Includes every paddle loadout's
  -- starting heroes (paddles.lua start_balls) — those must stay in sync.
  hero_pool = {
    'vagrant', 'swordsman', 'wizard', 'archer', 'scout', 'cleric',
    'bomber', 'stormweaver', 'cannoneer', 'spellblade', 'engineer',
    'barbarian', 'cryomancer', 'pyromancer', 'jester',
    'psykino', 'infestor', 'witch', 'gambler', 'vulcanist',
  }
end


-- Backdrop tones. The grid is KEPT -- it still tiles the whole canvas at the
-- same 15px pitch -- but pulled down to nearly black so it reads as texture
-- under the play field instead of a pattern competing with it. Roughly a third
-- of the old brightness (bg[0] was #0c0c14), holding the same ~0.6 lightness
-- ratio between the two tones that bg[0]/bg[-1] had, so the checker stays as
-- perceptible as it was -- just far dimmer.
--
-- Deliberately NOT a change to the bg ramp itself: bg[-1] and bg[-2] back
-- every dark outline, powerup badge, HUD plate and shot backing in the game
-- (60+ call sites), and darkening the palette would repaint all of them.
local GRID_BASE = Color(0.016, 0.016, 0.027, 1)
local GRID_CELL = Color(0.008, 0.008, 0.016, 1)


function shared_draw(draw_action)
  background_canvas:draw_to(function()
    graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, GRID_BASE)
    -- Tiled background grid. Cell counts derive from gw/gh so the grid
    -- always covers the canvas if the game dimensions change.
    local cols = math.ceil(gw/15)
    local rows = math.ceil(gh/15)
    for i = 0, cols do
      for j = 0, rows do
        if (i + j) % 2 == 0 then
          graphics.rectangle2(i*15, j*15, 15, 15, nil, nil, GRID_CELL)
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
