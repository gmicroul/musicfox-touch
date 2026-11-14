import argparse
import hashlib
import lzma
from pathlib import Path
import platform
import re
import subprocess
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor


def download(url, destination):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=90) as response:
                with destination.with_suffix(destination.suffix + ".part").open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
            destination.with_suffix(destination.suffix + ".part").replace(destination)
            return
        except OSError:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def read_index(index):
    packages = {}
    fields = {}
    with lzma.open(index, "rt", encoding="utf-8") as source:
        for line in source:
            if line == "\n":
                if "Package" in fields:
                    packages[fields["Package"]] = fields
                fields = {}
            elif not line.startswith(" "):
                name, separator, value = line.partition(": ")
                if separator and name in {"Package", "Depends", "Pre-Depends", "Provides", "Filename", "SHA256"}:
                    fields[name] = value.strip()
    return packages


def resolve(packages, requested):
    selected = {}
    pending = list(requested)
    providers = {}
    for package in packages.values():
        for provided in package.get("Provides", "").split(","):
            if provided.strip():
                providers.setdefault(provided.strip().split(" ")[0], package["Package"])
    excluded = re.compile(r"^(libc6(?:-.*)?|libc-dev-bin|linux-libc-dev|libstdc\+\+6|libgcc-s1|gcc-\d+-base)$")
    while pending:
        name = pending.pop()
        if name in selected or excluded.fullmatch(name):
            continue
        package = packages[name]
        selected[name] = package
        for field in ["Pre-Depends", "Depends"]:
            for dependency in package.get(field, "").split(","):
                alternatives = [choice.strip().split(" ")[0].split(":")[0] for choice in dependency.split("|")]
                available = [choice if choice in packages or excluded.fullmatch(choice) else providers[choice]
                             for choice in alternatives if choice in packages or excluded.fullmatch(choice) or choice in providers]
                if available:
                    pending.append(available[0])
                elif dependency.strip():
                    raise RuntimeError("Cannot resolve dependency: " + dependency)
    return selected


def main():
    parser = argparse.ArgumentParser(description="Extract a native Debian Qt6 build SDK without installing system packages")
    parser.add_argument("--directory", type=Path, default=Path(__file__).resolve().parent / ".sdk")
    arguments = parser.parse_args()
    architecture = {"aarch64": "arm64", "x86_64": "amd64"}.get(platform.machine())
    if architecture is None:
        parser.error("Supported native hosts are aarch64 and x86_64")
    directory = arguments.directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    cache = directory / "packages"
    cache.mkdir(exist_ok=True)
    mirror = "https://deb.debian.org/debian/"
    index = cache / ("bookworm-" + architecture + "-Packages.xz")
    if not index.exists():
        print("Downloading Debian bookworm " + architecture + " package index", flush=True)
        download(mirror + "dists/bookworm/main/binary-" + architecture + "/Packages.xz", index)
    packages = read_index(index)
    selected = resolve(packages, [
        "qt6-base-dev", "qt6-base-dev-tools", "qt6-declarative-dev", "qt6-multimedia-dev",
        "qml6-module-qtquick", "qml6-module-qtquick-window", "qml6-module-qtqml-workerscript",
        "qml6-module-qtqml", "qml6-module-qtqml-models",
    ])

    def fetch(package):
        archive = cache / Path(package["Filename"]).name
        if not archive.exists():
            print("Downloading " + package["Package"], flush=True)
            download(mirror + package["Filename"], archive)
        with archive.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        if digest != package["SHA256"]:
            raise RuntimeError("SHA256 mismatch: " + str(archive))
        return archive

    with ThreadPoolExecutor(max_workers=4) as executor:
        archives = list(executor.map(fetch, selected.values()))
    for archive in archives:
        members = subprocess.check_output(["ar", "t", str(archive)], text=True).splitlines()
        member = next(name for name in members if name.startswith("data.tar"))
        compression = {".xz": "-J", ".gz": "-z", ".zst": "--zstd"}.get(Path(member).suffix)
        command = ["tar", "--no-same-owner"]
        if compression:
            command.append(compression)
        command.extend(["-xf", "-", "-C", str(directory)])
        with subprocess.Popen(["ar", "p", str(archive), member], stdout=subprocess.PIPE) as unpacker:
            subprocess.run(command, stdin=unpacker.stdout, check=True)
            unpacker.stdout.close()
            if unpacker.wait() != 0:
                raise RuntimeError("Failed to extract " + str(archive))
    print("Qt6 SDK extracted to " + str(directory / "usr"), flush=True)


if __name__ == "__main__":
    main()
