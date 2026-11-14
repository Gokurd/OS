# E6400 · Black Hole Matrix

Sistema ligero de 64 bits para el **Dell Latitude E6400** (Core 2 Duo, 2 GB DDR2, BIOS A14 Legacy): base tipo Bodhi 5.1.0, kernel estable, ZRAM + earlyoom y un escritorio Openbox con look **«Windows Vista + Black Hole Matrix»**: cristal oscuro verde, orbe de Inicio, lluvia Matrix y agujero negro.

Todo lo que se instala aquí está pensado para un objetivo claro: **≤ 250 MB de RAM en reposo**, sin systemd si usas antiX, y con los parámetros de arranque que hacen estable al E6400.

## Contenido

```
OS/
├── install.sh                  # Instalador del look + escritorio (apartados 3.3 y 5 de la guía)
├── scripts/
│   └── blackhole.py            # Genera el fondo (agujero negro + lluvia Matrix) y el orbe de Inicio
├── config/
│   ├── openbox/themerc         # Tema de ventanas BlackHole-Aero
│   ├── openbox/autostart       # Autoarranque de la sesión
│   ├── tint2/tint2rc           # Barra de tareas estilo Vista con orbe de Inicio
│   ├── jgmenu/jgmenurc         # Menú Inicio
│   ├── picom.conf              # Cristal, sombras y transparencias
│   ├── gtk-3.0/settings.ini    # GTK oscuro
│   ├── gtk-3.0/gtk.css         # Selección verde
│   └── Xresources              # XTerm verde sobre negro
├── bin/
│   └── juego                   # Apaga picom, lanza el juego y lo reactiva al salir
├── system/
│   ├── sysctl/99-e6400.conf    # vm.swappiness, vfs_cache_pressure, page-cluster
│   ├── zramswap                # ZRAM con lz4 al 50 %
│   └── grub-cmdline-ejemplo.txt# Parámetros de arranque de ejemplo
└── docs/
    └── guia-e6400.md           # Guía completa: kernel, RAM, juegos y look
```

## Requisitos

- Base recomendada: **antiX 64-bit base/core** (sin systemd) o **Debian netinst 64-bit** sin tarea de escritorio.
- BIOS (F2): Boot en **Legacy**, USB boot activado, SATA Operation = **AHCI**.
- Primera conexión por cable Ethernet (para el firmware Broadcom, si tu unidad lo lleva).

## Instalación rápida del escritorio y el look

```sh
git clone https://github.com/Gokurd/OS.git
cd OS
chmod +x install.sh scripts/blackhole.py bin/juego
./install.sh
```

Cierra sesión y vuelve a entrar (`startx` en tty1). El fondo y el orbe se generan solos con `scripts/blackhole.py` (requiere `python3-pil`, lo instala el script).

## Orden de ataque recomendado (guía completa en `docs/guia-e6400.md`)

1. Extraer datos del Bodhi actual (`lsmod`, `cmdline`, `lspci`...).
2. ISO ligera de 64 bits + escalera de parámetros de arranque.
3. BIOS (actualizarla si nada funciona).
4. Kernel propio con `localmodconfig` (solo si hace falta).
5. ZRAM + earlyoom + sysctl.
6. Escritorio mínimo + look Black Hole Matrix (este repo).

## Notas

- Los recursos de Microsoft son propietarios: el look es de estilo propio (cristal oscuro, orbe verde, lluvia Matrix y agujero negro), no una copia de Vista.
- `mitigations=off` quita las protecciones Meltdown/Spectre y el Core 2 no recibe microcódigo anti-Spectre: con navegador es un riesgo real, decides tú.
- Deja siempre el kernel de la distro en «Advanced options» de GRUB como respaldo.

## Licencia

MIT. Los temas y scripts son de uso libre.
