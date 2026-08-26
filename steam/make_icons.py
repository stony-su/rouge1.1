"""Ball Pit X — Steam icon generator.

Renders four icon concepts at 4x supersample, then emits the two Steam assets:
  * Shortcut Icon : 512x512 PNG (RGBA, rounded corners) + a multi-size .ico
  * App Icon      : 184x184 JPG (no alpha, full-bleed square)

Palette and shape language are lifted from the game itself (shared.lua palette,
brick.lua's bright-rim/dark-fill bricks, paddle.lua's bar + round emblem core).
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # supersample resolution
OUT = os.path.dirname(os.path.abspath(__file__))

# ---- palette (shared.lua shared_init) --------------------------------------
BG      = (12, 12, 20)
BG_LIFT = (30, 30, 52)
GOLD    = (250, 207, 0)
YELLOW2 = (245, 159, 16)
ORANGE  = (240, 112, 33)
BLUE    = (1, 155, 214)
GREEN   = (139, 191, 64)
RED     = (233, 29, 57)
PURPLE  = (142, 85, 158)
FG      = (218, 218, 218)
WHITE   = (255, 255, 255)


def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def p(f):
    """fraction of canvas -> pixels"""
    return f * S


def glow(base, shape_layer, radius, strength=1.0, passes=2):
    """Bloom a shape layer under itself."""
    for i in range(passes):
        r = radius * (1.0 + i * 1.8)
        g = shape_layer.filter(ImageFilter.GaussianBlur(r))
        s = strength * (0.85 if i == 0 else 0.5)
        a = g.split()[3].point(lambda v, s=s: min(255, int(v * s)))
        g.putalpha(a)
        base.alpha_composite(g)


def shadow(base, shape_layer, radius, offset, strength=0.55):
    """Soft dark drop shadow, matching the game's shadow_canvas."""
    a = shape_layer.split()[3].filter(ImageFilter.GaussianBlur(radius))
    a = a.point(lambda v: int(v * strength))
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    sh.putalpha(a)
    base.alpha_composite(sh, (0, offset))


def backdrop(grid=True, lift=0.55):
    """Near-black field with a centre lift and a faint arcade grid."""
    im = Image.new("RGBA", (S, S), BG + (255,))
    rad = Image.radial_gradient("L").resize((S, S), Image.LANCZOS)
    mask = rad.point(lambda v: int((255 - v) * lift))
    im = Image.composite(Image.new("RGBA", (S, S), BG_LIFT + (255,)), im, mask)
    if grid:
        g = layer()
        d = ImageDraw.Draw(g)
        n = 9
        cell = S / n
        w = max(1, int(S * 0.0022))
        for i in range(1, n):
            d.line([i * cell, 0, i * cell, S], fill=(255, 255, 255, 12), width=w)
            d.line([0, i * cell, S, i * cell], fill=(255, 255, 255, 12), width=w)
        im.alpha_composite(g)
    return im


def brick(d, cx, cy, w, h, color, rim=0.055, dark=0.30):
    """brick.lua look: bright rounded rim, dark interior."""
    r = h * 0.22
    t = h * rim * 3.2
    d.rounded_rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2],
                        radius=r, fill=color + (255,))
    inner = [cx - w / 2 + t, cy - h / 2 + t, cx + w / 2 - t, cy + h / 2 - t]
    if inner[2] > inner[0] and inner[3] > inner[1]:
        d.rounded_rectangle(inner, radius=max(1, r - t * 0.6),
                            fill=tuple(int(c * dark) for c in color) + (255,))


def ball(base, cx, cy, r, color, core=WHITE, glow_amt=1.0):
    """Solid hero ball with bloom and a hot core."""
    gl = layer()
    ImageDraw.Draw(gl).ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))
    glow(base, gl, r * 0.55, strength=glow_amt)
    d = ImageDraw.Draw(base)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))
    cr = r * 0.42
    d.ellipse([cx - cr - r * 0.10, cy - cr - r * 0.12,
               cx + cr - r * 0.10, cy + cr - r * 0.12], fill=core + (255,))


def bezier(p0, p1, p2, t):
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
            u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1])


def trail(base, p0, p1, p2, r0, r1, color, a0=0, a1=225, steps=170):
    """Tapered motion trail along a quadratic bezier."""
    tl = layer()
    d = ImageDraw.Draw(tl)
    for i in range(steps):
        t = i / (steps - 1.0)
        x, y = bezier(p0, p1, p2, t)
        r = r0 + (r1 - r0) * t
        a = int(a0 + (a1 - a0) * (t ** 1.35))
        d.ellipse([x - r, y - r, x + r, y + r], fill=color + (a,))
    glow(base, tl, r1 * 0.6, strength=0.5, passes=1)
    base.alpha_composite(tl)


def paddle(base, cx, cy, w, h, color=GOLD, emblem=True, wings=True):
    """paddle.lua: ghosted wings + solid core bar with a round emblem."""
    pl = layer()
    d = ImageDraw.Draw(pl)
    r = h / 2
    if wings:
        d.rounded_rectangle([cx - w / 2, cy - h * 0.30, cx + w / 2, cy + h * 0.30],
                            radius=h * 0.30, fill=color + (95,))
    core_w = w * 0.52
    d.rounded_rectangle([cx - core_w / 2, cy - r, cx + core_w / 2, cy + r],
                        radius=r, fill=color + (255,))
    glow(base, pl, h * 0.55, strength=0.8)
    base.alpha_composite(pl)
    if emblem:
        d2 = ImageDraw.Draw(base)
        er = h * 0.92
        d2.ellipse([cx - er, cy - er, cx + er, cy + er], fill=color + (255,))
        ir = er * 0.46
        d2.ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=BG + (255,))


def _mask_bar(cx, cy, w, h):
    m = layer()
    ImageDraw.Draw(m).rounded_rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2],
                                        radius=h / 2, fill=(0, 0, 0, 255))
    return m


def seat_paddle(im, cy, w, h, **kw):
    shadow(im, _mask_bar(p(0.5), cy, w, h), p(0.022), int(p(0.020)))
    paddle(im, p(0.5), cy, w, h, **kw)


# =============================================================================
# Concepts
# =============================================================================

def concept_volley():
    """A ball arcing off the paddle into a rank of bricks. The whole game loop."""
    im = backdrop()
    d = ImageDraw.Draw(im)

    bw, bh = p(0.262), p(0.128)
    for fx, c in ((0.215, RED), (0.50, BLUE), (0.785, GREEN)):
        brick(d, p(fx), p(0.200), bw, bh, c)

    trail(im, (p(0.258), p(0.742)), (p(0.345), p(0.485)), (p(0.650), p(0.487)),
          p(0.012), p(0.070), GOLD, a1=255)
    ball(im, p(0.650), p(0.487), p(0.112), GOLD)

    seat_paddle(im, p(0.806), p(0.66), p(0.078))
    return im


def concept_impact():
    """The moment of the hit — ball detonating a brick, ULTRAKILL combo energy."""
    im = backdrop(lift=0.75)
    d = ImageDraw.Draw(im)

    cx, cy = p(0.5), p(0.408)

    # Tapered hit-sparks, biased upward and outward so nothing spears the paddle.
    burst = layer()
    bd = ImageDraw.Draw(burst)
    spikes = [(-90, 0.34, 0.052), (-40, 0.28, 0.036), (-140, 0.28, 0.036),
              (0, 0.32, 0.046), (180, 0.32, 0.046),
              (40, 0.235, 0.030), (140, 0.235, 0.030)]
    for deg, reach, half in spikes:
        a = math.radians(deg)
        r0, r1 = p(0.150), p(reach)
        hw = p(half)
        nx, ny = -math.sin(a), math.cos(a)
        bd.polygon([(cx + math.cos(a) * r0 + nx * hw, cy + math.sin(a) * r0 + ny * hw),
                    (cx + math.cos(a) * r0 - nx * hw, cy + math.sin(a) * r0 - ny * hw),
                    (cx + math.cos(a) * r1, cy + math.sin(a) * r1)],
                   fill=GOLD + (255,))
    glow(im, burst, p(0.026), strength=0.95)
    im.alpha_composite(burst)

    bw, bh = p(0.255), p(0.128)
    brick(d, cx - p(0.152), cy + p(0.005), bw, bh, RED)
    brick(d, cx + p(0.160), cy + p(0.038), bw, bh, BLUE)

    ball(im, cx, cy, p(0.128), GOLD, core=WHITE, glow_amt=1.4)

    seat_paddle(im, p(0.838), p(0.62), p(0.074))
    return im


def concept_pit():
    """Literal Ball Pit — the hero roster piled in the arena over the paddle."""
    im = backdrop()

    # Pyramid pile, biggest on top, slight overlap so it reads as a heap.
    for fx, fy, fr, c in (
        (0.500, 0.232, 0.122, GOLD),
        (0.268, 0.352, 0.108, RED),
        (0.732, 0.352, 0.108, BLUE),
        (0.500, 0.452, 0.092, FG),
        (0.318, 0.552, 0.104, GREEN),
        (0.682, 0.552, 0.104, ORANGE),
        (0.500, 0.645, 0.082, PURPLE),
    ):
        ball(im, p(fx), p(fy), p(fr), c, glow_amt=0.85)

    seat_paddle(im, p(0.838), p(0.72), p(0.074))
    return im


def concept_x():
    """The X in Ball Pit X, cut by two crossing ball trails."""
    im = backdrop(lift=0.65)

    trail(im, (p(0.115), p(0.135)), (p(0.42), p(0.39)), (p(0.715), p(0.612)),
          p(0.030), p(0.082), GOLD, a0=120, a1=255)
    trail(im, (p(0.885), p(0.135)), (p(0.58), p(0.39)), (p(0.285), p(0.612)),
          p(0.030), p(0.082), RED, a0=120, a1=255)

    ball(im, p(0.715), p(0.612), p(0.112), GOLD)
    ball(im, p(0.285), p(0.612), p(0.112), RED)

    seat_paddle(im, p(0.858), p(0.62), p(0.072))
    return im


CONCEPTS = {
    "volley": concept_volley,
    "impact": concept_impact,
    "pit":    concept_pit,
    "x":      concept_x,
}


# =============================================================================
# Output
# =============================================================================

def round_corners(im, radius_frac=0.16):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S - 1, S - 1],
                                        radius=int(S * radius_frac), fill=255)
    out = im.copy()
    out.putalpha(m)
    return out


def emit(name, im):
    d = os.path.join(OUT, "icons", name)
    os.makedirs(d, exist_ok=True)

    # Shortcut Icon — 512 PNG with rounded alpha corners
    rounded = round_corners(im)
    png512 = rounded.resize((512, 512), Image.LANCZOS)
    png512.save(os.path.join(d, f"shortcut_{name}_512.png"))

    # ICO with every size baked in so Steam doesn't have to downscale
    sizes = [256, 128, 64, 48, 32, 16]
    png512.save(os.path.join(d, f"shortcut_{name}.ico"),
                format="ICO", sizes=[(s, s) for s in sizes])

    # App Icon — 184 JPG, full bleed, no alpha
    jpg = im.convert("RGB").resize((184, 184), Image.LANCZOS)
    jpg.save(os.path.join(d, f"appicon_{name}_184.jpg"), quality=95, subsampling=0)

    return png512


def contact_sheet(previews):
    """2x2 of each concept at 256, with 16/32/48px proofs beside each."""
    tile_w, tile_h = 300, 300
    sheet = Image.new("RGB", (tile_w * 2 + 30, tile_h * 2 + 30), (24, 24, 30))
    for i, (name, im) in enumerate(previews.items()):
        col, row = i % 2, i // 2
        ox, oy = 10 + col * (tile_w + 10), 10 + row * (tile_h + 10)
        big = im.resize((256, 256), Image.LANCZOS)
        sheet.paste(big.convert("RGB"), (ox, oy), big)
        x = ox
        for s in (48, 32, 16):
            small = im.resize((s, s), Image.LANCZOS)
            proof = small.resize((s * 2, s * 2), Image.NEAREST)
            sheet.paste(proof.convert("RGB"), (x, oy + 262), proof)
            x += s * 2 + 8
    sheet.save(os.path.join(OUT, "contact_sheet.png"))


if __name__ == "__main__":
    previews = {}
    for name, fn in CONCEPTS.items():
        im = fn()
        previews[name] = emit(name, im)
        print("rendered", name)
    contact_sheet(previews)
    print("sheet ->", os.path.join(OUT, "contact_sheet.png"))
