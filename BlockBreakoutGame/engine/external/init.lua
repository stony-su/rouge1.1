local path = ...
if not path:find("init") then
  binser = require(path .. ".binser")
  mlib = require(path .. ".mlib")
  -- if not web then clipper = require(path .. ".clipper") end
  ripple = require(path .. ".ripple")

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
