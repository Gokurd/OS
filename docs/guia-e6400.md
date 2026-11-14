# E6400 en 64 bits: kernel estable tipo Bodhi 5.1.0, 2 GB de RAM y look Vista + Black Hole Matrix

Dell Latitude E6400 · Core 2 Duo · 2 GB DDR2 · BIOS A14 (Legacy) · comandos directos

## 0. Léelo antes de empezar

- Tu Core 2 Duo es de 64 bits y soporta PAE. Que el kernel de Bodhi sea no-PAE no es lo que lo estabiliza: lo hacen sus drivers, ACPI y sus parámetros de arranque. Por eso se copian los **módulos** y los **parámetros**, no el `.config` de 32 bits (no sirve tal cual en x86_64).
- Los kernels 4.9 (sin soporte desde ene-2023) y 4.19 (desde dic-2024) ya no reciben parches de seguridad y compilan mal con GCC modernos. Quedan como último recurso (apartado 2.6).
- En 2 GB, muchas ISOs de 64 bits «se congelan» por falta de RAM en el live (GNOME, Cinnamon, KDE), no por el kernel. Prueba siempre con una ISO ligera.
- Orden de ataque: extraer datos de Bodhi (1) → ISO ligera con los parámetros de Bodhi (2.1-2.2) → escalera de parámetros (2.2) → BIOS (2.7) → kernel propio (2.5) → kernel 4.19 (2.6).

## 1. Extraer todo de Bodhi 5.1.0 Legacy

Antes del `lsmod`, usa el equipo 5 minutos como siempre: conecta Wi-Fi, pendrive, tarjeta SD y audio, y monta ext4/vfat/ntfs/ISO. Así el `lsmod` incluye los módulos que se cargan bajo demanda.

```sh
mkdir -p ~/e6400 && cd ~/e6400
uname -a > uname.txt
cat /proc/cmdline > cmdline.txt
lsmod > lsmod.txt
cp /boot/config-$(uname -r) config-bodhi.txt || (sudo modprobe configs; zcat /proc/config.gz > config-bodhi.txt)
lspci -nnk > lspci.txt
lsusb > lsusb.txt
sudo dmesg > dmesg.txt
sudo dmidecode -t bios -t system > dmi.txt
cp /etc/default/grub grub-default.txt
cp /var/log/Xorg.0.log xorg.log
grep -rH . /etc/modprobe.d/ /etc/modules > modprobe-d.txt 2>/dev/null
glxinfo -B > glxinfo.txt 2>/dev/null
```

Identifica tu GPU y tu Wi-Fi reales (cambia el plan de los apartados 2 y 4):

```sh
grep -A3 -E 'VGA|Network' lspci.txt
grep -E '^(i915|nouveau|nvidia|wl|b43|brcm|ssb|bcma)' lsmod.txt
```

Parámetros de arranque de Bodhi listos para reutilizar (quita BOOT_IMAGE, root, resume, ro...):

```sh
xargs -n1 < cmdline.txt | grep -vE '^(BOOT_IMAGE|root|resume|initrd|rootflags)=|^(ro|rw)$' | xargs
```

Copia la carpeta `~/e6400` a un USB.

## 2. Pasar a 64 bits

### 2.1 USB y base

Base recomendada: **antiX 64-bit base/core** (sin systemd) o **Debian netinst 64-bit** sin tarea de escritorio; los comandos valen para ambas. En la BIOS (F2): Boot en Legacy, USB boot activado y SATA Operation = AHCI.

```sh
sha256sum tu-iso.iso    # compara con el SHA256SUMS oficial
lsblk                   # identifica tu USB (p. ej. /dev/sdb), NUNCA el disco del sistema
sudo dd if=tu-iso.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Si usas Rufus: esquema MBR + destino BIOS, o modo DD.

### 2.2 Escalera de parámetros (prueba de uno en uno)

En el menú de arranque pulsa Tab (ISOLINUX/syslinux) o e (GRUB), borra `quiet splash` y añade al final. No hay parámetros «obligatorios»: se eligen según dónde se detiene.

1. Diagnóstico: `loglevel=7 ignore_loglevel`. La última línea antes del bloqueo dice qué tocar.
2. Los parámetros de Bodhi (comando del apartado 1).
3. Se detiene en DRM, i915 o nouveau: `nomodeset`. Con NVIDIA: `nouveau.modeset=0` o `nouveau.noaccel=1`.
4. Se detiene en ACPI, PCI o IRQ: `acpi_osi=Linux`, luego `pci=noacpi`, luego `acpi=noirq`, luego `noapic`.
5. Se detiene en ata/sata: `libata.force=noncq`.
6. Congelamientos al azar con el sistema ya iniciado: `processor.max_cstate=1`.
7. Último recurso: `acpi=ht` (mantiene los 2 núcleos, sin gestión de energía); y, peor aún, `acpi=off` (1 solo núcleo, sin batería ni temperaturas).

Rendimiento, una vez estable: `mitigations=off transparent_hugepage=never zswap.enabled=0 nowatchdog`. Ojo: `mitigations=off` quita las protecciones contra Meltdown/Spectre y el Core 2 no recibe microcódigo anti-Spectre; con navegador es un riesgo real, decides tú.

### 2.3 Dejarlos fijos en el sistema instalado

```sh
sudoedit /etc/default/grub
```

Deja esta línea (con los parámetros que te hicieron falta en 2.2) y actualiza GRUB:

```
GRUB_CMDLINE_LINUX_DEFAULT='quiet mitigations=off transparent_hugepage=never zswap.enabled=0 nowatchdog'
```

```sh
sudo update-grub
```

### 2.4 Wi-Fi Broadcom (primer arranque con cable Ethernet)

Añade `contrib non-free non-free-firmware` a los componentes de `/etc/apt/sources.list` (o de `/etc/apt/sources.list.d/debian.sources`) y luego:

```sh
sudo apt update
sudo apt install firmware-b43-installer    # si Bodhi cargaba b43
sudo apt install broadcom-sta-dkms         # si Bodhi cargaba wl (necesita los linux-headers del kernel en uso)
```

### 2.5 Kernel propio con tus módulos (solo si 2.2 no basta)

Compilar casi nunca hace falta (el kernel de la distro ya trae todos los drivers del E6400) y ahorra poco RAM (≈5-15 MB). Si compilas en otro PC tarda ~10 veces menos: mismos comandos y pasas los .deb por USB.

```sh
sudo apt install build-essential debhelper bc bison flex libssl-dev libelf-dev libncurses-dev dwarves rsync cpio kmod fakeroot linux-source
mkdir -p ~/kbuild && cd ~/kbuild && tar xf /usr/src/linux-source-*.tar.xz && cd linux-source-*/
cp /boot/config-$(uname -r) .config
yes '' | make LSMOD=$HOME/e6400/lsmod.txt localmodconfig
scripts/config --set-str SYSTEM_TRUSTED_KEYS '' --set-str SYSTEM_REVOCATION_KEYS '' -d DEBUG_INFO_BTF -e DEBUG_INFO_NONE
scripts/config -m ZRAM -m CRYPTO_LZ4 -m CRYPTO_ZSTD
make olddefconfig
nice make -j2 bindeb-pkg LOCALVERSION=-e6400
sudo dpkg -i ../linux-image-*-e6400_*.deb ../linux-headers-*-e6400_*.deb
sudo update-grub
```

`localmodconfig` elimina todo lo que Bodhi no tenía cargado (por eso se reactivan zram y su compresión); si falta algo, usa `make menuconfig`. Deja siempre el kernel de la distro en «Advanced options» de GRUB como respaldo.

### 2.6 Último recurso: kernel 4.19 de Debian buster

Es un kernel sin soporte: sin parches de seguridad. Los kernels anteriores a 5.9 no leen initramfs comprimidos con zstd, por eso el primer comando. Con Debian 13 (systemd reciente) puede no arrancar; mejor con antiX (sin systemd).

```sh
sudo sed -i 's/^COMPRESS=.*/COMPRESS=gzip/' /etc/initramfs-tools/initramfs.conf
cd /tmp
BASE=https://archive.debian.org/debian-security/pool/updates/main/l/linux
F=$(curl -s $BASE/ | grep -o 'linux-image-4[.]19[.]0-[0-9]*-amd64-unsigned_[A-Za-z0-9._+~]*_amd64[.]deb' | sort -uV | tail -1)
wget $BASE/$F && sudo dpkg -i $F && sudo update-grub
```

Si el listado sale vacío, prueba con `https://archive.debian.org/debian/pool/main/l/linux/`. Para el 4.9 busca `linux-image-4.9.0-*-amd64` (Debian stretch).

### 2.7 Si nada funciona: actualiza la BIOS

La A14 es antigua y los fallos de ACPI a veces se corrigen con una BIOS posterior. Con cargador y batería conectados, baja la última BIOS del E6400 desde dell.com/support, cópiala a un USB FAT32 y usa F12 → BIOS Flash Update (si aparece), o ejecútala desde Windows/FreeDOS.

## 3. RAM: ZRAM, swappiness y escritorio mínimo

### 3.1 ZRAM + earlyoom

```sh
sudo apt install zram-tools earlyoom
sudoedit /etc/default/zramswap
```

```
ALGO=lz4
PERCENT=50
PRIORITY=100
```

```sh
sudo systemctl restart zramswap    # sin systemd: sudo service zramswap restart
zramctl; swapon --show; free -m
```

`lz4` gasta poca CPU (mejor para emuladores en un Core 2 Duo sin AVX); `ALGO=zstd` comprime más pero cuesta CPU: úsalo si navegas mucho y no juegas. Sube a `PERCENT=75` si te quedas corto. `earlyoom` mata al proceso culpable antes de que el equipo se congele por falta de RAM. Si tu release usa otro archivo de configuración: `dpkg -L zram-tools | grep etc`. Con kernel propio, comprueba `grep -E 'CONFIG_ZRAM=|CONFIG_CRYPTO_LZ4=|CONFIG_CRYPTO_ZSTD=' /boot/config-$(uname -r)`.

### 3.2 sysctl

```sh
sudo tee /etc/sysctl.d/99-e6400.conf << 'EOF'
vm.swappiness=100
vm.vfs_cache_pressure=50
vm.page-cluster=0
EOF
sudo sysctl --system
```

Con ZRAM como único swap, 100 es correcto; sube a 150 si el navegador hace thrash. No añadas swap en disco con prioridad mayor que la de ZRAM.

### 3.3 Escritorio mínimo (objetivo ≤ 250 MB en reposo)

Openbox + tint2 suman unos 30-40 MB. JWM (≈10 MB, panel integrado) es aún más ligero; Moksha solo está en el repo de Bodhi, no en Debian/antiX.

```sh
sudo apt install --no-install-recommends xserver-xorg-core xserver-xorg-input-libinput x11-xserver-utils xinit dbus-x11 libgl1-mesa-dri libglx-mesa0 mesa-utils openbox obconf tint2 jgmenu picom feh pcmanfm xterm fonts-open-sans fonts-dejavu-core papirus-icon-theme python3-pil alsa-utils network-manager network-manager-gnome
echo 'exec dbus-launch --exit-with-session openbox-session' > ~/.xinitrc
echo '[ -z $DISPLAY ] && [ $(tty) = /dev/tty1 ] && exec startx' >> ~/.bash_profile
```

Sin gestor de login (ahorras 30-60 MB): inicias sesión en tty1 y arranca solo. Para medir y recortar:

```sh
free -m    # columna used, tras 2-3 min en reposo
ps -eo rss,comm --sort=-rss | head -15
sudo systemctl disable --now bluetooth ModemManager avahi-daemon cups 2>/dev/null
```

Sin picom ahorras ≈ 20 MB; sin nm-applet ≈ 15 MB (usa nmtui). Automontaje de USB (opcional, +20 MB): `sudo apt install udisks2 gvfs`.

## 4. Juegos y tareas

### 4.1 Mesa y OpenGL

- Intel GMA 4500MHD (GM45): OpenGL 2.1 como máximo y sin Vulkan. Driver crocus en Mesa ≥ 22. Usa la Mesa de tu release (Debian 12 ≈ 22.3, Debian 13 ≈ 25.0); nada de PPAs ni Mesa git. Si notas tearing o lentitud: `sudo apt install xserver-xorg-video-intel`.
- Quadro NVS 160M (G98M): nouveau (OpenGL 3.3) con `sudo apt install xserver-xorg-video-nouveau`. Evita el driver propietario 340.x: no compila en kernels modernos.
- Comprobación: `glxinfo -B | grep -E 'renderer|OpenGL version'`
- Juego que pide GL 3.x: `MESA_GL_VERSION_OVERRIDE=3.3 MESA_GLSL_VERSION_OVERRIDE=330 programa` (anuncia 3.3; solo sirve si el juego usa pocas extensiones).
- Si crocus da fallos gráficos: `sudo apt install libgl1-amber-dri` y prueba `__GLX_VENDOR_LIBRARY_NAME=amber programa` (si el paquete existe en tu release).

### 4.2 Vídeo con aceleración (Intel)

```sh
sudo apt install i965-va-driver vainfo mpv yt-dlp
LIBVA_DRIVER_NAME=i965 vainfo | head
mpv --hwdec=vaapi --ytdl-format='bv*[height<=480]+ba/b[height<=480]' URL
```

### 4.3 Emuladores sin saturar la RAM

```sh
sudo apt install retroarch libretro-snes9x libretro-genesisplusgx libretro-nestopia libretro-gambatte libretro-mgba libretro-beetle-psx
apt search ^libretro-   # el resto de núcleos disponibles
```

En RetroArch: Ajustes → Controladores: Vídeo = gl y Menú = rgui (el más ligero); desactiva Rewind y Run-Ahead; Audio → latencia 64 ms. Realista en este equipo: NES, SNES, Mega Drive, GB/GBA, PS1 y arcade ligero a velocidad completa; N64, Dreamcast y PSP, no.

PPSSPP (solo juegos 2D o muy ligeros: resolución 1x, Skip buffer effects, frameskip automático):

```sh
sudo apt install flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.ppsspp.PPSSPP
```

MUGEN es solo para Windows: o Wine (+150-250 MB de RAM) o Ikemen GO (motor libre con build para Linux en su GitHub). Si el binario pide más OpenGL del que tienes, usa el truco `MESA_GL_VERSION_OVERRIDE` de 4.1. Antes de jugar, apaga el compositor con el comando `juego` del apartado 5.5.

### 4.4 Snap: mejor no

snapd y los montajes squashfs cuestan ≈ 60-120 MB de RAM y arranques lentos; prefiere apt, Flatpak o AppImage. Si insistes: `sudo apt install snapd && sudo snap install retroarch` (con kernel propio activa SQUASHFS y XZ).

### 4.5 Navegador (64 bits, 2 GB)

Firefox ESR es el viable: `sudo apt install firefox-esr`. En about:config: `dom.ipc.processCount = 2`, `browser.sessionhistory.max_total_viewers = 1`, `browser.tabs.unloadOnLowMemory = true`. Instala uBlock Origin (baja RAM y CPU) y limítate a 4-6 pestañas. Alternativa más ligera pero menos compatible: epiphany-browser. Evita Chromium, Brave y Falkon. Para YouTube, mpv (4.2).

## 5. Look «Windows Vista + Black Hole Matrix»

Los recursos de Microsoft son propietarios, así que esto usa estilo propio: cristal oscuro, orbe verde de Inicio, lluvia Matrix y agujero negro. Si prefieres un tema Vista de terceros, búscalo en gnome-look.org (Openbox «Vista Aero») y cópialo a `~/.themes`.

Este repositorio ya incluye todos los archivos del apartado 5 en `config/`, `scripts/` y `bin/`; el `install.sh` los coloca donde deben estar. A continuación, los comandos por si prefieres hacerlo a mano.

### 5.1 Fondo y orbe (se generan solos)

```sh
mkdir -p ~/bin ~/.config/tint2 ~/.config/openbox ~/.config/jgmenu ~/.themes/BlackHole-Aero/openbox-3
python3 scripts/blackhole.py    # genera ~/.config/blackhole.png y ~/.config/tint2/orb.png
```

### 5.2 Tema de ventanas Openbox

```sh
cp /usr/share/themes/Clearlooks/openbox-3/*.xbm ~/.themes/BlackHole-Aero/openbox-3/
cp /etc/xdg/openbox/rc.xml ~/.config/openbox/
cp config/openbox/themerc ~/.themes/BlackHole-Aero/openbox-3/themerc
sed -i '/<theme>/{n;s|<name>[^<]*</name>|<name>BlackHole-Aero</name>|}' ~/.config/openbox/rc.xml
sed -i 's|<titlelayout>[^<]*</titlelayout>|<titlelayout>LIMC</titlelayout>|' ~/.config/openbox/rc.xml
```

Si no existe la carpeta Clearlooks: `ls /usr/share/themes/*/openbox-3` y copia los .xbm de cualquiera. Después, obconf → Fuentes: Open Sans 9, y `openbox --reconfigure`.

### 5.3 Barra de tareas estilo Vista (tint2)

```sh
cp config/tint2/tint2rc ~/.config/tint2/tint2rc
```

### 5.4 Menú Inicio (jgmenu)

```sh
cp config/jgmenu/jgmenurc ~/.config/jgmenu/jgmenurc
```

### 5.5 Cristal, sombras y modo juego

```sh
cp config/picom.conf ~/.config/picom.conf
cp bin/juego ~/bin/juego && chmod +x ~/bin/juego
```

Uso: `juego retroarch` (apaga picom, lanza el juego y lo reactiva al salir). Sin compositor el escritorio funciona igual, solo sin transparencias.

### 5.6 GTK oscuro, terminal verde y autostart

```sh
cp config/gtk-3.0/settings.ini ~/.config/gtk-3.0/settings.ini
cp config/gtk-3.0/gtk.css ~/.config/gtk-3.0/gtk.css
cp config/Xresources ~/.Xresources
cp config/openbox/autostart ~/.config/openbox/autostart
```

Cierra sesión y vuelve a entrar (`startx` en tty1).

## 6. Verificación final

```sh
cat /proc/cmdline                              # parámetros activos
zramctl; swapon --show                         # zram activo
free -m                                        # objetivo: used ≈ 200-250 MB en reposo
glxinfo -B | grep -E 'renderer|OpenGL version' # GPU y driver reales
```

Si algo falla, anota la última línea que aparece antes del bloqueo (2.2, paso 1) y compárala con `cmdline.txt` y `lspci.txt` de Bodhi.
