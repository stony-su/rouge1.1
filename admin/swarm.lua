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


-- Shape catalogue. Each entry lists {col, row} cell offsets relative to its
-- own top-left and a `weight` controlling how often the placer picks it from
-- among the shapes that fit at a given grid spot. 1×1 is overwhelmingly
-- favoured so swarms still read as "a wall of small bricks with the
-- occasional big or weird piece" rather than a tetris assortment. Note that
-- each multi-cell shape also consumes multiple grid cells per pick, so a
-- single 3×3 displaces 9 potential 1×1s — the weight ratio understates how
-- dominant 1×1 really is in the placed result.
-- All shapes fit inside a 3x3 box so a wide enough swarm can host any of
-- them.
local SHAPES = {
  -- Rectangles (1x1 → 3x3)
  {cells = {{0,0}},                                                          weight = 200, name = '1x1'},
  {cells = {{0,0}, {1,0}},                                                   weight =   4, name = '2x1'},
  {cells = {{0,0}, {0,1}},                                                   weight =   3, name = '1x2'},
  {cells = {{0,0}, {1,0}, {2,0}},                                            weight =   2, name = '3x1'},
  {cells = {{0,0}, {0,1}, {0,2}},                                            weight =   1, name = '1x3'},
  {cells = {{0,0}, {1,0}, {0,1}, {1,1}},                                     weight =   2, name = '2x2'},
  {cells = {{0,0}, {1,0}, {2,0}, {0,1}, {1,1}, {2,1}},                       weight =   1, name = '3x2'},
  {cells = {{0,0}, {1,0}, {0,1}, {1,1}, {0,2}, {1,2}},                       weight =   1, name = '2x3'},
  {cells = {{0,0}, {1,0}, {2,0}, {0,1}, {1,1}, {2,1}, {0,2}, {1,2}, {2,2}},  weight =   1, name = '3x3'},
  -- Tetris pieces (all fit inside 3x3; O is omitted since it equals 2x2)
  {cells = {{0,0}, {1,0}, {2,0}, {1,1}},                                     weight =   1, name = 'T'},
  {cells = {{0,0}, {0,1}, {0,2}, {1,2}},                                     weight =   1, name = 'L'},
  {cells = {{1,0}, {1,1}, {0,2}, {1,2}},                                     weight =   1, name = 'J'},
  {cells = {{1,0}, {2,0}, {0,1}, {1,1}},                                     weight =   1, name = 'S'},
  {cells = {{0,0}, {1,0}, {1,1}, {2,1}},                                     weight =   1, name = 'Z'},
}

-- Precompute per-shape centroid/bounds so the placer doesn't recompute them
-- every spawn. Centroid is in cell-units; the brick's body position ends up
-- at this centroid so multi-cell bricks balance on their visual centre.
for _, s in ipairs(SHAPES) do
  local mnc, mxc, mnr, mxr = 1/0, -1/0, 1/0, -1/0
  local sum_c, sum_r = 0, 0
  for _, c in ipairs(s.cells) do
    if c[1] < mnc then mnc = c[1] end
    if c[1] > mxc then mxc = c[1] end
    if c[2] < mnr then mnr = c[2] end
    if c[2] > mxr then mxr = c[2] end
    sum_c = sum_c + c[1]; sum_r = sum_r + c[2]
  end
  s.cols, s.rows           = mxc - mnc + 1, mxr - mnr + 1
  s.centroid_cx            = sum_c / #s.cells
  s.centroid_cy            = sum_r / #s.cells
end


-- Static factory: roll an irregular formation that includes 1x1 through 3x3
-- rectangles and tetris pieces, returning a list of {dx, dy, shape_cells}
-- entries. dx/dy is the brick's CENTROID in pixel space, relative to the
-- swarm anchor. Lives on the class so BallPit can plan a swarm layout, run
-- an overlap test against the live grid, and only then commit the spawn.
function Swarm.generate_cells(rows_count, max_cols, density, spacing_x, spacing_y)
  spacing_x = spacing_x or 22
  spacing_y = spacing_y or 14
  density   = density   or 0.88

  -- 2D occupancy grid covering the planning area. Each spot gets visited
  -- once in row-major order so the placer never tries to overlap a shape
  -- with a cell it already claimed.
  local occupied = {}
  for r = 0, rows_count - 1 do occupied[r] = {} end

  local function fits(shape, col, row)
    for _, c in ipairs(shape.cells) do
      local cc, rr = col + c[1], row + c[2]
      if cc < 0 or cc >= max_cols or rr < 0 or rr >= rows_count then return false end
      if occupied[rr][cc] then return false end
    end
    return true
  end

  local function claim(shape, col, row)
    for _, c in ipairs(shape.cells) do
      occupied[row + c[2]][col + c[1]] = true
    end
  end

  local cells = {}
  for row = 0, rows_count - 1 do
    for col = 0, max_cols - 1 do
      if not occupied[row][col] and random:float(0, 1) < density then
        -- Build the candidate list each cell since fit depends on neighbours.
        local candidates, total_w = {}, 0
        for _, s in ipairs(SHAPES) do
          if fits(s, col, row) then
            table.insert(candidates, s)
            total_w = total_w + s.weight
          end
        end
        if #candidates > 0 then
          local roll = random:float(0, total_w)
          local pick
          for _, s in ipairs(candidates) do
            roll = roll - s.weight
            if roll <= 0 then pick = s; break end
          end
          pick = pick or candidates[#candidates]
          claim(pick, col, row)

          -- dx/dy is the brick centroid in pixels, relative to the swarm
          -- anchor (x_center, y_top). The shape's centroid is in cell-units,
          -- offset by the placement (col, row).
          local centroid_col = col + pick.centroid_cx
          local centroid_row = row + pick.centroid_cy
          local dx = (centroid_col - (max_cols - 1)/2) * spacing_x
          local dy = centroid_row * spacing_y
          table.insert(cells, {dx = dx, dy = dy, shape_cells = pick.cells})
        end
      end
    end
  end

  if #cells == 0 then table.insert(cells, {dx = 0, dy = 0, shape_cells = {{0,0}}}) end
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
      group       = main.current.main,
      x           = self.x_center + c.dx,
      y           = self.y_top + c.dy,
      variant     = picker(),
      swarm       = self,
      shape_cells = c.shape_cells,
    }
    -- shape_cells is mirrored on the swarm cell record so the arena's
    -- cross-swarm overlap test (BallPit:can_place_layout) and zone-occupancy
    -- counter can see brick footprints without having to dereference the
    -- live Brick instance every iteration.
    table.insert(self.cells, {brick = brick, dx = c.dx, dy = c.dy, shape_cells = c.shape_cells})
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

  -- Reposition surviving bricks and track the lowest occupied y for the
  -- breach test. For multi-cell bricks, the brick body lives at the shape
  -- centroid, so the lowest point is the bottom edge of the lowest cell
  -- (Brick:bottom_y), not the body y itself.
  local alive_count = 0
  local lowest_y    = -1/0
  for _, cell in ipairs(self.cells) do
    if cell.brick and not cell.brick.dead then
      alive_count = alive_count + 1
      local bx = self.x_center + cell.dx + self.x_offset
      local by = self.y_top + cell.dy + self.y_offset
      cell.brick:set_position(bx, by)
      local cell_bottom = cell.brick:bottom_y()
      if cell_bottom > lowest_y then lowest_y = cell_bottom end
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
