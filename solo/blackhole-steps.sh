#!/usr/bin/env bash
# Modulo: FASES 1-6 Black Hole + pasos de construccion (instalacion, manifiestos,
# squashfs, repack de la ISO). Lo sourcea solo/blackhole-linux.sh.

# ================= FASES 1-6 BLACK HOLE (estilo del autor) ====================
# FASE 1: auditoría de hardware   ->  /usr/local/bin/bh-audit
# FASE 2: autologin LightDM live  ->  lightdm.conf.d/70-blackhole-autologin.conf
# FASE 3: sesión Openbox Aero     ->  /usr/share/xsessions/openbox-blackhole.desktop
# FASE 4: bandeja (sonido/red)    ->  /etc/xdg/autostart/bh-tray.desktop
# FASE 5: pre-vuelo E6400         ->  /usr/local/bin/verificar-e6400
# FASE 6: docs + CI (readme de la ISO y workflows de GitHub; ya en el repo)

write_fase1_audit() {
    step "FASE 1: auditoría de hardware (bh-audit)"
    cat > "$ROOT/usr/local/bin/bh-audit" <<'BH_AUDIT'
#!/usr/bin/env bash
# bh-audit — Auditoría de hardware del Dell Latitude E6400 (FASE 1)
# Genera ~/e6400-audit.txt con todo lo necesario para diagnosticar la instalación.
set -u
OUT="$HOME/e6400-audit.txt"
{
printf '=== BLACK HOLE LINUX · FASE 1: AUDITORÍA E6400 ===\n'
printf 'Fecha: %s\n\n' "$(date)"
printf -- '--- uname ---\n'; uname -a; printf '\n'
printf -- '--- cmdline del kernel ---\n'; cat /proc/cmdline 2>/dev/null; printf '\n'
printf -- '--- CPU ---\n'; lscpu 2>/dev/null | grep -E 'Architecture|Model name|^CPU\(s\)'; printf '\n'
printf -- '--- vídeo (lspci) ---\n'; lspci -nn 2>/dev/null | grep -Ei 'vga|3d|display'; printf '\n'
printf -- '--- red (lspci) ---\n'; lspci -nn 2>/dev/null | grep -Ei 'network|ethernet'; printf '\n'
printf -- '--- audio (lspci) ---\n'; lspci -nn 2>/dev/null | grep -i audio; printf '\n'
printf -- '--- módulos gráficos ---\n'; lsmod | grep -E 'i915|drm' || echo 'sin i915/drm'; printf '\n'
printf -- '--- módulos wifi ---\n'; lsmod | grep -E 'iwl|b43|wl|wlan' || echo 'sin módulos wifi'; printf '\n'
printf -- '--- errores recientes (dmesg) ---\n'
dmesg 2>/dev/null | grep -iE 'error|fail' | tail -n 20 || true; printf '\n'
printf -- '--- RAM ---\n'; free -m; printf '\n'
printf -- '--- swap / zram ---\n'; swapon --show 2>/dev/null; zramctl 2>/dev/null || true; printf '\n'
printf -- '--- cmdline de GRUB ---\n'
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub 2>/dev/null || true; printf '\n'
} > "$OUT" 2>&1
printf 'Informe de auditoría guardado en %s\n' "$OUT"
BH_AUDIT
    chmod 755 "$ROOT/usr/local/bin/bh-audit"
    log "FASE 1 lista: bh-audit (informe en ~/e6400-audit.txt)."
}

write_fase2_session() {
    step "FASE 2: autologin LightDM de la sesión live"
    if [[ ! -d "$ROOT/etc/lightdm" ]]; then
        warn "FASE 2 omitida: este rootfs no usa LightDM."
        return 0
    fi
    local user
    user="$(grep -E '^USERNAME=' "$ROOT/etc/casper.conf" 2>/dev/null | cut -d= -f2 | tr -d '"' || true)"
    user="${user:-ubuntu}"
    if ! chroot "$ROOT" getent passwd "$user" >/dev/null 2>&1; then
        warn "FASE 2: el usuario live '$user' no existe aún; el autologin se aplicará igualmente."
    fi
    cat > "$ROOT/etc/lightdm/lightdm.conf.d/70-blackhole-autologin.conf" <<LDMFASE2
[Seat:*]
autologin-user=$user
autologin-user-timeout=0
autologin-session=moksha
autologin-guest=false
LDMFASE2
    log "FASE 2 lista: autologin LightDM para '$user' (sesión moksha)."
}

write_fase3_openbox() {
    step "FASE 3: sesión Openbox BlackHole-Aero"
    if [[ ! -x "$ROOT/usr/bin/openbox" ]]; then
        warn "FASE 3: openbox no está instalado; la sesión quedará incompleta."
    fi
    mkdir -p "$ROOT/usr/share/xsessions" \
             "$ROOT/etc/skel/.config/openbox" \
             "$ROOT/etc/skel/.config/tint2" \
             "$ROOT/etc/skel/.config/jgmenu"

    # Lanzador de la sesión (levanta openbox con autostart del usuario)
    cat > "$ROOT/usr/local/bin/bh-openbox-session" <<'OBXSESS'
#!/bin/sh
# FASE 3 — arranque de la sesión Openbox BlackHole-Aero
if [ ! -r "$HOME/.config/openbox/autostart" ]; then
    cp -rf /etc/skel/.config/openbox "$HOME/.config/" 2>/dev/null || true
fi
exec openbox-session
OBXSESS
    chmod 755 "$ROOT/usr/local/bin/bh-openbox-session"
    cat > "$ROOT/usr/share/xsessions/openbox-blackhole.desktop" <<'XSFASE3'
[Desktop Entry]
Type=Application
Name=Openbox BlackHole-Aero
Comment=Sesión Openbox estilo Black Hole Matrix (verde #2cff7a sobre negro)
Exec=bh-openbox-session
XSFASE3

    # Autostart de Openbox: tint2 + picom (xrender) + wallpaper + orbe de menú
    cat > "$ROOT/etc/skel/.config/openbox/autostart" <<'OBAUTO'
# FASE 3 — BlackHole-Aero: orbital mínimo para 2 GiB
(sleep 2 && tint2 -c "$HOME/.config/tint2/blackhole-tint2rc" >/dev/null 2>&1) &
picom --backend xrender -b 2>/dev/null \
    || picom -b 2>/dev/null \
    || compton -b 2>/dev/null || true
feh --bg-scale /usr/share/backgrounds/blackhole/wallpaper.jpg 2>/dev/null \
    || xsetroot -solid black || true
OBAUTO

    # Tint2: barra fina con orbe lanzador de jgmenu
    cat > "$ROOT/etc/skel/.config/tint2/blackhole-tint2rc" <<'TINTFASE3'
# FASE 3 — tint2 BlackHole (fondo negro, texto verde Matrix)
panel_items = LTSC
launcher_icon_theme = BlackHole
launcher_item_app = jgmenu.desktop
panel_size = 100% 24
panel_margin = 0 0
panel_background_id = 0
panel_color = #000000 100
task_font = Sans 9
task_font_color = #2cff7a 100
task_active_font_color = #ffffff 100
task_background_id = 0
task_active_background_id = 1
clock_font_color = #2cff7a 100
time1_format = %H:%M
clock_tooltip = %A %d %B
systray_padding = 0 4 4
launcher_padding = 0 4 4
launcher_icon_size = 18
launcher_background_id = 0
# fondos: 0 barras, 1 tarea activa
background = 0
background = 1
TINTFASE3

    # jgmenu: menú raíz verde sobre negro
    cat > "$ROOT/etc/skel/.config/jgmenu/jgmenurc" <<'JGMFASE3'
menu_width = 380
menu_margin_y = 34
menu_bg_color = #000000ee
menu_font = Sans 10
menu_fifo = 1
item_height = 22
item_color = #2cff7a
item_selected_bg = #2cff7a33
color_sel_text = #ffffff
sep_color = #2cff7a66
icon_size = 18
JGMFASE3

    # Aplicar el esqueleto a los usuarios que ya existan en el rootfs
    local d u
    for d in "$ROOT"/home/*; do
        [[ -d "$d" ]] || continue
        u="$(basename "$d")"
        mkdir -p "$d/.config"
        cp -rf "$ROOT/etc/skel/.config/openbox" "$ROOT/etc/skel/.config/tint2" \
               "$ROOT/etc/skel/.config/jgmenu" "$d/.config/" || true
        chroot "$ROOT" chown -R "$u:$u" "/home/$u/.config" || true
    done
    log "FASE 3 lista: sesión Openbox BlackHole-Aero en el selector de LightDM."
}

write_fase4_tray() {
    step "FASE 4: bandeja (volumeicon + nm-applet)"
    cat > "$ROOT/etc/xdg/autostart/bh-tray.desktop" <<'DESKFASE4'
[Desktop Entry]
Type=Application
Name=BlackHole Tray
Comment=Fase 4: volumen y red en la bandeja
Exec=sh -c "volumeicon >/dev/null 2>&1 & nm-applet >/dev/null 2>&1 &"
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
DESKFASE4
    if [[ ! -x "$ROOT/usr/bin/volumeicon" || ! -x "$ROOT/usr/bin/nm-applet" ]]; then
        warn "FASE 4: falta volumeicon o nm-applet; la entrada de autostart se ignora sola."
    fi
    log "FASE 4 lista: /etc/xdg/autostart/bh-tray.desktop."
}

write_fase5_verificar() {
    step "FASE 5: pre-vuelo verificar-e6400"
    cat > "$ROOT/usr/local/bin/verificar-e6400" <<'BHVERIFY'
#!/usr/bin/env bash
# verificar-e6400 — Pre-vuelo del Dell Latitude E6400 (FASE 5)
# Sale con 1 si hay fallos (0 = listo para volar).
set -u
fails=0; warns=0
ok()   { printf '  [ OK  ] %s\n' "$1"; }
warn1(){ printf '  [AVISO] %s\n' "$1"; warns=$((warns+1)); }
fail() { printf '  [FALLO] %s\n' "$1"; fails=$((fails+1)); }
section() { printf '\n=== %s ===\n' "$1"; }

section "RAM TOTAL"
total="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"
(( total >= 1900 )) && ok "RAM: ${total} MB" || fail "RAM: ${total} MB (se exigen 1900 MB)"

section "CPU 64 BITS"
if grep -qw lm /proc/cpuinfo 2>/dev/null; then
    ok "La CPU tiene la bandera lm (64 bits)"
else
    fail "La CPU no reporta 64 bits (bandera lm ausente)"
fi

section "GPU GMA 4500MHD"
if lspci -nn 2>/dev/null | grep -qi '8086:2a42'; then
    ok "GPU Intel 8086:2a42 detectada"
else
    warn1 "GPU 8086:2a42 no visible en lspci (¿otro modelo?)"
fi
if lsmod 2>/dev/null | grep -q '^i915'; then
    ok "Módulo i915 cargado"
else
    warn1 "i915 sin cargar (revisa tras la instalación)"
fi

section "FIRMWARE"
if [[ -d /sys/firmware/efi ]]; then
    warn1 "Arranque EFI detectado (el perfil está afinado para BIOS Legacy)"
else
    ok "Arranque BIOS Legacy"
fi

section "SWAP / ZRAM"
if swapon --show 2>/dev/null | grep -q zram || zramctl 2>/dev/null | grep -q zram; then
    ok "zram activa"
else
    warn1 "zram inactiva (solo swap de disco o nada)"
fi

section "ESPACIO EN RAÍZ"
mb_free="$(df -PM / 2>/dev/null | awk 'NR==2 {print $4}')"
(( mb_free >= 3000 )) && ok "Raíz con ${mb_free} MB libres" || warn1 "Raíz con ${mb_free} MB libres (justo para actualizar)"

section "RED"
if lspci -nn 2>/dev/null | grep -qiE 'network|ethernet'; then
    ok "Controlador de red detectado"
else
    fail "Sin controlador de red visible en lspci"
fi
if ip -o link 2>/dev/null | grep -qE 'eth|enp|wlp|wlan'; then
    ok "Interfaz de red presente"
else
    warn1 "Ninguna interfaz de red levantada aún"
fi

printf '\nResultado: %d fallo(s), %d aviso(s).\n' "$fails" "$warns"
(( fails == 0 )) || exit 1
printf 'E6400 listo para Black Hole Linux.\n'
BHVERIFY
    chmod 755 "$ROOT/usr/local/bin/verificar-e6400"
    log "FASE 5 lista: /usr/local/bin/verificar-e6400 (pre-vuelo)."
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

    # Base ligera + diagnóstico + gráficos Intel (S3TC ya va en Mesa de jammy)
    local base=(ca-certificates locales htop lm-sensors pciutils usbutils rfkill iproute2 \
                alsa-utils evtest joystick binutils file build-essential cmake pkg-config \
                intel-microcode xserver-xorg-video-intel libgl1-mesa-dri mesa-utils \
                libva2 i965-va-driver vainfo fonts-liberation gamemode libgamemodeauto0)
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
            libretro-gambatte libretro-mgba libretro-snes9x dosbox scummvm fceux
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
    # FASES 3-4 necesitan su orbital; garantizamos paquetes y enganchamos todo
    apt_install_group "sesión Openbox BlackHole-Aero (FASE 3-4)" \
        openbox tint2 jgmenu picom feh volumeicon network-manager-gnome
    write_fase1_audit
    write_fase2_session
    write_fase3_openbox
    write_fase4_tray
    write_fase5_verificar
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
    if ! mksquashfs "$ROOT" "$BH_WORK/filesystem.squashfs" \
        "${comp_args[@]}" -processors "$BH_MKFS_PROCS" -noappend -no-progress \
        >>"$LOG" 2>&1; then
        tail -n 25 "$LOG" >&2 || true
        die "mksquashfs falló; cola de $LOG arriba."
    fi
    [[ -s "$BH_WORK/filesystem.squashfs" ]] || die "No se creó filesystem.squashfs"
    # Verbatim del remaster (probo OK en r8 y r14): cabecera del superblock.
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
Comandos: blackhole help | bh-audit | verificar-e6400 | bh-doctor | bh-perf game
Tras instalar al disco: sudo blackhole firstboot && sudo blackhole upgrade
No para juegos 3D modernos (GMA 4500MHD sin Vulkan).
README
}

repack_iso() {
    step "Reconstruyendo ISO (rebuild completo con El Torito replicado)"
    [[ "$BH_FORCE" = 1 || ! -e "$BH_OUTPUT" ]] || die "La salida ya existe: $BH_OUTPUT (usa --force)."
    mkdir -p "$(dirname "$BH_OUTPUT")"
    ISO_TMP="${BH_OUTPUT}.partial.$$"
    [[ ! -e "$ISO_TMP" ]] || die "Ya existe el temporal de salida: $ISO_TMP"
    write_iso_readme

    # NOTA: "-boot_image any replay" NO sirve aquí: al reemplazar el squashfs
    # cambia el layout y el MBR isohybrid del original queda referenciando
    # datos fuera del nuevo ISO ("Cannot refer by isohybrid MBR to data
    # outside of ISO 9660 filesystem"). Método correcto: stage del árbol raíz
    # original + reconstrucción con xorriso -as mkisofs usando las opciones de
    # arranque que el propio xorriso reporta de la ISO base.
    step "Stage del árbol raíz original (conserva vmlinuz/initrd/.disk)"
    rm -rf "$BH_WORK/iso-stage"
    mkdir -p "$BH_WORK/iso-stage"
    xorriso -osirrox on -indev "$BH_BASE_ISO" -extract / "$BH_WORK/iso-stage" >>"$LOG" 2>&1 \
        || die "No pude extraer el árbol raíz de la ISO base."
    cp -f "$BH_WORK/filesystem.squashfs" "$BH_WORK/iso-stage/casper/filesystem.squashfs"
    cp -f "$BH_WORK/filesystem.manifest" "$BH_WORK/iso-stage/casper/filesystem.manifest"
    cp -f "$BH_WORK/filesystem.manifest-desktop" "$BH_WORK/iso-stage/casper/filesystem.manifest-desktop"
    cp -f "$BH_WORK/filesystem.size" "$BH_WORK/iso-stage/casper/filesystem.size"
    cp -f "$BH_WORK/README-BLACKHOLE.txt" "$BH_WORK/iso-stage/README-BLACKHOLE.txt"
    # Árbol de arranque personalizado encima del original
    local d
    for d in isolinux boot EFI syslinux; do
        if [[ -d "$BH_WORK/boot-tree/$d" && -n "$(ls -A "$BH_WORK/boot-tree/$d" 2>/dev/null)" ]]; then
            rm -rf "$BH_WORK/iso-stage/$d"
            cp -a "$BH_WORK/boot-tree/$d" "$BH_WORK/iso-stage/"
        fi
    done
    [[ -s "$BH_WORK/iso-stage/casper/filesystem.squashfs" ]] || die "Falta el squashfs en el stage de la ISO."

    step "Replicando opciones de arranque de la ISO base"
    local opts_file="$BH_WORK/mkisofs-opts.txt"
    xorriso -indev "$BH_BASE_ISO" -report_el_torito as_mkisofs 2>>"$LOG" \
        > "$opts_file" || die "No pude leer las opciones de arranque de la ISO base."
    # Depuracion CI: el reporte crudo queda en el issue si algo falla mas adelante
    warn "Reporte El Torito crudo (as_mkisofs):"
    sed 's/^/[reporte] /' "$opts_file" >&2 || true
    local -a mk_opts=()
    eval "mk_opts=($(tr '\n' ' ' < "$opts_file"))" \
        || die "Opciones de arranque ilegibles en $opts_file."
    # El reporte suele empezar por "-as mkisofs": ya lo invocamos asi, se salta.
    if [[ "${mk_opts[0]:-}" = "-as" && "${mk_opts[1]:-}" = "mkisofs" ]]; then
        mk_opts=("${mk_opts[@]:2}")
    fi
    # Filtrar lo no reproducible: -G/--embedded-boot (=area de sistema del
    # original) y su valor; -isohybrid-mbr y su valor (se repone con el MBR
    # del constructor); opciones de intervalo que apuntan a la ISO vieja.
    local -a final_opts=()
    local arg expect_g=0
    for arg in "${mk_opts[@]}"; do
        if ((expect_g)); then
            expect_g=0
            warn "Token de area de sistema no reproducible omitido: $arg"
            continue
        fi
        case "$arg" in
            -G|--embedded-boot|-isohybrid-mbr) expect_g=1 ;;
            --interval:*|*:imported_iso:*) ;;
            *) final_opts+=("$arg") ;;
        esac
    done
    # Red de seguridad: valores numericos huerfanos (p. ej. '16' de un
    # partition_offset al que se le perdio la opcion) no pueden ser fuentes.
    local i tok pre
    for i in "${!final_opts[@]}"; do
        tok="${final_opts[$i]}"
        [[ "$tok" =~ ^[0-9]+$ ]] || continue
        pre="${final_opts[$((i-1))]:-}"
        case "$pre" in
            -partition_offset|-partition_hd_cyl|-boot-load-size) ;;
            *)
                warn "Token numerico huerfano omitido: '$tok' (viene detras de '$pre')"
                unset "final_opts[$i]" ;;
        esac
    done
    final_opts=("${final_opts[@]}")
    # isohybrid: reponer el MBR del constructor si el path del reporte no existe
    local k has_isohybrid=0
    for k in "${!final_opts[@]}"; do
        [[ "${final_opts[$k]}" == "-isohybrid-mbr" || "${final_opts[$k]}" == --isohybrid-mbr=* ]] || continue
        local nxt="${final_opts[$((k+1))]:-}"
        if [[ "${final_opts[$k]}" == "-isohybrid-mbr" && ! -f "$nxt" ]]; then
            if [[ -f /usr/lib/ISOLINUX/isohdpfx.bin ]]; then
                final_opts[$((k+1))]=/usr/lib/ISOLINUX/isohdpfx.bin
            else
                warn "Sin isohdpfx.bin en el constructor (paquete isolinux): la ISO arrancara desde CD y USB-UEFI (sin USB-BIOS hibrido)."
                unset "final_opts[$k]" "final_opts[$((k+1))]"
            fi
        fi
        has_isohybrid=1
    done
    final_opts=("${final_opts[@]}")
    if ((has_isohybrid == 0)); then
        if [[ -f /usr/lib/ISOLINUX/isohdpfx.bin ]]; then
            final_opts+=(-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin)
        else
            warn "Sin isohdpfx.bin (paquete isolinux): la ISO arrancara desde CD y USB-UEFI (sin USB-BIOS hibrido)."
            final_opts+=(--protective-msdos-label)
        fi
    fi

    step "Escribiendo $BH_OUTPUT con xorriso -as mkisofs"
    printf '%s\n' "${final_opts[@]}" | sed 's/^/[mkopt] /' >&2 || true
    if ! xorriso -as mkisofs -r -J -joliet-long "${final_opts[@]}" \
            -output "$ISO_TMP" "$BH_WORK/iso-stage" >>"$LOG" 2>&1; then
        tail -n 25 "$LOG" >&2 || true
        warn "Fallo con las opciones del reporte; reintento con opciones conocidas de Bodhi 7."
        final_opts=(-V "Bodhi Live CD" -partition_cyl_align on -partition_offset 16 \
            -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
            -b isolinux/isolinux.bin -c isolinux/boot.cat \
            -no-emul-boot -boot-load-size 4 -boot-info-table)
        if [[ ! -f /usr/lib/ISOLINUX/isohdpfx.bin ]]; then
            warn "Sin isohdpfx.bin: arrancara desde CD y USB-UEFI (sin USB-BIOS hibrido)."
            final_opts=(-V "Bodhi Live CD" -b isolinux/isolinux.bin -c isolinux/boot.cat \
                -no-emul-boot -boot-load-size 4 -boot-info-table --protective-msdos-label)
        fi
        xorriso -as mkisofs -r -J -joliet-long "${final_opts[@]}" \
            -output "$ISO_TMP" "$BH_WORK/iso-stage" >>"$LOG" 2>&1 \
            || die "xorriso -as mkisofs no pudo reconstruir la ISO tras dos intentos; cola de $LOG arriba"
    fi

    [[ -s "$ISO_TMP" ]] || die "La ISO temporal no existe o está vacía."
    local final_boot_info
    final_boot_info="$(xorriso -indev "$ISO_TMP" -report_el_torito plain 2>>"$LOG")" \
        || die "ISO creada pero no se verificaron los registros de arranque."
    grep -qi "BIOS" <<< "$final_boot_info" \
        || die "La ISO final no conserva arranque Legacy BIOS (El Torito). No la uses en el E6400."
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
