#!/bin/bash
# Native build for Ubuntu Touch / Lomiri (aarch64), no Sailfish SDK and no
# root needed: Qt5 headers/libs come from .deb files extracted into
# ~/opt/qtdev, moc/rcc from the same place.
#
#   tools/build-ut.sh          # build app/harbour-musicfox
#
# Playback is an external mpv process (JSON IPC), so neither libmpv nor
# QtMultimedia is linked in.
set -euo pipefail

HOME_DIR="${HOME}"
QT_PREFIX="$HOME_DIR/opt/qtdev"
QT_INC="$QT_PREFIX/usr/include/aarch64-linux-gnu/qt5"
QT_LIB="$QT_PREFIX/usr/lib/aarch64-linux-gnu"
QT_BIN="$QT_PREFIX/usr/lib/qt5/bin"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/app"
BUILD_DIR="$APP_DIR/build-ut"
OUT="$APP_DIR/harbour-musicfox"

[ -d "$QT_INC" ] || { echo "Qt5 headers missing in $QT_INC (see tools/install-deps-ut.sh)" >&2; exit 1; }

mkdir -p "$BUILD_DIR"
cd "$APP_DIR"

INCLUDES="-I$QT_PREFIX/usr/include -I$QT_INC -I$QT_INC/QtCore -I$QT_INC/QtGui -I$QT_INC/QtNetwork \
-I$QT_INC/QtQml -I$QT_INC/QtQuick"
CXXFLAGS="-fPIC -std=c++14 -O2 -DQT_NO_DEBUG $INCLUDES"
LDFLAGS="-L$QT_LIB -L/usr/lib/aarch64-linux-gnu -pie -rdynamic"
LIBS="-lQt5Quick -lQt5Qml -lQt5Network -lQt5Gui -lQt5Core"

SOURCES="src/main.cpp src/neteaseapi.cpp src/mpvcontroller.cpp src/playqueue.cpp \
src/lyricsync.cpp src/covercache.cpp src/pulselevels.cpp"
HEADERS="src/neteaseapi.h src/mpvcontroller.h src/playqueue.h src/lyricsync.h \
src/covercache.h src/pulselevels.h"


echo "==> moc"
for h in $HEADERS; do
    "$QT_BIN/moc" "$h" -o "$BUILD_DIR/moc_$(basename "${h%.h}.cpp")"
done

echo "==> rcc"
"$QT_BIN/rcc" --name musicfox-qml qml.qrc -o "$BUILD_DIR/qrc_qml.cpp"

echo "==> compile"
objects=()
for s in $SOURCES "$BUILD_DIR"/moc_*.cpp "$BUILD_DIR/qrc_qml.cpp"; do
    out="$BUILD_DIR/$(basename "${s%.cpp}").o"
    g++ $CXXFLAGS -c "$s" -o "$out"
    objects+=("$out")
done

echo "==> link"
g++ $LDFLAGS "${objects[@]}" $LIBS -o "$OUT"
echo "built $OUT"