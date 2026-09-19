#!/bin/bash
# ======================================================================
# Build a Sailfish 5.1-compatible RPM for harbour-musicfox on armv7hl
#
# This script builds the MusicFox app for Sailfish OS 5.1 (glibc 2.41)
# targeting armv7hl (32-bit ARM) architecture.
#
# Approach:
#   - Daemon (Go): built locally with CGO_ENABLED=0 -> fully static, zero libc
#   - App (Qt/C++): built inside Sailfish Platform SDK Docker container
#
# Output: harbour-musicfox-<VERSION>-<RELEASE>.armv7hl.rpm
# ======================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_SRC="$ROOT/app"
DAEMON_SRC="$ROOT/daemon"
BIN="harbour-musicfox"
ARCH="armv7hl"
VERSION="0.5.0"
RELEASE="1"
SFOS_RELEASE="5.1.0.11"  # Current Sailfish OS version

echo "==> Building MusicFox for Sailfish OS $SFOS_RELEASE - $ARCH"
echo "Root: $ROOT"

# === Step 1: Cross-compile static daemon for armv7hl (locally) ===
echo "==> Step 1: Cross-compile static daemon for armv7hl"

(cd "$DAEMON_SRC" && \
  GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  ~/toolchain/go/bin/go build -ldflags '-s -w' -o "$DAEMON_SRC/musicfox-daemon" .)

if file "$DAEMON_SRC/musicfox-daemon" | grep -qi "ARM.*statically"; then
    echo "   ✅ Daemon built successfully for ARM"
    file "$DAEMON_SRC/musicfox-daemon"
else
    echo "   ❌ ERROR: Daemon not built for ARM!"
    exit 1
fi

# === Step 2: Build Qt app + assemble RPM in Sailfish Platform SDK ===
echo "==> Step 2: Build Qt application and assemble RPM in Sailfish Platform SDK"

# Pull the SDK container if not already available
echo "   Pulling Sailfish Platform SDK container..."
docker pull "coderus/sailfishos-platform-sdk:${SFOS_RELEASE}" 2>&1 | tail -3

# Create a working directory for output
mkdir -p "$ROOT/out"

echo "   Running MB2 build inside container..."
docker run --rm \
  -v "$ROOT":/src \
  -w /src \
  "coderus/sailfishos-platform-sdk:${SFOS_RELEASE}" \
  /bin/bash -c "
    set -e
    echo 'Setting up build environment...'
    # Ensure the daemon is properly placed
    cp /src/daemon/musicfox-daemon /src/daemon/musicfox-daemon.armv7hl 2>/dev/null || true
    
    echo 'Running mb2 build for armv7hl...'
    mb2 -t \"SailfishOS-${SFOS_RELEASE}-armv7hl\" build -s packaging/harbour-musicfox.spec
    
    echo 'Copying RPM to output directory...'
    mkdir -p /src/out
    cp -r RPMBUILD/RPMS/* /src/out/ 2>/dev/null || true
    find /src/out -name \"*.rpm\" -print
  " 2>&1 | tee /tmp/build-output.log

# Verify the RPM was built
OUT_RPM=$(find "$ROOT/out" -name "*.armv7hl.rpm" | head -1)

if [ -z "$OUT_RPM" ]; then
    echo "   ❌ ERROR: No armv7hl RPM was produced"
    echo "   Build log:"
    cat /tmp/build-output.log | tail -50
    exit 1
fi

# Copy to a proper name if needed
FINAL_RPM="$ROOT/${BIN}-${VERSION}-${RELEASE}.${ARCH}.rpm"
cp "$OUT_RPM" "$FINAL_RPM"

echo "==> DONE: $FINAL_RPM"
echo "    Installing RPM requires:"
rpm -qp --requires "$FINAL_RPM" 2>/dev/null | grep -E "(GLIBC|sailfish|qt5|silica|mpris)" | sort | sed 's/^/      /'
