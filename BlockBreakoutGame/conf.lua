function love.conf(t)
  t.version = "11.3"
  t.identity = "RicoRite"
  t.window.width = 720
  t.window.height = 984
  t.window.vsync = 1
  t.window.msaa = 0
  t.window.title = "Rico Rite"
  -- Window / taskbar icon. Set here rather than via love.window.setIcon
  -- so it is right from the first frame instead of swapping after boot.
  -- (The .exe file icon is a Windows resource and is NOT set by this --
  -- that needs a resource editor run over the fused binary.)
  t.window.icon = "assets/icon.png"
end
