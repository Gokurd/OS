#!/usr/bin/env bash
# Modulo: pasos de construccion (servicios, extraccion, instalacion, squashfs, repack)
# Parte de Black Hole Linux v8.0 ULTIMATE-E6400. Lo sourcea blackhole-linux.sh

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
    # Sesion Openbox BlackHole-Aero (tint2 + jgmenu + picom + fondo generado)
    if declare -F write_matrix_look >/dev/null 2>&1; then
        write_matrix_look
    else
        warn "matrix-look.sh no encontrado junto al script; omito la sesion BlackHole-Aero."
    fi
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
    unsquashfs -s "$BH_WORK/filesystem.squashfs" >>"$LOG" 2>&1 \
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

