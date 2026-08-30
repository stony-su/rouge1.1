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
    body  = {'This bar is you. A and D slide it, W and S lift',
             'it inside the dodge band above the red line.',
             'Only the BRIGHT CORE can be hit by enemy fire --',
             'the faded wings are reach, not exposure.'},
  },

  enemy_shot = {
    title = 'ENEMY FIRE',
    body  = {'Blocks shoot back. A shot that lands on your',
             'core costs you health -- but it also sets off a',
             'blank that sweeps every other shot off the',
             'screen and stops the ranks firing for a beat.'},
  },

  ball_return = {
    title = 'RECALL AND CHARGE',
    body  = {'A ball you miss is not lost. It is pulled back',
             'and sticks to the paddle, charging while it',
             'waits -- a full two seconds doubles its speed',
             'and adds half again its damage. SPACE launches.'},
  },

  combo_a = {
    title = 'COMBO: A RANK',
    body  = {'Chaining block hits without missing builds the',
             'meter. It pays TEMPO, not damage: every ball',
             'moves faster the higher you hold it. It bleeds',
             'while you idle, and a ball in the pit costs you.'},
  },

  levelup = {
    title = 'LEVEL UP',
    body  = {'Clearing a wave earns a level, and a level opens',
             'this draft. Arrows pick a card, ENTER takes it.',
             'A new hero joins your ball pit, or one you have',
             'already drafted gets stronger.'},
  },

  shop = {
    title = 'THE SHOP',
    body  = {'Every block you break banks a coin that outlives',
             'the run. Spend them here to unlock paddles --',
             'each one rewrites a core verb of the game.',
             'Press R when you want the next run.'},
  },

  -- ---- Powerups, one card per KIND -----------------------------------------
  -- Every card stands on its own, because there is no order these arrive in:
  -- a player can meet the floor before they ever see a heal. So each tier-two
  -- card states the deflect-then-catch rule itself rather than assuming an
  -- earlier card taught it.
  pw_heal = {
    title = 'HEAL',
    body  = {'Catch it with the paddle and it hands a heart',
             'straight back. Tier one: no arming, just get',
             'under it.'},
  },

  pw_wide_paddle = {
    title = 'WIDE PADDLE',
    body  = {'Catch it for a much longer bar -- and while it',
             'lasts you are PHASED: enemy shots pass straight',
             'through you instead of landing.'},
  },

  pw_big_ball = {
    title = 'BIG BALL',
    body  = {'Catch it and every ball swells. Bigger, heavier,',
             'and it hits harder for it.'},
  },

  pw_fire_trail = {
    title = 'FIRE TRAIL',
    body  = {'Catch it and your balls lay burning ground behind',
             'them. Blocks that sit in it cook without you',
             'having to hit them again.'},
  },

  pw_freeze_wave = {
    title = 'FREEZE',
    body  = {'Catch it and the whole arena stops for a few',
             'seconds. Blocks, shots, everything but you.'},
  },

  pw_water_wave = {
    title = 'WATER WAVE',
    body  = {'A tier two: DEFLECT it off the paddle to arm it,',
             'then catch it on the way back down. A surge',
             'rolls up the arena and shoves every swarm back',
             'where it came from.'},
  },

  pw_multi_ball = {
    title = 'MULTI BALL',
    body  = {'A tier two: DEFLECT it to arm it, then catch it.',
             'More balls in play at once -- more of everything,',
             'and more to lose down the pit.'},
  },

  pw_pierce = {
    title = 'PIERCE',
    body  = {'A tier two: DEFLECT it to arm it, then catch it.',
             'Your balls punch THROUGH blocks instead of',
             'bouncing off them.'},
  },

  pw_floor = {
    title = 'THE FLOOR',
    body  = {'A tier two: DEFLECT it to arm it, then catch it.',
             'A wall seals the bottom of the arena, and while',
             'it holds no ball can fall out. It does not',
             'survive the wave.'},
  },

  pw_level_random = {
    title = 'LEVEL ORB',
    body  = {'This one opens no draft. Deflect it to arm it,',
             'catch it, and several of your BALLS level up on',
             'the spot. It drops on its own timer, not with',
             'the other powerups.'},
  },

  -- ---- Blocks, one card per VARIANT ----------------------------------------
  -- Fired the first time each kind actually reaches the playfield, so a block
  -- is explained while it is on screen to be looked at.
  brick_seeker = {
    title = 'SEEKER',
    body  = {'The basic block. It drifts down and breaches --',
             'no tricks, just pressure. Everything else you',
             'will meet is this with something added.'},
  },

  brick_speed_booster = {
    title = 'BOOSTER',
    body  = {'It speeds up the whole formation it sits in.',
             'Kill it first and the swarm slows back down.'},
  },

  brick_exploder = {
    title = 'EXPLODER',
    body  = {'Kill it and it detonates, taking its neighbours',
             'with it -- which can chain. Excellent, unless',
             'the chain is what reaches your line.'},
  },

  brick_headbutter = {
    title = 'HEADBUTTER',
    body  = {'This one does not drift. It LUNGES, in bursts,',
             'straight down the screen at you.'},
  },

  brick_tank = {
    title = 'TANK',
    body  = {'Slow, and very high HP. It will not die to one',
             'pass -- grind it down or work around it.'},
  },

  brick_shooter = {
    title = 'SHOOTER',
    body  = {'The first block that shoots back. Plain aimed',
             'shots at wherever your paddle is standing.'},
  },

  brick_forcer = {
    title = 'FORCER',
    body  = {'It shoves your balls AWAY from it, so shots that',
             'looked good curve off before they land.'},
  },

  brick_randomizer = {
    title = 'RANDOMIZER',
    body  = {'It scrambles the direction of whatever touches',
             'it. Your ball comes off it pointing anywhere.'},
  },

  brick_sniper = {
    title = 'SNIPER',
    body  = {'One shot, fast and long-ranged, straight at you.',
             'You get a telegraph first -- move on it.'},
  },

  brick_spreader = {
    title = 'SPREADER',
    body  = {'It fires a whole fan at once. You cannot dodge',
             'all of it, so pick your gap early.'},
  },

  brick_spiraler = {
    title = 'SPIRALER',
    body  = {'A rotating spray that keeps turning. Read which',
             'way it is winding and move against it.'},
  },

  brick_burster = {
    title = 'BURSTER',
    body  = {'A rapid string of shots down one line. Not aimed',
             'especially well -- just relentless.'},
  },

  brick_arc_lobber = {
    title = 'ARC LOBBER',
    body  = {'Its shot CURVES down onto you, so where it is',
             'pointing is not where it is going to land.'},
  },

  -- ---- Loadouts ------------------------------------------------------------
  -- Keyed 'sig_' .. paddle id and fired on the first run with that paddle
  -- equipped, so each one teaches itself once. Only paddles with an entry here
  -- say anything; the rest are silent by design.
  sig_aegis = {
    title = 'AEGIS',
    body  = {'This paddle answers back. E or click raises the',
             'shield: time it into incoming fire and you PARRY',
             '-- balls and bullets fly back at them. Parries',
             'bank bulwark; a full meter turns the next raise',
             'gold.'},
  },

  hive_infest = {
    title = 'INFESTED',
    body  = {'That block is rotting. Infestation does not kill',
             'on contact -- it eats a share of its health every',
             'second, and CREEPS to a neighbour block on its',
             'own. Start it in the middle of a pack and let it',
             'spread.'},
  },
}
