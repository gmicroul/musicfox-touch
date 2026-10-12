#!/bin/bash
# Fetch everything tools/build-ut.sh needs, without root and without touching
# the system: the Go toolchain and the Qt5 / mpv .deb payloads are unpacked into
# ~/opt and the libraries are found at runtime through an explicit
# LD_LIBRARY_PATH (see tools/package-deb.py).
set -euo pipefail

PREFIX="${HOME}/opt"
GO_VERSION="${GO_VERSION:-1.23.4}"
GO_URL="https://dl.google.com/go/go${GO_VERSION}.linux-arm64.tar.gz"
QT="$PREFIX/qtdev"
MPV="$PREFIX/mpv"
MPV_LIBDIR="$MPV/usr/lib/aarch64-linux-gnu"

log() { printf '==> %s\n' "$*"; }

# Debian packages providing the headers/tools and mpv itself.
QT_PACKAGES="qtbase5-dev qtbase5-dev-tools qtdeclarative5-dev qtmultimedia5-dev libgl-dev libglx-dev"
MPV_PACKAGES="mpv libmpv2"

have_qt() { [ -d "$QT/usr/include/aarch64-linux-gnu/qt5" ] && [ -x "$QT/usr/lib/qt5/bin/moc" ]; }
have_mpv() { LD_LIBRARY_PATH="$MPV_LIBDIR" "$MPV/usr/bin/mpv" --version >/dev/null 2>&1; }

# ---------------------------------------------------------------- Go ------
if [ -x "$PREFIX/go/bin/go" ]; then
    log "Go already installed: $("$PREFIX/go/bin/go" version)"
else
    log "downloading Go ${GO_VERSION}"
    tmp=$(mktemp -d)
    curl -sSfL -o "$tmp/go.tar.gz" "$GO_URL"
    # GNU tar is broken on some kernels (openat2 -> ENOSYS), so untar in python.
    python3 - "$tmp/go.tar.gz" "$PREFIX" <<'PY'
import sys, tarfile
with tarfile.open(sys.argv[1]) as t:
    for m in t:
        if m.name.startswith("go/test/") or m.name == "go/test" or m.name.startswith("go/api/"):
            continue
        t.extract(m, sys.argv[2])
PY
    chmod +x "$PREFIX/go/bin/go" "$PREFIX/go/pkg/tool/linux_arm64/"*
    rm -rf "$tmp"
fi

# --------------------------------------------------------------- debs -----
# dpkg-deb shells out to GNU tar, so extract the ar + data.tar.* in python.
undeb() {
    python3 - "$1" "$2" <<'PY'
import io, sys, tarfile
path, dest = sys.argv[1], sys.argv[2]
with open(path, "rb") as f:
    if f.read(8) != b"!<arch>\n":
        raise SystemExit("not an ar archive: " + path)
    while True:
        header = f.read(60)
        if len(header) < 60:
            raise SystemExit("no data member in " + path)
        name = header[0:16].decode().strip().rstrip("/")
        size = int(header[48:58].decode().strip())
        data = f.read(size + size % 2)
        if name.startswith("data.tar"):
            mode = {"data.tar": "r:", "data.tar.gz": "r:gz", "data.tar.xz": "r:xz",
                    "data.tar.bz2": "r:bz2", "data.tar.zst": "r:zst"}[name]
            tarfile.open(fileobj=io.BytesIO(data), mode=mode).extractall(dest)
            break
PY
}

fetch_debs() {
    local dest="$1"; shift
    mkdir -p "$dest"
    ( cd "$dest"
      for spec in "$@"; do
          local name="${spec%%:*}" url
          url=$(apt-get install --print-uris -y --no-install-recommends "$name" 2>/dev/null \
                | awk -F"'" '/^'"'"'/ {print $2}' | tr '\n' ' ')
          [ -z "$url" ] && { echo "no download URI for $name" >&2; return 1; }
          for u in $url; do curl -sSfL -O "$u"; done
      done )
}

if have_qt; then
    log "Qt5 headers already present in $QT"
else
    log "fetching Qt5 development headers"
    tmp=$(mktemp -d)
    fetch_debs "$tmp" $QT_PACKAGES
    mkdir -p "$QT"
    for d in "$tmp"/*.deb; do undeb "$d" "$QT"; done
    # The -dev packages ship symlinks such as libQt5Core.so -> libQt5Core.so.5.15.18
    # whose targets live in the system library dir; point them there so the
    # linker can find them.
    python3 - "$QT/usr/lib/aarch64-linux-gnu" <<'PY'
import os, sys
d = sys.argv[1]
for name in sorted(os.listdir(d)):
    p = os.path.join(d, name)
    if not os.path.islink(p) or os.path.exists(os.path.join(d, os.readlink(p))):
        continue
    sys_lib = os.path.join("/usr/lib/aarch64-linux-gnu", os.readlink(p))
    if os.path.exists(sys_lib):
        os.remove(p)
        os.symlink(sys_lib, p)
PY
    rm -rf "$tmp"
fi

if have_mpv; then
    log "mpv already available in $MPV"
else
    log "fetching mpv and its missing libraries"
    tmp=$(mktemp -d)
    fetch_debs "$tmp" $MPV_PACKAGES
    mkdir -p "$MPV"
    for d in "$tmp"/*.deb; do undeb "$d" "$MPV"; done
    rm -rf "$tmp"
fi

log "done - now run tools/build-ut.sh"