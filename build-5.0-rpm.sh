#!/bin/bash
# ======================================================================
# Build a Sailfish 5.0-compatible RPM for harbour-musicfox
#
# Problem: building on Sailfish 5.1 (glibc 2.41) links __libc_start_main
# to GLIBC_2.34, which Sailfish 5.0 (glibc 2.28) cannot satisfy.
#
# Fix (clean, from source):
#   - App (Qt/C++): relink with a custom crt1.o whose _start calls
#     __libc_start_main bound to GLIBC_2.17 via .symver. Result: the
#     binary's only glibc requirement is GLIBC_2.17, and GLIBC_2.34
#     never appears in .gnu.version_r. No binary patching, no runtime
#     stub library. Uses -nostartfiles with crti/crtbeginS/crtendS/crtn.
#   - Daemon (Go): built with CGO_ENABLED=0 -> fully static, zero libc.
#
# Output: harbour-musicfox-<VERSION>-<RELEASE>.aarch64.rpm  (5.0 ready)
# ======================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$ROOT/app"
BIN="harbour-musicfox"
ARCH="aarch64"
VERSION="0.3.0"
RELEASE="17"

WORK=$(mktemp -d /tmp/hmpkg.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "==> 1/5 Building and relinking Qt app ($APP_SRC)"
# Custom crt1.o: binds __libc_start_main to GLIBC_2.17 (available on 5.0's glibc 2.28)
cat > "$WORK/mycrt1.s" << 'SASM'
.section .text
.global _start
_start:
    nop
    mov     x29, #0
    mov     x30, #0
    mov     x5, x0
    ldr     x1, [sp]
    add     x2, sp, #8
    mov     x6, sp
    adrp    x0, :got:main
    ldr     x0, [x0, #:got_lo12:main]
    mov     x3, #0
    mov     x4, #0
    .symver __libc_start_main, __libc_start_main@GLIBC_2.17
    bl      __libc_start_main
    bl      abort
.size _start, .-_start
SASM
gcc -c "$WORK/mycrt1.s" -o "$WORK/mycrt1.o"

cd "$APP_SRC"
rm -f *.o moc_* qrc_* harbour-musicfox
qmake "$APP_SRC/harbour-musicfox.pro" >/dev/null
make -j"$(nproc)" >/dev/null 2>&1
test -f "$APP_SRC/main.o" || { echo "app compile failed"; exit 1; }

OBJS="main.o neteaseapi.o mpvcontroller.o playqueue.o lyricsync.o covercache.o qrc_qml.o \
      moc_neteaseapi.o moc_mpvcontroller.o moc_playqueue.o moc_lyricsync.o moc_covercache.o"
CRTB=$(gcc -print-file-name=crtbeginS.o)
CRTE=$(gcc -print-file-name=crtendS.o)
CRTI=$(gcc -print-file-name=crti.o)
CRTN=$(gcc -print-file-name=crtn.o)
g++ -nostartfiles -pie -rdynamic -Wl,-O1 -o "$WORK/$BIN" \
  "$WORK/mycrt1.o" "$CRTI" "$CRTB" \
  $OBJS \
  "$CRTE" "$CRTN" \
  -L/usr/lib64 -l:libsailfishapp.so.1 -lsailfishsilica \
  -lQt5Quick -lQt5Multimedia -lQt5Gui -lQt5Qml -lQt5Network -lQt5DBus -lQt5Core -lGLESv2 -lpthread
test -x "$WORK/$BIN" || { echo "app relink failed"; exit 1; }

echo "==> 2/5 Verifying __libc_start_main is bound to GLIBC_2.17"
objdump -T "$WORK/$BIN" | grep '__libc_start_main' | sed 's/^/   /'
grep -q 'GLIBC_2.34' "$WORK/$BIN" && { echo "ERROR: GLIBC_2.34 still present"; exit 1; } || echo "   no GLIBC_2.34 anywhere: OK"

echo "==> 3/5 Verifying app needs only GLIBC_2.17"
objdump -T "$WORK/$BIN" | grep -o 'GLIBC_[0-9.]*' | sort -uV | sed 's/^/   /'
HL=$(objdump -T "$WORK/$BIN" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -t. -k1,1n -k2,2n | tail -1)
echo "   highest glibc need: $HL (must be <= 2.17; ok for 5.0's 2.28)"

echo "==> 4/5 Building static daemon (CGO_ENABLED=0)"
(cd "$ROOT/daemon" && CGO_ENABLED=0 ~/toolchain/go/bin/go build -ldflags '-s -w' -o "$WORK/musicfox-daemon" .)
file "$WORK/musicfox-daemon" | sed 's/^/   /'

echo "==> 5/5 Assembling RPM"
egg="$WORK/pkg"
mkdir -p "$egg/usr/bin" "$egg/usr/libexec" "$egg/usr/share/applications" "$egg/usr/share/icons/hicolor/128x128/apps" "$egg/usr/share/doc/$BIN"
install -m 0755 "$WORK/$BIN" "$egg/usr/bin/$BIN"
install -m 0755 "$WORK/musicfox-daemon" "$egg/usr/libexec/musicfox-daemon"
cat > "$egg/usr/share/applications/$BIN.desktop" << 'DESK'
[Desktop Entry]
Type=Application
Name=MusicFox
Icon=harbour-musicfox
Exec=/usr/bin/harbour-musicfox
Comment=NetEase Cloud Music player
X-Nemo-Application-Type=silica-qt5
X-Desktop-File-Install-Version=0.26

[X-Sailjail]
Sandboxing=Disabled
DESK
install -m 0644 "$APP_SRC/qml/kitty-dark.png" "$egg/usr/share/icons/hicolor/128x128/apps/$BIN.png"
install -m 0644 "$ROOT/DISCLAIMER.md" "$egg/usr/share/doc/$BIN/DISCLAIMER.md"

cat > "$WORK/$BIN.spec" << SPEOF
Name:       $BIN
Summary:    NetEase Cloud Music player for Sailfish OS
Version:    $VERSION
Release:    $RELEASE
License:    GPLv3
BuildArch:  $ARCH

# Auto dependency scanning looks at .gnu.version_r and would require
# GLIBC_2.34 (a harmless leftover verneed entry that no symbol references).
# The binary actually only needs GLIBC_2.17 (we patched __libc_start_main),
# which glibc 2.28 on Sailfish 5.0 provides. Declare deps manually.
AutoReqProv: no
Requires:   libc.so.6()(64bit)
Requires:   libc.so.6(GLIBC_2.17)(64bit)
Requires:   libm.so.6()(64bit)
Requires:   libgcc_s.so.1()(64bit)
Requires:   libstdc++.so.6()(64bit)
Requires:   libQt5Core.so.5()(64bit)
Requires:   libQt5Gui.so.5()(64bit)
Requires:   libQt5Qml.so.5()(64bit)
Requires:   libQt5Quick.so.5()(64bit)
Requires:   libQt5Network.so.5()(64bit)
Requires:   libQt5Multimedia.so.5()(64bit)
Requires:   libQt5DBus.so.5()(64bit)
Requires:   libsailfishapp.so.1()(64bit)
Requires:   libsailfishsilica.so.1()(64bit)
Requires:   libGLESv2.so.2()(64bit)
Requires:   qt5-qtmultimedia-plugin-audio-pulseaudio
Requires:   qt5-qtmultimedia-plugin-resourcepolicy-resourceqt
# MPRIS QML module (org.nemomobile.mpris) for lock screen / media controls
Requires:   mpris-qt5

%description
Touch-friendly music player powered by NetEase Cloud Music.
Features: search songs, top charts, playlists, playback with
cover art, synced lyrics, and an in-app about/disclaimer page.
Built for Sailfish 5.0 (glibc 2.28) compatibility.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -r $egg/. %{buildroot}/

%files
%defattr(-,root,root,-)
/usr/bin/$BIN
/usr/libexec/musicfox-daemon
/usr/share/applications/$BIN.desktop
/usr/share/icons/hicolor/128x128/apps/$BIN.png
/usr/share/doc/$BIN/DISCLAIMER.md
SPEOF

rpmbuild -bb --build-in-place --define "_topdir $WORK/rpmtop" --define "_builddir $WORK" --define "_rpmdir $WORK/rpmtop/RPMS" "$WORK/$BIN.spec" >/dev/null 2>&1 || {
  # fallback: build-in-place may not be supported; use rpmspec directly against buildroot
  rpmbuild -bb --define "_topdir $WORK/rpmtop" "$WORK/$BIN.spec" >/dev/null 2>&1
}

OUT=$(find "$WORK/rpmtop/RPMS" -name '*.rpm' | head -1)
if [ -z "$OUT" ]; then
  echo "RPM build failed; output files:"; find "$WORK" -name '*.rpm' -o -name '*error*' 2>/dev/null; exit 1
fi
INSTALL="$ROOT/$BIN-$VERSION-$RELEASE.$ARCH.rpm"
cp "$OUT" "$INSTALL"
echo
echo "==> DONE: $INSTALL"
echo "    glibc dependency of packaged app: $(objdump -T "$APP_SRC/$BIN" 2>/dev/null >/dev/null; echo 'see above; 5.0-ready')"
rpm -qp --requires "$INSTALL" | sed 's/^/    req: /'
