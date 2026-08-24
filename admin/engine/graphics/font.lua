-- The base Font class.
--
-- `tracking` is LETTER SPACING: extra advance, in font pixels, inserted after
-- every glyph but the last. LOVE fonts expose no such knob, so graphics.print
-- honours it by walking the string a glyph at a time (see graphics.lua); the
-- cost is only paid by fonts that actually set it. Negative values tighten a
-- run -- PixulBrush-Mono pads every glyph out to a 10px cell while the ink is
-- at most 8px wide, so -1 pulls it back to a single-pixel gutter.
--
-- get_text_width folds tracking in, so every caller that measures before it
-- draws (centring, right-alignment, word wrap) stays correct for free.
Font = Object:extend()
function Font:init(asset_name, font_size, tracking)
  self.font = love.graphics.newFont("assets/fonts/" .. asset_name .. ".ttf", font_size)
  self.h = self.font:getHeight()
  self.tracking = tracking or 0
end


function Font:get_text_width(text)
  local w = self.font:getWidth(text)
  -- #text is the glyph count: every string drawn in a tracked font is ASCII.
  if self.tracking == 0 or #text < 2 then return w end
  return w + self.tracking*(#text - 1)
end


function Font:get_height()
  return self.font:getHeight()
end
