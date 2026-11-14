#!/usr/bin/env bash
# Modulo: ajustes de sistema para E6400 (sysctl, zram, GRUB, locales, utilidades bh-*)
# Parte de Black Hole Linux v8.0 ULTIMATE-E6400. Lo sourcea blackhole-linux.sh

# --------------------------- SYSTEM TUNING (E6400) ----------------------------
write_target_config() {
    step "Ajustes de sistema Black Hole para E6400 (2 GiB)"
    mkdir -p "$ROOT/etc/blackhole" "$ROOT/usr/local/bin" "$ROOT/usr/local/sbin" \
             "$ROOT/etc/sysctl.d" "$ROOT/etc/modules-load.d" "$ROOT/etc/X11/xorg.conf.d" \
             "$ROOT/etc/udev/rules.d" "$ROOT/etc/default/grub.d" "$ROOT/etc/systemd/system" \
             "$ROOT/usr/share/doc/blackhole" "$ROOT/etc/skel/.config/retroarch"

    cat > "$ROOT/etc/blackhole-release" <<RELEASE
${BH_NAME} ${BH_VERSION} ${BH_PROFILE}
Base: Bodhi Linux 7.0.0 / Ubuntu 22.04 LTS (amd64) + Moksha
Target: Dell Latitude E6400, Core 2 Duo P8400 (Penryn), GMA 4500MHD, 2 GiB DDR2
Firmware: Legacy BIOS A14; ACPI normal conservado
Theme: Black Hole / Matrix edition
RELEASE

    # Ethernet remains available; NetworkManager will not manage Wi-Fi in this profile.
    mkdir -p "$ROOT/etc/NetworkManager/conf.d"
    cat > "$ROOT/etc/NetworkManager/conf.d/90-blackhole-wired-only.conf" <<'NM'
[keyfile]
unmanaged-devices=type:wifi
NM

    printf '%s\n' "$BH_HOSTNAME" > "$ROOT/etc/hostname"
    if grep -qE '^127\.0\.1\.1[[:space:]]' "$ROOT/etc/hosts"; then
        sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1\t${BH_HOSTNAME}/" "$ROOT/etc/hosts"
    else
        printf '127.0.1.1\t%s\n' "$BH_HOSTNAME" >> "$ROOT/etc/hosts"
    fi

    # --- sysctl: rendimiento en 2 GiB + latencia baja ---
    local swappiness=60
    [[ "$BH_DO_ZRAM" = 1 ]] && swappiness=100
    cat > "$ROOT/etc/sysctl.d/90-blackhole-e6400.conf" <<SYSCTL
# Perfil conservador para 2 GiB; zram activa mayor disposición a comprimir páginas.
vm.swappiness = ${swappiness}
vm.vfs_cache_pressure = 100
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.page-cluster = 0
SYSCTL

    # --- zram (LZ4, 60% de RAM) ---
    if [[ "$BH_DO_ZRAM" = 1 ]]; then
        cat > "$ROOT/etc/default/zramswap" <<'ZRAM'
ALGO=lz4
PERCENT=60
PRIORITY=100
ZRAM
        printf 'zram\n' > "$ROOT/etc/modules-load.d/blackhole-zram.conf"
    fi

    # --- Planificador de E/S: mq-deadline para SSD, bfq para HDD rotativo ---
    cat > "$ROOT/etc/udev/rules.d/60-blackhole-scheduler.rules" <<'UDEV'
# Black Hole: planificador de E/S según tipo de disco
ACTION=="add|change", KERNEL=="sd[a-z]|nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
UDEV

    # --- Parámetros de kernel (se aplican al instalar: update-grub en firstboot) ---
    # Parámetros conservadores: no forzar ACPI, mitigaciones, clocksource ni i915.
    local grub_theme_line=""
    [[ "$BH_DO_THEME" = 1 ]] && grub_theme_line='GRUB_THEME="/boot/grub/themes/blackhole/theme.txt"'
    cat > "$ROOT/etc/default/grub.d/90-blackhole.cfg" <<GRUB
# No se fuerzan opciones ACPI, TSC ni parámetros experimentales de i915.
# ACPI permanece activo y el kernel selecciona los controladores adecuados.
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_DISTRIBUTOR="Black Hole Linux"
GRUB_TIMEOUT=3
GRUB_GFXMODE=1280x800
GRUB_GFXPAYLOAD_LINUX=keep
$grub_theme_line
GRUB

    # --- Servicio de primer arranque (instala GRUB, regenera initramfs, claves SSH) ---
    cat > "$ROOT/etc/systemd/system/blackhole-firstboot.service" <<'FB'
[Unit]
Description=Black Hole Linux first-boot configuration
ConditionPathExists=!/etc/blackhole/firstboot.done
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/blackhole-firstboot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
FB

    cat > "$ROOT/usr/local/sbin/blackhole-firstboot" <<'FBSCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
exec >>/var/log/blackhole-firstboot.log 2>&1

DONE=/etc/blackhole/firstboot.done
[[ -e "$DONE" ]] && exit 0
[[ "$(id -u)" -eq 0 ]] || { echo "Debe ejecutarse como root."; exit 1; }
echo "=== Black Hole firstboot $(date) ==="

command -v update-grub >/dev/null 2>&1 || { echo "Falta update-grub"; exit 1; }
command -v update-initramfs >/dev/null 2>&1 || { echo "Falta update-initramfs"; exit 1; }
update-grub
update-initramfs -u -k all

# Crear claves SSH únicas sin hacer fallar el primer arranque si SSH no está instalado.
if command -v ssh-keygen >/dev/null 2>&1 && [[ -d /etc/ssh ]]; then
    for t in ed25519 ecdsa rsa; do
        [[ -f "/etc/ssh/ssh_host_${t}_key" ]] || \
            ssh-keygen -t "$t" -f "/etc/ssh/ssh_host_${t}_key" -N '' >/dev/null 2>&1 || true
    done
fi

# Añadir noatime únicamente a la cuarta columna (opciones) de la raíz.
if [[ -f /etc/fstab ]]; then
    tmp="$(mktemp /etc/fstab.blackhole.XXXXXX)"
    awk '
      /^[[:space:]]*#/ || NF < 4 { print; next }
      $2 == "/" {
        n = split($4, opts, ","); found = 0
        for (i = 1; i <= n; i++) if (opts[i] == "noatime") found = 1
        if (!found) $4 = $4 ",noatime"
      }
      { print }
    ' /etc/fstab > "$tmp"
    cat "$tmp" > /etc/fstab
    rm -f "$tmp"
fi

mkdir -p /etc/blackhole
touch "$DONE"
echo "=== firstboot completado correctamente ==="
FBSCRIPT
    chmod 755 "$ROOT/usr/local/sbin/blackhole-firstboot"

    # --- Zona horaria / teclado / locale (República Dominicana) ---
    if [[ -e "$ROOT/usr/share/zoneinfo/America/Santo_Domingo" ]]; then
        ln -sfn /usr/share/zoneinfo/America/Santo_Domingo "$ROOT/etc/localtime"
        printf 'America/Santo_Domingo\n' > "$ROOT/etc/timezone"
    fi
    cat > "$ROOT/etc/default/keyboard" <<'KEYBOARD'
XKBMODEL="pc105"
XKBLAYOUT="latam"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
KEYBOARD
    if [[ -f "$ROOT/etc/locale.gen" ]]; then
        if grep -qE '^#?es_DO\.UTF-8 UTF-8$' "$ROOT/etc/locale.gen"; then
            sed -i -E 's/^#(es_DO\.UTF-8 UTF-8)$/\1/' "$ROOT/etc/locale.gen"
        else
            printf '\nes_DO.UTF-8 UTF-8\n' >> "$ROOT/etc/locale.gen"
        fi
    fi
    printf 'LANG=es_DO.UTF-8\nLANGUAGE=es_DO:es\n' > "$ROOT/etc/default/locale"

    # --- Intel GMA 4500MHD: permitir selección automática de i915/Mesa ---
    # No fijar SNA/UXA globalmente: en Gen4.5 el resultado depende de Mesa/Xorg.
    rm -f "$ROOT/etc/X11/xorg.conf.d/20-blackhole-intel.conf"

    # --- Audio PulseAudio: latencia moderada (3 fragmentos de 25 ms) ---
    mkdir -p "$ROOT/etc/pulse/daemon.conf.d"
    cat > "$ROOT/etc/pulse/daemon.conf.d/90-blackhole.conf" <<'PULSE'
realtime-scheduling = yes
rlimit-rttime = -1
default-fragments = 3
default-fragment-size-msec = 25
resample-method = speex-fixed-2
PULSE

    # --- RetroArch preconfigurado: RGUI, vídeo en hilo, audio bajo ---
    cat > "$ROOT/etc/skel/.config/retroarch/retroarch.cfg" <<'RA'
menu_driver = "rgui"
video_driver = "gl"
video_threaded = "false"
video_vsync = "true"
video_fullscreen = "true"
audio_driver = "pulse"
audio_latency = 128
input_max_users = "2"
input_joypad_driver = "udev"
input_autodetect_enable = "true"
core_assets_directory = "/usr/share/libretro/assets"
libretro_directory = "/usr/lib/x86_64-linux-gnu/libretro"
rgui_aspect_ratio = "1.7778"
RA

    # --- Utilidades bh-* (heredadas, mejoradas) ---
    cat > "$ROOT/usr/local/sbin/bh-gpu-config" <<'GPUCONFIG'
#!/usr/bin/env bash
set -euo pipefail
F=/etc/X11/xorg.conf.d/20-blackhole-intel.conf
mode="${1:-status}"
case "$mode" in
  status)
    echo "Configuración Xorg Intel (GMA 4500MHD):"
    [[ -f "$F" ]] && cat "$F" || echo "Automática."
    command -v glxinfo >/dev/null 2>&1 && glxinfo -B 2>/dev/null | sed -n '1,14p' || true
    ;;
  auto) rm -f "$F"; echo "Automática restaurada. Cierra sesión." ;;
  uxa|sna)
    command -v Xorg >/dev/null 2>&1 || { echo "Xorg no instalado." >&2; exit 1; }
    mkdir -p "$(dirname "$F")"
    cat > "$F" <<EOF2
Section "Device"
    Identifier "BlackHoleIntelGMA"
    Driver "intel"
    Option "AccelMethod" "$mode"
    Option "DRI" "2"
    Option "TearFree" "false"
EndSection
EOF2
    echo "Intel $mode aplicado. Sal de la sesión gráfica."
    ;;
  *) echo "Uso: bh-gpu status|auto|uxa|sna" >&2; exit 2 ;;
esac
GPUCONFIG
    chmod 755 "$ROOT/usr/local/sbin/bh-gpu-config"
    cat > "$ROOT/usr/local/bin/bh-gpu" <<'GPUSCRIPT'
#!/bin/sh
case "${1:-status}" in
  status) exec /usr/local/sbin/bh-gpu-config status ;;
  auto|uxa|sna) exec sudo /usr/local/sbin/bh-gpu-config "$1" ;;
  *) echo "Uso: bh-gpu status|auto|uxa|sna" >&2; exit 2 ;;
esac
GPUSCRIPT
    chmod 755 "$ROOT/usr/local/bin/bh-gpu"

    cat > "$ROOT/usr/local/sbin/bh-cpupower" <<'CPUPOWER'
#!/usr/bin/env bash
set -euo pipefail
[[ "$(id -u)" = 0 ]] || { echo "Ejecuta con sudo." >&2; exit 1; }
mode="${1:-status}"
case "$mode" in
  game) wanted=performance ;;
  balanced) wanted=balanced ;;
  *) echo "Uso: bh-cpupower game|balanced" >&2; exit 2 ;;
esac
changed=0
for govfile in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
  [[ -w "$govfile" ]] || continue
  availfile="${govfile%scaling_governor}scaling_available_governors"
  [[ -r "$availfile" ]] || continue
  avail="$(cat "$availfile")"
  target="$wanted"
  if [[ "$mode" = balanced ]]; then
    if grep -qw schedutil <<<"$avail"; then target=schedutil
    elif grep -qw ondemand <<<"$avail"; then target=ondemand
    elif grep -qw powersave <<<"$avail"; then target=powersave
    else echo "Sin gobernador equilibrado para $govfile"; continue; fi
  fi
  if grep -qw "$target" <<<"$avail"; then
    printf '%s\n' "$target" > "$govfile"
    changed=$((changed+1))
  else
    echo "Kernel no ofrece '$target' en $(dirname "$govfile")."
  fi
done
((changed)) && echo "Gobernador actualizado en $changed CPU(s)." || echo "Sin cpufreq; control automático del kernel."
CPUPOWER
    chmod 755 "$ROOT/usr/local/sbin/bh-cpupower"
    cat > "$ROOT/usr/local/bin/bh-perf" <<'PERFSCRIPT'
#!/bin/sh
case "${1:-status}" in
  status)
    echo "Gobernadores actuales:"
    for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
      [ -r "$f" ] && printf '%s: %s\n' "$(dirname "$f")" "$(cat "$f")"
    done
    ;;
  game|balanced) exec sudo /usr/local/sbin/bh-cpupower "$1" ;;
  *) echo "Uso: bh-perf status|game|balanced" >&2; exit 2 ;;
esac
PERFSCRIPT
    chmod 755 "$ROOT/usr/local/bin/bh-perf"

    cat > "$ROOT/usr/local/bin/bh-doctor" <<'DOCTOR'
#!/usr/bin/env bash
set -u
section() { printf '\n========== %s ==========\n' "$*"; }
run_if() { command -v "$1" >/dev/null 2>&1 && "$@" || true; }
section "BLACK HOLE / SISTEMA"
cat /etc/blackhole-release 2>/dev/null || true
printf 'Kernel: '; uname -r
printf 'Arquitectura: '; dpkg --print-architecture 2>/dev/null || uname -m
section "CPU, RAM Y SWAP"
run_if lscpu | grep -E 'Model name|Architecture|CPU\(s\)|MHz' || true
free -h
swapon --show 2>/dev/null || true
run_if zramctl
section "TEMPERATURA Y BATERIA"
run_if sensors
for f in /sys/class/power_supply/*/capacity; do
    [[ -r "$f" ]] && printf '%s: %s%%\n' "$(basename "$(dirname "$f")")" "$(cat "$f")"
done
section "GRAFICOS, WIFI Y AUDIO"
run_if lspci -nnk | grep -A3 -Ei 'VGA|Display|Network|Audio' || true
run_if glxinfo -B
run_if rfkill list
run_if iw dev
run_if ip -brief link
run_if aplay -l
run_if pactl info
section "ALMACENAMIENTO"
run_if lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
run_if df -hT
section "ACPI / FIRMWARE / KERNEL"
journalctl -k -b --no-pager 2>/dev/null | grep -Ei 'ACPI|i915|drm|firmware|b43|thermal|cpufreq' | tail -n 100 || true
section "ERRORES DEL ARRANQUE"
journalctl -b -p err --no-pager 2>/dev/null | tail -n 60 || true
DOCTOR
    chmod 755 "$ROOT/usr/local/bin/bh-doctor"

    cat > "$ROOT/usr/local/bin/bh-apps" <<'BHAPPS'
#!/usr/bin/env bash
set -Eeuo pipefail
cmd="${1:-help}"; shift || true
need_args() { (($#)) || { echo "Faltan argumentos. Usa: bh-apps help" >&2; exit 2; }; }
case "$cmd" in
  update) exec sudo apt-get update ;;
  upgrade) exec sudo apt-get upgrade ;;
  install) need_args "$@"; exec sudo apt-get install --no-install-recommends "$@" ;;
  remove|purge) need_args "$@"; exec sudo apt-get "$cmd" "$@" ;;
  search) need_args "$@"; exec apt-cache search "$*" ;;
  show) need_args "$@"; exec apt-cache show "$1" ;;
  list) exec dpkg-query -W -f='${Package}\t${Version}\n' ;;
  autoremove) exec sudo apt-get autoremove ;;
  clean) exec sudo apt-get clean ;;
  help|-h|--help)
    cat <<'HELP'
Uso: bh-apps update|upgrade|install PKG|remove PKG|purge PKG|search TEXTO|show PKG|list|autoremove|clean
HELP
    ;;
  *) echo "Acción desconocida: $cmd. Usa bh-apps help." >&2; exit 2 ;;
esac
BHAPPS
    chmod 755 "$ROOT/usr/local/bin/bh-apps"

    cat > "$ROOT/usr/local/bin/bh-retro" <<'BHRETRO'
#!/usr/bin/env bash
set -Eeuo pipefail
cmd="${1:-status}"; shift || true
case "$cmd" in
  status)
    command -v retroarch >/dev/null 2>&1 && retroarch --version || echo "RetroArch no instalado."
    [[ -d /usr/lib/x86_64-linux-gnu/libretro ]] && { echo "Núcleos:"; find /usr/lib/x86_64-linux-gnu/libretro -maxdepth 1 -type f -printf '  %f\n' | sort; }
    ;;
  cores) apt-cache search '^libretro-' || true ;;
  launch) exec retroarch "$@" ;;
  install) (($#)) || { echo "Uso: bh-retro install paquete-libretro" >&2; exit 2; }; exec bh-apps install "$@" ;;
  help|-h|--help) echo "Uso: bh-retro status|cores|launch|install PKG" ;;
  *) echo "Uso: bh-retro status|cores|launch|install" >&2; exit 2 ;;
esac
BHRETRO
    chmod 755 "$ROOT/usr/local/bin/bh-retro"

    # --- Diagnóstico gamepad: no falsifica el ID del mando ni impone perfil DS4 ---
    cat > "$ROOT/usr/local/bin/bh-gamepad" <<'GAMEPAD'
#!/usr/bin/env bash
set -u
printf '%s\n' '=== Dispositivos de entrada ==='
if [[ -d /dev/input/by-id ]]; then
    ls -l /dev/input/by-id
else
    echo 'No existe /dev/input/by-id (¿estás en una sesión Live o sin mando conectado?).'
fi
if command -v evtest >/dev/null 2>&1; then
    echo
    evtest --list-devices 2>/dev/null || true
fi
if command -v lsusb >/dev/null 2>&1; then
    echo
    lsusb
fi
cat <<'TIP'
Prueba: conecta el mando por USB y ejecuta sudo evtest; selecciona su eventN.
El mapeo de 13 botones debe calibrarse según los códigos reales del dispositivo.
No se fuerza una identidad DualShock 4: evdev informa el hardware detectado.
TIP
GAMEPAD
    chmod 755 "$ROOT/usr/local/bin/bh-gamepad"

    # Compila proyectos locales; no descompila binarios ni modifica juegos cerrados.
    cat > "$ROOT/usr/local/bin/bh-build" <<'BUILD'
#!/usr/bin/env bash
set -Eeuo pipefail
src="${1:-.}"
[[ -d "$src" ]] || { echo "Uso: bh-build [directorio-del-proyecto]" >&2; exit 2; }
src="$(cd "$src" && pwd -P)"
export CFLAGS="${CFLAGS:--O2 -pipe -march=core2 -mtune=core2}"
export CXXFLAGS="${CXXFLAGS:--O2 -pipe -march=core2 -mtune=core2}"
export MAKEFLAGS="${MAKEFLAGS:--j1}"
cd "$src"
printf 'Target compiler flags: %s\n' "$CFLAGS"
if [[ -f CMakeLists.txt ]]; then
    command -v cmake >/dev/null 2>&1 || { echo 'Falta cmake.' >&2; exit 1; }
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS"
    cmake --build build --parallel 1
elif [[ -x ./configure ]]; then
    ./configure --prefix="$HOME/.local"
    make -j1
elif [[ -f Makefile || -f makefile ]]; then
    make -j1
else
    echo 'No encuentro CMakeLists.txt, configure ejecutable ni Makefile.' >&2
    exit 1
fi
printf '\nCompilación terminada. No se instalaron archivos en el sistema.\n'
BUILD
    chmod 755 "$ROOT/usr/local/bin/bh-build"

    cat > "$ROOT/usr/local/bin/bh-inspect" <<'INSPECT'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# -eq 1 && -f "$1" ]] || { echo 'Uso: bh-inspect archivo-ELF-o-binario' >&2; exit 2; }
file "$1"
if readelf -h "$1" >/dev/null 2>&1; then
    printf '\n=== ELF header ===\n'
    readelf -h "$1"
    printf '\n=== Dependencias dinámicas ===\n'
    readelf -d "$1" 2>/dev/null | grep -E 'NEEDED|RPATH|RUNPATH' || true
    printf '\n=== Símbolos (muestra) ===\n'
    nm -D "$1" 2>/dev/null | head -n 40 || true
    printf '\n=== Desensamblado (primeras instrucciones) ===\n'
    objdump -d -M intel "$1" 2>/dev/null | head -n 80 || true
else
    echo 'No es un ELF reconocido por readelf; se muestra información de strings.'
    strings -n 8 "$1" | head -n 80 || true
fi
cat <<'NOTE'
NOTA: esto inspecciona metadatos y cadenas; no reconstruye código fuente.
Para ingeniería inversa legal de binarios propios se requiere análisis separado.
NOTE
INSPECT
    chmod 755 "$ROOT/usr/local/bin/bh-inspect"

    # --- Comando maestro 'blackhole' ---
    cat > "$ROOT/usr/local/bin/blackhole" <<'MAIN'
#!/usr/bin/env bash
set -u
cmd="${1:-help}"; shift || true
case "$cmd" in
  firstboot) exec sudo /usr/local/sbin/blackhole-firstboot ;;
  upgrade)   sudo apt-get update && exec sudo apt-get upgrade -y ;;
  doctor)    exec bh-doctor ;;
  perf)      exec bh-perf "$@" ;;
  gpu)       exec bh-gpu "$@" ;;
  apps)      exec bh-apps "$@" ;;
  retro)     exec bh-retro "$@" ;;
  gamepad)   exec bh-gamepad "$@" ;;
  build)     exec bh-build "$@" ;;
  inspect)   exec bh-inspect "$@" ;;
  matrix)    exec cmatrix -b -u 2 ;;
  neofetch)  exec neofetch ;;
  help|-h|--help)
    cat <<'HELP'
Black Hole Linux — comando central
  blackhole firstboot   Aplicar GRUB/initramfs/fstab tras instalar
  blackhole upgrade     Actualizar paquetes
  blackhole doctor      Diagnóstico completo del sistema
  blackhole perf status|game|balanced  Gobernador CPU
  blackhole gpu  status|auto|uxa|sna   Driver Intel GMA
  blackhole apps ...    Gestión de paquetes (bh-apps)
  blackhole retro ...   RetroArch (bh-retro)
  blackhole gamepad      Detectar gamepad USB (evdev/evtest)
  blackhole build DIR    Compilar proyecto local con perfil Core 2 Duo
  blackhole inspect FILE Inspeccionar metadatos ELF/binario
  blackhole matrix      Lluvia de código Matrix (cmatrix)
  blackhole neofetch    Información del sistema
HELP
    ;;
  *) echo "Comando desconocido. Usa: blackhole help" >&2; exit 2 ;;
esac
MAIN
    chmod 755 "$ROOT/usr/local/bin/blackhole"

    cat > "$ROOT/usr/share/doc/blackhole/README-E6400.txt" <<'README'
BLACK HOLE LINUX 8.0 — DELL LATITUDE E6400 (Matrix edition)
Base: Bodhi 7.0.0 amd64 / Ubuntu 22.04 / Moksha. Hardware: Core 2 Duo P8400,
GMA 4500MHD, 2 GiB DDR2. BIOS A14 Legacy.
PRIMER ARRANQUE TRAS INSTALAR AL DISCO:
  sudo blackhole firstboot   (actualiza GRUB/initramfs y aplica noatime correctamente)
  sudo blackhole upgrade
RENDIMIENTO:
  blackhole perf game        (gobernador performance para jugar)
  blackhole perf balanced    (equilibrado)
  blackhole gpu status|auto|uxa|sna   (aceleración Intel; prueba UXA si hay fallos)
  ACPI y las mitigaciones de seguridad del kernel conservan sus valores predeterminados.
  zram LZ4 al 60% + earlyoom activados por defecto (2 GiB es justo).
JUEGOS:
  RetroArch con núcleos GB/GBC/GBA/NES/SNES/Genesis. Usa RGUI, cierra el navegador.
  blackhole retro status | cores | launch
  blackhole matrix (cmatrix) para el ambiente.
TEMA:
  Plymouth Black Hole en arranque. Conky verde en escritorio. GTK Arc-Dark +
  iconos BlackHole (con herencia Papirus-Dark). Wallpaper en /usr/share/backgrounds/blackhole/.
DIAGNOSTICO:
  blackhole doctor
RED:
  Ethernet queda disponible. Wi-Fi queda sin gestionar por NetworkManager.
  Para añadir firmware Broadcom durante la construcción: --with-b43-firmware.
AVISO:
  GMA 4500MHD es hardware gráfico antiguo: prioriza juegos 2D y emulación clásica.
  No se promete compatibilidad con juegos 3D modernos ni FPS constantes.
  ACPI permanece activo; no uses acpi=off, pci=noacpi ni mitigations=off como ajuste general.
README

    log "Ajustes de sistema Black Hole escritos."
}

