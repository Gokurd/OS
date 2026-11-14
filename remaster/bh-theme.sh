#!/usr/bin/env bash
# Modulo: personalizacion Black Hole / Matrix (tema Plymouth, GRUB, GTK, conky, MOTD)
# Parte de Black Hole Linux v8.0 ULTIMATE-E6400. Lo sourcea blackhole-linux.sh

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

