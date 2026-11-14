# ==============================================================================
# matrix-look.sh — modulo BlackHole-Aero para blackhole-linux.sh (Matrix edition)
# Lo carga automaticamente el script principal si vive junto a el.
# Aporta:
#   * generate_blackhole_assets(): crea splash + wallpaper por codigo (PIL)
#     si no existen en $BH_ASSETS (no hace falta descargar nada).
#   * write_matrix_look(): sesion Openbox "Windows Vista + Black Hole Matrix"
#     (tint2 con orbe de Inicio verde, jgmenu, picom, feh) instalada JUNTO a
#     Moksha; Moksha sigue siendo la sesion por defecto del remaster.
#   * Al final instala el arranque tipo Zorin (bh-bootlook.sh: splash Plymouth
#     "BLACK HOLE" en verde, iconos generados y fundido al escritorio).
# ==============================================================================

BH_MATRIX_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

# Modulo de arranque tipo Zorin (splash BLACK HOLE + iconos + fundido)
source "$BH_MATRIX_DIR/bh-bootlook.sh"

generate_blackhole_assets() {
    step "Assets Black Hole (splash + wallpaper) por codigo, si faltan"
    mkdir -p "$BH_ASSETS"
    if [[ -f "$BH_ASSETS/blackhole-splash.png" && -f "$BH_ASSETS/blackhole-wallpaper.jpg" ]]; then
        log "Assets ya presentes en $BH_ASSETS."
        return 0
    fi
    if have python3 && [[ -f "$BH_MATRIX_DIR/generate-assets.py" ]]; then
        python3 "$BH_MATRIX_DIR/generate-assets.py" --out "$BH_ASSETS" >>"$LOG" 2>&1 \
            && log "Assets generados por codigo en $BH_ASSETS." \
            || warn "Fallo la generacion de assets; el tema usara colores solidos."
    else
        warn "Sin python3/PIL o generate-assets.py; el tema usara colores solidos."
    fi
}

write_matrix_look() {
    [[ "$BH_DO_MATRIXLOOK" = 1 ]] || { info "Sesion BlackHole-Aero desactivada (--no-matrixlook)."; return 0; }
    step "Sesion Openbox BlackHole-Aero (Vista + Black Hole Matrix)"

    apt_install_group "sesion Openbox BlackHole-Aero" \
        openbox tint2 jgmenu picom feh fonts-open-sans python3-pil network-manager-gnome

    # --- Tema de ventanas BlackHole-Aero (cristal oscuro verde) ---
    mkdir -p "$ROOT/usr/share/themes/BlackHole-Aero/openbox-3"
    cat > "$ROOT/usr/share/themes/BlackHole-Aero/openbox-3/themerc" <<'THEMERC'
border.width: 1
padding.width: 6
padding.height: 4
window.handle.width: 0
window.client.padding.width: 4
window.label.text.justify: Left
window.active.border.color: #2cff7a
window.inactive.border.color: #0e3a20
window.active.client.color: #07210f
window.inactive.client.color: #04120a
window.active.title.separator.color: #2cff7a
window.inactive.title.separator.color: #0e3a20
window.active.title.bg: Flat Gradient SplitVertical
window.active.title.bg.color: #2a7a4a
window.active.title.bg.colorTo: #124a2a
window.active.title.bg.color.splitTo: #0a3a1f
window.active.title.bg.colorTo.splitTo: #03140a
window.inactive.title.bg: Flat Gradient SplitVertical
window.inactive.title.bg.color: #17402a
window.inactive.title.bg.colorTo: #0b2616
window.inactive.title.bg.color.splitTo: #06180e
window.inactive.title.bg.colorTo.splitTo: #020a05
window.active.label.bg: Parentrelative
window.inactive.label.bg: Parentrelative
window.active.label.text.color: #eafff1
window.inactive.label.text.color: #7fb08f
window.active.label.text.font: shadow=y:shadowtint=60:shadowoffset=1
window.active.button.unpressed.bg: Parentrelative
window.active.button.unpressed.image.color: #eafff1
window.active.button.hover.bg: Flat Gradient Vertical
window.active.button.hover.bg.color: #3dff8a
window.active.button.hover.bg.colorTo: #0f8a3e
window.active.button.hover.image.color: #02140a
window.active.button.pressed.bg: Flat Solid
window.active.button.pressed.bg.color: #0f8a3e
window.active.button.pressed.image.color: #ffffff
window.inactive.button.unpressed.bg: Parentrelative
window.inactive.button.unpressed.image.color: #7fb08f
menu.border.color: #2cff7a
menu.border.width: 1
menu.title.bg: Flat Gradient Vertical
menu.title.bg.color: #2a7a4a
menu.title.bg.colorTo: #0a3a1f
menu.title.text.color: #ffffff
menu.items.bg: Flat Solid
menu.items.bg.color: #04170c
menu.items.text.color: #d8ffe4
menu.items.disabled.text.color: #4c7a5a
menu.items.active.bg: Flat Gradient Vertical
menu.items.active.bg.color: #2a7a4a
menu.items.active.bg.colorTo: #145a30
menu.items.active.text.color: #ffffff
osd.border.color: #2cff7a
osd.bg: Flat Solid
osd.bg.color: #04170c
osd.label.text.color: #d8ffe4
osd.hilight.bg: Flat Solid
osd.hilight.bg.color: #2a7a4a
osd.unhilight.bg: Flat Solid
osd.unhilight.bg.color: #0b2b17
THEMERC

    cat > "$ROOT/usr/share/themes/BlackHole-Aero/openbox-3/close.xbm" <<'XBM1'
#define close_width 10
#define close_height 10
static unsigned char close_bits[] = {
   0x01,0x02,0x02,0x01,0x04,0x80,0x08,0x40,0x10,0x20,
   0x20,0x10,0x40,0x08,0x80,0x04,0x02,0x01,0x01,0x02 };
XBM1

    cat > "$ROOT/usr/share/themes/BlackHole-Aero/openbox-3/iconify.xbm" <<'XBM2'
#define iconify_width 10
#define iconify_height 10
static unsigned char iconify_bits[] = {
   0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
   0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0x03 };
XBM2

    cat > "$ROOT/usr/share/themes/BlackHole-Aero/openbox-3/max.xbm" <<'XBM3'
#define max_width 10
#define max_height 10
static unsigned char max_bits[] = {
   0xff,0x03,0x01,0x02,0x01,0x02,0x01,0x02,0x01,0x02,
   0x01,0x02,0x01,0x02,0x01,0x02,0x01,0x02,0xff,0x03 };
XBM3

    # --- Configs de usuario (skel). No toca settings.ini de Arc-Dark del
    #     tema principal: solo anade la seleccion verde via gtk.css. ---
    mkdir -p "$ROOT/etc/skel/.config/openbox" \
             "$ROOT/etc/skel/.config/tint2" \
             "$ROOT/etc/skel/.config/jgmenu" \
             "$ROOT/etc/skel/.config/gtk-3.0"

    cat > "$ROOT/etc/skel/.config/openbox/autostart" <<'AUTOSTART'
xrdb -merge ~/.Xresources
feh --bg-fill ~/.config/blackhole.png &
picom -b --config ~/.config/picom.conf
nm-applet &
tint2 &
AUTOSTART

    cat > "$ROOT/etc/skel/.config/tint2/tint2rc" <<'TINT2RC'
rounded = 0
border_width = 1
border_sides = T
background_color = #03140a 88
border_color = #2cff7a 70

rounded = 5
border_width = 1
border_sides = TBLR
background_color = #145a30 35
border_color = #2cff7a 25

rounded = 5
border_width = 1
border_sides = TBLR
background_color = #2a7a4a 75
border_color = #2cff7a 85

panel_items = PTSBC
panel_size = 100% 36
panel_margin = 0 0
panel_padding = 4 2 4
panel_background_id = 1
wm_menu = 1
panel_dock = 0
panel_layer = top
panel_position = bottom center horizontal
strut_policy = follow_size
mouse_left = toggle_iconify
mouse_middle = none
mouse_right = close
mouse_scroll_up = toggle
mouse_scroll_down = iconify

button = new
button_icon = ~/.config/tint2/orb.png
button_tooltip = Inicio
button_lclick_command = jgmenu_run
button_padding = 6 0 8
button_background_id = 0

taskbar_mode = single_desktop
taskbar_padding = 2 2 4
taskbar_background_id = 0
task_text = 1
task_icon = 1
task_centered = 0
task_maximum_size = 180 30
task_padding = 6 3 6
task_font = Open Sans 9
task_font_color = #d8ffe4 100
task_active_font_color = #ffffff 100
task_iconified_font_color = #7fb08f 100
task_background_id = 2
task_active_background_id = 3
task_iconified_background_id = 2
task_urgent_background_id = 3

systray_padding = 4 2 4
systray_background_id = 0
systray_icon_size = 18

battery_hide = 101
bat1_font = Open Sans 8
bat2_font = Open Sans 8
battery_font_color = #b6ffcb 100
battery_padding = 6 0
battery_background_id = 0

time1_format = %H:%M
time1_font = Open Sans Bold 10
time2_format = %d/%m/%Y
time2_font = Open Sans 8
clock_font_color = #b6ffcb 100
clock_padding = 8 0
clock_background_id = 0
TINT2RC

    cat > "$ROOT/etc/skel/.config/jgmenu/jgmenurc" <<'JGMENU'
csv_cmd = apps
menu_halign = left
menu_valign = bottom
menu_margin_x = 0
menu_margin_y = 36
menu_width = 270
menu_border = 1
item_height = 28
icon_size = 22
font = Open Sans 10
color_menu_bg = #02140a 94
color_menu_border = #2cff7a 60
color_norm_bg = #000000 0
color_norm_fg = #d8ffe4 100
color_sel_bg = #2a7a4a 85
color_sel_fg = #ffffff 100
color_sep_fg = #2cff7a 30
color_title_fg = #2cff7a 100
JGMENU

    cat > "$ROOT/etc/skel/.config/picom.conf" <<'PICOM'
backend = "xrender";
vsync = false;
shadow = true;
shadow-radius = 10;
shadow-offset-x = -8;
shadow-offset-y = -8;
shadow-opacity = 0.55;
shadow-exclude = [ "window_type = 'dock'", "window_type = 'desktop'" ];
fading = true;
fade-in-step = 0.08;
fade-out-step = 0.08;
inactive-opacity = 0.93;
frame-opacity = 0.9;
PICOM

    cat > "$ROOT/etc/skel/.config/gtk-3.0/gtk.css" <<'GTKCSS'
@define-color theme_selected_bg_color #1f9d55;
@define-color theme_selected_fg_color #ffffff;
GTKCSS

    cat > "$ROOT/etc/skel/.Xresources" <<'XRES'
XTerm*background: #000a04
XTerm*foreground: #2cff7a
XTerm*cursorColor: #2cff7a
XTerm*faceName: DejaVu Sans Mono
XTerm*faceSize: 10
XRES

    # --- Sesion registrada para el gestor de sesion (junto a Moksha) ---
    mkdir -p "$ROOT/usr/share/xsessions"
    if [[ ! -e "$ROOT/usr/share/xsessions/openbox-blackhole.desktop" ]]; then
        cat > "$ROOT/usr/share/xsessions/openbox-blackhole.desktop" <<'SESSION'
[Desktop Entry]
Name=Openbox (BlackHole-Aero)
Comment=Sesion Openbox estilo Windows Vista + Black Hole Matrix
Exec=openbox-session
Type=Application
Keywords=wm;windowmanager;matrix;blackhole;
SESSION
    fi

    # --- Generador de fondo/orbe dentro del rootfs + generacion para skel ---
    if [[ -f "$BH_MATRIX_DIR/generate-assets.py" ]]; then
        cp -f "$BH_MATRIX_DIR/generate-assets.py" "$ROOT/usr/local/bin/blackhole-wallpaper"
        chmod 755 "$ROOT/usr/local/bin/blackhole-wallpaper"
        chroot_run env HOME=/etc/skel python3 /usr/local/bin/blackhole-wallpaper --user \
            || warn "No se pudo pregenerar el fondo/orbe del skel."
    fi

    # --- Arranque tipo Zorin: splash BLACK HOLE + iconos + fundido ---
    write_bootlook

    log "Sesion Openbox BlackHole-Aero instalada (elige 'Openbox (BlackHole-Aero)' en el gestor de sesion)."
}
