#!/bin/sh
# Instalador del escritorio mínimo + look «Windows Vista + Black Hole Matrix»
# Para Dell Latitude E6400 (antiX o Debian, 64 bits). Ejecutar como usuario normal.
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
CFG="$HOME/.config"

echo '== 1. Paquetes =='
sudo apt update
sudo apt install --no-install-recommends \
    xserver-xorg-core xserver-xorg-input-libinput x11-xserver-utils xinit dbus-x11 \
    libgl1-mesa-dri libglx-mesa0 mesa-utils \
    openbox obconf tint2 jgmenu picom feh pcmanfm xterm \
    fonts-open-sans fonts-dejavu-core papirus-icon-theme python3-pil \
    alsa-utils network-manager network-manager-gnome

echo '== 2. Carpetas =='
mkdir -p "$HOME/bin" "$CFG/tint2" "$CFG/openbox" "$CFG/jgmenu" "$CFG/gtk-3.0" "$HOME/.themes/BlackHole-Aero/openbox-3"

echo '== 3. Fondo y orbe (se generan solos) =='
python3 "$REPO/scripts/blackhole.py"

echo '== 4. Tema Openbox BlackHole-Aero =='
cp "$REPO/config/openbox/themerc" "$HOME/.themes/BlackHole-Aero/openbox-3/themerc"
# Botones .xbm: copiarlos de cualquier tema instalado
if [ -d /usr/share/themes/Clearlooks/openbox-3 ]; then
    cp /usr/share/themes/Clearlooks/openbox-3/*.xbm "$HOME/.themes/BlackHole-Aero/openbox-3/" 2>/dev/null || true
else
    for t in /usr/share/themes/*/openbox-3; do
        [ -e "$t" ] && cp "$t"/*.xbm "$HOME/.themes/BlackHole-Aero/openbox-3/" 2>/dev/null && break
    done
fi

echo '== 5. Configuraciones de usuario =='
cp "$REPO/config/tint2/tint2rc" "$CFG/tint2/tint2rc"
cp "$REPO/config/jgmenu/jgmenurc" "$CFG/jgmenu/jgmenurc"
cp "$REPO/config/picom.conf" "$CFG/picom.conf"
cp "$REPO/config/gtk-3.0/settings.ini" "$CFG/gtk-3.0/settings.ini"
cp "$REPO/config/gtk-3.0/gtk.css" "$CFG/gtk-3.0/gtk.css"
cp "$REPO/config/Xresources" "$HOME/.Xresources"
cp "$REPO/config/openbox/autostart" "$CFG/openbox/autostart"
cp "$REPO/bin/juego" "$HOME/bin/juego"
chmod +x "$HOME/bin/juego"

# Si no existe rc.xml de Openbox, copiar el de sistema y activar el tema
if [ ! -f "$CFG/openbox/rc.xml" ]; then
    cp /etc/xdg/openbox/rc.xml "$CFG/openbox/"
fi
sed -i '/<theme>/{n;s|<name>[^<]*</name>|<name>BlackHole-Aero</name>|}' "$CFG/openbox/rc.xml"
sed -i 's|<titlelayout>[^<]*</titlelayout>|<titlelayout>LIMC</titlelayout>|' "$CFG/openbox/rc.xml" || true

echo '== 6. Sesión sin gestor de login (ahorra 30-60 MB) =='
echo 'exec dbus-launch --exit-with-session openbox-session' > "$HOME/.xinitrc"
grep -q 'exec startx' "$HOME/.bash_profile" 2>/dev/null || \
    echo '[ -z $DISPLAY ] && [ $(tty) = /dev/tty1 ] && exec startx' >> "$HOME/.bash_profile"

echo '== Listo =='
echo 'Cierra sesión y vuelve a entrar (startx en tty1).'
echo 'Después, opcional: obconf → Fuentes: Open Sans 9, y openbox --reconfigure.'
