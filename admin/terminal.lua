-- Admin terminal: an in-game cheat / debug console for the admin build.
--
-- Toggle with backtick (`) or F1. When open, gameplay is paused, the textinput
-- buffer is drained into the command line, and the registered command table
-- dispatches actions against the live BallPit arena.
--
-- Supported commands (type `help` in-game for the live list):
--   help                       — list commands
--   heroes                     — list every spawnable hero name
--   spawn <hero|random>        — add a ball-hero of that type to the run
--   speed <n>                  — set game-speed multiplier (1.0 = normal)
--   wave [n]                   — show current wave, or jump to wave n
--   skip                       — advance to the next wave immediately
--   kill / clear               — destroy every live brick on screen
--   hp <n>                     — set max hp (also fills to full)
--   heal                       — refill hp to max
--   god                        — toggle invulnerability
--   xp <n>                     — gain n xp (will trigger level-ups)
--   level                      — open the level-up upgrade picker
--   cls                        — clear the terminal log

Terminal = Object:extend()


function Terminal:init(arena)
  self.arena       = arena
  self.open        = false
  self.buffer      = ""
  self.lines       = {}
  self.max_lines   = 24
  self.history     = {}
  self.history_idx = 0
  self.commands    = {}
  self:register_commands()
  self:log("admin terminal — press ` or F1 to toggle. type 'help'.")
end


function Terminal:toggle()
  self.open = not self.open
  -- Always drain whatever is in the textinput buffer at the moment of toggle,
  -- so the toggle key itself doesn't end up appended to the prompt line.
  input:get_and_clear_textinput_buffer()
  if self.open then self.buffer = "" end
end


function Terminal:update(dt)
  if not self.open then return end

  -- Pull queued characters from the engine's textinput buffer, then strip any
  -- stray backticks (they leak in when the toggle key is held down across
  -- update frames before the textinput event finishes firing).
  local typed = input:get_and_clear_textinput_buffer() or ""
  typed = typed:gsub("`", "")
  if #typed > 0 then self.buffer = self.buffer .. typed end

  if input.backspace.pressed and #self.buffer > 0 then
    self.buffer = self.buffer:sub(1, -2)
  end

  if input["return"].pressed or input.kpenter.pressed then
    self:execute(self.buffer)
    if self.buffer ~= "" then
      table.insert(self.history, self.buffer)
      self.history_idx = #self.history + 1
    end
    self.buffer = ""
  end

  -- Command history scrub with up / down.
  if input.up.pressed and #self.history > 0 then
    self.history_idx = math.max(1, self.history_idx - 1)
    self.buffer = self.history[self.history_idx] or ""
  end
  if input.down.pressed and #self.history > 0 then
    self.history_idx = math.min(#self.history + 1, self.history_idx + 1)
    self.buffer = self.history[self.history_idx] or ""
  end
end


function Terminal:draw()
  if not self.open then return end

  -- Anchored to the top of the canvas (just under the HUD strip) so the panel
  -- stays visible even when the window is taller than the user's monitor and
  -- the bottom edge of the window is clipped off-screen.
  local pad  = 6
  local line_h = 9
  local y0   = 22                                -- below the HUD heart / xp row
  local h    = math.floor(gh*0.45)
  -- Cap height so it never spills past the HUD's bottom-row HUD text, in case
  -- some future resolution is shorter than expected.
  if y0 + h > gh - 16 then h = gh - 16 - y0 end

  -- Backing panel + border.
  graphics.rectangle(gw/2, y0 + h/2, gw, h, nil, nil, Color(0, 0, 0, 0.82))
  graphics.rectangle(gw/2, y0 + h/2, gw, h, nil, nil, fg_transparent_weak, 1)

  -- Title strip.
  graphics.print('ADMIN TERMINAL', pixul_font, pad, y0 + pad - 2, 0, 1, 1, 0, 0, yellow[0])
  graphics.print('speed ' .. string.format('%.2f', admin_speed or 1)
              .. '  god ' .. tostring(self.arena.god and 'ON' or 'off')
              .. '  wave ' .. tostring(self.arena.wave),
              pixul_font, pad + 90, y0 + pad - 2, 0, 1, 1, 0, 0, fg_alt[0])

  -- Scrollback. Newest line at the bottom of the log area.
  local log_top    = y0 + pad + line_h + 2
  local log_bottom = y0 + h - line_h - pad - 4
  local visible    = math.max(1, math.floor((log_bottom - log_top)/line_h))
  local start_i    = math.max(1, #self.lines - visible + 1)
  local ly         = log_top
  for i = start_i, #self.lines do
    graphics.print(self.lines[i], pixul_font, pad, ly, 0, 1, 1, 0, 0, fg[0])
    ly = ly + line_h
  end

  -- Prompt line. Underline + blinking caret. The `time` global ticks every
  -- update frame in the engine, so a fast %2 toggle gives us a cursor blink.
  local prompt_y = y0 + h - line_h - pad
  graphics.rectangle(gw/2, prompt_y + line_h/2 - 1, gw - pad*2, line_h + 2, nil, nil, bg[-2])
  local caret = (math.floor((time or 0)*2) % 2 == 0) and '_' or ' '
  graphics.print('> ' .. self.buffer .. caret, pixul_font, pad + 2, prompt_y, 0, 1, 1, 0, 0, yellow[0])
end


function Terminal:log(s)
  for line in tostring(s):gmatch('[^\n]+') do
    table.insert(self.lines, line)
  end
  while #self.lines > self.max_lines do
    table.remove(self.lines, 1)
  end
end


function Terminal:execute(line)
  line = (line or ''):match('^%s*(.-)%s*$')
  if line == '' then return end
  self:log('> ' .. line)
  local parts = {}
  for p in line:gmatch('%S+') do table.insert(parts, p) end
  local cmd = (parts[1] or ''):lower()
  local args = {}
  for i = 2, #parts do args[i - 1] = parts[i] end
  local fn = self.commands[cmd]
  if not fn then
    self:log("unknown command '" .. cmd .. "'. try 'help'.")
    return
  end
  local ok, err = pcall(fn, self, args)
  if not ok then self:log('error: ' .. tostring(err)) end
end


-- ----- Commands -----

local function valid_hero(name)
  for _, h in ipairs(hero_pool) do if h == name then return true end end
  return false
end


function Terminal:register_commands()
  local C = self.commands

  C.help = function(t, args)
    t:log("commands:")
    t:log("  help                    list commands")
    t:log("  heroes                  list spawnable heroes")
    t:log("  spawn <hero|random>     add a ball-hero to the run")
    t:log("  speed <n>               game-speed multiplier (1.0 = normal)")
    t:log("  wave [n]                show or jump to wave n")
    t:log("  skip                    advance to next wave")
    t:log("  kill | clear            destroy all live bricks")
    t:log("  hp <n>                  set max hp and refill")
    t:log("  heal                    refill hp to max")
    t:log("  god                     toggle invulnerability")
    t:log("  xp <n>                  gain n xp")
    t:log("  level                   open level-up picker")
    t:log("  cls                     clear log")
  end

  C.heroes = function(t, args)
    local row = ''
    for i, h in ipairs(hero_pool) do
      row = row .. h
      if i % 5 == 0 or i == #hero_pool then
        t:log(row); row = ''
      else
        row = row .. ', '
      end
    end
  end

  C.spawn = function(t, args)
    local name = args[1]
    if not name then t:log("usage: spawn <hero|random>"); return end
    if name == 'random' then name = hero_pool[random:int(1, #hero_pool)] end
    if not valid_hero(name) then t:log("unknown hero: " .. name); return end
    t.arena:add_hero(name)
    t:log("spawned " .. name)
  end

  C.speed = function(t, args)
    local n = tonumber(args[1])
    if not n then t:log("usage: speed <n>  (e.g. 0.5, 1, 2, 5)"); return end
    admin_speed = math.max(0.1, math.min(20, n))
    t:log("game speed = " .. string.format('%.2f', admin_speed))
  end

  C.wave = function(t, args)
    if not args[1] then t:log("current wave: " .. t.arena.wave); return end
    local n = tonumber(args[1])
    if not n or n < 1 then t:log("usage: wave [n]"); return end
    -- advance_wave bumps wave by 1, so subtract 1 from the target.
    t.arena.wave = math.max(0, math.floor(n) - 1)
    t.arena:advance_wave()
    t:log("jumped to wave " .. t.arena.wave)
  end

  C.skip = function(t, args)
    t.arena:advance_wave()
    t:log("now on wave " .. t.arena.wave)
  end

  local function clear_all_bricks(arena)
    local killed = 0
    for _, swarm in ipairs(arena.swarms.objects) do
      if swarm and not swarm.dead then
        for _, cell in ipairs(swarm.cells or {}) do
          if cell.brick and not cell.brick.dead then
            cell.brick.dead = true
            killed = killed + 1
          end
        end
        swarm.dead = true
      end
    end
    return killed
  end

  C.kill  = function(t, args) t:log("killed " .. clear_all_bricks(t.arena) .. " bricks") end
  C.clear = C.kill

  C.hp = function(t, args)
    local n = tonumber(args[1])
    if not n then t:log("usage: hp <n>"); return end
    t.arena.player_hp_max = math.max(1, math.floor(n))
    t.arena.player_hp     = t.arena.player_hp_max
    t:log("hp = " .. t.arena.player_hp .. "/" .. t.arena.player_hp_max)
  end

  C.heal = function(t, args)
    t.arena.player_hp = t.arena.player_hp_max
    t:log("healed to " .. t.arena.player_hp)
  end

  C.god = function(t, args)
    t.arena.god = not t.arena.god
    t:log("godmode = " .. tostring(t.arena.god))
  end

  C.xp = function(t, args)
    local n = tonumber(args[1]) or 5
    t.arena:gain_xp(math.max(1, math.floor(n)))
  end

  C.level = function(t, args)
    t.arena:level_up()
    t:log("level-up picker opened")
  end

  C.cls = function(t, args) t.lines = {} end
end
