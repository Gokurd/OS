#!/usr/bin/env python3
# Fondo «agujero negro + lluvia Matrix» y orbe de Inicio.
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H = 1280, 800  # tu resolución: xrandr | grep '*'
random.seed(7)
cfg = os.path.expanduser('~/.config')
os.makedirs(cfg + '/tint2', exist_ok=True)
try:
    font = ImageFont.truetype(
        '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 14)
except OSError:
    font = ImageFont.load_default()

cx, cy, R = int(W * 0.66), H // 2, 90
bg = Image.new('RGB', (W, H), (0, 5, 2))
d = ImageDraw.Draw(bg)
glyphs = '0123456789ABCDEF<>/|=+*#$'
for x in range(0, W, 14):
    head, n = random.randint(5, H // 14 + 20), random.randint(8, 36)
    for i in range(n):
        y = (head - i) * 14
        if not 0 <= y < H:
            continue
        dist = math.hypot(x - cx, y - cy)
        if dist < R * 1.1:
            continue
        k = (1 - i / n) * (0.3 + 0.7 * min(1.0, (dist - R) / 320))
        g = int(255 * k)
        d.text((x, y), random.choice(glyphs), font=font,
               fill=(190, 255, 210) if i == 0 else (0, g, g // 4))

glow = Image.new('RGB', (W, H), (0, 0, 0))
gd = ImageDraw.Draw(glow)
for w, c in ((30, (0, 80, 28)), (14, (0, 170, 70)), (5, (150, 255, 190))):
    gd.ellipse((cx - R - w // 2, cy - R - w // 2,
                cx + R + w // 2, cy + R + w // 2), outline=c, width=w)
disk = (cx - int(3.3 * R), cy - int(0.5 * R),
        cx + int(3.3 * R), cy + int(0.5 * R))
for w, c in ((12, (0, 110, 40)), (4, (150, 255, 190))):
    gd.ellipse(disk, outline=c, width=w)
img = ImageChops.add(bg, glow.filter(ImageFilter.GaussianBlur(8)))
d = ImageDraw.Draw(img)
d.ellipse((cx - R, cy - R, cx + R, cy + R), fill=(0, 0, 0),
          outline=(130, 255, 175), width=2)
d.arc(disk, 0, 180, fill=(150, 255, 190), width=3)  # el disco pasa por delante del horizonte
img.save(cfg + '/blackhole.png')

orb = Image.new('RGBA', (48, 48), (0, 0, 0, 0))
o = ImageDraw.Draw(orb)
for r in range(22, 0, -1):
    t = 1 - r / 22
    o.ellipse((24 - r, 24 - r, 24 + r, 24 + r),
              fill=(int(15 + 190 * t), int(90 + 165 * t), int(40 + 110 * t), 255))
o.ellipse((2, 2, 45, 45), outline=(0, 255, 102, 255), width=2)
o.ellipse((12, 6, 36, 20), fill=(255, 255, 255, 70))
orb.filter(ImageFilter.GaussianBlur(0.6)).save(cfg + '/tint2/orb.png')
print('OK: fondo y orbe generados')
