#!/usr/bin/env python3
"""
Rico Rite -- Steam store graphical asset generator.

Renders the five required Steam capsules using the game's OWN visual language,
reproducing the real render pipeline from BlockBreakoutGame/:

  * palette          -- shared.lua shared_init()   (#0c0c14 bg, hero ramps)
  * background grid  -- shared.lua GRID_BASE / GRID_CELL, 15px checker
  * brick body       -- brick.lua Brick:draw()     (18x10 r1 body + 16x8 dark inset)
  * brick grid       -- brick.lua CELL_W/CELL_H    (22 x 14 spacing)
  * swarm shapes     -- swarm.lua SHAPES           (1x1..3x3 + tetrominoes)
  * breach line      -- ballpit.lua                (red dashed, 5 on / 4 off)
  * paddle           -- paddle.lua                 (ghost wings + emblem core)
  * drop shadow      -- shadow.frag                (rgb 0.1, alpha*0.5, +1.5px)
  * upscale          -- engine/init.lua            (nearest filter)

Everything is drawn in GAME PIXELS at SSx supersample, box-downsampled to the
game-pixel grid (which is what LOVE's antialiased vector draws produce), then
upscaled by an integer factor with NEAREST -- so the assets carry the same
chunky pixel cadence the player actually sees on screen.

Usage:  python capsule_generator.py
Output: the five Steam PNGs, beside this file.
"""

import math
import os
import random
import colorsys

from PIL import Image, ImageDraw, ImageFont, ImageChops, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_PATH = os.path.join(HERE, "..", "BlockBreakoutGame", "assets", "fonts", "FatPixelFont.ttf")

SS = 4  # supersample factor inside game-pixel space


# ---------------------------------------------------------------------------
# Palette -- lifted verbatim from shared.lua shared_init()
# ---------------------------------------------------------------------------

def _hex(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


PAL = {
    "white":   _hex("#ffffff"),
    "bg":      _hex("#0c0c14"),
    "fg":      _hex("#dadada"),
    "fg_alt":  _hex("#b0a89f"),
    "yellow":  _hex("#facf00"),
    "orange":  _hex("#f07021"),
    "blue":    _hex("#019bd6"),
    "green":   _hex("#8bbf40"),
    "red":     _hex("#e91d39"),
    "purple":  _hex("#8e559e"),
    "blue2":   _hex("#4778ba"),
    "yellow2": _hex("#f59f10"),
}

# shared.lua GRID_BASE / GRID_CELL -- the near-black checker under the play field
GRID_BASE = (4, 4, 7)
GRID_CELL = (2, 2, 4)
GRID_PITCH = 15


def lighten(rgb, v):
    """engine/graphics/color.lua Color:lighten -- an HSL lightness offset."""
    r, g, b = [c / 255.0 for c in rgb]
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = max(0.0, min(1.0, l + v))
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return (int(r * 255), int(g * 255), int(b * 255))


def mul(rgb, f):
    return tuple(max(0, min(255, int(c * f))) for c in rgb)


def rgba(rgb, a):
    return (rgb[0], rgb[1], rgb[2], max(0, min(255, int(a * 255))))


# ---------------------------------------------------------------------------
# Scene -- a game-pixel canvas with the engine's compositing layers
# ---------------------------------------------------------------------------

class Scene:
    """
    obj  -- RGBA object layer; casts the +1.5px shadow, like main_canvas.
    glow -- RGB additive layer for bloom (the engine's stacked alpha circles).
    """

    BRICK_W, BRICK_H = 18, 10
    CELL_W, CELL_H = 22, 14

    SHAPES = [
        ([(0, 0)], 200), ([(0, 0), (1, 0)], 5), ([(0, 0), (0, 1)], 3),
        ([(0, 0), (1, 0), (2, 0)], 2), ([(0, 0), (0, 1), (0, 2)], 1),
        ([(0, 0), (1, 0), (0, 1), (1, 1)], 3),
        ([(0, 0), (1, 0), (2, 0), (1, 1)], 2),   # T
        ([(0, 0), (0, 1), (0, 2), (1, 2)], 2),   # L
        ([(1, 0), (2, 0), (0, 1), (1, 1)], 2),   # S
        ([(0, 0), (1, 0), (1, 1), (2, 1)], 2),   # Z
    ]

    def __init__(self, gw, gh, seed=7, z=1.0):
        """
        z -- "camera distance". Every entity keeps its exact in-game proportions
        but is drawn z times larger. Capsules are viewed small and compressed;
        at z = 1 the 1px bright brick frame collapses against the 0.7 interior
        and the whole swarm goes muddy brown. z pulls the camera in instead of
        redesigning anything, so the art stays honest to the game.
        """
        self.gw, self.gh = gw, gh
        self.z = z
        self.W, self.H = gw * SS, gh * SS
        self.obj = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        self.glow = Image.new("RGB", (self.W, self.H), (0, 0, 0))
        self.d = ImageDraw.Draw(self.obj, "RGBA")
        self.gd = ImageDraw.Draw(self.glow, "RGBA")
        self.rng = random.Random(seed)

    # ---- primitives (coordinates in game pixels) ----

    def rect(self, cx, cy, w, h, color, a=1.0, r=0):
        x0, y0 = (cx - w / 2) * SS, (cy - h / 2) * SS
        x1, y1 = (cx + w / 2) * SS, (cy + h / 2) * SS
        if r:
            self.d.rounded_rectangle([x0, y0, x1, y1], radius=r * SS, fill=rgba(color, a))
        else:
            self.d.rectangle([x0, y0, x1, y1], fill=rgba(color, a))

    def circle(self, cx, cy, rad, color, a=1.0, layer=None):
        d = layer if layer is not None else self.d
        d.ellipse([(cx - rad) * SS, (cy - rad) * SS,
                   (cx + rad) * SS, (cy + rad) * SS], fill=rgba(color, a))

    def ring(self, cx, cy, rad, color, a=1.0, w=1):
        self.d.ellipse([(cx - rad) * SS, (cy - rad) * SS,
                        (cx + rad) * SS, (cy + rad) * SS],
                       outline=rgba(color, a), width=max(1, int(w * SS)))

    def line(self, x0, y0, x1, y1, color, a=1.0, w=1):
        self.d.line([x0 * SS, y0 * SS, x1 * SS, y1 * SS],
                    fill=rgba(color, a), width=max(1, int(w * SS)))

    def poly(self, pts, color, a=1.0):
        self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=rgba(color, a))

    def dashed_line(self, x0, y, x1, color, a, dash=5, gap=4, w=1):
        """ballpit.lua graphics.dashed_line(..., 5, 4, ...) -- the defense line."""
        x = x0
        while x < x1:
            self.line(x, y, min(x + dash, x1), y, color, a, w)
            x += dash + gap

    def glow_at(self, cx, cy, rad, color, strength=0.5, steps=14):
        """
        Stacked falling-alpha circles into the additive layer -- the same idiom
        as Paddle:core_halo and the effect entities, which is what gives the
        game its soft neon bloom without a real blur pass.
        """
        for i in range(steps, 0, -1):
            t = i / steps
            a = strength * (1.0 - t) ** 2 / steps * 3.2
            self.circle(cx, cy, rad * t, color, a, layer=self.gd)

    # ---- game entities ----

    def brick(self, cx, cy, color, cells=((0, 0),), a=1.0, glow=0.0):
        """
        brick.lua Brick:draw() -- per cell an 18x10 r1 body in the variant
        colour with a 16x8 sharp-cornered interior at 0.7 brightness.
        """
        z = self.z
        dark = mul(color, 0.7)
        sx = sum(c[0] for c in cells) / len(cells)
        sy = sum(c[1] for c in cells) / len(cells)
        for c in cells:
            x = cx + (c[0] - sx) * self.CELL_W * z
            y = cy + (c[1] - sy) * self.CELL_H * z
            if glow:
                self.glow_at(x, y, self.BRICK_W * z * 1.5, color, glow, steps=8)
            self.rect(x, y, self.BRICK_W * z, self.BRICK_H * z, color, a, r=1 * z)
            self.rect(x, y, (self.BRICK_W - 2) * z, (self.BRICK_H - 2) * z, dark, a)

    def ball(self, cx, cy, r, color, glow=1.0):
        r *= self.z
        self.glow_at(cx, cy, r * 5.0, color, 0.62 * glow)
        self.circle(cx, cy, r, color)
        self.circle(cx - r * 0.30, cy - r * 0.32, r * 0.30, lighten(color, 0.30), 0.85)

    def trail(self, x, y, ang, color, n=9, step=5.5, r0=3.2, a0=0.5):
        """Motion sampler: a tapering string of dots behind a moving ball."""
        step *= self.z
        r0 *= self.z
        for i in range(n):
            t = 1.0 - i / n
            d = (i + 1) * step
            wob = math.sin(i * 0.9) * 1.4 * self.z
            px = x - math.cos(ang) * d - math.sin(ang) * wob
            py = y - math.sin(ang) * d + math.cos(ang) * wob
            self.circle(px, py, r0 * t, color, a0 * t * t)

    def paddle(self, cx, cy, w=108, color=None, emblem=None):
        """paddle.lua -- ghosted wing rig (WING_ALPHA) + solid emblem core."""
        z = self.z
        color = color or PAL["fg"]
        emblem = emblem or PAL["blue"]
        self.rect(cx, cy, w * z, 4 * z, color, 0.34, r=2 * z)
        for i in range(1, 4):                       # core_shoulders
            a = 0.26 - (i - 1) * 0.08
            self.line(cx - (4 * i + 5) * z, cy, cx - (4 * (i - 1) + 5) * z, cy, emblem, a, z)
            self.line(cx + (4 * (i - 1) + 5) * z, cy, cx + (4 * i + 5) * z, cy, emblem, a, z)
        r = 9 * z
        self.glow_at(cx, cy, r * 4.5, emblem, 0.9)
        for i in (3, 2, 1):                         # core_halo
            self.circle(cx, cy, r + i * 2.2 * z, emblem, 0.07 * (4 - i))
        self.circle(cx, cy, r, emblem)
        self.circle(cx, cy, r - 2.2 * z, mul(emblem, 0.45))
        self.ring(cx, cy, r - 4.2 * z, lighten(emblem, 0.25), 0.9, z)
        self.circle(cx, cy, 1.6 * z, PAL["white"], 0.95)

    def enemy_shot(self, x, y, ang, color=None, r=2.6, n=7):
        """enemies.lua EnemyProjectile -- the bullet-hell rain coming down."""
        color = color or PAL["red"]
        r *= self.z
        for i in range(n):
            t = 1.0 - i / n
            d = (i + 1) * 4.2 * self.z
            self.circle(x - math.cos(ang) * d, y - math.sin(ang) * d,
                        r * 0.72 * t, color, 0.34 * t * t)
        self.glow_at(x, y, r * 5.5, color, 0.45)
        self.circle(x, y, r, color)
        self.circle(x, y, r * 0.42, PAL["white"], 0.9)

    def breach_line(self, x0, x1, y, a=0.50):
        self.glow_at((x0 + x1) / 2, y, (x1 - x0) * 0.42, PAL["red"], 0.13, steps=10)
        self.dashed_line(x0, y, x1, PAL["red"], a,
                         dash=5 * self.z, gap=4 * self.z, w=self.z)

    def burst(self, cx, cy, color, n=10, r0=8, r1=26, size=1.4):
        for _ in range(n):
            ang = self.rng.uniform(0, math.tau)
            d = self.rng.uniform(r0, r1) * self.z
            self.circle(cx + math.cos(ang) * d, cy + math.sin(ang) * d,
                        size * self.z * self.rng.uniform(0.6, 1.4), color,
                        self.rng.uniform(0.45, 0.95))

    def explosion(self, cx, cy, color=None, scale=1.0):
        """
        effects.lua spawn_burst -- radiating spark streaks, not concentric
        rings. Clean rings around a bright core read as a ringed planet at
        capsule size; what says "blast" is debris travelling outward.
        """
        color = color or PAL["orange"]
        k = scale * self.z
        self.glow_at(cx, cy, 50 * k, color, 1.40)
        self.glow_at(cx, cy, 22 * k, PAL["yellow"], 1.20)

        # One faint shockwave, then irregular debris. Evenly spaced rays with a
        # dot on the end draw a dandelion, so angles, lengths and sizes are all
        # rolled independently and most fragments carry no head at all.
        self.ring(cx, cy, 19 * k, color, 0.18, self.z)
        for _ in range(9):                      # short motion streaks
            a = self.rng.uniform(0, math.tau)
            r0 = self.rng.uniform(5, 14) * k
            r1 = r0 + self.rng.uniform(2, 10) * k
            col = PAL["yellow"] if self.rng.random() < 0.6 else color
            self.line(cx + math.cos(a) * r0, cy + math.sin(a) * r0,
                      cx + math.cos(a) * r1, cy + math.sin(a) * r1,
                      col, self.rng.uniform(0.30, 0.62), self.z)
        for _ in range(13):                     # square shrapnel
            a = self.rng.uniform(0, math.tau)
            d = self.rng.uniform(6, 27) * k
            sz = 1.15 * k * self.rng.uniform(0.55, 1.25)
            self.rect(cx + math.cos(a) * d, cy + math.sin(a) * d, sz * 2, sz * 2,
                      PAL["yellow"] if self.rng.random() < 0.55 else color,
                      self.rng.uniform(0.6, 0.95))

        self.circle(cx, cy, 7.6 * k, PAL["yellow"], 0.90)
        self.circle(cx, cy, 4.0 * k, PAL["white"], 0.96)

    def arrow(self, x, y, ang, color, length=13, streak=26):
        """projectile.lua shooters -- a bolt with a motion streak behind it."""
        z = self.z
        length, streak = length * z, streak * z
        dx, dy = math.cos(ang), math.sin(ang)
        self.line(x - dx * streak, y - dy * streak, x, y, color, 0.28, z)
        self.line(x - dx * length, y - dy * length, x, y, color, 0.95, z)
        px, py = -dy, dx
        self.poly([(x + dx * 3.5 * z, y + dy * 3.5 * z),
                   (x - dx * 3 * z + px * 2.6 * z, y - dy * 3 * z + py * 2.6 * z),
                   (x - dx * 3 * z - px * 2.6 * z, y - dy * 3 * z - py * 2.6 * z)], color)
        self.glow_at(x, y, 13 * z, color, 0.45)

    def blade(self, x, y, ang, color, r=4.4):
        """spellblade blade_storm shard -- a spinning diamond."""
        r *= self.z
        pts = []
        for k in range(4):
            a = ang + k * math.pi / 2
            rr = r if k % 2 == 0 else r * 0.45
            pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
        self.poly(pts, color)
        self.glow_at(x, y, 15 * self.z, color, 0.50)

    def xp_orb(self, x, y, r=2.2):
        r *= self.z
        self.glow_at(x, y, 11 * self.z, PAL["blue"], 0.45)
        self.circle(x, y, r, PAL["blue"])
        self.circle(x, y, r * 0.45, PAL["white"], 0.85)

    def swarm(self, x0, y0, cols, rows, colors, density=0.72, a=1.0,
              jitter=1.6, glow=0.10, flash=0.05):
        """
        swarm.lua -- a springy chunk of bricks on the 22x14 cell grid. The gaps
        and the per-brick jitter are what separate a SWARM from a Breakout wall:
        a Swarm owns its bricks' positions and they ride its spring, so the rows
        never sit perfectly true.
        """
        taken = set()
        pool = []
        for cells, w in self.SHAPES:
            pool += [cells] * w
        for r in range(rows):
            for c in range(cols):
                if (c, r) in taken or self.rng.random() > density:
                    continue
                cells = self.rng.choice(pool)
                abs_cells = [(c + dc, r + dr) for dc, dr in cells]
                if any(k in taken or k[0] >= cols or k[1] >= rows for k in abs_cells):
                    cells, abs_cells = [(0, 0)], [(c, r)]
                taken.update(abs_cells)
                mcx = sum(k[0] for k in abs_cells) / len(abs_cells)
                mcy = sum(k[1] for k in abs_cells) / len(abs_cells)
                jx = self.rng.uniform(-jitter, jitter) * self.z
                jy = self.rng.uniform(-jitter, jitter) * self.z
                # Brick:draw swaps body_color to fg[0] while hfx.hit is firing,
                # so a few white bricks read as "being hit right now".
                hit = self.rng.random() < flash
                col = PAL["fg"] if hit else self.rng.choice(colors)
                self.brick(x0 + mcx * self.CELL_W * self.z + jx,
                           y0 + mcy * self.CELL_H * self.z + jy,
                           col, cells, a, glow=0.42 if hit else glow)

    # ---- compositing ----

    def compose(self, vignette=0.0, scrims=(), bg_glows=()):
        base = Image.new("RGB", (self.W, self.H), GRID_BASE)
        bd = ImageDraw.Draw(base)
        p = GRID_PITCH * SS
        for j in range(self.gh // GRID_PITCH + 2):
            for i in range(self.gw // GRID_PITCH + 2):
                if (i + j) % 2 == 0:
                    bd.rectangle([i * p, j * p, i * p + p - 1, j * p + p - 1], fill=GRID_CELL)

        # Ambient arena light: wide, very low-alpha colour washes, so the near
        # black field reads as lit space rather than a flat void.
        if bg_glows:
            wash = Image.new("RGB", (self.W, self.H), (0, 0, 0))
            wd = ImageDraw.Draw(wash, "RGBA")
            for (cx, cy, rad, col, st) in bg_glows:
                for i in range(18, 0, -1):
                    t = i / 18
                    wd.ellipse([(cx - rad * t) * SS, (cy - rad * t) * SS,
                                (cx + rad * t) * SS, (cy + rad * t) * SS],
                               fill=rgba(col, st * (1 - t) ** 2 / 18 * 3.0))
            base = ImageChops.add(base, wash)

        # Darkening scrims sit UNDER the objects, so the plate that makes the
        # wordmark legible never dims the art standing in front of it.
        for (cx, cy, rx, ry, strength) in scrims:
            sc = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
            sd = ImageDraw.Draw(sc, "RGBA")
            for i in range(20, 0, -1):
                t = i / 20
                sd.ellipse([(cx - rx * t) * SS, (cy - ry * t) * SS,
                            (cx + rx * t) * SS, (cy + ry * t) * SS],
                           fill=(0, 0, 0, int(255 * strength * (1 - t) ** 1.6 / 20 * 3.2)))
            base = Image.alpha_composite(base.convert("RGBA"), sc).convert("RGB")

        # shadow.frag: rgb 0.1, alpha*0.5, drawn at +1.5px (shared.lua compose)
        shadow = Image.new("RGBA", (self.W, self.H), (26, 26, 26, 0))
        shadow.putalpha(self.obj.split()[3].point(lambda v: int(v * 0.5)))
        off = int(1.5 * SS)
        shifted = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        shifted.paste(shadow, (off, off))
        base = Image.alpha_composite(base.convert("RGBA"), shifted)
        base = Image.alpha_composite(base, self.obj).convert("RGB")
        base = ImageChops.add(base, self.glow)

        game = base.resize((self.gw, self.gh), Image.Resampling.BOX)

        if vignette:
            v = Image.new("L", (self.gw, self.gh), 0)
            vd = ImageDraw.Draw(v)
            steps = 26
            for i in range(steps):
                t = i / steps
                ix, iy = self.gw * 0.28 * t, self.gh * 0.28 * t
                vd.rectangle([ix, iy, self.gw - ix, self.gh - iy],
                             fill=int(255 * (1 - t) ** 2))
            v = v.filter(ImageFilter.GaussianBlur(self.gw * 0.02))
            dark = Image.new("RGB", (self.gw, self.gh), (0, 0, 0))
            game = Image.composite(game, Image.blend(game, dark, vignette), v)
        return game


# ---------------------------------------------------------------------------
# Wordmark -- FatPixelFont, the game's own title face. It rasterises with zero
# midtones at every multiple of 8, so size = 8*m gives m x m device pixels per
# font pixel and the wordmark shares the scene's pixel grid exactly.
# ---------------------------------------------------------------------------

def wordmark(img, text, m, cx, cy, fill_top=(255, 255, 255), fill_bot=None,
             outline=None, glow_col=None, glow_strength=1.0):
    fill_bot = fill_bot or PAL["fg"]
    outline = outline or lighten(PAL["bg"], -0.045)
    font = ImageFont.truetype(FONT_PATH, 8 * m)
    bb = font.getbbox(text)

    pad = m * 16   # room for the wide glow pass to fall off inside the mask
    mask = Image.new("L", (bb[2] - bb[0] + pad * 2, bb[3] - bb[1] + pad * 2), 0)
    ImageDraw.Draw(mask).text((pad - bb[0], pad - bb[1]), text, font=font, fill=255)

    ox = int(cx - mask.width / 2)
    oy = int(cy - mask.height / 2)

    img = img.convert("RGB")

    # Additive glow behind the letters, so the wordmark sits in the same light
    # as the art rather than on top of it.
    if glow_col:
        # Deliberately wide and weak: a tight bright glow builds a visible
        # rectangle of haze around the block of letters instead of reading as
        # light. Two passes, one broad wash and one close halo.
        acc = Image.new("L", mask.size, 0)
        for blur, amt in ((m * 9.0, 0.30), (m * 3.0, 0.16)):
            g = mask.filter(ImageFilter.GaussianBlur(blur))
            acc = ImageChops.add(acc, g.point(lambda v: int(v * amt * glow_strength)))
        layer = Image.new("RGB", img.size, (0, 0, 0))
        layer.paste(Image.new("RGB", mask.size, glow_col), (ox, oy), acc)
        img = ImageChops.add(img, layer)

    # Square pixel outline: dilate the glyph mask by exactly one font pixel.
    out_mask = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(2 * m + 1)), mask)
    img.paste(Image.new("RGB", mask.size, outline), (ox, oy), out_mask)

    # Two-tone vertical fill -- bright at the top, settling into fg[0].
    grad = Image.new("RGB", mask.size)
    gd = ImageDraw.Draw(grad)
    for y in range(mask.size[1]):
        t = (y / max(1, mask.size[1] - 1)) ** 1.5
        gd.line([(0, y), (mask.size[0], y)],
                fill=tuple(int(fill_top[k] + (fill_bot[k] - fill_top[k]) * t) for k in range(3)))
    img.paste(grad, (ox, oy), mask)
    return img


def finish(game_img, scale, out_name, expect):
    """engine/init.lua sets a nearest filter -- upscale the same way."""
    w, h = game_img.size
    final = game_img.resize((w * scale, h * scale), Image.Resampling.NEAREST)
    assert final.size == expect, f"{out_name}: got {final.size}, want {expect}"
    final.save(os.path.join(HERE, out_name), "PNG", optimize=True)
    print("  %-34s %dx%d" % (out_name, final.size[0], final.size[1]))


BRICKS = [PAL["red"], PAL["green"], PAL["blue"], PAL["orange"], PAL["yellow"],
          PAL["purple"], PAL["blue2"], PAL["yellow2"], PAL["fg"]]
HEROES = [PAL["fg"], PAL["yellow"], PAL["blue"], PAL["green"], PAL["red"],
          PAL["orange"], PAL["purple"], PAL["yellow2"]]


# ---------------------------------------------------------------------------
# Shared scene beats
# ---------------------------------------------------------------------------

def hero_volley(s, balls):
    """balls = [(x, y, r, colour, angle, trail_len)] -- ball + aftertrail."""
    for (x, y, r, col, ang, n) in balls:
        s.trail(x, y, ang, col, n=n, step=r * 1.05, r0=r * 0.72, a0=0.46)
        s.ball(x, y, r, col)


def fire(s, shots):
    for (kind, x, y, ang, col) in shots:
        if kind == "arrow":
            s.arrow(x, y, ang, col)
        else:
            s.blade(x, y, ang, col)


def orbs(s, pts):
    for (x, y) in pts:
        s.xp_orb(x, y)


# ---------------------------------------------------------------------------
# 1. Main capsule -- 1232 x 706  (key art, front-page carousel)
# ---------------------------------------------------------------------------

def main_capsule():
    """
    Banded so the wordmark gets a clear lane and nothing important is drawn
    under it:  swarm 20-130  |  fire 130-168  |  RICO RITE 172-232  |
    heroes 236-300  |  breach 306  |  paddle 332.
    """
    S, GW, GH = 2, 616, 353
    s = Scene(GW, GH, seed=11, z=1.55)

    # Separate formations rather than one wall -- the gaps between swarms are
    # how the game actually looks, and they let the backdrop breathe.
    s.swarm(44, 26, 8, 4, BRICKS, density=0.80)
    s.swarm(302, 18, 6, 3, BRICKS, density=0.78)
    s.swarm(466, 42, 5, 4, BRICKS, density=0.72)
    s.swarm(156, 100, 6, 2, BRICKS, density=0.52, a=0.9)

    for (x, y, sc) in [(124, 98, 1.3), (394, 52, 1.0), (306, 120, 0.8), (524, 112, 0.9)]:
        s.explosion(x, y, PAL["orange"], sc)

    # Enemy fire raining down past the heroes going up. The two-way traffic is
    # the thing that separates this from Breakout.
    for (x, y, a, col) in [(88, 150, 1.45, PAL["red"]), (238, 160, 1.72, PAL["purple"]),
                           (410, 146, 1.40, PAL["red"]), (556, 158, 1.62, PAL["blue2"]),
                           (150, 252, 1.52, PAL["purple"]), (466, 262, 1.78, PAL["red"]),
                           (596, 244, 1.66, PAL["red"])]:
        s.enemy_shot(x, y, a, col)

    fire(s, [
        ("arrow", 186, 146, -math.pi / 2 - 0.16, PAL["green"]),
        ("arrow", 272, 158, -math.pi / 2 + 0.10, PAL["green"]),
        ("arrow", 448, 140, -math.pi / 2 - 0.28, PAL["green"]),
        ("blade", 336, 148, 0.7, PAL["blue"]),
        ("blade", 360, 166, 2.1, PAL["blue"]),
        ("blade", 312, 168, 1.3, PAL["blue"]),
        ("arrow", 96, 164, -math.pi / 2 + 0.34, PAL["red"]),
        ("arrow", 528, 160, -math.pi / 2 - 0.40, PAL["red"]),
        ("blade", 208, 262, 0.4, PAL["blue"]),
        ("blade", 392, 280, 1.9, PAL["blue"]),
    ])

    # The party, below the wordmark, every trail streaming down behind it.
    hero_volley(s, [
        (74, 250, 6.5, PAL["yellow"], -1.75, 11),
        (168, 268, 6.0, PAL["green"], -1.35, 10),
        (262, 246, 7.0, PAL["red"], -2.05, 12),
        (352, 262, 6.0, PAL["blue"], -1.15, 10),
        (442, 244, 6.5, PAL["purple"], -1.95, 11),
        (534, 268, 5.5, PAL["orange"], -1.45, 9),
        (26, 276, 5.5, PAL["fg"], -1.10, 9),
        (300, 292, 5.5, PAL["yellow2"], -2.35, 9),
        (592, 288, 5.0, PAL["green"], -1.70, 8),
    ])

    orbs(s, [(118, 288), (216, 306), (398, 300), (492, 292), (58, 312),
             (346, 318), (566, 312), (146, 322)])

    s.breach_line(22, GW - 22, 306)
    s.paddle(GW / 2, 332, 108, emblem=PAL["blue"])

    img = s.compose(
        vignette=0.48,
        scrims=[(GW / 2, 202, 340, 78, 0.82)],
        bg_glows=[(124, 90, 230, PAL["red"], 0.34),
                  (470, 60, 210, PAL["blue2"], 0.30),
                  (GW / 2, 322, 280, PAL["purple"], 0.26),
                  (GW / 2, 202, 250, PAL["blue"], 0.12)],
    )
    img = wordmark(img, "RICO RITE", 4, GW / 2, 202, glow_col=PAL["red"], glow_strength=1.0)
    finish(img, S, "main_capsule_1232x706.png", (1232, 706))


# ---------------------------------------------------------------------------
# 2. Header capsule -- 920 x 430  (store page top, library grid)
# ---------------------------------------------------------------------------

def header_capsule():
    """
    Also serves as the library grid tile, so the wordmark runs wide (85% of the
    width) and the art is arranged as a thin band above and below it.
    """
    S, GW, GH = 2, 460, 215
    s = Scene(GW, GH, seed=23, z=1.35)

    s.swarm(24, 18, 6, 3, BRICKS, density=0.80)
    s.swarm(214, 12, 5, 3, BRICKS, density=0.76)
    s.swarm(360, 26, 4, 3, BRICKS, density=0.72)

    for (x, y, sc) in [(96, 62, 1.15), (300, 40, 0.95), (410, 74, 0.75)]:
        s.explosion(x, y, PAL["orange"], sc)

    for (x, y, a, col) in [(66, 96, 1.48, PAL["red"]), (196, 90, 1.70, PAL["purple"]),
                           (350, 100, 1.42, PAL["red"]), (128, 170, 1.58, PAL["purple"]),
                           (410, 176, 1.74, PAL["red"])]:
        s.enemy_shot(x, y, a, col)

    fire(s, [
        ("arrow", 148, 94, -math.pi / 2 - 0.14, PAL["green"]),
        ("arrow", 268, 88, -math.pi / 2 + 0.20, PAL["green"]),
        ("blade", 226, 96, 0.6, PAL["blue"]),
        ("blade", 246, 78, 2.0, PAL["blue"]),
        ("arrow", 384, 92, -math.pi / 2 - 0.30, PAL["red"]),
        ("blade", 300, 172, 1.1, PAL["blue"]),
    ])

    hero_volley(s, [
        (58, 158, 6.0, PAL["yellow"], -1.75, 9),
        (152, 168, 5.5, PAL["green"], -1.30, 8),
        (238, 156, 6.5, PAL["red"], -2.05, 9),
        (326, 166, 5.5, PAL["blue"], -1.20, 8),
        (398, 152, 6.0, PAL["purple"], -1.95, 9),
        (12, 172, 5.0, PAL["fg"], -1.45, 7),
        (446, 176, 5.0, PAL["orange"], -2.10, 7),
    ])

    orbs(s, [(104, 186), (196, 192), (286, 190), (366, 196), (34, 196)])

    s.breach_line(16, GW - 16, 188)
    s.paddle(GW / 2, 204, 108, emblem=PAL["blue"])

    img = s.compose(
        vignette=0.46,
        scrims=[(GW / 2, 122, 254, 50, 0.84)],
        bg_glows=[(96, 58, 170, PAL["red"], 0.34),
                  (330, 44, 160, PAL["blue2"], 0.30),
                  (GW / 2, 196, 210, PAL["purple"], 0.24),
                  (GW / 2, 122, 190, PAL["blue"], 0.12)],
    )
    img = wordmark(img, "RICO RITE", 3, GW / 2, 122, glow_col=PAL["red"], glow_strength=1.0)
    finish(img, S, "header_capsule_920x430.png", (920, 430))


# ---------------------------------------------------------------------------
# 3. Small capsule -- 462 x 174  (search results, lists; logo must dominate)
# ---------------------------------------------------------------------------

def small_capsule():
    S, GW, GH = 3, 154, 58
    s = Scene(GW, GH, seed=41)

    # Just enough of the game to be recognisable behind an almost-full wordmark.
    s.swarm(6, 3, 7, 2, BRICKS, density=0.85, a=0.80)
    s.breach_line(5, GW - 5, 47, a=0.45)
    s.paddle(GW / 2, 53, 62, emblem=PAL["blue"])

    hero_volley(s, [
        (26, 33, 4.5, PAL["yellow"], -1.7, 6),
        (126, 30, 4.5, PAL["red"], -2.0, 6),
        (76, 40, 4.0, PAL["blue"], -1.4, 5),
    ])

    img = s.compose(
        vignette=0.42,
        scrims=[(GW / 2, 27, 84, 20, 0.94)],
        bg_glows=[(30, 18, 60, PAL["red"], 0.30),
                  (124, 16, 56, PAL["blue2"], 0.26),
                  (GW / 2, 27, 66, PAL["blue"], 0.10)],
    )
    img = wordmark(img, "RICO RITE", 1, GW / 2, 27, glow_col=PAL["red"], glow_strength=1.1)
    finish(img, S, "small_capsule_462x174.png", (462, 174))


# ---------------------------------------------------------------------------
# 4. Vertical capsule -- 748 x 896  (seasonal sale pages)
# ---------------------------------------------------------------------------

def vertical_capsule():
    S, GW, GH = 2, 374, 448
    s = Scene(GW, GH, seed=59)

    # The portrait shape is the game's own -- so this one is close to a real
    # play field: a deep swarm bearing down the full width of the arena.
    s.swarm(24, 18, 15, 9, BRICKS, density=0.84)
    s.swarm(35, 156, 13, 2, BRICKS, density=0.50, a=0.85)

    for (x, y, sc) in [(96, 96, 1.15), (268, 58, 0.95), (180, 140, 0.8)]:
        s.explosion(x, y, PAL["orange"], sc)

    fire(s, [
        ("arrow", 112, 196, -math.pi / 2 - 0.10, PAL["green"]),
        ("arrow", 232, 210, -math.pi / 2 + 0.16, PAL["green"]),
        ("arrow", 306, 186, -math.pi / 2 - 0.32, PAL["red"]),
        ("blade", 176, 188, 0.7, PAL["blue"]),
        ("blade", 196, 214, 2.2, PAL["blue"]),
        ("blade", 154, 218, 1.4, PAL["blue"]),
        ("arrow", 52, 224, -math.pi / 2 + 0.36, PAL["red"]),
    ])

    hero_volley(s, [
        (78, 262, 7.0, PAL["yellow"], -1.9, 11),
        (152, 240, 6.0, PAL["green"], -1.4, 9),
        (214, 276, 6.5, PAL["red"], -2.3, 10),
        (292, 250, 6.0, PAL["blue"], -1.2, 9),
        (44, 300, 5.5, PAL["purple"], -1.6, 8),
        (330, 300, 5.5, PAL["orange"], -2.2, 8),
        (176, 312, 6.0, PAL["fg"], -1.9, 9),
    ])

    orbs(s, [(112, 300), (250, 314), (66, 330), (300, 336), (188, 344)])

    s.breach_line(20, GW - 20, 392)
    s.paddle(GW / 2, 424, 108, emblem=PAL["blue"])

    img = s.compose(
        vignette=0.52,
        scrims=[(GW / 2, 356, 190, 56, 0.92)],
        bg_glows=[(96, 96, 170, PAL["red"], 0.30),
                  (280, 70, 160, PAL["blue2"], 0.26),
                  (GW / 2, 410, 200, PAL["purple"], 0.24),
                  (GW / 2, 354, 170, PAL["blue"], 0.10)],
    )
    img = wordmark(img, "RICO RITE", 2, GW / 2, 356, glow_col=PAL["red"], glow_strength=1.0)
    finish(img, S, "vertical_capsule_748x896.png", (748, 896))


# ---------------------------------------------------------------------------
# 5. Page background -- 1438 x 810
# Steam tints this blue and fades the edges, so it must stay ambient: no text,
# no hard contrast, nothing that competes with the store content on top of it.
# ---------------------------------------------------------------------------

def page_background():
    S, GW, GH = 2, 719, 405
    s = Scene(GW, GH, seed=97)

    s.swarm(20, 30, 30, 5, BRICKS, density=0.62, a=0.55)
    s.swarm(60, 150, 26, 3, BRICKS, density=0.40, a=0.34)

    hero_volley(s, [
        (140, 250, 6.0, PAL["yellow"], -1.8, 8),
        (300, 224, 5.5, PAL["green"], -1.4, 7),
        (470, 262, 6.0, PAL["red"], -2.1, 8),
        (600, 232, 5.5, PAL["blue"], -1.3, 7),
        (60, 300, 5.0, PAL["purple"], -1.6, 6),
    ])
    orbs(s, [(220, 300), (390, 320), (540, 306), (110, 336), (650, 330)])

    s.breach_line(30, GW - 30, 344, a=0.28)
    s.paddle(GW / 2, 376, 108, emblem=PAL["blue"])

    img = s.compose(
        vignette=0.72,
        bg_glows=[(170, 90, 260, PAL["red"], 0.22),
                  (540, 80, 250, PAL["blue2"], 0.20),
                  (GW / 2, 350, 300, PAL["purple"], 0.18)],
    )
    # Pull the whole plate down so it can never fight the page content above it.
    img = Image.blend(img, Image.new("RGB", img.size, (0, 0, 0)), 0.42)
    finish(img, S, "page_background_1438x810.png", (1438, 810))


if __name__ == "__main__":
    print("Rico Rite -- Steam graphical assets")
    main_capsule()
    header_capsule()
    small_capsule()
    vertical_capsule()
    page_background()
    print("done ->", HERE)
