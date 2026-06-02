require 'engine'
require 'shared'
require 'ballpit'
require 'paddle'
require 'ball_hero'
require 'brick'
require 'swarm'
require 'enemies'
require 'projectile'
require 'xp_orb'
require 'powerup'
require 'effects'
require 'terminal'


-- Global cheat-speed multiplier driven by the admin terminal's `speed` cmd.
-- Defaults to 1.0 (= normal) so the game runs the same as the public build
-- until the operator changes it.
admin_speed = 1.0


function init()
  shared_init()

  -- Input bindings.
  input:bind('move_left',  {'a', 'dpleft'})
  input:bind('move_right', {'d', 'dpright'})
  input:bind('move_up',    {'w', 'dpup'})
  input:bind('move_down',  {'s', 'dpdown'})
  input:bind('aim_left',   {'left'})
  input:bind('aim_right',  {'right'})
  input:bind('launch',     {'space', 'fdown'})
  input:bind('confirm',    {'return', 'kpenter'})
  input:bind('click',      {'m1'})
  input:bind('restart',    {'r'})
  -- Admin terminal toggle. `bind_all` doesn't include backtick, so we add an
  -- explicit action that listens to both backtick and F1.
  input:bind('toggle_terminal', {'`', 'f1'})

  local s = {tags = {sfx}}

  -- Pick a few SNKRX sound files that exist in assets/sounds.
  hit1        = Sound('Player Takes Damage 17.ogg', s)
  hit2        = Sound('Body Head (Headshot) 1.ogg', s)
  enemy_die1  = Sound('Bloody punches 7.ogg', s)
  enemy_die2  = Sound('Bloody punches 10.ogg', s)
  shoot1      = Sound('Shooting Projectile (Classic) 11.ogg', s)
  archer1     = Sound('Releasing Bow String 1.ogg', s)
  wizard1     = Sound('Wind Bolt 20.ogg', s)
  swordsman1  = Sound('Heavy sword woosh 1.ogg', s)
  scout1      = Sound('Throwing Knife (Thrown) 3.ogg', s)
  fire1       = Sound('Fire bolt 3.ogg', s)
  fire2       = Sound('Fire bolt 5.ogg', s)
  frost1      = Sound('Frost Bolt 20.ogg', s)
  thunder1    = Sound('399656__bajko__sfx-thunder-blast.ogg', s)
  explosion1  = Sound('Explosion Grenade_04.ogg', s)
  heal1       = Sound('Buff 3.ogg', s)
  level_up1   = Sound('Buff 4.ogg', s)
  gold1       = Sound('Collect 5.ogg', s)
  orb1        = Sound('Collect 2.ogg', s)
  pop1        = Sound('Pop sounds 10.ogg', s)
  spawn1      = Sound('Buff 13.ogg', s)
  buff1       = Sound('Buff 14.ogg', s)
  mine1       = Sound('Weapon Swap 2.ogg', s)
  dot1        = Sound('Magical Swoosh 18.ogg', s)
  force1      = Sound('Magical Impact 18.ogg', s)
  flagellant1 = Sound('Whipping Horse 3.ogg', s)
  critter1    = Sound('Critters eating 2.ogg', s)
  critter2    = Sound('Crickets Chirping 4.ogg', s)
  critter3    = Sound('Popping bloody Sac 1.ogg', s)
  confirm1    = Sound('80921__justinbw__buttonchime02up.ogg', s)
  ui_switch1  = Sound('Switch.ogg', s)
  bounce1     = Sound('Player Takes Damage 2.ogg', s)

  -- Music: auto-discover whatever's in assets/music/. Drop any .ogg / .mp3 /
  -- .wav file in there and it'll be picked up next launch. Empty folder =
  -- the game runs silent on the music channel (sfx still plays). The
  -- original Kubbi - Ember soundtrack was moved to assets/music_archive/
  -- and is preserved but not auto-loaded.
  --
  -- Long tracks stream from disk ('stream' mode) instead of decoding into
  -- RAM up-front, so big files don't bloat the process.
  local m = {tags = {music}, loop = true}
  songs = {}
  if love.filesystem.getInfo('assets/music') then
    for _, name in ipairs(love.filesystem.getDirectoryItems('assets/music')) do
      local ext = name:lower():match('%.(%w+)$')
      if ext == 'ogg' or ext == 'mp3' or ext == 'wav' then
        local ok, snd = pcall(function()
          return ripple.newSound(love.audio.newSource('assets/music/' .. name, 'stream'), m)
        end)
        if ok and snd then
          table.insert(songs, snd)
        else
          print("[music] failed to load: " .. name)
        end
      end
    end
  end
  print(string.format("[music] loaded %d track(s) from assets/music/", #songs))

  main = Main()
  main:add(BallPit'ballpit')
  main:go_to('ballpit')
end


function update(dt)
  main:update(dt)
end


function draw()
  shared_draw(function()
    main:draw()
  end)
end


function love.run()
  return engine_run({
    game_name     = 'BallPitX-Admin',
    game_width    = 480,
    game_height   = 656,
    window_width  = 720,
    window_height = 984,
    vsync         = 1,
  })
end
