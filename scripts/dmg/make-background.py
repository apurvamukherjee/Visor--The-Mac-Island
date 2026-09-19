"""Renders the .dmg window background. Run only when the art changes; the
PNGs are committed, so a release build needs no Python and no Pillow."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math

W, H = 1080, 800                     # @2x canvas for a 540x400 window
HN = "/System/Library/Fonts/HelveticaNeue.ttc"
REG, BOLD, MED = 0, 1, 10

# Measured from a built image, not assumed: Finder snaps a dropped icon to its
# grid row, so the positions the AppleScript asks for are not the positions the
# icons land on. The arrow follows the icons, never the other way round.
ICON_Y = 436                         # centre of both icon slots, @2x
APP_X, ALIAS_X = 290, 790            # icon centres, @2x

def font(size, idx):
    return ImageFont.truetype(HN, size, index=idx)

img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
px = img.load()
for y in range(H):
    t = y / (H - 1)
    v = 18 + 6 * math.sin(math.pi * t) - 8 * t
    px_row = (int(v), int(v), int(v + 5), 255)
    for x in range(W):
        px[x, y] = px_row

# Indigo bloom behind the notch, echoing the app's album halo. Drawn small and
# upscaled: a per-pixel radial gradient bands visibly on a flat dark field.
bloom = Image.new("L", (W // 8, H // 8), 0)
bp = bloom.load()
bw, bh = bloom.size
cx, cy, r = bw * 0.5, bh * 0.02, bw * 0.78
for y in range(bh):
    for x in range(bw):
        d = math.hypot(x - cx, (y - cy) * 1.25) / r
        if d < 1.0:
            bp[x, y] = int(255 * (1 - d) ** 2.0)
bloom = bloom.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(12))
tint = Image.new("RGBA", (W, H), (88, 104, 255, 0))
tint.putalpha(bloom.point(lambda v: int(v * 0.34)))
img = Image.alpha_composite(img, tint)

d = ImageDraw.Draw(img)

# The island, hanging off the top edge the way the real notch does.
L, R, B, RAD = 396, 684, 108, 32
d.rounded_rectangle([L, -RAD, R, B], radius=RAD, fill=(0, 0, 0, 255))
d.rectangle([L, 0, R, RAD], fill=(0, 0, 0, 255))
hair = (255, 255, 255, 30)
d.line([(L, 0), (L, B - RAD)], fill=hair, width=3)
d.line([(R, 0), (R, B - RAD)], fill=hair, width=3)
d.arc([L, B - 2 * RAD, L + 2 * RAD, B], 90, 180, fill=hair, width=3)
d.arc([R - 2 * RAD, B - 2 * RAD, R, B], 0, 90, fill=hair, width=3)
d.line([(L + RAD, B), (R - RAD, B)], fill=hair, width=3)
d.ellipse([444, 47, 462, 65], fill=(255, 255, 255, 64))
d.rounded_rectangle([482, 49, 636, 63], radius=7, fill=(255, 255, 255, 36))

def centered(y, text, f, fill, track=0):
    ws = [d.textlength(c, font=f) for c in text]
    total = sum(ws) + track * (len(text) - 1)
    x = W / 2 - total / 2
    for c, w in zip(text, ws):
        d.text((x, y), c, font=f, fill=fill)
        x += w + track

centered(150, "Visor", font(46, BOLD), (255, 255, 255, 240), 1)
centered(212, "DRAG TO APPLICATIONS TO INSTALL", font(17, MED), (255, 255, 255, 112), 4)

# Arrow between the two icon slots. It starts and ends clear of the icons so
# neither sits on top of it.
x0, x1 = APP_X + 118, ALIAS_X - 118
head = 44
shaft_end = x1 - head
for x in range(x0, shaft_end):
    t = (x - x0) / max(1, shaft_end - x0)
    a = int(255 * (0.18 + 0.82 * t ** 0.7))
    c = (int(118 + 137 * t), int(134 + 121 * t), 255, a)
    d.line([(x, ICON_Y), (x + 1, ICON_Y)], fill=c, width=14)
d.polygon([(shaft_end - 2, ICON_Y - 34), (x1, ICON_Y), (shaft_end - 2, ICON_Y + 34)],
          fill=(255, 255, 255, 255))

centered(708, "Unsigned build — if macOS blocks it, see the README",
         font(15, REG), (255, 255, 255, 72), 1)

img.convert("RGB").save("scripts/dmg/background@2x.png")
img.convert("RGB").resize((W // 2, H // 2), Image.LANCZOS).save("scripts/dmg/background.png")
print("wrote scripts/dmg/background.png and @2x")
