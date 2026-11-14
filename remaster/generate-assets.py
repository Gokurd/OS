#!/usr/bin/env python3
# ==============================================================================
# generate-assets.py — Black Hole Linux (Matrix edition)
# Genera todos los graficos del tema sin necesitar archivos externos:
#   --out DIR    ->  DIR/blackhole-wallpaper.jpg + DIR/blackhole-splash.png
#                    + DIR/blackhole-logo.png + DIR/blackhole-dot.png
#                    (build: ISOLINUX, GRUB y Plymouth "BLACK HOLE" en verde)
#   --user       ->  ~/.config/blackhole.png + ~/.config/tint2/orb.png
#                    (sesion Openbox BlackHole-Aero: feh + orbe de Inicio)
#   --icons DIR  ->  mini tema de iconos BlackHole 48x48 (apps/places/devices)
# Arte: agujero negro con disco de acrecion + lluvia Matrix en verde.
# ==============================================================================
import argparse
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

GREEN = (44, 255, 122)


def _load_font(size=14, bold=False):
    base = '/usr/share/fonts/truetype/dejavu/'
    names = (['DejaVuSansMono-Bold.ttf', 'DejaVuSans-Bold.ttf', 'DejaVuSans.ttf']
             if bold else
             ['DejaVuSansMono.ttf', 'DejaVuSans.ttf'])
    for n in names:
        try:
            return ImageFont.truetype(base + n, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _blackhole_art(w, h, seed=7, matrix_rain=True):
    """Fondo comun: lluvia Matrix + agujero negro con disco de acrecion."""
    random.seed(seed)
    cx, cy, r = int(w * 0.66), h // 2, max(48, h // 9)
    bg = Image.new('RGB', (w, h), (0, 5, 2))
    d = ImageDraw.Draw(bg)
    if matrix_rain:
        font = _load_font(max(10, h // 56))
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
    return img, cx, cy, r


def render(w, h, seed=7):
    """Wallpaper del escritorio: arte + titulo BLACK HOLE en verde."""
    img, _, _, _ = _blackhole_art(w, h, seed)
    d = ImageDraw.Draw(img)
    f_big = _load_font(max(28, h // 22), bold=True)
    f_sub = _load_font(max(12, h // 52))
    tx, ty = 36, h - int(h * 0.16)
    # sombra suave para legibilidad
    d.text((tx + 2, ty + 2), 'BLACK HOLE', font=f_big, fill=(0, 20, 8))
    d.text((tx, ty), 'BLACK HOLE', font=f_big, fill=GREEN)
    sub = 'LINUX 8.0 · ULTIMATE-E6400'
    d.text((tx + 3, ty + f_big.size + 10), sub, font=f_sub, fill=(120, 220, 160))
    return img


def render_splash(w=640, h=480):
    """Splash de arranque (ISOLINUX/GRUB): centro limpio + BLACK HOLE verde."""
    img, _, _, _ = _blackhole_art(w, h, seed=11, matrix_rain=True)
    d = ImageDraw.Draw(img)
    f_big = _load_font(34, bold=True)
    f_sub = _load_font(14)
    title = 'BLACK HOLE'
    tw = d.textlength(title, font=f_big)
    tx, ty = (w - tw) / 2, int(h * 0.78)
    d.text((tx + 2, ty + 2), title, font=f_big, fill=(0, 24, 10))
    d.text((tx, ty), title, font=f_big, fill=GREEN)
    sub = 'LINUX 8.0 · ULTIMATE-E6400'
    sw = d.textlength(sub, font=f_sub)
    d.text(((w - sw) / 2, ty + 44), sub, font=f_sub, fill=(150, 235, 180))
    return img


def render_logo(size=256):
    """Logo para Plymouth: agujero negro con anillo verde (fondo transparente)."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size // 2
    r = int(size * 0.36)
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for lw, col in ((26, (0, 90, 35, 90)), (12, (0, 190, 80, 160)), (4, (170, 255, 200, 255))):
        gd.ellipse((c - r - lw // 2, c - r - lw // 2, c + r + lw // 2, c + r + lw // 2),
                   outline=col, width=lw)
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(6)))
    d = ImageDraw.Draw(img)
    disk = (c - int(1.8 * r), c - int(0.28 * r), c + int(1.8 * r), c + int(0.28 * r))
    for lw, col in ((8, (0, 120, 50, 220)), (3, (160, 255, 200, 255))):
        d.ellipse(disk, outline=col, width=lw)
    d.ellipse((c - r, c - r, c + r, c + r), fill=(0, 0, 0, 255),
              outline=(140, 255, 185, 255), width=3)
    d.arc(disk, 0, 180, fill=(170, 255, 205, 255), width=4)
    return img


def render_dot(size=12):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((1, 1, size - 2, size - 2), fill=GREEN + (255,))
    return img.filter(ImageFilter.GaussianBlur(0.4))


def make_orb(size=48):
    orb = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    o = ImageDraw.Draw(orb)
    c = size // 2
    for rad in range(c - 2, 0, -1):
        t = 1 - rad / (c - 2)
        o.ellipse((c - rad, c - rad, c + rad, c + rad),
                  fill=(int(15 + 190 * t), int(90 + 165 * t), int(40 + 110 * t), 255))
    o.ellipse((2, 2, size - 3, size - 3), outline=(0, 255, 102, 255), width=2)
    o.ellipse((int(size * 0.25), int(size * 0.12), int(size * 0.75), int(size * 0.42)),
              fill=(255, 255, 255, 70))
    return orb.filter(ImageFilter.GaussianBlur(0.6))


# ------------------------------ iconos 48x48 ---------------------------------

def _icon_base():
    img = Image.new('RGBA', (48, 48), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def icon_folder(home=False):
    img, d = _icon_base()
    d.rounded_rectangle((5, 14, 43, 40), radius=5, fill=(10, 40, 22, 255),
                        outline=GREEN + (255,), width=2)
    d.polygon([(5, 14), (16, 14), (20, 8), (30, 8), (34, 14)], fill=(16, 70, 36, 255))
    if home:
        d.polygon([(24, 20), (14, 29), (34, 29)], outline=GREEN + (255,), width=2)
        d.rectangle((19, 29, 29, 37), outline=GREEN + (255,), width=2)
    else:
        d.line((10, 22, 38, 22), fill=(60, 200, 120, 180), width=2)
    return img


def icon_terminal():
    img, d = _icon_base()
    d.rounded_rectangle((5, 8, 43, 40), radius=5, fill=(2, 14, 6, 255),
                        outline=GREEN + (255,), width=2)
    d.text((11, 14), '>_', font=_load_font(16, bold=True), fill=GREEN + (255,))
    return img


def icon_browser():
    img, d = _icon_base()
    d.ellipse((4, 4, 44, 44), fill=(2, 12, 6, 255), outline=GREEN + (255,), width=2)
    d.ellipse((8, 18, 40, 30), outline=(150, 255, 190, 255), width=3)
    d.ellipse((19, 19, 29, 29), fill=(0, 0, 0, 255), outline=GREEN + (255,), width=2)
    return img


def icon_monitor():
    img, d = _icon_base()
    d.rounded_rectangle((5, 8, 43, 32), radius=3, fill=(2, 14, 6, 255),
                        outline=GREEN + (255,), width=2)
    d.line((11, 20, 18, 20), fill=GREEN + (255,), width=2)
    d.line((21, 20, 26, 14), fill=GREEN + (255,), width=2)
    d.line((26, 14, 31, 24), fill=GREEN + (255,), width=2)
    d.line((31, 24, 37, 20), fill=GREEN + (255,), width=2)
    d.rectangle((21, 32, 27, 38), fill=(16, 70, 36, 255))
    d.line((14, 40, 34, 40), fill=GREEN + (255,), width=3)
    return img


def icon_sysmon():
    img, d = _icon_base()
    d.rounded_rectangle((5, 8, 43, 40), radius=5, fill=(2, 14, 6, 255),
                        outline=GREEN + (255,), width=2)
    pts = [(9, 30), (15, 30), (19, 18), (24, 36), (28, 24), (32, 30), (39, 30)]
    d.line(pts, fill=GREEN + (255,), width=2)
    return img


def icon_editor():
    img, d = _icon_base()
    d.rounded_rectangle((10, 5, 38, 43), radius=3, fill=(4, 20, 10, 255),
                        outline=GREEN + (255,), width=2)
    for y in (14, 21, 28, 35):
        d.line((15, y, 33, y), fill=(90, 230, 140, 220), width=2)
    return img


def icon_gamepad():
    img, d = _icon_base()
    d.rounded_rectangle((6, 16, 42, 34), radius=9, fill=(8, 34, 18, 255),
                        outline=GREEN + (255,), width=2)
    d.line((12, 25, 20, 25), fill=GREEN + (255,), width=2)
    d.line((16, 21, 16, 29), fill=GREEN + (255,), width=2)
    d.ellipse((31, 21, 37, 27), outline=GREEN + (255,), width=2)
    return img


def write_icons(outdir):
    apps = os.path.join(outdir, '48x48', 'apps')
    places = os.path.join(outdir, '48x48', 'places')
    devices = os.path.join(outdir, '48x48', 'devices')
    for p in (apps, places, devices):
        os.makedirs(p, exist_ok=True)
    make_orb(48).save(os.path.join(apps, 'start-here.png'))
    make_orb(48).save(os.path.join(apps, 'preferences-system.png'))
    icon_terminal().save(os.path.join(apps, 'utilities-terminal.png'))
    icon_browser().save(os.path.join(apps, 'web-browser.png'))
    icon_browser().save(os.path.join(apps, 'internet-web-browser.png'))
    icon_sysmon().save(os.path.join(apps, 'utilities-system-monitor.png'))
    icon_editor().save(os.path.join(apps, 'accessories-text-editor.png'))
    icon_gamepad().save(os.path.join(apps, 'input-gaming.png'))
    icon_folder().save(os.path.join(places, 'folder.png'))
    icon_folder(home=True).save(os.path.join(places, 'user-home.png'))
    icon_monitor().save(os.path.join(devices, 'computer.png'))
    with open(os.path.join(outdir, 'index.theme'), 'w') as f:
        f.write(
            '[Icon Theme]\n'
            'Name=BlackHole\n'
            'Comment=Black Hole Linux icon theme (Matrix edition)\n'
            'Inherits=Papirus-Dark,hicolor\n'
            'Directories=48x48/apps,48x48/places,48x48/devices\n'
            '\n[48x48/apps]\nSize=48\nType=Fixed\nContext=Applications\n'
            '\n[48x48/places]\nSize=48\nType=Fixed\nContext=Places\n'
            '\n[48x48/devices]\nSize=48\nType=Fixed\nContext=Devices\n')
    print('OK: tema de iconos BlackHole generado en', outdir)


def main():
    ap = argparse.ArgumentParser(
        description='Generador de graficos Black Hole (Matrix edition)')
    ap.add_argument('--out', help='carpeta de salida para splash + wallpaper + logo + dot')
    ap.add_argument('--user', action='store_true',
                    help='generar fondo y orbe en ~/.config para la sesion Openbox')
    ap.add_argument('--icons', help='carpeta de salida del tema de iconos BlackHole')
    ap.add_argument('--width', type=int, default=1280)
    ap.add_argument('--height', type=int, default=800)
    args = ap.parse_args()
    if not args.out and not args.user and not args.icons:
        ap.error('indica --out DIR y/o --user y/o --icons DIR')

    if args.out:
        os.makedirs(args.out, exist_ok=True)
        render(args.width, args.height).save(
            os.path.join(args.out, 'blackhole-wallpaper.jpg'), quality=90)
        render_splash().save(os.path.join(args.out, 'blackhole-splash.png'))
        render_logo().save(os.path.join(args.out, 'blackhole-logo.png'))
        render_dot().save(os.path.join(args.out, 'blackhole-dot.png'))
        print('OK: splash, wallpaper, logo y dot generados en', args.out)
    if args.user:
        cfg = os.path.expanduser('~/.config')
        os.makedirs(os.path.join(cfg, 'tint2'), exist_ok=True)
        render(args.width, args.height).save(os.path.join(cfg, 'blackhole.png'))
        make_orb().save(os.path.join(cfg, 'tint2', 'orb.png'))
        print('OK: fondo y orbe generados en', cfg)
    if args.icons:
        write_icons(args.icons)


if __name__ == '__main__':
    main()
