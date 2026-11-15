#!/usr/bin/env bash
# ==============================================================================
# BLACK HOLE LINUX v7.0 ULTIMATE-E6400 — Bodhi Linux remaster (Matrix edition)
# Base: Bodhi Linux 7.0.0 amd64 ISO (Ubuntu 22.04 LTS + Moksha)
# Design: coherent Ubuntu/glibc/apt/systemd remaster; no mixed Alpine/Void userspace.
# Target: Dell Latitude E6400 · Core 2 Duo P8400 (Penryn) · GMA 4500MHD · 2 GiB DDR2
# Firmware: Legacy BIOS A14 (El Torito boot records preserved)
#
# WHAT THIS SCRIPT IS: an ISO remaster. It unpacks Bodhi's live squashfs,
# chroots into it, installs/tunes/customizes, repacks the squashfs and rebuilds
# the ISO while preserving the original Live kernel/initrd and BIOS boot data.
# The installed system gets its own Black Hole Plymouth/initramfs configuration
# on first boot; the Live initrd is never replaced by a possibly mismatched file.
#
# WHAT IT IS NOT: a Linux From Scratch / Gentoo source build. On a 2 GiB Core 2
# Duo a full source compile is impractical (days). This remaster gives you a
# bootable, customized, tuned ISO in ~20-40 min on any 64-bit build host.
#
# Build on a 64-bit Linux host, as root, with 12 GB+ free and a local Bodhi ISO.
# Place blackhole-splash.png and blackhole-wallpaper.jpg in ./assets/ (or pass
# --assets DIR) for the full theme; without them it falls back to text theme.
# ==============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

# ------------------------------- VERSION / PATHS ------------------------------
BH_VERSION="8.0"
BH_NAME="Black Hole Linux"
BH_PROFILE="ULTIMATE-E6400"
BH_ARCH="amd64"
BH_HOSTNAME="${BH_HOSTNAME:-blackhole}"
BH_BASE_ISO="${BH_BASE_ISO:-}"
BH_WORK="${BH_WORK:-}"
BH_OUTPUT="${BH_OUTPUT:-}"
BH_ASSETS="${BH_ASSETS:-}"
BH_MIN_FREE_GB="${BH_MIN_FREE_GB:-12}"
BH_KEEP_WORK="${BH_KEEP_WORK:-1}"
BH_SQUASH_COMP="${BH_SQUASH_COMP:-zstd}"   # zstd (fast) | xz (small) | gzip
BH_ZSTD_LEVEL="${BH_ZSTD_LEVEL:-6}"
BH_MKFS_PROCS="${BH_MKFS_PROCS:-1}"        # 1 is safest on low-RAM build hosts
BH_DO_GAMES="${BH_DO_GAMES:-1}"
BH_DO_OFFICE="${BH_DO_OFFICE:-1}"
BH_DO_BROWSER="${BH_DO_BROWSER:-1}"        # epiphany (lightweight, deb, no snap)
BH_DO_FIREFOX="${BH_DO_FIREFOX:-0}"        # firefox-esr from mozillateam PPA (heavier)
BH_DO_B43="${BH_DO_B43:-0}"
BH_DO_ZRAM="${BH_DO_ZRAM:-1}"
BH_DO_EARLYOOM="${BH_DO_EARLYOOM:-1}"      # ON by default: 2 GiB is tight
BH_DO_TLP="${BH_DO_TLP:-1}"                # battery/power management, tiny footprint
BH_DO_THEME="${BH_DO_THEME:-1}"            # Plymouth / boot menu / GTK / icons / conky
BH_DO_DEVTOOLS="${BH_DO_DEVTOOLS:-1}"
BH_DO_WINE="${BH_DO_WINE:-0}"
BH_DO_ANTIMICRO="${BH_DO_ANTIMICRO:-0}"
BH_EXTRA_PACKAGES="${BH_EXTRA_PACKAGES:-}"
BH_FORCE=0
BH_CLEAN=0
BH_DRY_RUN=0

LOG=""
ROOT=""
MOUNTED=()
RESOLV_BACKUP=""
RESOLV_CHANGED=0
ISO_TMP=""
WORK_CREATED=0
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
STAMP="$(date +%Y%m%d-%H%M%S)"
[[ -n "$BH_WORK" ]] || BH_WORK="$SCRIPT_DIR/bh-work-bodhi-$STAMP"
[[ -n "$BH_OUTPUT" ]] || BH_OUTPUT="$SCRIPT_DIR/blackhole-bodhi-ultimate-e6400-v${BH_VERSION}-${STAMP}.iso"
[[ -n "$BH_ASSETS" ]] || BH_ASSETS="$SCRIPT_DIR/assets"

# --------------------------------- UI / LOG -----------------------------------
if [[ -t 2 ]]; then
    C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'; C_CYAN=$'\033[1;36m'; C_RESET=$'\033[0m'
else
    C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_RESET=""
fi
log()  { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
info() { printf '%s[ .. ]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
warn() { printf '%s[ ! ]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
step() { printf '\n%s==>%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<USAGE
${BH_NAME} v${BH_VERSION} — Bodhi remaster for Dell Latitude E6400 (Matrix/Black Hole edition)
USO:
  sudo $0 --base /ruta/bodhi-7.0.0-64.iso [opciones]
OPCIONES OBLIGATORIAS:
  --base ISO              ISO Bodhi 7.0.0 Standard amd64
OPCIONES DE SALIDA:
  --output ISO            Ruta de la ISO resultante
  --work DIR              Carpeta temporal de construcción
  --assets DIR            Carpeta con blackhole-splash.png y blackhole-wallpaper.jpg
  --compression zstd|xz|gzip  Compresión del squashfs (por defecto: zstd, más rápido)
  --mkfs-procs N          Procesadores para mksquashfs (por defecto: 1, poca RAM)
  --min-free-gb N         Espacio libre mínimo (por defecto: 12)
  --force                 Sobrescribir ISO de salida
  --clean                 Borrar carpeta de trabajo identificada y reconstruir
GRUPOS DE SOFTWARE (desactivar con --no-...):
  --no-games              Sin RetroArch/emuladores
  --no-office             Sin AbiWord/Gnumeric/Mousepad/Evince
  --no-browser            Sin navegador ligero (Epiphany)
  --with-firefox-esr      Añade Firefox ESR (deb, PPA mozillateam; ~200 MB extra)
  --with-b43-firmware     Añade firmware Broadcom (desactivado por defecto)
  --no-zram               Sin zram
  --no-earlyoom           Sin protección OOM (NO recomendado con 2 GiB)
  --no-tlp                Sin TLP (gestión de energía/batería)
  --no-theme              Sin personalización Black Hole/Matrix (solo tuning)
  --no-devtools            Sin herramientas de compilación/diagnóstico ELF
  --with-wine              Añade Wine multiarch (consume bastante espacio/RAM)
  --with-antimicro         Añade AntiMicro para mapear gamepads
  --extra-packages "A B"  Paquetes adicionales de los repos
OTROS:
  --dry-run               Validar requisitos e ISO, sin construir
  --check-host            Comprobar solo herramientas del constructor
  -h, --help              Esta ayuda
VARIABLES EQUIVALENTES:
  BH_BASE_ISO, BH_OUTPUT, BH_WORK, BH_ASSETS, BH_SQUASH_COMP, BH_MKFS_PROCS,
  BH_MIN_FREE_GB, BH_EXTRA_PACKAGES, BH_HOSTNAME, BH_ZSTD_LEVEL
IMPORTANTE:
  * Construye en un Linux x86_64 con root e Internet. NO construyas en el E6400.
  * Solo se genera una ISO; no se toca el disco del portátil.
  * Usa Bodhi 7.0.0 amd64. El P8400 es Intel 64; no fuerces -m32.
  * El kernel/initrd Live original se conserva como pareja.
  * Tras instalar al disco: sudo blackhole firstboot && sudo blackhole upgrade
USAGE
}

on_error() {
    local rc=$? line="${1:-?}" cmd="${2:-?}"
    printf '\n[FAIL] Error en línea %s (código %s): %s\n' "$line" "$rc" "$cmd" >&2
    [[ -n "$LOG" && -f "$LOG" ]] && printf '       Revisa el registro: %s\n' "$LOG" >&2
    exit "$rc"
}

cleanup_mounts() {
    local p
    if ((${#MOUNTED[@]})); then
        for p in "${MOUNTED[@]}"; do
            if mountpoint -q "$p" 2>/dev/null; then
                umount -R "$p" 2>/dev/null || umount -l "$p" 2>/dev/null || true
            fi
        done
    fi
    MOUNTED=()
    if [[ "$RESOLV_CHANGED" = 1 && -n "$ROOT" && -n "$RESOLV_BACKUP" && -e "$RESOLV_BACKUP" ]]; then
        mkdir -p "$ROOT/etc"
        rm -f "$ROOT/etc/resolv.conf"
        cp -a "$RESOLV_BACKUP" "$ROOT/etc/resolv.conf" 2>/dev/null || true
        RESOLV_CHANGED=0
    fi
}

cleanup() {
    cleanup_mounts
    [[ -z "$ISO_TMP" ]] || rm -f -- "$ISO_TMP" 2>/dev/null || true
    if [[ "$WORK_CREATED" = 1 && "$BH_KEEP_WORK" != 1 && -n "$BH_WORK" && -d "$BH_WORK" ]]; then
        rm -rf --one-file-system -- "$BH_WORK" 2>/dev/null || true
    fi
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
trap cleanup EXIT

# --------------------------------- ARGUMENTOS ---------------------------------
parse_args() {
    while (($#)); do
        case "$1" in
            --base)           (($# >= 2)) || die "Falta valor de --base";           BH_BASE_ISO="$2"; shift 2 ;;
            --output)         (($# >= 2)) || die "Falta valor de --output";         BH_OUTPUT="$2"; shift 2 ;;
            --work)           (($# >= 2)) || die "Falta valor de --work";           BH_WORK="$2"; shift 2 ;;
            --assets)         (($# >= 2)) || die "Falta valor de --assets";         BH_ASSETS="$2"; shift 2 ;;
            --compression)    (($# >= 2)) || die "Falta valor de --compression";    BH_SQUASH_COMP="$2"; shift 2 ;;
            --mkfs-procs)     (($# >= 2)) || die "Falta valor de --mkfs-procs";     BH_MKFS_PROCS="$2"; shift 2 ;;
            --min-free-gb)    (($# >= 2)) || die "Falta valor de --min-free-gb";    BH_MIN_FREE_GB="$2"; shift 2 ;;
            --extra-packages) (($# >= 2)) || die "Falta valor de --extra-packages"; BH_EXTRA_PACKAGES="$2"; shift 2 ;;
            --no-games)       BH_DO_GAMES=0; shift ;;
            --no-office)      BH_DO_OFFICE=0; shift ;;
            --no-browser)     BH_DO_BROWSER=0; shift ;;
            --with-firefox-esr) BH_DO_FIREFOX=1; shift ;;
            --with-b43-firmware) BH_DO_B43=1; shift ;;
            --no-b43-firmware) BH_DO_B43=0; shift ;; # compatibilidad con v7
            --no-zram)        BH_DO_ZRAM=0; shift ;;
            --no-earlyoom)    BH_DO_EARLYOOM=0; shift ;;
            --no-tlp)         BH_DO_TLP=0; shift ;;
            --no-theme)       BH_DO_THEME=0; shift ;;
            --no-devtools)    BH_DO_DEVTOOLS=0; shift ;;
            --with-wine)      BH_DO_WINE=1; shift ;;
            --with-antimicro) BH_DO_ANTIMICRO=1; shift ;;
            --dry-run)        BH_DRY_RUN=1; shift ;;
            --check-host)     if check_host; then exit 0; else exit 1; fi ;;
            --clean)          BH_CLEAN=1; shift ;;
            --force)          BH_FORCE=1; shift ;;
            -h|--help)        usage; exit 0 ;;
            --) shift; (($# == 0)) || die "No se aceptan argumentos posicionales tras --" ;;
            *) die "Opción desconocida: $1 (usa --help)" ;;
        esac
    done
}

# ------------------------------- VALIDACIONES ---------------------------------
check_host() {
    local missing=() c
    for c in bash xorriso unsquashfs mksquashfs chroot mount umount mountpoint \
             sha256sum awk sed grep sort stat du df realpath findmnt cp cmp; do
        have "$c" || missing+=("$c")
    done
    if [[ "$BH_SQUASH_COMP" = zstd ]]; then
        local squash_help
        squash_help="$(mksquashfs -help 2>&1 || true)"
        grep -qi zstd <<<"$squash_help" || missing+=("mksquashfs con soporte zstd (o usa --compression xz)")
    fi
    if ((${#missing[@]})); then
        printf 'Faltan herramientas: ' >&2; printf '%s ' "${missing[@]}" >&2; printf '\n' >&2
        printf 'Debian/Ubuntu: apt install xorriso squashfs-tools coreutils util-linux\n' >&2
        return 1
    fi
    [[ "$(uname -m)" = x86_64 ]] || { echo "El constructor debe ser x86_64." >&2; return 1; }
    [[ "$(id -u)" = 0 ]] || { echo "Ejecuta con sudo/root." >&2; return 1; }
    log "Herramientas y arquitectura del constructor correctas."
}

safe_paths() {
    local w out base
    [[ -n "$BH_WORK" && -n "$BH_OUTPUT" ]] || die "Rutas de trabajo/salida vacías."
    w="$(realpath -m -- "$BH_WORK")"
    out="$(realpath -m -- "$BH_OUTPUT")"
    [[ "$w" != / && "$w" != "$SCRIPT_DIR" && "$w" != "$HOME" ]] || die "Ruta de trabajo peligrosa: $w"
    [[ "$out" != "$w" && "$out" != "$w/"* ]] || die "La ISO de salida no puede estar dentro de la carpeta temporal."
    if [[ -e "$out" && "$BH_FORCE" != 1 ]]; then
        die "La ISO de salida ya existe: $out (usa --force)."
    fi
    if [[ -n "$BH_BASE_ISO" ]]; then
        base="$(realpath -e -- "$BH_BASE_ISO" 2>/dev/null)" || die "No existe la ISO base: $BH_BASE_ISO"
        [[ "$base" != "$out" ]] || die "ISO original y salida no pueden ser el mismo archivo."
        [[ "$base" != "$w" && "$base" != "$w/"* ]] || die "La ISO base no puede estar dentro de --work."
        BH_BASE_ISO="$base"
    fi
    [[ "$BH_HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
        || die "BH_HOSTNAME debe ser un nombre DNS simple (1-63 caracteres)."
    [[ "$BH_MIN_FREE_GB" =~ ^[0-9]+$ ]] || die "--min-free-gb debe ser entero."
    ((BH_MIN_FREE_GB >= 4 && BH_MIN_FREE_GB <= 500)) || die "--min-free-gb entre 4 y 500."
    [[ "$BH_MKFS_PROCS" =~ ^[0-9]+$ ]] || die "--mkfs-procs debe ser entero."
    ((BH_MKFS_PROCS >= 1 && BH_MKFS_PROCS <= 64)) || die "--mkfs-procs entre 1 y 64."
    case "$BH_SQUASH_COMP" in zstd|xz|gzip) ;; *) die "--compression debe ser zstd|xz|gzip" ;; esac
    [[ "$BH_ZSTD_LEVEL" =~ ^[0-9]+$ ]] && ((BH_ZSTD_LEVEL >= 1 && BH_ZSTD_LEVEL <= 19)) \
        || die "BH_ZSTD_LEVEL debe estar entre 1 y 19."
    BH_WORK="$w"; BH_OUTPUT="$out"
}

validate_base_iso() {
    [[ -n "$BH_BASE_ISO" ]] || die "Indica --base /ruta/bodhi-7.0.0-64.iso"
    [[ -f "$BH_BASE_ISO" && -r "$BH_BASE_ISO" ]] || die "No puedo leer la ISO base: $BH_BASE_ISO"
    [[ "$(stat -c %s "$BH_BASE_ISO")" -gt 500000000 ]] || die "La ISO parece demasiado pequeña."
    info "Comprobando estructura Bodhi/casper…"
    xorriso -indev "$BH_BASE_ISO" -ls /casper 2>/dev/null | grep -q 'filesystem\.squashfs' \
        || die "La ISO no contiene /casper/filesystem.squashfs. Usa Bodhi Standard amd64."
    xorriso -indev "$BH_BASE_ISO" -ls /casper 2>/dev/null | grep -Eq 'vmlinuz|initrd' \
        || warn "No se encontró vmlinuz/initrd en /casper; revisa la ISO."
    local boot_info
    boot_info="$(xorriso -indev "$BH_BASE_ISO" -report_el_torito plain 2>/dev/null)" \
        || die "No pude leer la tabla de arranque de la ISO."
    grep -qi 'BIOS' <<< "$boot_info" \
        || die "La ISO base no anuncia arranque El Torito BIOS/Legacy."
    if [[ -n "${BH_BASE_SHA256:-}" ]]; then
        local got
        got="$(sha256sum "$BH_BASE_ISO" | awk '{print $1}')"
        [[ "${got,,}" = "${BH_BASE_SHA256,,}" ]] || die "SHA256 de la ISO base incorrecto."
        log "SHA256 de la ISO base verificado."
    fi
    log "ISO base válida: $(basename "$BH_BASE_ISO")"
}

check_space() {
    local parent out_parent avail out_avail required
    parent="$(dirname "$BH_WORK")"; out_parent="$(dirname "$BH_OUTPUT")"
    mkdir -p "$parent" "$out_parent"
    avail="$(df -Pk "$parent" | awk 'NR==2 {print $4}')"
    out_avail="$(df -Pk "$out_parent" | awk 'NR==2 {print $4}')"
    required=$((BH_MIN_FREE_GB * 1024 * 1024))
    [[ "$avail" =~ ^[0-9]+$ && "$out_avail" =~ ^[0-9]+$ ]] || die "No pude calcular espacio libre."
    ((avail >= required)) || die "Espacio insuficiente en trabajo: $((avail/1024/1024)) GB libres, se exigen ${BH_MIN_FREE_GB} GB."
    ((out_avail >= 2 * 1024 * 1024)) || die "La unidad de salida necesita al menos 2 GB libres."
    log "Espacio libre: trabajo $((avail/1024/1024)) GB, salida $((out_avail/1024/1024)) GB."
}

prepare_workspace() {
    if [[ -e "$BH_WORK" ]]; then
        [[ "$BH_CLEAN" = 1 ]] || die "Ya existe $BH_WORK. Usa --work otra ruta o --clean."
        [[ -d "$BH_WORK" && ! -L "$BH_WORK" ]] || die "La ruta de trabajo existente no es carpeta normal."
        [[ -f "$BH_WORK/.blackhole-workspace" ]] || die "No borro $BH_WORK: falta marcador .blackhole-workspace."
        grep -Fqx "Black Hole Linux workspace v${BH_VERSION}" "$BH_WORK/.blackhole-workspace" \
            || die "No borro $BH_WORK: el marcador no coincide con v${BH_VERSION}."
        if findmnt -rn -o TARGET | awk -v w="$BH_WORK" '$0 == w || index($0, w "/") == 1 { found=1 } END { exit !found }'; then
            die "No borro $BH_WORK: hay sistemas de archivos montados dentro. Desmonta y reintenta."
        fi
        rm -rf --one-file-system -- "$BH_WORK"
    fi
    mkdir -p "$BH_WORK"
    chmod 700 "$BH_WORK"
    WORK_CREATED=1
    printf 'Black Hole Linux workspace v%s\n' "$BH_VERSION" > "$BH_WORK/.blackhole-workspace"
    LOG="$BH_WORK/build.log"
    : > "$LOG"
    ROOT="$BH_WORK/rootfs"
}

# --------------------------------- CHROOT -------------------------------------
mount_target() {
    mkdir -p "$ROOT"/{dev,proc,sys,run}
    mount --rbind /dev "$ROOT/dev";  mount --make-rslave "$ROOT/dev";  MOUNTED+=("$ROOT/dev")
    mount -t proc proc "$ROOT/proc"; MOUNTED+=("$ROOT/proc")
    mount --rbind /sys "$ROOT/sys";  mount --make-rslave "$ROOT/sys";  MOUNTED+=("$ROOT/sys")
    mount --rbind /run "$ROOT/run";  mount --make-rslave "$ROOT/run";  MOUNTED+=("$ROOT/run")
    RESOLV_BACKUP="$BH_WORK/resolv.conf.original"
    if [[ -e "$ROOT/etc/resolv.conf" || -L "$ROOT/etc/resolv.conf" ]]; then
        cp -a "$ROOT/etc/resolv.conf" "$RESOLV_BACKUP"
    else
        : > "$RESOLV_BACKUP"
    fi
    rm -f "$ROOT/etc/resolv.conf"
    cp -L /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null \
        || printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' > "$ROOT/etc/resolv.conf"
    RESOLV_CHANGED=1
}

chroot_run() {
    chroot "$ROOT" /usr/bin/env -i \
        HOME=/root TERM="${TERM:-linux}" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        "$@" >>"$LOG" 2>&1
}

apt_install_group() {
    local label="$1"; shift
    local pkg
    (($#)) || return 0
    step "$label"
    if chroot_run apt-get -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$@"; then
        log "Grupo instalado: $label"
        return 0
    fi
    warn "El grupo '$label' falló; instalaré paquete por paquete."
    for pkg in "$@"; do
        if chroot_run apt-get -o Dpkg::Use-Pty=0 install -y --no-install-recommends "$pkg"; then
            log "  instalado: $pkg"
        else
            warn "  omitido: $pkg (revisa $LOG)"
        fi
    done
}

apt_purge_group() {
    local label="$1"; shift
    local pkg present=() p status
    (($#)) || return 0
    for p in "$@"; do
        # Consulta directa (sin redirigir a LOG) para saber si está instalado
        status="$(chroot "$ROOT" /usr/bin/dpkg-query -W -f='${Status}' "$p" 2>/dev/null || true)"
        if grep -q 'install ok installed' <<<"$status"; then
            present+=("$p")
        fi
    done
    ((${#present[@]})) || return 0
    step "$label (purga)"
    chroot_run apt-get -y purge "${present[@]}" || warn "Purga parcial; revisa $LOG"
    log "Purga completada: ${present[*]}"
}

# --------------------- BLACK HOLE / MATRIX CUSTOMIZATION ----------------------
# Todo lo estético (Plymouth, boot menu, GTK, iconos, conky, MOTD, prompt)
write_blackhole_theme() {
    [[ "$BH_DO_THEME" = 1 ]] || { info "Personalización de tema desactivada (--no-theme)."; return 0; }
    step "Personalización Black Hole / Matrix"
    local splash="$BH_ASSETS/blackhole-splash.png"
    local wall="$BH_ASSETS/blackhole-wallpaper.jpg"
    local has_assets=0
    [[ -f "$splash" && -f "$wall" ]] && has_assets=1

    # --- Fondo de pantalla y greeter ---
    mkdir -p "$ROOT/usr/share/backgrounds/blackhole" "$ROOT/usr/share/plymouth/themes/blackhole" \
             "$ROOT/usr/share/icons/BlackHole/scalable/apps" "$ROOT/usr/share/icons/BlackHole/48x48/apps" \
             "$ROOT/etc/xdg/autostart"
    cat > "$ROOT/usr/share/icons/BlackHole/index.theme" <<'ICONINDEX'
[Icon Theme]
Name=BlackHole
Comment=Black Hole Linux icon overlay
Inherits=Papirus-Dark,hicolor
Directories=scalable/apps,48x48/apps
[scalable/apps]
Size=48
Type=Scalable
MinSize=16
MaxSize=256
[48x48/apps]
Size=48
Type=Fixed
ICONINDEX
    cat > "$ROOT/usr/share/icons/BlackHole/scalable/apps/blackhole.svg" <<'ICONSVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
 <defs><radialGradient id="disk"><stop offset="0" stop-color="#050505"/><stop offset=".42" stop-color="#050505"/><stop offset=".54" stop-color="#00ff66"/><stop offset=".72" stop-color="#087b45"/><stop offset="1" stop-color="#031b12"/></radialGradient></defs>
 <circle cx="64" cy="64" r="58" fill="#020704" stroke="#00b85a" stroke-width="3"/>
 <ellipse cx="64" cy="64" rx="54" ry="21" fill="none" stroke="#45ff9a" stroke-width="8" transform="rotate(-24 64 64)"/>
 <circle cx="64" cy="64" r="27" fill="#000" stroke="#092b1b" stroke-width="2"/>
 <circle cx="64" cy="64" r="6" fill="#000"/>
</svg>
ICONSVG
    cp -f "$ROOT/usr/share/icons/BlackHole/scalable/apps/blackhole.svg" "$ROOT/usr/share/icons/BlackHole/scalable/apps/utilities-terminal.svg"
    cp -f "$ROOT/usr/share/icons/BlackHole/scalable/apps/blackhole.svg" "$ROOT/usr/share/icons/BlackHole/scalable/apps/preferences-system.svg"
    if [[ "$has_assets" != 1 ]]; then
        mkdir -p "$ROOT/boot/grub/themes/blackhole"
        cat > "$ROOT/boot/grub/themes/blackhole/theme.txt" <<'GRUBTEXTTHEME'
title-text: "Black Hole Linux"
title-color: "#7CFC00"
desktop-color: "#000000"
message-color: "#7CFC00"
+ boot_menu {
  left = 15%
  top = 60%
  width = 70%
  height = 30%
  item_color = "#7CFC00"
  selected_item_color = "#00FF00"
  item_bg_color = "#000000"
  selected_item_bg_color = "#003300"
  item_height = 24
  item_padding = 8
}
GRUBTEXTTHEME
    fi
    if [[ "$has_assets" = 1 ]]; then
        cp -f "$wall"   "$ROOT/usr/share/backgrounds/blackhole/wallpaper.jpg"
        cp -f "$splash" "$ROOT/usr/share/plymouth/themes/blackhole/background.png"
        # Tema GRUB también en /boot del rootfs (para el sistema instalado)
        mkdir -p "$ROOT/boot/grub/themes/blackhole"
        cp -f "$splash" "$ROOT/boot/grub/themes/blackhole/background.png"
        cat > "$ROOT/boot/grub/themes/blackhole/theme.txt" <<'GRUBTHEME'
title-text: "Black Hole Linux"
title-color: "#7CFC00"
desktop-image: "background.png"
desktop-color: "#000000"
message-color: "#7CFC00"
+ boot_menu {
  left = 15%
  top = 60%
  width = 70%
  height = 30%
  item_color = "#7CFC00"
  selected_item_color = "#00FF00"
  item_bg_color = "#000000"
  selected_item_bg_color = "#003300"
  item_height = 24
  item_padding = 8
  icon_width = 0
  icon_height = 0
}
GRUBTHEME
        log "Assets gráficos incorporados (wallpaper + Plymouth + GRUB)."
    else
        warn "No se encontraron assets en $BH_ASSETS; el tema usará colores sólidos."
    fi

    # --- Plymouth + temas (necesario para el splash de arranque) ---
    apt_install_group "Plymouth y plugins para splash Black Hole" plymouth plymouth-themes initramfs-tools

    # --- Tema Plymouth (script plugin): fondo agujero negro + barra verde ---
    cat > "$ROOT/usr/share/plymouth/themes/blackhole/blackhole.plymouth" <<'PLY'
[Plymouth Theme]
Name=Black Hole
Description=Black Hole Linux boot splash (Matrix edition)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/blackhole
ScriptFile=/usr/share/plymouth/themes/blackhole/blackhole.script
PLY

    cat > "$ROOT/usr/share/plymouth/themes/blackhole/blackhole.script" <<'SCRIPT'
// Black Hole Linux — Plymouth boot splash
// Fondo estático (agujero negro) + barra de progreso verde estilo Matrix + texto
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

bg_image = Image("background.png");
if (bg_image) {
    bg_sprite = Sprite(bg_image);
    iw = bg_image.GetWidth(); ih = bg_image.GetHeight();
    if (iw > 0 && ih > 0) {
        scale = Math.Max(screen_width / iw, screen_height / ih);
        nw = iw * scale; nh = ih * scale;
        bg_sprite.SetScale(scale);
        bg_sprite.SetX((screen_width - nw) / 2);
        bg_sprite.SetY((screen_height - nh) / 2);
    }
    bg_sprite.SetZ(0);
}

// Barra de progreso
bar_w = screen_width * 0.4;
bar_h = 6;
bar_x = (screen_width - bar_w) / 2;
bar_y = screen_height * 0.78;

progress_image = Image.Create(bar_w, bar_h);
progress_image.Fill(0.13, 0.55, 0.13, 1.0); // verde Matrix
progress_sprite = Sprite(progress_image);
progress_sprite.SetX(bar_x);
progress_sprite.SetY(bar_y);
progress_sprite.SetZ(2);

progress_bg = Image.Create(bar_w, bar_h);
progress_bg.Fill(0.0, 0.2, 0.0, 0.6);
progress_bg_sprite = Sprite(progress_bg);
progress_bg_sprite.SetX(bar_x);
progress_bg_sprite.SetY(bar_y);
progress_bg_sprite.SetZ(1);

// Texto del título (Image.Text: texto, r, g, b — sin alpha)
title = Image.Text("BLACK HOLE LINUX", 0.5, 1.0, 0.5);
title_sprite = Sprite(title);
title_sprite.SetX((screen_width - title.GetWidth()) / 2);
title_sprite.SetY(screen_height * 0.70);
title_sprite.SetZ(3);

status_sprite = 0;

fun progress_callback (duration, progress) {
    w = bar_w * progress;
    if (w < 1) w = 1;
    progress_sprite.SetScaleX(w / bar_w);
}
Plymouth.SetProgressFunction(progress_callback);

fun message_callback (text) {
    if (status_sprite) status_sprite.Remove();
    msg = Image.Text(text, 0.6, 1.0, 0.6);
    status_sprite = Sprite(msg);
    status_sprite.SetX((screen_width - msg.GetWidth()) / 2);
    status_sprite.SetY(bar_y + 20);
    status_sprite.SetZ(3);
}
Plymouth.SetMessageFunction(message_callback);
SCRIPT

    # --- GTK dark theme + iconos + cursor ---
    apt_install_group "tema oscuro e iconos (Black Hole)" \
        arc-theme papirus-icon-theme dmz-cursor-theme conky cmatrix neofetch

    mkdir -p "$ROOT/etc/gtk-3.0" "$ROOT/etc/skel/.config/gtk-3.0" "$ROOT/etc/skel/.config"
    cat > "$ROOT/etc/gtk-3.0/settings.ini" <<'GTK'
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=BlackHole
gtk-cursor-theme-name=DMZ-Black
gtk-application-prefer-dark-theme=1
gtk-font-name=Sans 10
GTK
    cp -f "$ROOT/etc/gtk-3.0/settings.ini" "$ROOT/etc/skel/.config/gtk-3.0/settings.ini"

    # --- Conky estilo Matrix (verde sobre negro, sistema en tiempo real) ---
    mkdir -p "$ROOT/usr/share/blackhole"
    cat > "$ROOT/usr/share/blackhole/conky.conf" <<'CONKY'
conky.config = {
    background = true,
    use_xft = true,
    font = 'DejaVu Sans Mono:size=9',
    xftalpha = 0.9,
    update_interval = 2.0,
    total_run_times = 0,
    own_window = true,
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    double_buffer = true,
    minimum_width = 220,
    draw_shades = false,
    draw_outline = false,
    draw_borders = false,
    alignment = 'top_right',
    gap_x = 12,
    gap_y = 30,
    default_color = 'green',
    color1 = 'green',
    color2 = 'lightgreen',
    uppercase = false,
};
conky.text = [[
${color lightgreen}BLACK HOLE LINUX ${hr 2}${color green}
$sysname $kernel on $machine
Uptime: $uptime
CPU:  ${cpu cpu0}%  ${cpubar 4,120}
${cpugraph 20,120 green black}
RAM:  $mem / $memmax ($memperc%)
${membar 4,120}
Swap: $swap / $swapmax
${swapbar 4,120}
Root: $fs_used / $fs_size (${fs_used_perc}%)
${fs_bar 4,120 /}
Net: ↓ ${downspeed eth0}  ↑ ${upspeed eth0}
${downspeedgraph eth0 16,120 green black}
Temp: ${acpitemp}°C  Bat: ${battery_percent}%
Procs: $processes  Load: $loadavg
]];
CONKY
    # Autostart de conky
    mkdir -p "$ROOT/etc/xdg/autostart"
    cat > "$ROOT/etc/xdg/autostart/blackhole-conky.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Black Hole Conky
Exec=conky -c /usr/share/blackhole/conky.conf
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESK

    # --- LightDM greeter (fondo negro + wallpaper + tema oscuro) ---
    if [[ -d "$ROOT/etc/lightdm" ]]; then
        mkdir -p "$ROOT/etc/lightdm/lightdm.conf.d"
        local greeter_background="#000000"
        [[ "$has_assets" = 1 ]] && greeter_background="/usr/share/backgrounds/blackhole/wallpaper.jpg"
        cat > "$ROOT/etc/lightdm/lightdm-gtk-greeter.conf" <<LDM
[greeter]
background=$greeter_background
theme-name=Arc-Dark
icon-theme-name=BlackHole
font-name=Sans 10
xft-antialias=true
xft-hintstyle=hintslight
xft-rgba=rgb
indicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power
clock-format=%H:%M
position=50%,center 50%,center
default-user-image=#computer
LDM
        cat > "$ROOT/etc/lightdm/lightdm.conf.d/90-blackhole.conf" <<'LDM2'
[Seat:*]
greeter-hide-users=false
greeter-show-manual-login=false
allow-guest=false
LDM2
    fi

    # --- Prompt bash estilo Matrix (verde) ---
    cat > "$ROOT/etc/profile.d/blackhole-prompt.sh" <<'PROMPT'
# Black Hole Linux — prompt verde estilo Matrix
if [ -n "$BASH_VERSION" ] && [ "$TERM" != "linux" ]; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
PROMPT

    # --- MOTD con arte ASCII de agujero negro ---
    mkdir -p "$ROOT/etc/update-motd.d"
    cat > "$ROOT/etc/motd" <<'MOTD'

   ██████╗ ██╗      █████╗  ██████╗██╗  ██╗    ██╗  ██╗ ██████╗ ██╗     ███████╗
   ██╔══██╗██║     ██╔══██╗██╔════╝██║ ██╔╝    ██║  ██║██╔═══██╗██║     ██╔════╝
   ██████╔╝██║     ███████║██║     █████╔╝     ███████║██║   ██║██║     █████╗
   ██╔══██╗██║     ██╔══██║██║     ██╔═██╗     ██╔══██║██║   ██║██║     ██╔══╝
   ██████╔╝███████╗██║  ██║╚██████╗██║  ██╗    ██║  ██║╚██████╔╝███████╗███████╗
   ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝    ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚══════╝
                        >> EVENT HORIZON SYSTEMS ONLINE <<
MOTD

    # --- Neofetch config con logo personalizado ---
    mkdir -p "$ROOT/etc/skel/.config/neofetch"
    cat > "$ROOT/etc/skel/.config/neofetch/config.conf" <<'NEOF'
print_info() {
    info title
    info underline
    info "OS" distro
    info "Kernel" kernel
    info "Uptime" uptime
    info "Packages" packages
    info "Shell" shell
    info "Resolution" resolution
    info "DE" de
    info "WM" wm
    info "CPU" cpu
    info "GPU" gpu
    info "Memory" memory
    info "Battery" battery
}
color_blocks="off"
block_width=3
block_height=1
NEOF

    # --- Script de primer arranque gráfico (wallpaper en Moksha) ---
    cat > "$ROOT/usr/local/sbin/bh-firstrun-gui" <<'FIRSTGUI'
#!/usr/bin/env bash
# Se ejecuta una vez en la sesión gráfica: aplica wallpaper/tema en Moksha
set -u
FLAG="$HOME/.config/blackhole-firstrun.done"
[[ -f "$FLAG" ]] && exit 0
WALL=/usr/share/backgrounds/blackhole/wallpaper.jpg
[[ -f "$WALL" ]] || { touch "$FLAG"; exit 0; }
# Moksha/E17: establecer fondo mediante enlightenment_remote si está disponible
if command -v enlightenment_remote >/dev/null 2>&1; then
    enlightenment_remote -desktop-bg-add 0 0 0 "$WALL" >/dev/null 2>&1 || true
fi
# GTK ya está en /etc/gtk-3.0/settings.ini
touch "$FLAG"
FIRSTGUI
    chmod 755 "$ROOT/usr/local/sbin/bh-firstrun-gui"
    cat > "$ROOT/etc/xdg/autostart/blackhole-firstrun.desktop" <<'DESK2'
[Desktop Entry]
Type=Application
Name=Black Hole First Run
Exec=/usr/local/sbin/bh-firstrun-gui
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESK2

    log "Tema Black Hole / Matrix escrito en el rootfs."
}

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
    echo '\n=== ELF header ==='
    readelf -h "$1"
    echo '\n=== Dependencias dinámicas ==='
    readelf -d "$1" 2>/dev/null | grep -E 'NEEDED|RPATH|RUNPATH' || true
    echo '\n=== Símbolos (muestra) ==='
    nm -D "$1" 2>/dev/null | head -n 40 || true
    echo '\n=== Desensamblado (primeras instrucciones) ==='
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

configure_services() {
    if ! have systemctl; then
        warn "El host constructor no tiene systemctl; habilita servicios desde el Bodhi instalado."
        return 0
    fi
    step "Habilitando/deshabilitando servicios (mínimo background)"
    # Servicios a habilitar
    local enable=()
    [[ "$BH_DO_ZRAM" = 1 ]] && enable+=(zramswap.service)
    [[ "$BH_DO_EARLYOOM" = 1 ]] && enable+=(earlyoom.service)
    [[ "$BH_DO_TLP" = 1 ]] && enable+=(tlp.service)
    enable+=(blackhole-firstboot.service)
    local s
    for s in "${enable[@]}"; do
        systemctl --root="$ROOT" enable "$s" >>"$LOG" 2>&1 \
            || warn "No se pudo habilitar $s (compruébalo tras instalar)."
    done

    # Servicios a deshabilitar (bloat / telemetría / background)
    local disable=(whoopsie.service apport.service kerneloops.service \
        ModemManager.service bluetooth.service cups.service avahi-daemon.service \
        saned.service packagekit.service fwupd.service)
    for s in "${disable[@]}"; do
        systemctl --root="$ROOT" disable "$s" >>"$LOG" 2>&1 || true
    done
    # Timers de apt automáticos (evitar actualizaciones en segundo plano en 2 GiB)
    local timers=(apt-daily.timer apt-daily-upgrade.timer motd-news.timer \
        fwupd-refresh.timer e2scrub_all.timer)
    for t in "${timers[@]}"; do
        systemctl --root="$ROOT" disable "$t" >>"$LOG" 2>&1 || true
    done
    log "Servicios ajustados."
}

# ----------------------------------- BUILD ------------------------------------
extract_rootfs() {
    step "Extrayendo filesystem.squashfs de Bodhi"
    xorriso -osirrox on -indev "$BH_BASE_ISO" \
        -extract /casper/filesystem.squashfs "$BH_WORK/base-filesystem.squashfs" >>"$LOG" 2>&1
    [[ -s "$BH_WORK/base-filesystem.squashfs" ]] || die "No se extrajo el squashfs."
    unsquashfs -processors "$BH_MKFS_PROCS" -no-progress -d "$ROOT" "$BH_WORK/base-filesystem.squashfs" >>"$LOG" 2>&1
    [[ -x "$ROOT/usr/bin/apt-get" && -x "$ROOT/usr/bin/dpkg-query" ]] \
        || die "El rootfs extraído no parece Bodhi/Ubuntu (falta apt-get/dpkg-query)."
    local target_arch
    target_arch="$(chroot "$ROOT" /usr/bin/dpkg --print-architecture)"
    [[ "$target_arch" = amd64 ]] || die "La ISO base no es amd64 (encontrado: $target_arch)."
    xorriso -osirrox on -indev "$BH_BASE_ISO" \
        -extract /casper/filesystem.manifest "$BH_WORK/base-filesystem.manifest" >>"$LOG" 2>&1 \
        || warn "Sin filesystem.manifest; usaré lista derivada."
    xorriso -osirrox on -indev "$BH_BASE_ISO" \
        -extract /casper/filesystem.manifest-desktop "$BH_WORK/base-filesystem.manifest-desktop" >>"$LOG" 2>&1 \
        || warn "Sin filesystem.manifest-desktop; usaré lista derivada."
    log "Rootfs Bodhi amd64 extraído."
}

extract_boot_tree() {
    # Extraer árbol de arranque para personalizar menú ISOLINUX/GRUB
    step "Extrayendo árbol de arranque (ISOLINUX/GRUB) para personalizar"
    mkdir -p "$BH_WORK/boot-tree"
    for d in isolinux boot EFI syslinux; do
        xorriso -osirrox on -indev "$BH_BASE_ISO" -extract "/$d" "$BH_WORK/boot-tree/$d" >>"$LOG" 2>&1 || true
    done
    # Reemplazar títulos en los menús (solo texto visible; no tocar rutas)
    find "$BH_WORK/boot-tree" -type f \( -name '*.cfg' -o -name '*.txt' -o -name '*.conf' \) -print0 2>/dev/null \
        | while IFS= read -r -d '' f; do
            sed -i -e 's/Bodhi Linux/Black Hole Linux/g' \
                   -e 's/Bodhi/Black Hole/g' \
                   -e 's/hostname=bodhi/hostname=blackhole/g' \
                   -e 's/hostname=Bodhi/hostname=Black Hole/g' "$f" 2>/dev/null || true
            # Añadir 'splash' a las líneas de kernel cmdline para Plymouth
            sed -i -E '/^[[:space:]]*(append|linux)[[:space:]]/ { /splash/! s/$/ splash/ }' "$f" 2>/dev/null || true
        done
    # Splash para ISOLINUX (vesamenu): detectar el nombre real en MENU BACKGROUND
    local splash="$BH_ASSETS/blackhole-splash.png"
    local wall="$BH_ASSETS/blackhole-wallpaper.jpg"
    if [[ -f "$splash" && -d "$BH_WORK/boot-tree/isolinux" ]]; then
        local bgfile
        bgfile="$(grep -hE 'MENU BACKGROUND' "$BH_WORK/boot-tree/isolinux/"*.cfg 2>/dev/null \
            | head -n1 | awk '{print $NF}' | xargs -n1 basename 2>/dev/null || true)"
        if [[ "$bgfile" == *.png ]]; then
            cp -f "$splash" "$BH_WORK/boot-tree/isolinux/$bgfile"
            log "Splash PNG ISOLINUX sustituido: $bgfile"
        elif [[ "$bgfile" == *.jpg || "$bgfile" == *.jpeg ]]; then
            if [[ -f "$wall" ]]; then
                cp -f "$wall" "$BH_WORK/boot-tree/isolinux/$bgfile"
                log "Fondo JPEG ISOLINUX sustituido: $bgfile"
            else
                warn "El menú espera JPEG pero solo existe blackhole-splash.png; se conserva el fondo original."
            fi
        fi
        # Fallbacks comunes
        cp -f "$splash" "$BH_WORK/boot-tree/isolinux/splash.png" 2>/dev/null || true
        # GRUB background (arranque UEFI; el E6400 usa BIOS, pero se incluye)
        mkdir -p "$BH_WORK/boot-tree/boot/grub/themes/blackhole"
        cp -f "$splash" "$BH_WORK/boot-tree/boot/grub/themes/blackhole/background.png"
        cat > "$BH_WORK/boot-tree/boot/grub/themes/blackhole/theme.txt" <<'GRUBTHEME'
title-text: "Black Hole Linux"
title-color: "#7CFC00"
desktop-image: "background.png"
desktop-color: "#000000"
message-color: "#7CFC00"
+ boot_menu {
  left = 15%
  top = 60%
  width = 70%
  height = 30%
  item_color = "#7CFC00"
  selected_item_color = "#00FF00"
  item_bg_color = "#000000"
  selected_item_bg_color = "#003300"
  item_height = 24
  item_padding = 8
  icon_width = 0
  icon_height = 0
}
GRUBTHEME
        # Activar el tema en grub.cfg del ISO si existe
        if [[ -f "$BH_WORK/boot-tree/boot/grub/grub.cfg" ]]; then
            sed -i '1i set theme=/boot/grub/themes/blackhole/theme.txt' "$BH_WORK/boot-tree/boot/grub/grub.cfg"
        fi
    fi
    log "Árbol de arranque personalizado (menú Black Hole)."
}

install_software() {
    step "Preparando apt/dpkg de Bodhi"
    mount_target
    # Reparar cualquier estado a medias y habilitar componentes universe/multiverse
    chroot_run dpkg --configure -a || true
    chroot_run apt-get -f install -y || true
    # Asegurar universe/multiverse (RetroArch, firmware, codecs)
    if [[ -f "$ROOT/etc/apt/sources.list" ]]; then
        sed -i -E 's/^(deb .* (main|restricted))( universe)?( multiverse)?$/\1 universe multiverse/' "$ROOT/etc/apt/sources.list" 2>/dev/null || true
    fi
    chroot_run apt-get update || die "apt-get update falló; revisa red/repositorios en $LOG"

    # Base ligera + diagnóstico + gráficos Intel + codecs textura S3TC
    local base=(ca-certificates locales htop lm-sensors pciutils usbutils rfkill iproute2 \
                alsa-utils evtest joystick binutils file build-essential cmake pkg-config \
                intel-microcode xserver-xorg-video-intel libgl1-mesa-dri mesa-utils \
                libva2 i965-va-driver vainfo fonts-liberation libtxc-dxtn-s2tc0 gamemode libgamemodeauto0)
    apt_install_group "base ligera, red, gráficos Intel y gamemode" "${base[@]}"

    [[ "$BH_DO_ZRAM" = 1 ]] && apt_install_group "zram (60% LZ4)" zram-tools
    [[ "$BH_DO_EARLYOOM" = 1 ]] && apt_install_group "earlyoom (protección OOM)" earlyoom
    [[ "$BH_DO_TLP" = 1 ]] && apt_install_group "TLP (energía/batería)" tlp
    [[ "$BH_DO_BROWSER" = 1 ]] && apt_install_group "navegador ligero (Epiphany, deb sin snap)" epiphany-browser

    if [[ "$BH_DO_FIREFOX" = 1 ]]; then
        step "Firefox ESR (deb, PPA mozillateam)"
        apt_install_group "software-properties-common (para PPA)" software-properties-common
        chroot_run add-apt-repository -y ppa:mozillateam/ppa \
            || warn "No se pudo añadir PPA mozillateam; Firefox ESR omitido."
        if chroot_run apt-get update; then
            # Pin para que el deb de PPA tenga prioridad sobre el paquete snap transicional
            printf 'Package: *\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n' \
                > "$ROOT/etc/apt/preferences.d/mozillateam" 2>/dev/null || true
            apt_install_group "Firefox ESR (deb)" firefox-esr
        fi
    fi

    if [[ "$BH_DO_OFFICE" = 1 ]]; then
        apt_install_group "herramientas de estudio ligeras" abiword gnumeric mousepad evince
    fi

    if [[ "$BH_DO_GAMES" = 1 ]]; then
        apt_install_group "emulación retro (RetroArch + núcleos)" \
            retroarch retroarch-assets libretro-core-info \
            libretro-gambatte libretro-mgba libretro-snes9x libretro-nestopia \
            libretro-stella libretro-picodrive dosbox scummvm fceux
    fi

    if [[ "$BH_DO_B43" = 1 ]]; then
        apt_install_group "firmware Broadcom b43 (opcional)" \
            b43-fwcutter firmware-b43-installer firmware-b43legacy-installer
    fi
    if [[ "$BH_DO_ANTIMICRO" = 1 ]]; then
        apt_install_group "mapeador de gamepad AntiMicro" antimicro
    fi
    if [[ "$BH_DO_WINE" = 1 ]]; then
        step "Wine multiarch (opcional; pesado para 2 GiB)"
        chroot_run dpkg --add-architecture i386
        chroot_run apt-get update
        apt_install_group "Wine 64/32 bits" wine64 wine32:i386
    fi
    if [[ "$BH_DO_DEVTOOLS" = 1 ]]; then
        apt_install_group "herramientas CLI de diagnóstico y desarrollo" gdb strace ltrace
    fi

    if [[ -n "$BH_EXTRA_PACKAGES" ]]; then
        local -a extra=()
        IFS=' ' read -r -a extra <<< "$BH_EXTRA_PACKAGES"
        local p
        for p in "${extra[@]}"; do
            [[ "$p" =~ ^[a-zA-Z0-9][a-zA-Z0-9+.-]*$ ]] || die "Nombre de paquete no válido: $p"
        done
        apt_install_group "paquetes adicionales solicitados" "${extra[@]}"
    fi

    # Tema Black Hole / Matrix (Plymouth, GTK, iconos, conky, cmatrix, neofetch)
    write_blackhole_theme
    # Establecer tema Plymouth por defecto y reconstruir initramfs
    if [[ "$BH_DO_THEME" = 1 && -x "$ROOT/usr/sbin/plymouth-set-default-theme" ]]; then
        chroot_run plymouth-set-default-theme -R blackhole \
            || warn "No se pudo establecer el tema Plymouth; se usará el de Bodhi."
    fi

    # Purga de bloat / telemetría
    apt_purge_group "telemetría y bloat" \
        whoopsie apport apport-symptoms ubuntu-report popularity-contest \
        modemmanager cups cups-bsd avahi-daemon saned

    write_target_config
    configure_services

    # Limpieza final del rootfs
    chroot_run apt-get clean || true
    chroot_run apt-get autoremove -y || true
    rm -rf "$ROOT/var/lib/apt/lists/"* "$ROOT/var/cache/apt/archives/"*.deb \
           "$ROOT/var/tmp/"* "$ROOT/tmp/"* 2>/dev/null || true
    [[ -e "$ROOT/etc/machine-id" ]] && : > "$ROOT/etc/machine-id"
    rm -f "$ROOT/etc/ssh/ssh_host_"*_key "$ROOT/etc/ssh/ssh_host_"*_key.pub 2>/dev/null || true
    # Regenerar locale es_DO
    if [[ -x "$ROOT/usr/sbin/locale-gen" ]]; then
        chroot_run locale-gen es_DO.UTF-8 || warn "No se generó es_DO.UTF-8; cámbialo en Configuración de idioma."
    fi

    cleanup_mounts
    log "Paquetes, tema y ajustes aplicados."
}

make_manifests() {
    step "Actualizando manifiestos del instalador"
    chroot "$ROOT" /usr/bin/dpkg-query -W -f='${Package} ${Version}\n' \
        | LC_ALL=C sort > "$BH_WORK/filesystem.manifest"
    if [[ -s "$BH_WORK/base-filesystem.manifest" && -s "$BH_WORK/base-filesystem.manifest-desktop" ]]; then
        awk '
            FILENAME == ARGV[1] { base[$1]=1; next }
            FILENAME == ARGV[2] { desktop[$1]=1; next }
            { if (!($1 in base) || ($1 in desktop)) print }
        ' "$BH_WORK/base-filesystem.manifest" \
          "$BH_WORK/base-filesystem.manifest-desktop" \
          "$BH_WORK/filesystem.manifest" > "$BH_WORK/filesystem.manifest-desktop"
    else
        warn "Sin manifiestos originales; manifest-desktop = manifiesto completo."
        cp -f "$BH_WORK/filesystem.manifest" "$BH_WORK/filesystem.manifest-desktop"
    fi
    du -sx --block-size=1 "$ROOT" | awk '{print $1}' > "$BH_WORK/filesystem.size"
    [[ -s "$BH_WORK/filesystem.manifest" && -s "$BH_WORK/filesystem.manifest-desktop" && -s "$BH_WORK/filesystem.size" ]] \
        || die "No se generaron los manifiestos/filesystem.size"
}

make_squashfs() {
    step "Creando squashfs (compresión: $BH_SQUASH_COMP, procs: $BH_MKFS_PROCS)"
    local comp_args=()
    case "$BH_SQUASH_COMP" in
        zstd) comp_args=(-comp zstd -b 1M -Xcompression-level "$BH_ZSTD_LEVEL") ;;
        xz)   comp_args=(-comp xz -b 256K -Xdict-size 256K) ;;
        gzip) comp_args=(-comp gzip -b 256K) ;;
    esac
    mksquashfs "$ROOT" "$BH_WORK/filesystem.squashfs" \
        "${comp_args[@]}" -processors "$BH_MKFS_PROCS" -noappend -no-progress \
        >>"$LOG" 2>&1
    [[ -s "$BH_WORK/filesystem.squashfs" ]] || die "No se creó filesystem.squashfs"
    unsquashfs -test -processors 1 "$BH_WORK/filesystem.squashfs" >>"$LOG" 2>&1 \
        || die "Prueba de integridad del SquashFS falló."
    log "SquashFS íntegro: $(du -h "$BH_WORK/filesystem.squashfs" | awk '{print $1}')"
}

write_iso_readme() {
    cat > "$BH_WORK/README-BLACKHOLE.txt" <<README
${BH_NAME} v${BH_VERSION} — ${BH_PROFILE} (Matrix edition)
Base: Bodhi Linux 7.0.0 amd64 / Ubuntu 22.04 / Moksha
Target: Dell Latitude E6400 · Core 2 Duo P8400 · GMA 4500MHD · 2 GiB DDR2
Conserva kernel, initrd y registros de arranque de Bodhi. Incluye: zram LZ4,
earlyoom, gamemode, RetroArch, herramientas de estudio/desarrollo ligeras,
navegador opcional, tema Black Hole/Matrix (Plymouth, Conky, GTK Arc-Dark,
iconos BlackHole, cmatrix). ACPI y mitigaciones del kernel sin cambios forzados.
Comandos: blackhole help | bh-doctor | bh-perf game | bh-gpu | bh-retro
Tras instalar al disco: sudo blackhole firstboot && sudo blackhole upgrade
No para juegos 3D modernos (GMA 4500MHD sin Vulkan).
README
}

repack_iso() {
    step "Reconstruyendo ISO (conservando registros de arranque originales)"
    [[ "$BH_FORCE" = 1 || ! -e "$BH_OUTPUT" ]] || die "La salida ya existe: $BH_OUTPUT (usa --force)."
    mkdir -p "$(dirname "$BH_OUTPUT")"
    ISO_TMP="${BH_OUTPUT}.partial.$$"
    [[ ! -e "$ISO_TMP" ]] || die "Ya existe el temporal de salida: $ISO_TMP"
    write_iso_readme

    # Construir lista de -map: squashfs + manifiestos + readme + árbol de arranque modificado
    local maps=(
        -map "$BH_WORK/filesystem.squashfs" /casper/filesystem.squashfs
        -map "$BH_WORK/filesystem.manifest" /casper/filesystem.manifest
        -map "$BH_WORK/filesystem.manifest-desktop" /casper/filesystem.manifest-desktop
        -map "$BH_WORK/filesystem.size" /casper/filesystem.size
        -map "$BH_WORK/README-BLACKHOLE.txt" /README-BLACKHOLE.txt
    )
    # Mapear árbol de arranque modificado (isolinux, boot, EFI, syslinux)
    local d
    for d in isolinux boot EFI syslinux; do
        if [[ -d "$BH_WORK/boot-tree/$d" && -n "$(ls -A "$BH_WORK/boot-tree/$d" 2>/dev/null)" ]]; then
            maps+=(-map "$BH_WORK/boot-tree/$d" "/$d")
        fi
    done
    # Se conserva intacta la pareja vmlinuz/initrd de la ISO original.
    # El initramfs del sistema instalado se actualiza desde blackhole-firstboot.

    xorriso -indev "$BH_BASE_ISO" -outdev "$ISO_TMP" -overwrite on \
        "${maps[@]}" \
        -boot_image any replay -compliance no_emul_toc -padding included -commit \
        >>"$LOG" 2>&1 || die "xorriso no pudo reconstruir la ISO; revisa $LOG"

    [[ -s "$ISO_TMP" ]] || die "La ISO temporal no existe o está vacía."
    local final_boot_info
    final_boot_info="$(xorriso -indev "$ISO_TMP" -report_el_torito plain 2>>"$LOG")" \
        || die "ISO creada pero no se verificaron los registros de arranque."
    grep -qi 'BIOS' <<< "$final_boot_info" \
        || die "La ISO final no conserva arranque Legacy BIOS. No la uses en el E6400."
    xorriso -osirrox on -indev "$ISO_TMP" \
        -extract /casper/filesystem.squashfs "$BH_WORK/verify-filesystem.squashfs" >>"$LOG" 2>&1
    cmp -s "$BH_WORK/filesystem.squashfs" "$BH_WORK/verify-filesystem.squashfs" \
        || die "La ISO final no contiene el SquashFS construido."
    rm -f "$BH_WORK/verify-filesystem.squashfs"
    mv -f -- "$ISO_TMP" "$BH_OUTPUT"
    ISO_TMP=""
    (cd "$(dirname "$BH_OUTPUT")" && sha256sum "$(basename "$BH_OUTPUT")" > "$(basename "$BH_OUTPUT").sha256")
    log "ISO creada: $BH_OUTPUT ($(du -h "$BH_OUTPUT" | awk '{print $1}'))"
    log "SHA256: ${BH_OUTPUT}.sha256"
}

finish() {
    printf '\n'
    log "BLACK HOLE LINUX v${BH_VERSION} (Matrix edition) terminado."
    printf '  Base Bodhi: %s\n' "$BH_BASE_ISO"
    printf '  ISO final:  %s\n' "$BH_OUTPUT"
    printf '  SHA256:     %s.sha256\n' "$BH_OUTPUT"
    printf '  Registro:   %s\n' "$LOG"
    printf '\nPrueba primero la ISO en modo Live. No instales sin copia de seguridad.\n'
    printf 'Tras instalar al disco: sudo blackhole firstboot && sudo blackhole upgrade\n'
    printf 'En el E6400 conserva ACPI y las mitigaciones del kernel por defecto.\n'
}

main() {
    parse_args "$@"
    safe_paths
    check_host || die "El constructor no cumple los requisitos."
    validate_base_iso
    check_space
    if [[ "$BH_DRY_RUN" = 1 ]]; then
        log "Dry-run correcto. No se extrajo ni modificó nada."
        printf 'ISO base: %s\nSalida: %s\nTrabajo: %s\nAssets: %s\n' "$BH_BASE_ISO" "$BH_OUTPUT" "$BH_WORK" "$BH_ASSETS"
        exit 0
    fi
    prepare_workspace
    info "Perfil: ${BH_PROFILE} · ${BH_ARCH} · compresión=${BH_SQUASH_COMP} · zram=${BH_DO_ZRAM} · earlyoom=${BH_DO_EARLYOOM} · juegos=${BH_DO_GAMES} · tema=${BH_DO_THEME}"
    extract_rootfs
    extract_boot_tree
    install_software
    # No reemplazamos el initrd Live: debe coincidir exactamente con el kernel original.
    make_manifests
    make_squashfs
    repack_iso
    finish
}

main "$@"
