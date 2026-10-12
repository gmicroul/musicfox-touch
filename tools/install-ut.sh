#!/bin/bash
# Install the Ubuntu Touch build into the user session (no root):
#   ~/.local/libexec/musicfox-touch/musicfox-bin     the Qt app
#   ~/.local/libexec/musicfox-touch/musicfox-daemon  NetEase API daemon (stdio JSON-RPC)
#   ~/.local/bin/musicfox-touch          launcher wrapper (sets the Lomiri QPA env)
#   ~/.local/bin/musicfox-touch-mpv      wrapper for the local mpv build
#   ~/.local/share/applications/musicfox-touch.desktop  app-grid entry
#   ~/Desktop/musicfox-touch.desktop               desktop icon
#
# The "musicfox-touch" prefix avoids clashing with the go-musicfox CLI
# package, which owns /usr/bin/musicfox.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="$HOME"
BIN_DIR="$PREFIX/.local/bin"
LIBEXEC="$PREFIX/.local/libexec/musicfox-touch"
APPS_DIR="$PREFIX/.local/share/applications"
ICON_DIR="$PREFIX/.local/share/icons/hicolor/512x512/apps"
DESKTOP_DIR="$PREFIX/Desktop"
MPV_PREFIX="$PREFIX/opt/mpv"

[ -x "$REPO/app/harbour-musicfox" ] || { echo "build the app first: tools/build-ut.sh" >&2; exit 1; }
[ -x "$REPO/daemon/musicfox-daemon" ] || { echo "build the daemon first" >&2; exit 1; }

rm -rf "$PREFIX/.local/libexec/musicfox-bin" "$PREFIX/.local/libexec/musicfox-daemon"
mkdir -p "$BIN_DIR" "$LIBEXEC" "$APPS_DIR" "$ICON_DIR" "$DESKTOP_DIR"

install -m 0755 "$REPO/app/harbour-musicfox" "$LIBEXEC/musicfox-bin"
install -m 0755 "$REPO/daemon/musicfox-daemon" "$LIBEXEC/musicfox-daemon"

cat > "$BIN_DIR/musicfox-touch" <<EOF
#!/bin/sh
# MusicFox launcher for Ubuntu Touch / Lomiri.
export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-ubuntumirclient}"
[ "\$QT_QPA_PLATFORM" = "mirserver" ] && export QT_QPA_PLATFORM=ubuntumirclient
export LD_LIBRARY_PATH="$MPV_PREFIX/usr/lib/aarch64-linux-gnu:\${LD_LIBRARY_PATH}"
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/run/user\$(id -u)}"
exec "$LIBEXEC/musicfox-bin" "\$@"
EOF
chmod 0755 "$BIN_DIR/musicfox-touch"

cat > "$BIN_DIR/musicfox-touch-mpv" <<EOF
#!/bin/sh
export LD_LIBRARY_PATH="$MPV_PREFIX/usr/lib/aarch64-linux-gnu:\${LD_LIBRARY_PATH}"
exec "$MPV_PREFIX/usr/bin/mpv" "\$@"
EOF
cp "$BIN_DIR/musicfox-touch-mpv" "$LIBEXEC/musicfox-mpv"
chmod 0755 "$BIN_DIR/musicfox-touch-mpv" "$LIBEXEC/musicfox-mpv"

# Never install over an icon the user already provided.
if find "$PREFIX/.local/share/icons" -name 'musicfox.*' -print -quit 2>/dev/null | grep -q .; then
    echo "note: keeping the existing user icon for 'musicfox' (no icon installed)"
else
    install -m 0644 "$REPO/app/assets/musicfox.png" \
        "$PREFIX/.local/share/icons/hicolor/512x512/apps/musicfox.png"
fi

desktop_entry() {
cat <<EOF
[Desktop Entry]
Type=Application
Name=MusicFox
Name[zh_CN]=MusicFox 音乐
Comment=NetEase Cloud Music player
Comment[zh_CN]=网易云音乐播放器
Exec=$BIN_DIR/musicfox-touch
Icon=musicfox
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=music;netease;audio;player;
StartupNotify=true
X-Lomiri-Single-Instance=true
EOF
}

desktop_entry > "$APPS_DIR/musicfox-touch.desktop"
desktop_entry > "$DESKTOP_DIR/musicfox-touch.desktop"
chmod 0755 "$DESKTOP_DIR/musicfox-touch.desktop"

echo "installed:"
echo "  $BIN_DIR/musicfox-touch"
echo "  $LIBEXEC/musicfox-daemon"
echo "  $APPS_DIR/musicfox-touch.desktop"
echo "  $DESKTOP_DIR/musicfox-touch.desktop"
echo
echo "log file: $PREFIX/.local/share/musicfox.log"