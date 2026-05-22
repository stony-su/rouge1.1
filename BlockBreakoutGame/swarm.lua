-- A Swarm is a 2D chunk of bricks that moves as a single unit.
--
-- This is the Ball-x-Pit-style replacement for single-row formations. A swarm
-- is a grid of slots (cols × rows) with some fraction of slots randomly empty,
-- so each swarm has organic-looking interior gaps. Several swarms can be on
-- screen at once, each with its own springy knockback offset.
--
-- All bricks in a swarm are kinematic; the swarm owns their positions every
-- frame. When a ball hits any brick, the swarm gets a small impulse — the
-- whole chunk shifts together and springs back, so the formation stays tidy.

Swarm = Object:extend()
Swarm:implement(GameObject)


-- Static factory: roll a per-row irregular shape and return a list of {dx, dy}
-- offsets. Lives on the class so BallPit can plan a swarm layout, run an
-- overlap test against the live grid, and only then actually spawn the swarm.
function Swarm.generate_cells(rows_count, max_cols, density, spacing_x, spacing_y)
  spacing_x = spacing_x or 22
  spacing_y = spacing_y or 14
  density   = density   or 0.88
  local cells = {}
  for r = 1, rows_count do
    local min_w   = math.max(2, math.floor(max_cols*0.55))
    local row_w   = random:int(min_w, max_cols)
    local row_off = random:int(0, max_cols - row_w)
    for k = 1, row_w do
      if random:float(0, 1) < density then
        local col_idx = row_off + k - 1
        local dx = (col_idx - (max_cols - 1)/2) * spacing_x
        local dy = (r - 1) * spacing_y
        table.insert(cells, {dx = dx, dy = dy})
      end
    end
  end
  if #cells == 0 then table.insert(cells, {dx = 0, dy = 0}) end
  return cells
end


function Swarm:init(args)
  self:init_game_object(args)

  -- Args contract:
  --   x_center       : horizontal centre of the swarm (snap-aligned by caller)
  --   y              : starting y of the TOP row of the swarm
  --   spacing_x      : horizontal pixels between brick centres
  --   spacing_y      : vertical pixels between brick centres
  --   drift          : downward drift in px/s
  --   variant_picker : zero-arg function returning a variant name per brick
  --   cells_layout   : list of {dx, dy} offsets pre-computed by BallPit
  --                    (so the arena can vet the layout against the grid
  --                    before committing the spawn).
  self.x_center    = self.x_center or gw/2
  self.y_top       = self.y or 24
  self.spacing_x   = self.spacing_x or 22
  self.spacing_y   = self.spacing_y or 14
  self.drift_speed = self.drift or 4
  local picker     = self.variant_picker or function() return 'seeker' end
  local layout     = self.cells_layout or {{dx = 0, dy = 0}}

  -- Spring offsets for knockback. Damped harmonic oscillator on (x_off, y_off).
  self.x_offset = 0
  self.y_offset = 0
  self.vx       = 0
  self.vy       = 0
  self.spring_k = 80
  self.damping  = 6

  -- Place bricks at each pre-planned offset.
  self.cells = {}
  for _, c in ipairs(layout) do
    local brick = Brick{
      group   = main.current.main,
      x       = self.x_center + c.dx,
      y       = self.y_top + c.dy,
      variant = picker(),
      swarm   = self,
    }
    table.insert(self.cells, {brick = brick, dx = c.dx, dy = c.dy})
  end
end


function Swarm:update(dt)
  self:update_game_object(dt)

  -- Damped harmonic oscillator on the (x_offset, y_offset) pair.
  local ax = -self.spring_k*self.x_offset - self.damping*self.vx
  local ay = -self.spring_k*self.y_offset - self.damping*self.vy
  self.vx = self.vx + ax*dt
  self.vy = self.vy + ay*dt
  self.x_offset = self.x_offset + self.vx*dt
  self.y_offset = self.y_offset + self.vy*dt

  -- Continuous downward drift.
  self.y_top = self.y_top + self.drift_speed*dt

  -- Reposition surviving bricks and track lowest occupied y for breach test.
  local alive_count = 0
  local lowest_y    = -1/0
  for _, cell in ipairs(self.cells) do
    if cell.brick and not cell.brick.dead then
      alive_count = alive_count + 1
      local bx = self.x_center + cell.dx + self.x_offset
      local by = self.y_top + cell.dy + self.y_offset
      cell.brick:set_position(bx, by)
      if by > lowest_y then lowest_y = by end
    end
  end

  -- Garbage-collect dead cells so they don't pile up in the list.
  for i = #self.cells, 1, -1 do
    if self.cells[i].brick.dead then table.remove(self.cells, i) end
  end

  if alive_count == 0 then
    self.dead = true
    return
  end

  -- Breach: the lowest still-alive brick crossed the paddle line.
  local arena = main.current
  if arena and arena.paddle and lowest_y > arena.paddle.y - 10 then
    arena:on_row_breached(self, alive_count)
    for _, cell in ipairs(self.cells) do
      if cell.brick and not cell.brick.dead then cell.brick.dead = true end
    end
    self.dead = true
  end
end


-- Called by a brick on ball contact. `force` is the magnitude, `angle` the
-- direction the swarm gets shoved. Intentionally small so the formation only
-- nudges a few pixels before springing back.
function Swarm:apply_knockback(force, angle)
  self.vx = self.vx + force*math.cos(angle)
  self.vy = self.vy + force*math.sin(angle)
end


function Swarm:draw() end
