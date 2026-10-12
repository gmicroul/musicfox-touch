#!/usr/bin/env python3
"""Build a self-contained arm64 .deb for MusicFox Touch (Ubuntu Touch / Lomiri).

The device has no Sailfish SDK and no Qt5 multimedia backend, so the package
bundles:
  * the Qt/QML app (links only the system Qt5 runtime)
  * the static Go NetEase API daemon
  * mpv plus the handful of shared libraries that are missing from the system

Everything lands under /usr/lib/musicfox-touch; nothing outside /usr is touched.
dpkg-deb is unusable here (it shells out to GNU tar, which returns ENOSYS on
this kernel), so the ar/tar container is written directly.
"""
import io
import os
import shutil
import stat
import subprocess
import sys
import tarfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(REPO, "build", "deb")
STAGE = os.path.join(BUILD, "musicfox-touch")
MPV_PREFIX = os.path.expanduser("~/opt/mpv")
MPV_LIBDIR = os.path.join(MPV_PREFIX, "usr/lib/aarch64-linux-gnu")
INST_LIBDIR = "/usr/lib/aarch64-linux-gnu"

PACKAGE = "musicfox-touch"
VERSION = "0.5.0"
RELEASE = "5"
ARCH = "arm64"
MAINTAINER = "musicfox-touch <gmicroul@users.noreply.github.com>"
SECTION = "sound"
PRIORITY = "optional"

CORE_DEPS = [
    "libc6", "libgcc-s1", "libstdc++6",
    "libqt5core5t64", "libqt5gui5-gles", "libqt5qml5", "libqt5quick5-gles",
    "libqt5network5t64",
    "qml-module-qtquick2",       # import QtQuick 2.6
    "pulseaudio-utils",         # parec, used by the level visualiser
    "libpulse0", "libasound2t64",
]

INST_MPV_LIBDIR = "/usr/lib/musicfox-touch/mpv/usr/lib/aarch64-linux-gnu"
INST_ICON = "/usr/share/icons/hicolor/512x512/apps/musicfox.png"

LAUNCHER = """#!/bin/sh
# MusicFox Touch launcher (Ubuntu Touch / Lomiri).
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-ubuntumirclient}"
[ "$QT_QPA_PLATFORM" = "mirserver" ] && export QT_QPA_PLATFORM=ubuntumirclient
export LD_LIBRARY_PATH="@INST_LIBDIR@${LD_LIBRARY_PATH}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user$(id -u)}"
exec /usr/lib/musicfox-touch/musicfox-bin "$@"
"""

MPV_WRAPPER = """#!/bin/sh
export LD_LIBRARY_PATH="@INST_LIBDIR@${LD_LIBRARY_PATH}"
exec /usr/lib/musicfox-touch/mpv/usr/bin/mpv "$@"
"""


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def sonames(binary):
    out = run(["readelf", "-d", binary]).stdout
    res = []
    for line in out.splitlines():
        if "NEEDED" in line and "[" in line:
            res.append(line.split("[")[1].split("]")[0])
    return res


def bundle_closure(root):
    """mpv + every lib it needs that is not provided by the system."""
    env = dict(os.environ, LD_LIBRARY_PATH=MPV_LIBDIR)
    seen, queue, bundled = set(), [root], []
    while queue:
        path = queue.pop()
        if path in seen:
            continue
        seen.add(path)
        bundled.append(path)
        for line in run(["ldd", path], env=env).stdout.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[2].startswith(MPV_LIBDIR + os.sep):
                queue.append(parts[2])
    return sorted(bundled)


def package_for(soname):
    out = run(["dpkg", "-S", soname]).stdout.strip()
    if not out:
        return None
    name = out.split(":")[0].split(",")[0].strip()
    if name in ("libc6-dev", "libc-dev") or name == PACKAGE:
        return None  # libc6-dev, or a lib we bundle inside this very package
    return name


def exists_in_archive(pkg):
    out = run(["apt-cache", "show", pkg]).stdout
    return bool(out.strip())


def write(path, content, mode=0o644):
    full = os.path.join(STAGE, path.lstrip("/"))
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(full, mode)


def copy(src, path, mode=0o755):
    full = os.path.join(STAGE, path.lstrip("/"))
    os.makedirs(os.path.dirname(full), exist_ok=True)
    shutil.copy2(src, full)
    os.chmod(full, mode)


def desktop_entry(exec_path, icon_path):
    return f"""[Desktop Entry]
Type=Application
Name=MusicFox
Name[zh_CN]=MusicFox 音乐
Comment=NetEase Cloud Music player
Comment[zh_CN]=网易云音乐播放器
Exec={exec_path}
Icon={icon_path}
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=music;netease;audio;player;
StartupNotify=true
"""


def add_tree(tf, root, prefix, arc_prefix):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        rel = os.path.relpath(dirpath, root)
        if rel == ".":
            arc = arc_prefix
        else:
            arc = os.path.join(arc_prefix, rel)
        info = tf.gettarinfo(dirpath, arc + "/")
        info.type = tarfile.DIRTYPE
        info.mode = 0o755
        tf.addfile(info)
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            arc_file = os.path.join(arc, name)
            info = tf.gettarinfo(full, arc_file)
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mode = 0o755 if (info.mode & stat.S_IXUSR) else 0o644
            with open(full, "rb") as fh:
                tf.addfile(info, fh)


def ar_archive(members, out_path):
    with open(out_path, "wb") as out:
        out.write(b"!<arch>\n")
        for name, data in members:
            hdr = "%-16s%-12d%-6d%-6d%-8o%-10d`\n" % (name, 0, 0, 0, 0o100644, len(data))
            out.write(hdr.encode())
            out.write(data)
            if len(data) % 2:
                out.write(b"\n")


def main():
    app = os.path.join(REPO, "app", "harbour-musicfox")
    daemon = os.path.join(REPO, "daemon", "musicfox-daemon")
    for f in (app, daemon):
        if not os.access(f, os.X_OK):
            sys.exit("missing %s - run tools/build-ut.sh and build the daemon" % f)

    shutil.rmtree(BUILD, ignore_errors=True)
    os.makedirs(STAGE)

    copy(app, "/usr/lib/musicfox-touch/musicfox-bin")
    copy(daemon, "/usr/lib/musicfox-touch/musicfox-daemon")
    write("/usr/bin/musicfox-touch", LAUNCHER.replace("@INST_LIBDIR@", INST_MPV_LIBDIR), 0o755)
    write("/usr/lib/musicfox-touch/musicfox-mpv", MPV_WRAPPER.replace("@INST_LIBDIR@", INST_MPV_LIBDIR), 0o755)
    write("/usr/bin/musicfox-touch-mpv", MPV_WRAPPER.replace("@INST_LIBDIR@", INST_MPV_LIBDIR), 0o755)

    mpv_root = os.path.join(MPV_PREFIX, "usr/bin/mpv")
    closure = bundle_closure(mpv_root)
    if len(closure) < 5:
        sys.exit("mpv library closure looks wrong (%d files) - is ~/opt/mpv intact?"
                 % len(closure))
    for src in closure:
        rel = os.path.relpath(src, MPV_PREFIX)
        copy(src, "/usr/lib/musicfox-touch/mpv/" + rel)

    # The icon shipped in the package is the one the user actually wants
    # (app/assets/musicfox.png). The old green placeholder SVG is deliberately
    # not installed: on Lomiri it can shadow the real icon.
    icon = os.path.join(REPO, "app/assets/musicfox.png")
    copy(icon, INST_ICON, 0o644)
    write("/usr/share/applications/musicfox-touch.desktop",
          desktop_entry("/usr/bin/musicfox-touch", INST_ICON))

    readme_path = os.path.join(REPO, "README.md")
    readme = ""
    if os.path.exists(readme_path):
        with open(readme_path, encoding="utf-8") as f:
            readme = f.read()
    write("/usr/share/doc/musicfox-touch/README.md", readme or "MusicFox Touch\n", 0o644)

    # dependencies: core set + external mpv libs that exist in the archive
    deps = list(CORE_DEPS)
    for soname in sonames(mpv_root):
        pkg = package_for(soname)
        if pkg and pkg not in deps and exists_in_archive(pkg):
            deps.append(pkg)
    deps = sorted(set(deps))

    installed_kb = int(run(["du", "-sk", STAGE]).stdout.split()[0])

    control = f"""Package: {PACKAGE}
Version: {VERSION}
Section: {SECTION}
Priority: {PRIORITY}
Architecture: {ARCH}
Maintainer: {MAINTAINER}
Installed-Size: {installed_kb}
Depends: {', '.join(deps)}
Description: NetEase Cloud Music player for Ubuntu Touch
 MusicFox Touch is a QML music player for the NetEase Cloud Music service,
 built for Ubuntu Touch / Lomiri on aarch64. Playback is handled by a bundled
 mpv, API requests by a bundled static Go daemon.
 .
 This package is self-contained apart from the Qt5 runtime already present on
 the device; it installs into /usr/lib/musicfox and /usr/bin.
"""

    md5sums = []
    for dirpath, dirnames, filenames in os.walk(STAGE):
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            arc = os.path.relpath(full, STAGE)
            digest = run(["md5sum", full]).stdout.split()[0]
            md5sums.append(f"{digest}  {arc}")
    md5sums.sort(key=lambda line: line.split("  ", 1)[1])

    ctrl_buf = io.BytesIO()
    with tarfile.open(fileobj=ctrl_buf, mode="w:gz", format=tarfile.GNU_FORMAT) as tf:
        for name, text in (("./control", control),
                           ("./md5sums", "\n".join(md5sums) + "\n")):
            data = text.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = int(time.time())
            tf.addfile(info, io.BytesIO(data))

    data_buf = io.BytesIO()
    with tarfile.open(fileobj=data_buf, mode="w:gz", format=tarfile.GNU_FORMAT) as tf:
        add_tree(tf, STAGE, STAGE, ".")

    out = os.path.join(BUILD, f"{PACKAGE}_{VERSION}-{RELEASE}_{ARCH}.deb")
    ar_archive([("debian-binary", b"2.0\n"),
                ("control.tar.gz", ctrl_buf.getvalue()),
                ("data.tar.gz", data_buf.getvalue())], out)

    print(f"packages: {len(deps)} dependencies")
    print(f"payload:  {installed_kb / 1024:.1f} MiB staged")
    print(f"deb:      {out} ({os.path.getsize(out) / 1048576:.1f} MiB)")
    print("\ninstall with:\n  sudo dpkg -i " + os.path.basename(out))


if __name__ == "__main__":
    main()