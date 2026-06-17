-- ============================================================================
-- Admin spawn panel  (DEBUG TOOL -- SNKRX reference build only)
--
-- Press RETURN during a run (in the Arena) to toggle a panel that lists every
-- hero in the game. Clicking a hero:
--   * you don't have it      -> SPAWN it (added to the persistent party, so it
--                               lasts between rounds and shows in the shop where
--                               you can read its description),
--   * you already have it    -> LEVEL it up (up to level 3),
--   * it's already level 3   -> DELETE it (never empties the party).
-- There's also an INFINITE COINS toggle.
--
-- It edits main.current.units (the real party list, passed by reference into the
-- shop + next round) and then rebuilds the live arena party to match. The game is
-- frozen while open (see update() in main.lua) so clicks pick heroes instead of
-- steering the leader. This is a testing convenience and bypasses the normal
-- party-size / shop / set-bonus rules.
-- ============================================================================

admin_panel = {open = false, hover = nil, msg = "", msg_t = 0, list = nil, coins = false}

local COLS = 5
local MX, MY, TW, TH, GX, GY = 15, 33, 86, 14, 5, 3
local BTN = {x = 14, y = 5, w = 104, h = 13}   -- infinite-coins button (top-left)

-- True only while a run is live (so RETURN keeps its normal meaning in the menus
-- and shop, and so there's a leader unit + units list to operate on).
local function in_arena()
  return main and main.current and main.current.is and main.current:is(Arena) and main.current.units
end

-- Stable, alphabetically-sorted list of every SPAWNABLE hero. A few names in
-- character_names have their class/tier entries commented out (saboteur, hunter,
-- lich, launcher, illusionist); spawning those crashes calculate_stats (nil
-- self.classes), so only list heroes that actually have class + tier data.
local function build_list()
  if admin_panel.list then return end
  local keys = {}
  for k in pairs(character_names) do
    if character_classes[k] and character_tiers[k] then keys[#keys + 1] = k end
  end
  table.sort(keys)
  admin_panel.list = keys
end

-- Top-left x,y + size of the i-th hero tile (row-major across COLS columns).
local function tile_rect(i)
  local col = (i - 1) % COLS
  local row = math.floor((i - 1)/COLS)
  return MX + col*(TW + GX), MY + row*(TH + GY), TW, TH
end

-- Rebuild the live arena party from main.current.units (mirrors Arena:on_enter's
-- unit-creation), so spawns / level-ups / deletes show up immediately in the round.
local function rebuild_party()
  local a = main.current
  if not (in_arena() and #a.units > 0) then return end
  if a.player then
    for _, u in ipairs(a.player:get_all_units()) do
      if u.character_hp then u.character_hp.dead = true end
      u.dead = true
    end
  end
  a.player = nil
  for i, unit in ipairs(a.units) do
    if i == 1 then
      a.player = Player{group = a.main, x = gw/2, y = gh/2 + 16, leader = true,
                        character = unit.character, level = unit.level or 1, passives = a.passives, ii = i}
    else
      a.player:add_follower(Player{group = a.main, character = unit.character, level = unit.level or 1,
                                   passives = a.passives, ii = i})
    end
  end
  for _, unit in ipairs(a.player:get_all_units()) do
    unit.character_hp = CharacterHP{group = a.effects, x = a.x1 + 8 + (unit.ii - 1)*22, y = a.y2 + 14, parent = unit}
  end
end

-- Click handler: spawn (new) / level-up (have it, < 3) / delete (have it, at 3).
function admin_click_hero(character)
  if not in_arena() then
    admin_panel.msg, admin_panel.msg_t = "enter a run (Arena) to spawn", 2.5
    return
  end
  if not (character_classes[character] and character_tiers[character]) then
    admin_panel.msg, admin_panel.msg_t = "not spawnable: " .. tostring(character), 2.0
    return
  end
  local a, nm = main.current, (character_names[character] or character)
  local idx
  for i, u in ipairs(a.units) do if u.character == character then idx = i; break end end

  if not idx then
    table.insert(a.units, {character = character, level = 1, reserve = {0, 0}})
    admin_panel.msg, admin_panel.msg_t = "spawned " .. nm, 2.0
    if spawn1 then spawn1:play{volume = 0.4} end
  else
    local u = a.units[idx]
    if (u.level or 1) < 3 then
      u.level = (u.level or 1) + 1
      admin_panel.msg, admin_panel.msg_t = "leveled " .. nm .. " -> " .. u.level, 2.0
      if level_up1 then level_up1:play{volume = 0.4} end
    elseif #a.units > 1 then
      table.remove(a.units, idx)
      admin_panel.msg, admin_panel.msg_t = "removed " .. nm, 2.0
      if error1 then error1:play{volume = 0.4} end
    else
      admin_panel.msg, admin_panel.msg_t = "can't remove the last hero", 2.0
      return
    end
  end
  rebuild_party()
end

-- Called every frame from the global update() in main.lua, BEFORE main:update.
function admin_panel_update(dt)
  build_list()
  if admin_panel.coins then gold = 9999 end          -- keep coins topped while toggled on
  if admin_panel.msg_t > 0 then admin_panel.msg_t = admin_panel.msg_t - dt end

  if admin_panel.open and not in_arena() then admin_panel.open = false end
  if in_arena() and input['return'].pressed then admin_panel.open = not admin_panel.open end
  if not admin_panel.open then admin_panel.hover = nil; return end
  if input.escape.pressed then admin_panel.open = false; return end

  -- Hover detection (infinite-coins button vs hero tiles). The game is frozen while
  -- open, so m1 (also "move left") just picks here -- it won't steer the leader.
  local on_btn = mouse.x >= BTN.x and mouse.x <= BTN.x + BTN.w and mouse.y >= BTN.y and mouse.y <= BTN.y + BTN.h
  admin_panel.hover = nil
  if not on_btn then
    for i = 1, #admin_panel.list do
      local x, y, w, h = tile_rect(i)
      if mouse.x >= x and mouse.x <= x + w and mouse.y >= y and mouse.y <= y + h then
        admin_panel.hover = i
        break
      end
    end
  end
  if input.m1.pressed then
    if on_btn then
      admin_panel.coins = not admin_panel.coins
      admin_panel.msg, admin_panel.msg_t = "infinite coins " .. (admin_panel.coins and "ON" or "off"), 2.0
    elseif admin_panel.hover then
      admin_click_hero(admin_panel.list[admin_panel.hover])
    end
  end
end

-- Called every frame from the global draw() in main.lua, inside shared_draw. No-op closed.
function admin_panel_draw()
  if not admin_panel.open then return end
  build_list()

  graphics.rectangle(gw/2, gh/2, gw, gh, nil, nil, Color(0, 0, 0, 0.82))
  graphics.print_centered("ADMIN  -  SPAWN HERO", fat_font, gw/2, 11, 0, 1, 1, 0, 0, fg[0])

  -- Infinite-coins toggle button.
  local on = admin_panel.coins
  graphics.rectangle2(BTN.x, BTN.y, BTN.w, BTN.h, 3, 3, on and Color(0.55, 0.45, 0.05, 0.95) or Color(0.10, 0.10, 0.15, 0.95))
  graphics.rectangle2(BTN.x, BTN.y, BTN.w, BTN.h, 3, 3, on and yellow[0] or Color(0.5, 0.5, 0.5, 0.6), 1)
  graphics.print_centered("coins: " .. (on and "INFINITE" or "off"), pixul_font, BTN.x + BTN.w/2, BTN.y + BTN.h/2, 0, 1, 1, 0, 0, on and yellow[0] or fg[0])

  -- Hero tiles. Top-left badge = your current level "Lx" (if owned); top-right
  -- badge = the hero's TIER "Tn", colour-coded by tier (1 white .. 4 gold).
  local TC = {fg[0], green[0], blue[0], yellow[0]}
  for i = 1, #admin_panel.list do
    local key     = admin_panel.list[i]
    local x, y, w, h = tile_rect(i)
    local c       = character_colors[key] or fg[0]
    local hovered = (admin_panel.hover == i)
    local tier    = character_tiers[key] or 1
    local owned   = nil
    if in_arena() then for _, u in ipairs(main.current.units) do if u.character == key then owned = (u.level or 1); break end end end
    if hovered then
      graphics.rectangle2(x, y, w, h, 3, 3, Color(c.r, c.g, c.b, 0.9))
      graphics.print_centered(string.lower(character_names[key]), pixul_font, x + w/2, y + h/2, 0, 1, 1, 0, 0, bg[0])
    else
      graphics.rectangle2(x, y, w, h, 3, 3, Color(0.10, 0.10, 0.15, 0.92))
      graphics.rectangle2(x, y, w, h, 3, 3, owned and Color(c.r, c.g, c.b, 0.95) or Color(c.r, c.g, c.b, 0.45), owned and 1.5 or 1)
      graphics.print_centered(string.lower(character_names[key]), pixul_font, x + w/2, y + h/2, 0, 1, 1, 0, 0, c)
    end
    if owned then graphics.print(("L%d"):format(owned), pixul_font, x + 2, y + 1, 0, 1, 1, 0, 0, owned >= 3 and red[0] or fg[0]) end
    graphics.print(("T%d"):format(tier), pixul_font, x + w - 13, y + 1, 0, 1, 1, 0, 0, (hovered and bg[0]) or TC[tier] or fg[0])
  end

  -- Hovered-hero info (name + classes + party level).
  if admin_panel.hover then
    local key = admin_panel.list[admin_panel.hover]
    local classes = (character_classes[key] and table.concat(character_classes[key], " / ")) or "?"
    local extra = ""
    if in_arena() then for _, u in ipairs(main.current.units) do if u.character == key then extra = "   (in party, lvl " .. (u.level or 1) .. (u.level == 3 and " -- click to DELETE" or "") .. ")"; break end end end
    graphics.print_centered(string.lower(character_names[key]) .. "  -  tier " .. (character_tiers[key] or "?") .. "  -  " .. classes .. extra, pixul_font, gw/2, 244, 0, 1, 1, 0, 0, character_colors[key] or fg[0])
  end

  if admin_panel.msg_t > 0 then
    graphics.print_centered(admin_panel.msg, pixul_font, gw/2, 253, 0, 1, 1, 0, 0, yellow[0])
  end
  graphics.print_centered("click: spawn  /  level-up  /  delete at lvl 3      -      Enter / Esc to close",
                          pixul_font, gw/2, 262, 0, 1, 1, 0, 0, fg[0])
end
