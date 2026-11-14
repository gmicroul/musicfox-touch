#!/bin/bash
set -euo pipefail
source_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build_directory="${MUSICFOX_BUILD_DIR:-$source_directory/build}"
qt6_prefix="${MUSICFOX_QT6_PREFIX:-$source_directory/.sdk/usr}"
if [[ ${1:-} == --bootstrap ]]; then
    python3 "$source_directory/bootstrap-qt6.py"
elif [[ $# != 0 ]]; then
    printf 'Usage: %s [--bootstrap]\n' "$0" >&2
    exit 2
fi
if [[ ! -d "$qt6_prefix" ]]; then
    printf 'Set MUSICFOX_QT6_PREFIX to your Qt6 SDK, or run %s --bootstrap\n' "$0" >&2
    exit 1
fi
source "$source_directory/environment.sh"
musicfox_qt6_environment "$qt6_prefix"
cmake -S "$source_directory" -B "$build_directory" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$qt6_prefix" \
    -DQt6_DIR="$library_directory/cmake/Qt6" \
    -DPython3_EXECUTABLE="$(command -v python3)" \
    -DCMAKE_LIBRARY_PATH="$library_directory" \
    -DCMAKE_INCLUDE_PATH="$qt6_prefix/include" \
    -DCMAKE_BUILD_RPATH="$library_directory;$qt6_prefix/lib" \
    -DCMAKE_INSTALL_PREFIX=/usr/palm/applications/org.musicfox.touch \
    -DMUSICFOX_DAEMON="${MUSICFOX_DAEMON:-$source_directory/../daemon/musicfox-daemon}"
cmake --build "$build_directory" --parallel "${MUSICFOX_BUILD_JOBS:-4}"
stage_directory="$source_directory/dist/root"
mkdir -p "$stage_directory"
DESTDIR="$stage_directory" cmake --install "$build_directory" --strip
python3 "$source_directory/package.py" "$stage_directory" "$source_directory/dist"
printf '\nBuild: %s\nPackage: %s/dist/musicfox-touch-luneos_0.5.0-1_%s.ipk\n' \
    "$build_directory" "$source_directory" "$(uname -m)"
