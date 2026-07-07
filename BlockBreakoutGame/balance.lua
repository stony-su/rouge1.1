-- Damage master-file system. Every damage number in the game is read through
-- here so it can be tuned per-paddle from a plain data file, with NO code edit:
--
--   balance/<paddle_id>.lua     one COMPLETE master file per paddle loadout
--                               (standard, pinball, aegis, mitosis, hive,
--                               vampire, boomerang, twincast, tesla,
--                               terrorist, cannon)
--
-- The active file is picked by the equipped paddle and re-read FROM DISK at
-- the start of every run (BallPit:reset_run -> Balance.set_paddle), so the
-- tuning loop is: edit the file, press R in-game, the new numbers are live.
-- No game restart needed.
--
-- Every lookup carries the original hardcoded value as its default: a missing
-- key, a deleted line, a broken file or a wrong type falls back to that
-- default (with a --console warning) instead of crashing the game. Deleting a
-- line from a master file therefore means "use the built-in value", never an
-- error.
--
-- Four entry points:
--   Balance.set_paddle(id)          reload balance/<id>.lua as the active table
--   BAL('a.b.c', default)           read one number (dotted path, cached split)
--   Balance.merge_hero_stats(c, s)  copy of HERO_STATS[c] overridden by the
--                                   active file's heroes.<c> numbers
--   Balance.effective_def(pdef)     copy of the PADDLES def overridden by the
--                                   active file's loadout + signature sections

Balance = {}
Balance.active    = {}    -- the active paddle's master table ({} = all defaults)
Balance.active_id = nil

local path_cache = {}     -- 'a.b.c' -> {'a','b','c'}
local warned     = {}     -- one console warning per bad key, not one per frame


local function warn_once(key, msg)
  if warned[key] then return end
  warned[key] = true
  print('[balance] ' .. msg)
end


-- Load balance/<id>.lua fresh from disk. Returns the table or nil (+ prints
-- why). love.filesystem reads from the game source dir, so edits to the file
-- are picked up without restarting LÖVE.
local function load_file(id)
  local path = 'balance/' .. id .. '.lua'
  local chunk, err = love.filesystem.load(path)
  if not chunk then
    print('[balance] could not load ' .. path .. ' (' .. tostring(err) .. ') — using built-in defaults')
    return nil
  end
  local ok, result = pcall(chunk)
  if not ok then
    print('[balance] error running ' .. path .. ': ' .. tostring(result) .. ' — using built-in defaults')
    return nil
  end
  if type(result) ~= 'table' then
    print('[balance] ' .. path .. ' did not return a table — using built-in defaults')
    return nil
  end
  return result
end


-- Called from BallPit:reset_run with the equipped paddle's id, BEFORE
-- run_mods / the paddle / the heroes are built, so everything downstream
-- reads the fresh table.
function Balance.set_paddle(id)
  id = id or 'standard'
  local t = load_file(id)
  Balance.active    = t or {}
  Balance.active_id = id
  warned = {}
  if t then print('[balance] loaded balance/' .. id .. '.lua') end
end


-- Read one value off the active table by dotted path ('combo.ranks.3.mult').
-- Numeric segments index arrays. Missing key or type mismatch -> default.
function BAL(path, default)
  local segs = path_cache[path]
  if not segs then
    segs = {}
    for s in path:gmatch('[^%.]+') do segs[#segs + 1] = s end
    path_cache[path] = segs
  end
  local node = Balance.active
  for i = 1, #segs do
    if type(node) ~= 'table' then return default end
    node = node[segs[i]] or node[tonumber(segs[i])]
  end
  if node == nil then return default end
  if default ~= nil and type(node) ~= type(default) then
    warn_once(path, path .. ' should be a ' .. type(default) .. ' (got ' .. type(node) .. ') — using default ' .. tostring(default))
    return default
  end
  return node
end


-- Copy of a hero's HERO_STATS block with every NUMERIC field overridden by
-- the active file's heroes.<character> entry. Structure (behavior, skin,
-- color, on_bounce) always stays code-side; the master file owns numbers
-- only. Always returns a fresh table, safe for the caller to mutate.
function Balance.merge_hero_stats(character, base)
  local out = {}
  for k, v in pairs(base) do out[k] = v end
  local heroes = Balance.active.heroes
  local h = heroes and heroes[character]
  if h then
    for k, v in pairs(h) do
      if type(v) == 'number' and (out[k] == nil or type(out[k]) == 'number') then
        out[k] = v
      end
    end
  end
  return out
end


-- Copy of a PADDLES def with the numeric stat multipliers overridden by the
-- file's `loadout` section and the sig table overridden by its `signature`
-- section (numbers and booleans — booleans so flags like the Hive's
-- contact_zero stay tunable). The def AND its sig are copied, so the shared
-- PADDLES.defs table is never mutated across runs.
function Balance.effective_def(pdef)
  local def = {}
  for k, v in pairs(pdef) do def[k] = v end
  local sig = {}
  for k, v in pairs(pdef.sig or {}) do sig[k] = v end
  def.sig = sig

  local loadout = Balance.active.loadout
  if loadout then
    for k, v in pairs(loadout) do
      if type(v) == 'number' and (def[k] == nil or type(def[k]) == 'number') then
        def[k] = v
      end
    end
  end
  local signature = Balance.active.signature
  if signature then
    for k, v in pairs(signature) do
      if type(v) == 'number' or type(v) == 'boolean' then sig[k] = v end
    end
  end
  return def
end
