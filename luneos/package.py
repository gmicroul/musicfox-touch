import argparse
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile


def root_owner(member):
    member.uid = 0
    member.gid = 0
    member.uname = "root"
    member.gname = "root"
    return member


def main():
    parser = argparse.ArgumentParser(description="Package the LuneOS install tree as an IPK")
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    architecture = platform.machine()
    installed_size = sum((item.stat().st_size + 1023) // 1024 for item in root.rglob("*") if item.is_file())
    archive = output / ("musicfox-touch-luneos_0.5.0-1_" + architecture + ".ipk")
    with tempfile.TemporaryDirectory(prefix="musicfox-ipk-") as temporary:
        directory = Path(temporary)
        control = directory / "control"
        control.mkdir()
        (control / "control").write_text(
            "Package: org.musicfox.touch\n"
            "Version: 0.5.0-1\n"
            "Architecture: " + architecture + "\n"
            "Installed-Size: " + str(installed_size) + "\n"
            "Maintainer: MusicFox\n"
            "Section: multimedia\n"
            "Priority: optional\n"
            "Description: MusicFox touch music player for LuneOS, with NetEase Cloud Music\n"
            " Requires system Qt6 >= 6.4, QtQuick, QtMultimedia, webOS Wayland and PulseAudio.\n",
            encoding="utf-8",
        )
        with tarfile.open(directory / "control.tar.gz", "w:gz", format=tarfile.GNU_FORMAT) as bundle:
            bundle.add(control / "control", arcname="./control", filter=root_owner)
        with tarfile.open(directory / "data.tar.gz", "w:gz", format=tarfile.GNU_FORMAT) as bundle:
            for child in sorted(root.iterdir()):
                bundle.add(child, arcname="./" + child.name, filter=root_owner)
        (directory / "debian-binary").write_text("2.0\n", encoding="ascii")
        subprocess.run(
            ["ar", "rc", str(archive), "debian-binary", "control.tar.gz", "data.tar.gz"],
            cwd=directory, check=True,
        )
    print(archive)


if __name__ == "__main__":
    main()
