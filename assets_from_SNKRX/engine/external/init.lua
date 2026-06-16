local path = ...
if not path:find("init") then
  binser = require(path .. ".binser")
  mlib = require(path .. ".mlib")
  -- if not web then clipper = require(path .. ".clipper") end
  ripple = require(path .. ".ripple")
  -- luasteam is the native Steam binding; it isn't bundled with this source dump,
  -- so load it safely and fall back to a no-op stub (any steam.*() call returns
  -- false / does nothing) when it's missing -- lets the game boot without Steam.
  local ok, mod = pcall(require, 'luasteam')
  if ok then
    steam = mod
  else
    steam = setmetatable({
      userStats = setmetatable({}, {__index = function() return function() end end}),
      friends = setmetatable({}, {__index = function() return function() end end}),
    }, {__index = function() return function() return false end end})
  end
end
