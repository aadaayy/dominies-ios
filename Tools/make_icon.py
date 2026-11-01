"""Draws the app icon: an ivory double-nine-style tile on a graphite background.
Run: python3 Tools/make_icon.py (needs Pillow)."""
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGB", (S, S), (28, 28, 30))
grad = ImageDraw.Draw(img)
for y in range(S):
    t = y / S
    c = int(44 - 18 * t)
    grad.line([(0, y), (S, y)], fill=(c, c, c + 2))

# Tile, standing, with a soft shadow.
w, h = 400, 760
x0, y0 = (S - w) // 2, (S - h) // 2
shadow = Image.new("L", (S, S), 0)
ImageDraw.Draw(shadow).rounded_rectangle([x0, y0 + 24, x0 + w, y0 + h + 24], radius=70, fill=150)
shadow = shadow.filter(ImageFilter.GaussianBlur(28))
img.paste((0, 0, 0), (0, 0), shadow)
d = ImageDraw.Draw(img)
d.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=70, fill=(253, 251, 246))
d.line([(x0 + 70, S // 2), (x0 + w - 70, S // 2)], fill=(190, 188, 182), width=10)

def pips(cx0, cy0, n):
    l, m, r = 0.0, 0.5, 1.0
    spots = {
        6: [(l, l), (r, l), (l, m), (r, m), (l, r), (r, r)],
        3: [(r, l), (m, m), (l, r)],
    }[n]
    inset, side = 95, w
    rad = 38
    for sx, sy in spots:
        cx = cx0 + inset + sx * (side - inset * 2)
        cy = cy0 + inset + sy * (side - inset * 2)
        d.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=(28, 28, 30))

pips(x0, y0 - 10, 6)
pips(x0, y0 + h // 2 - 30, 3)
img.save("Dominoes/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
