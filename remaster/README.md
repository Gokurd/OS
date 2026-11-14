# Black Hole Linux v8.0 — Remaster ULTIMATE-E6400 (Bodhi 7.0.0 / Matrix edition)

Remaster de la ISO oficial de **Bodhi Linux 7.0.0 amd64** (Ubuntu 22.04 LTS + Moksha)
adaptado al **Dell Latitude E6400** (Core 2 Duo P8400, GMA 4500MHD, 2 GiB DDR2,
BIOS Legacy A14), con la sesión extra **Openbox (BlackHole-Aero)** estilo
*Windows Vista + Black Hole Matrix*.

A diferencia de un build desde cero, este remaster conserva el kernel, el initrd
y el arranque El Torito BIOS **originales de Bodhi** (conocidos buenos en el
E6400), descomprime el squashfs live, personaliza, reempaqueta y reconstruye la
ISO. No se reemplaza nunca el initrd Live.

## Qué incluye

- **Arranque tipo Zorin OS**: splash Plymouth negro con logo de agujero negro
  pulsante, título **BLACK HOLE** en verde y punto de progreso; al llegar al
  escritorio, fundido de entrada de negro a escritorio (`bh-bootfade`), en
  Moksha y en Openbox.
- **Tema de iconos BlackHole** generado por código (inicio, terminal, navegador,
  carpetas, equipo, monitor de sistema, editor, gamepad), hereda Papirus-Dark.
- **Fondo de pantalla y splash** generados por código con PIL: agujero negro con
  disco de acreción + lluvia Matrix + título BLACK HOLE en verde.
- **Sesión Openbox BlackHole-Aero**: tint2 con orbe de Inicio verde, jgmenu,
  picom (xrender), feh. Moksha sigue siendo la sesión por defecto.
- **Ajustes E6400**: zram LZ4 60%, earlyoom, TLP, planificadores E/S, locales
  es_DO, teclado latam, gamemode, RetroArch con núcleos GB/GBC/GBA/NES/SNES/
  Genesis, utilidades `blackhole`/`bh-*`.

## Estructura modular

El script principal carga los módulos que viven en esta misma carpeta:

| Archivo | Contenido |
| --- | --- |
| `blackhole-linux.sh` | Script principal: argumentos, validaciones, chroot y flujo `main` |
| `bh-theme.sh` | Tema Black Hole/Matrix: Plymouth base, GRUB, GTK oscuro, conky, MOTD, LightDM |
| `bh-system.sh` | Ajustes E6400: sysctl, zram, planificadores E/S, locales es_DO, utilidades `bh-*` |
| `bh-build-steps.sh` | Pasos de construcción: servicios, extracción, instalación, squashfs, repack |
| `matrix-look.sh` | Sesión Openbox **BlackHole-Aero** (tint2 + orbe, jgmenu, picom, feh) |
| `bh-bootlook.sh` | Arranque tipo Zorin: splash **BLACK HOLE** verde, iconos, fundido al escritorio |
| `generate-assets.py` | Genera wallpaper/splash/logo/orbe/iconos por código (PIL) |
| `kernel-e6400.config` | Fragmento de configuración del **kernel a la medida** E6400 |

## Uso (en un host Linux x86_64 con root e Internet, NO en el E6400)

```bash
# 1. Descarga la ISO base de Bodhi 7.0.0 Standard amd64 (~1,2 GB)
#    https://sourceforge.net/projects/bodhilinux/files/7.0.0/bodhi-7.0.0-64.iso/download

# 2. Requisitos del host
sudo apt install xorriso squashfs-tools python3-pil fonts-dejavu-core

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

## Kernel a la medida (opcional, para el sistema instalado)

El workflow `build-kernel` compila un kernel 6.6 LTS con la configuración
`remaster/kernel-e6400.config` (i915 integrado, solo gráficos Intel, WiFi del
E6400 como módulos, zram, sin KVM/Xen/Bluetooth, sin debug info) y publica los
`.deb` en una release `kernel-<N>`. Instalación en el E6400 **tras instalar el
sistema al disco**:

```bash
sudo apt install ./linux-image-*-blackhole-e6400_*.deb ./linux-headers-*-blackhole-e6400_*.deb
sudo blackhole firstboot    # o sudo update-grub
```

El kernel Live de la ISO sigue siendo el de Bodhi (pareja vmlinuz/initrd
original); el kernel a la medida se usa en el sistema instalado, donde ahorra
RAM y tiempo de arranque.

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

- `build-remaster`: construye el remaster en cada cambio bajo `remaster/**`
  (o manual con *workflow_dispatch*); publica la ISO como release
  `remaster-<run_number>` y abre un issue con el log si falla.
- `build-kernel`: compila el kernel a la medida; publica los `.deb` como
  release `kernel-<run_number>`.
