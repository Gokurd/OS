#!/usr/bin/env bash
# ==============================================================================
# BLACK HOLE LINUX v8.0 ULTIMATE-E6400 — Bodhi Linux remaster (Matrix edition)
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
BH_DO_MATRIXLOOK="${BH_DO_MATRIXLOOK:-1}"  # Sesion Openbox BlackHole-Aero (tint2+jgmenu+picom)
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

# Modulo opcional: look BlackHole-Aero + generacion automatica de assets.
# Debe vivir junto a este script (remaster/matrix-look.sh).
BH_MATRIX_LOOK="$SCRIPT_DIR/matrix-look.sh"
[[ -f "$BH_MATRIX_LOOK" ]] && source "$BH_MATRIX_LOOK"

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
  --no-matrixlook         Sin sesión Openbox BlackHole-Aero (tint2/jgmenu/picom)
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
            --no-matrixlook)  BH_DO_MATRIXLOOK=0; shift ;;
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


# Modulos Black Hole (funciones)
source "$SCRIPT_DIR/bh-theme.sh"
source "$SCRIPT_DIR/bh-system.sh"
source "$SCRIPT_DIR/bh-build-steps.sh"
source "$SCRIPT_DIR/matrix-look.sh"
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
    info "Perfil: ${BH_PROFILE} · ${BH_ARCH} · compresión=${BH_SQUASH_COMP} · zram=${BH_DO_ZRAM} · earlyoom=${BH_DO_EARLYOOM} · juegos=${BH_DO_GAMES} · tema=${BH_DO_THEME} · matrixlook=${BH_DO_MATRIXLOOK}"
    if declare -F generate_blackhole_assets >/dev/null 2>&1; then
        generate_blackhole_assets
    fi
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
