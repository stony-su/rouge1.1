-- ============================================================================
-- TUTORIAL TEXT
--
-- Every word the in-game tutorial cards say, and nothing else. This file is
-- pure data: edit it freely without opening ballpit.lua. The system that shows
-- the cards (when they fire, the spotlight, the panel) lives in ballpit.lua
-- under `-- ----- Guided tutorial`.
--
-- ---------------------------------------------------------------------------
-- EDITING
--
--   title   Drawn in fat_font. Keep it short -- a few words.
--   body    ONE STRING PER DRAWN LINE. Nothing word-wraps at runtime: the
--           breaks are yours, deliberately, so the copy reads the way you
--           wrote it.
--
--   * LINE BUDGET: 308 px, which is about 45-48 characters in PixulBrush. Go
--     over and the line runs off the panel edge with no warning. The longest
--     line here is 293 px ('Only the BRIGHT CORE can be hit by enemy fire --').
--   * Line COUNT is free. The card sizes itself to #body and re-parks in
--     whichever half of the screen the spotlight is not in, so two lines and
--     six lines both lay out correctly.
--   * Strings are single-quoted, so an apostrophe needs escaping (\'). Easier
--     to just write around it.
--
-- ---------------------------------------------------------------------------
-- KEYS
--
-- The key is what wires a card to the moment it fires. Renaming one silently
-- disables that card; adding one turns a card on. Triggers build the key from
-- the thing that fired them, so most families extend by adding an entry here
-- and nothing else:
--
--   pw_<powerup kind>    first orb of that kind    (Powerup.KINDS, powerup.lua)
--   brick_<variant>      first block of that kind  (VARIANTS, brick.lua)
--   sig_<paddle id>      first run on that paddle  (PADDLES.defs, paddles.lua)
--
-- and the fixed ones, each fired from one named place:
--
--   paddle        the title screen handing over to a live run
--   enemy_shot    the first enemy projectile
--   hurt          the first time the player actually loses HP
--   ball_return   a ball first arriving home after a miss
--   combo_a       first promotion to combo rank A
--   levelup       the first draft
--   shop          the first game-over / shop page
--   hive_infest   the first block to catch the infestation rot
--
-- A key with no trigger is dead copy; a trigger with no key is silent. Neither
-- errors -- which is what makes it safe to add a paddle card (sig_pinball, say)
-- without touching any other file.
--
-- ---------------------------------------------------------------------------
-- Cards fire ONCE EVER, recorded in state.tut_seen in the LOVE save. To see an
-- edit fire again, delete state.txt from the save directory.
-- ============================================================================

TUTORIAL_TEXT = {
  paddle = {
    title = 'YOUR PADDLE',
    body  = {'WSAD to move the paddle',
             'cannot move past the dotted red line',
             'Only the BRIGHT CORE can be hit by enemy fire --',
             'but the paddle can bounce balls.'},
  },

  enemy_shot = {
    title = 'ENEMY FIRE',
    body  = {'Blocks shoot back. AVOID THEM!',
             'Hitting the core depletes your health.'},
  },

  hurt = {
    title = 'CORE HIT',
    body  = {'Your core took damage and you lost health.',
             'At zero the run ends. Catch HEAL orbs',
             'and avoid enemy fire to survive.'},
  },

  ball_return = {
    title = 'RECALL AND CHARGE',
    body  = {'A ball you miss is not lost.',
             'It returns - charging while it',
             "waits -- increasing it's speed and damage",
             'press SPACE to launch.'},
  },

  combo_a = {
    title = 'COMBO: A RANK',
    body  = {'Chaining block hits without missing builds the',
             'meter. The higher the rank, the faster the balls move.',
             'a missed ball reduces the meter'},
  },

  levelup = {
    title = 'LEVEL UP',
    body  = {'Clearing a wave earns a level, and a level opens',
             'this draft. Arrows pick a card, ENTER takes it.'},
  },

  shop = {
    title = 'THE SHOP',
    body  = {'Every block you break banks a coin that outlives',
             'the run. Spend them here to unlock paddles --'},
  },

  -- ---- Powerups, one card per KIND -----------------------------------------
  -- Every card stands on its own, because there is no order these arrive in:
  -- a player can meet the floor before they ever see a heal. So every card
  -- opens by teaching HOW this orb is claimed -- tier 1: caught on first
  -- paddle touch; tier 2: knocked UP with the paddle to arm it, then caught
  -- on the way back down -- before saying what it grants.
  pw_heal = {
    title = 'HEAL',
    body  = {'Catch it with the paddle to claim it:',
             'it restores one heart.'},
  },

  pw_wide_paddle = {
    title = 'WIDE PADDLE',
    body  = {'Catch it with the paddle to claim it:',
             'your bar grows much longer for a while.'},
  },

  pw_big_ball = {
    title = 'BIG BALL',
    body  = {'Catch it with the paddle to claim it:',
             'every ball swells.'},
  },

  pw_fire_trail = {
    title = 'FIRE TRAIL',
    body  = {'Catch it with the paddle to claim it:',
             'your balls leave a burning trail.'},
  },

  pw_freeze_wave = {
    title = 'FREEZE',
    body  = {'Catch it with the paddle to claim it:',
             'the whole arena freezes for a few seconds.'},
  },

  pw_water_wave = {
    title = 'WATER WAVE',
    body  = {'Knock it UP with the paddle to arm it,',
             'then catch it as it falls to claim it:',
             'a surge rolls up and shoves enemies back.'},
  },

  pw_multi_ball = {
    title = 'MULTI BALL',
    body  = {'Knock it UP with the paddle to arm it,',
             'then catch it as it falls to claim it:',
             'your balls multiply.'},
  },

  pw_pierce = {
    title = 'PIERCE',
    body  = {'Knock it UP with the paddle to arm it,',
             'then catch it as it falls to claim it:',
             'balls fly straight through blocks.'},
  },

  pw_floor = {
    title = 'THE FLOOR',
    body  = {'Knock it UP with the paddle to arm it,',
             'then catch it as it falls to claim it:',
             'balls bounce off the bottom for a while.'},
  },

  pw_level_random = {
    title = 'LEVEL ORB',
    body  = {'The number is bounces still needed: knock',
             'it up with the paddle that many times,',
             'then catch it -- random balls level up',
             'once per bounce it took.'},
  },

  -- ---- Blocks, one card per VARIANT ----------------------------------------
  -- Fired the first time each kind actually reaches the playfield, so a block
  -- is explained while it is on screen to be looked at.
  brick_seeker = {
    title = 'SEEKER',
    body  = {'A block. DESTROY IT'},
  },

  brick_speed_booster = {
    title = 'BOOSTER',
    body  = {'Speeds up the enemy swarm'},
  },

  brick_exploder = {
    title = 'EXPLODER',
    body  = {'Kill it and it detonates'},
  },

  brick_headbutter = {
    title = 'HEADBUTTER',
    body  = {'Lunges, in bursts'},
  },

  brick_tank = {
    title = 'TANK',
    body  = {'Slow, and very high HP.'},
  },

  brick_shooter = {
    title = 'SHOOTER',
    body  = {'Shoots back.'},
  },

  brick_forcer = {
    title = 'FORCER',
    body  = {'Curves balls away from it'},
  },

  brick_randomizer = {
    title = 'RANDOMIZER',
    body  = {'It scrambles the direction of balls that touch it.'},
  },

  brick_sniper = {
    title = 'SNIPER',
    body  = {'Shoots fast and long-ranged projectiles'},
  },

  brick_spreader = {
    title = 'SPREADER',
    body  = {'It fires a whole fan at once.'},
  },

  brick_spiraler = {
    title = 'SPIRALER',
    body  = {'Sprays projectiles'},
  },

  brick_burster = {
    title = 'BURSTER',
    body  = {'A rapidly fires a string of shots'},
  },

  brick_arc_lobber = {
    title = 'ARC LOBBER',
    body  = {'Shoots homing projectiles'},
  },

  -- ---- Loadouts ------------------------------------------------------------
  -- Keyed 'sig_' .. paddle id and fired on the first run with that paddle
  -- equipped, so each one teaches itself once. Every paddle with a signature
  -- has a card; Standard is silent -- the base 'paddle' card IS its tutorial.
  sig_pinball = {
    title = 'PINBALL LOBBER',
    body  = {'Gravity rules this table: balls fall, and',
             'the flippers lob them back up.',
             'LEFT / RIGHT arrows flip.',
             'Mind the drain between the bats.'},
  },

  sig_aegis = {
    title = 'AEGIS',
    body  = {'Pressing E or left mouse button raises the',
             'shield: reflecting enemy bullets'},
  },

  sig_mitosis = {
    title = 'MITOSIS',
    body  = {'Every kill splits a ball in two.',
             'One daughter decays -- bounce it off the',
             'paddle to keep it alive.'},
  },

  sig_hive = {
    title = 'HIVE',
    body  = {'Balls deal NO contact damage here.',
             'Maggots infest blocks with a rot that',
             'spreads to their neighbours.'},
  },

  sig_vampire = {
    title = 'VAMPIRE',
    body  = {'Health drains constantly.',
             'Killing blocks restores it.',
             'Stop killing and you die.'},
  },

  sig_boomerang = {
    title = 'BOOMERANG',
    body  = {'Balls curl back toward the paddle after',
             'any wall hit -- no ball is ever lost.'},
  },

  sig_twincast = {
    title = 'TWIN CAST',
    body  = {'The twins burn a tether that cuts',
             'whatever it crosses. At full charge they',
             'FUSE and detonate -- the wider apart they',
             'were, the bigger the nova.'},
  },

  sig_tesla = {
    title = 'TESLA',
    body  = {'Every paddle bounce arcs lightning',
             'between ALL live balls.',
             'More balls, more damage.'},
  },

  sig_terrorist = {
    title = 'TERRORIST',
    body  = {'Press E to detonate balls near blocks --',
             'the blast is your real damage.',
             'Spent balls are gone; a level-up',
             'arms a fresh one.'},
  },

  sig_cannon = {
    title = 'CANNON',
    body  = {'Strike a ball with a moving paddle to',
             'launch a HOP: it flies over blocks and',
             'crashes down in a damaging splash.',
             'Charge forward into the ball for height.'},
  },

  hive_infest = {
    title = 'INFESTED',
    body  = {'That block is rotting. It deals DoT and spreads to nearby blocks'},
  },
}
