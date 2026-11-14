#!/usr/bin/env python3
# ==============================================================================
# generate-assets.py — Black Hole Linux (Matrix edition)
# Genera todos los graficos del tema sin necesitar archivos externos:
#   --out DIR  ->  DIR/blackhole-wallpaper.jpg + DIR/blackhole-splash.png
#                  (build: fondo ISOLINUX, GRUB y Plymouth)
#   --user     ->  ~/.config/blackhole.png + ~/.config/tint2/orb.png
#                  (sesion Openbox BlackHole-Aero: feh + orbe de Inicio)
# Arte: agujero negro con disco de acrecion + lluvia Matrix en verde.
# ==============================================================================
import argparse
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


def _load_font(size=14):
    for p in ('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
              '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'):
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()


def render(w, h, seed=7):
    random.seed(seed)
    cx, cy, r = int(w * 0.66), h // 2, max(60, h // 9)
    bg = Image.new('RGB', (w, h), (0, 5, 2))
    d = ImageDraw.Draw(bg)
    font = _load_font(14)
    glyphs = '0123456789ABCDEF<>/|=+*#$'
    for x in range(0, w, 14):
        head = random.randint(5, h // 14 + 20)
        n = random.randint(8, 36)
        for i in range(n):
            y = (head - i) * 14
            if not 0 <= y < h:
                continue
            dist = math.hypot(x - cx, y - cy)
            if dist < r * 1.1:
                continue
            k = (1 - i / n) * (0.3 + 0.7 * min(1.0, (dist - r) / 320))
            g = int(255 * k)
            d.text((x, y), random.choice(glyphs), font=font,
                   fill=(190, 255, 210) if i == 0 else (0, g, g // 4))

    glow = Image.new('RGB', (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for lw, c in ((30, (0, 80, 28)), (14, (0, 170, 70)), (5, (150, 255, 190))):
        gd.ellipse((cx - r - lw // 2, cy - r - lw // 2,
                    cx + r + lw // 2, cy + r + lw // 2), outline=c, width=lw)
    disk = (cx - int(3.3 * r), cy - int(0.5 * r),
            cx + int(3.3 * r), cy + int(0.5 * r))
    for lw, c in ((12, (0, 110, 40)), (4, (150, 255, 190))):
        gd.ellipse(disk, outline=c, width=lw)

    img = ImageChops.add(bg, glow.filter(ImageFilter.GaussianBlur(8)))
    d = ImageDraw.Draw(img)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(0, 0, 0),
              outline=(130, 255, 175), width=2)
    d.arc(disk, 0, 180, fill=(150, 255, 190), width=3)
    return img


def make_orb():
    orb = Image.new('RGBA', (48, 48), (0, 0, 0, 0))
    o = ImageDraw.Draw(orb)
    for rad in range(22, 0, -1):
        t = 1 - rad / 22
        o.ellipse((24 - rad, 24 - rad, 24 + rad, 24 + rad),
                  fill=(int(15 + 190 * t), int(90 + 165 * t), int(40 + 110 * t), 255))
    o.ellipse((2, 2, 45, 45), outline=(0, 255, 102, 255), width=2)
    o.ellipse((12, 6, 36, 20), fill=(255, 255, 255, 70))
    return orb.filter(ImageFilter.GaussianBlur(0.6))


def main():
    ap = argparse.ArgumentParser(
        description='Generador de graficos Black Hole (Matrix edition)')
    ap.add_argument('--out', help='carpeta de salida para splash + wallpaper')
    ap.add_argument('--user', action='store_true',
                    help='generar fondo y orbe en ~/.config para la sesion Openbox')
    ap.add_argument('--width', type=int, default=1280)
    ap.add_argument('--height', type=int, default=800)
    args = ap.parse_args()
    if not args.out and not args.user:
        ap.error('indica --out DIR y/o --user')

    img = render(args.width, args.height)
    if args.out:
        os.makedirs(args.out, exist_ok=True)
        img.save(os.path.join(args.out, 'blackhole-wallpaper.jpg'), quality=90)
        img.save(os.path.join(args.out, 'blackhole-splash.png'))
        print('OK: splash y wallpaper generados en', args.out)
    if args.user:
        cfg = os.path.expanduser('~/.config')
        os.makedirs(os.path.join(cfg, 'tint2'), exist_ok=True)
        img.save(os.path.join(cfg, 'blackhole.png'))
        make_orb().save(os.path.join(cfg, 'tint2', 'orb.png'))
        print('OK: fondo y orbe generados en', cfg)


if __name__ == '__main__':
    main()
