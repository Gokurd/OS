# ==============================================================================
# bh-bootlook.sh — arranque tipo Zorin OS para Black Hole Linux (Matrix edition)
# Lo sourcea matrix-look.sh; se ejecuta tras write_blackhole_theme, por lo que
# SOBREESCRIBE el tema Plymouth 'blackhole' con una version verificada contra
# la API real del plugin script de Plymouth (sin Image.Create ni
# SetProgressFunction, que no existen y romperian el splash).
# Aporta:
#   * Splash Plymouth: fondo negro, logo agujero negro pulsante, texto
#     "BLACK HOLE" en verde y punto de progreso que cruza la pantalla.
#   * Tema de iconos BlackHole generado por codigo (48x48).
#   * bh-bootfade: fundido de entrada al escritorio (negro -> escritorio),
#     estilo Zorin, en ambas sesiones (Moksha y Openbox BlackHole-Aero).
# ==============================================================================

write_bootlook() {
    [[ "$BH_DO_THEME" = 1 ]] || { info "Arranque Black Hole desactivado (--no-theme)."; return 0; }
    step "Arranque tipo Zorin: splash BLACK HOLE en verde + fundido al escritorio"

    # --- 1) Regenerar assets con logo y punto para Plymouth ---
    if have python3 && [[ -f "$BH_MATRIX_DIR/generate-assets.py" ]]; then
        python3 "$BH_MATRIX_DIR/generate-assets.py" --out "$BH_ASSETS" >>"$LOG" 2>&1 \
            || warn "No se pudieron regenerar los assets del splash."
        python3 "$BH_MATRIX_DIR/generate-assets.py" --icons "$BH_ASSETS/icons" >>"$LOG" 2>&1 \
            || warn "No se pudieron generar los iconos BlackHole."
    fi

    # --- 2) Tema Plymouth 'blackhole' (script plugin, API verificada) ---
    mkdir -p "$ROOT/usr/share/plymouth/themes/blackhole"
    if [[ -f "$BH_ASSETS/blackhole-logo.png" ]]; then
        cp -f "$BH_ASSETS/blackhole-logo.png" "$ROOT/usr/share/plymouth/themes/blackhole/"
        cp -f "$BH_ASSETS/blackhole-dot.png"  "$ROOT/usr/share/plymouth/themes/blackhole/"
    fi
    cat > "$ROOT/usr/share/plymouth/themes/blackhole/blackhole.plymouth" <<'PLY'
[Plymouth Theme]
Name=Black Hole
Description=Black Hole Linux boot splash (Zorin-style, Matrix edition)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/blackhole
ScriptFile=/usr/share/plymouth/themes/blackhole/blackhole.script
PLY

    cat > "$ROOT/usr/share/plymouth/themes/blackhole/blackhole.script" <<'PSCRIPT'
// Black Hole Linux — splash estilo Zorin OS, "BLACK HOLE" en verde
// Solo APIs verificadas del plugin script: Window, Image(), Image.Text,
// Image.Scale, Sprite, SetX/SetY/SetZ/SetOpacity/SetImage, Math, y las
// funciones Plymouth.SetRefreshFunction / SetBootProgressFunction /
// SetMessageFunction.

Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.03, 0.0);

screen_w = Window.GetWidth();
screen_h = Window.GetHeight();

// --- Logo (agujero negro con anillo verde), pulsante ---
logo_sprite = 0;
logo_image = Image("blackhole-logo.png");
if (logo_image) {
    target = screen_w / 6;
    if (target < 96) target = 96;
    if (target > 220) target = 220;
    lw = target;
    lh = target * logo_image.GetHeight() / logo_image.GetWidth();
    logo_scaled = logo_image.Scale(lw, lh);
    logo_sprite = Sprite(logo_scaled);
    logo_sprite.SetX((screen_w - logo_scaled.GetWidth()) / 2);
    logo_sprite.SetY(screen_h * 0.26);
    logo_sprite.SetZ(2);
}

// --- Titulo BLACK HOLE en verde ---
title = Image.Text("BLACK HOLE", 0.17, 1.0, 0.48, 1.0, "DejaVu Sans Bold 30");
title_sprite = Sprite(title);
title_sprite.SetX((screen_w - title.GetWidth()) / 2);
title_sprite.SetY(screen_h * 0.55);
title_sprite.SetZ(3);

sub = Image.Text("LINUX 8.0 · ULTIMATE-E6400", 0.45, 0.9, 0.55, 1.0, "DejaVu Sans 14");
sub_sprite = Sprite(sub);
sub_sprite.SetX((screen_w - sub.GetWidth()) / 2);
sub_sprite.SetY(screen_h * 0.55 + title.GetHeight() + 8);
sub_sprite.SetZ(3);

// --- Punto de progreso que cruza la parte baja ---
dot_sprite = 0;
dot_image = Image("blackhole-dot.png");
if (dot_image) {
    dot_sprite = Sprite(dot_image);
    dot_sprite.SetZ(4);
}
track_y = screen_h * 0.78;
track_w = screen_w * 0.36;
track_x = (screen_w - track_w) / 2;

status_sprite = 0;
tick = 0;
progress_seen = 0;

fun bh_refresh () {
    tick = tick + 1;
    if (logo_sprite) {
        pulse = 0.72 + 0.28 * Math.Sin(tick / 10);
        logo_sprite.SetOpacity(pulse);
    }
    if (dot_sprite && progress_seen == 0) {
        k = (Math.Sin(tick / 18) + 1) / 2;
        dot_sprite.SetX(track_x + (track_w - dot_image.GetWidth()) * k);
        dot_sprite.SetY(track_y);
    }
}
Plymouth.SetRefreshFunction(bh_refresh);

fun bh_progress (duration, progress) {
    if (progress > 0) progress_seen = 1;
    if (dot_sprite && progress > 0) {
        p = progress;
        if (p > 1) p = 1;
        dot_sprite.SetX(track_x + (track_w - dot_image.GetWidth()) * p);
        dot_sprite.SetY(track_y);
    }
}
Plymouth.SetBootProgressFunction(bh_progress);

fun bh_message (text) {
    if (text == "") {
        if (status_sprite) { status_sprite.SetOpacity(0); }
        return;
    }
    msg = Image.Text(text, 0.45, 0.9, 0.55, 1.0, "DejaVu Sans 13");
    if (status_sprite) { status_sprite.SetImage(msg); }
    else { status_sprite = Sprite(msg); status_sprite.SetZ(5); }
    status_sprite.SetX((screen_w - msg.GetWidth()) / 2);
    status_sprite.SetY(track_y + 26);
    status_sprite.SetOpacity(1);
}
Plymouth.SetMessageFunction(bh_message);
PSCRIPT

    # --- 3) Tema de iconos BlackHole generado por codigo ---
    if [[ -d "$BH_ASSETS/icons" ]]; then
        mkdir -p "$ROOT/usr/share/icons"
        rm -rf "$ROOT/usr/share/icons/BlackHole"
        cp -a "$BH_ASSETS/icons" "$ROOT/usr/share/icons/BlackHole"
        log "Iconos BlackHole instalados en /usr/share/icons/BlackHole."
    fi
    # Asegurar que GTK usa el tema BlackHole (bh-theme ya lo escribe; reafirmar)
    if [[ -d "$ROOT/etc/skel/.config/gtk-3.0" ]]; then
        sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name=BlackHole/' \
            "$ROOT/etc/skel/.config/gtk-3.0/settings.ini" 2>/dev/null || true
        sed -i 's/^gtk-icon-theme-name=.*/gtk-icon-theme-name=BlackHole/' \
            "$ROOT/etc/gtk-3.0/settings.ini" 2>/dev/null || true
    fi

    # --- 4) Fundido de entrada al escritorio (estilo Zorin) ---
    cat > "$ROOT/usr/local/bin/bh-bootfade" <<'FADE'
#!/bin/sh
# Black Hole Linux — fundido de entrada: de negro al escritorio (estilo Zorin)
OUT=$(xrandr 2>/dev/null | awk '/ connected/{print $1; exit}')
[ -n "$OUT" ] || exit 0
xrandr --output "$OUT" --brightness 0 2>/dev/null || exit 0
i=1
while [ $i -le 20 ]; do
    b=$(awk "BEGIN{printf \"%.2f\", $i/20}")
    xrandr --output "$OUT" --brightness "$b" 2>/dev/null || break
    i=$((i+1))
    sleep 0.05
done
xrandr --output "$OUT" --brightness 1 2>/dev/null || true
FADE
    chmod 755 "$ROOT/usr/local/bin/bh-bootfade"
    mkdir -p "$ROOT/etc/xdg/autostart"
    cat > "$ROOT/etc/xdg/autostart/bh-bootfade.desktop" <<'DESK'
[Desktop Entry]
Type=Application
Name=Black Hole Boot Fade
Comment=Fundido de entrada al escritorio (estilo Zorin)
Exec=/usr/local/bin/bh-bootfade
NoDisplay=true
X-GNOME-Autostart-enabled=true
DESK

    # --- 5) El Openbox BlackHole-Aero tambien funde (por si xdg autostart
    #        no aplica en esa sesion) ---
    if [[ -f "$ROOT/etc/skel/.config/openbox/autostart" ]] \
       && ! grep -q 'bh-bootfade' "$ROOT/etc/skel/.config/openbox/autostart"; then
        printf '/usr/local/bin/bh-bootfade &\n' >> "$ROOT/etc/skel/.config/openbox/autostart"
    fi

    log "Splash BLACK HOLE (Plymouth), iconos y fundido estilo Zorin instalados."
}
