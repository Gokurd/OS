# Black Hole Linux v8.0 — Remaster ULTIMATE-E6400 (Bodhi 7.0.0 / Matrix edition)

Remaster de la ISO oficial de **Bodhi Linux 7.0.0 amd64** (Ubuntu 22.04 LTS + Moksha)
adaptado al **Dell Latitude E6400** (Core 2 Duo P8400, GMA 4500MHD, 2 GiB DDR2,
BIOS Legacy A14), con la sesión extra **Openbox (BlackHole-Aero)** estilo
*Windows Vista + Black Hole Matrix*.

A diferencia de un build desde cero, este remaster conserva el kernel, el initrd
y el arranque El Torito BIOS **originales de Bodhi** (conocidos buenos en el
E6400), descomprime el squashfs live, personaliza, reempaqueta y reconstruye la
ISO. No se reemplaza nunca el initrd Live.

## Estructura modular

El script principal carga los módulos que viven en esta misma carpeta:

| Archivo | Contenido |
| --- | --- |
| `blackhole-linux.sh` | Script principal: argumentos, validaciones, chroot y flujo `main` |
| `bh-theme.sh` | Tema Black Hole/Matrix: Plymouth, GRUB, GTK oscuro, conky, MOTD, LightDM |
| `bh-system.sh` | Ajustes E6400: sysctl, zram, planificadores E/S, locales es_DO, utilidades `bh-*` |
| `bh-build-steps.sh` | Pasos de construcción: servicios, extracción, instalación, squashfs, repack |
| `matrix-look.sh` | Sesión Openbox **BlackHole-Aero** (tint2 + orbe de Inicio, jgmenu, picom, feh) |
| `generate-assets.py` | Genera wallpaper/splash/orbe por código (PIL), sin descargar nada |

## Uso (en un host Linux x86_64 con root e Internet, NO en el E6400)

```bash
# 1. Descarga la ISO base de Bodhi 7.0.0 Standard amd64 (~1,2 GB)
#    https://sourceforge.net/projects/bodhilinux/files/7.0.0/bodhi-7.0.0-64.iso/download

# 2. Requisitos del host
sudo apt install xorriso squashfs-tools python3-pil

# 3. Dry-run (valida la ISO base sin construir)
sudo bash remaster/blackhole-linux.sh --base /ruta/bodhi-7.0.0-64.iso --dry-run

# 4. Construcción completa (20-40 min, 12 GB libres)
sudo bash remaster/blackhole-linux.sh \
    --base /ruta/bodhi-7.0.0-64.iso \
    --output /mnt/blackhole-bodhi-ultimate-e6400.iso \
    --work /mnt/bh-work
```

Opciones útiles: `--compression zstd|xz|gzip`, `--mkfs-procs N`, `--no-games`,
`--no-office`, `--no-browser`, `--with-firefox-esr`, `--with-b43-firmware`,
`--no-zram`, `--no-earlyoom`, `--no-tlp`, `--no-theme`, `--no-matrixlook`,
`--with-wine`, `--with-antimicro`, `--extra-packages "pkg1 pkg2"`, `--dry-run`,
`--check-host`, `--clean`, `--force`.

Si pones `assets/blackhole-splash.png` y `assets/blackhole-wallpaper.jpg` junto
al script se usan como arte real; si no, `generate-assets.py` los dibuja por
código (agujero negro + lluvia Matrix).

## En el E6400 tras instalar

```bash
sudo blackhole firstboot    # instala GRUB, regenera initramfs, fstab noatime
sudo blackhole upgrade      # actualización completa
blackhole doctor            # diagnóstico completo del sistema
bh-gpu uxa                  # si X fuera inestable en la GMA 4500MHD (raro)
```

La sesión por defecto sigue siendo **Moksha**; en el gestor de sesión elige
**Openbox (BlackHole-Aero)** para el escritorio Vista + Matrix con orbe de
Inicio verde.

## CI

El workflow `.github/workflows/build-remaster.yml` construye este remaster en
cada cambio bajo `remaster/**` (o manualmente con *workflow_dispatch*):
descarga la ISO base de Bodhi, ejecuta el script como root y publica la ISO
resultante como release `remaster-<run_number>`.
