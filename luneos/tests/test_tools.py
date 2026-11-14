import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


def load_module(name, filename):
    specification = importlib.util.spec_from_file_location(name, ROOT / filename)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


generator = load_module("generator", "generate-sources.py")
bootstrap = load_module("bootstrap", "bootstrap-qt6.py")
installer = load_module("installer", "install.py")


class SourceTests(unittest.TestCase):
    def test_unique_replacements(self):
        self.assertEqual(generator.replace_once("before marker after", "marker", "native"), "before native after")
        with self.assertRaises(ValueError):
            generator.replace_once("marker marker", "marker", "native")
        with self.assertRaises(ValueError):
            generator.replace_section("unchanged", "start", "finish")

    def test_generation_preserves_sailfish(self):
        source = ROOT.parent / "app"
        names = ["qml/harbour-musicfox.qml", "src/neteaseapi.cpp", "src/covercache.cpp", "src/pulselevels.cpp"]
        before = {name: hashlib.sha256((source / name).read_bytes()).digest() for name in names}
        with tempfile.TemporaryDirectory() as temporary:
            subprocess.run([sys.executable, str(ROOT / "generate-sources.py"), str(source), temporary], check=True)
            output = Path(temporary)
            qml = (output / "qml/main.qml").read_text(encoding="utf-8")
            self.assertNotIn("Sailfish.Silica", qml)
            self.assertNotIn("org.nemomobile.mpris", qml)
            self.assertNotIn("CoverAction", qml)
            self.assertIn("Item {", qml)
            self.assertIn("api.getSongUrl", qml)
            self.assertIn("NoLessSafeRedirectPolicy", (output / "covercache.cpp").read_text())
            self.assertIn("MUSICFOX_PULSE_MONITOR", (output / "pulselevels.cpp").read_text())
            self.assertNotIn("/usr/local/bin", (output / "neteaseapi.cpp").read_text())
            self.assertEqual((output / "qml/VinylDisc.qml").read_bytes(), (source / "qml/VinylDisc.qml").read_bytes())
        after = {name: hashlib.sha256((source / name).read_bytes()).digest() for name in names}
        self.assertEqual(before, after)

    def test_output_cannot_overwrite_sailfish(self):
        source = ROOT.parent / "app"
        result = subprocess.run(
            [sys.executable, str(ROOT / "generate-sources.py"), str(source), str(source)],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("must not be inside", result.stderr)


class PackageTests(unittest.TestCase):
    def test_luna_call_keeps_stdin_open(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            sender = directory / "luna-send"
            sender.write_text(
                "#!" + sys.executable + "\n"
                "import json, select, sys\n"
                "ready = select.select([sys.stdin], [], [], 0)[0]\n"
                "print(json.dumps({'returnValue': not bool(ready)}))\n"
            )
            sender.chmod(0o755)
            environment = os.environ.copy()
            environment["PATH"] = str(directory) + os.pathsep + environment["PATH"]
            result = subprocess.run(
                ["sh", str(ROOT / "packaging/luna-call"), "luna://test/service", "{}"],
                env=environment, capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('"returnValue": true', result.stdout)

    def test_virtual_dependencies_and_host_libc(self):
        packages = {
            "development": {"Package": "development", "Depends": "qt6-base-abi (= 6.4.2), libc6 (>= 2.34)"},
            "runtime": {"Package": "runtime", "Provides": "qt6-base-abi (= 6.4.2)"},
        }
        self.assertEqual(set(bootstrap.resolve(packages, ["development"])), {"development", "runtime"})

    def test_ipk_metadata_and_ownership(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            root = directory / "root"
            application = root / "usr/palm/applications/org.musicfox.touch"
            application.mkdir(parents=True)
            (application / "appinfo.json").write_text('{"id":"org.musicfox.touch"}')
            output = directory / "output"
            subprocess.run([sys.executable, str(ROOT / "package.py"), str(root), str(output)], check=True, capture_output=True)
            archive = next(output.glob("*.ipk"))
            members = subprocess.check_output(["ar", "t", str(archive)], text=True).splitlines()
            self.assertEqual(members, ["debian-binary", "control.tar.gz", "data.tar.gz"])
            control_bytes = subprocess.check_output(["ar", "p", str(archive), "control.tar.gz"])
            with tarfile.open(fileobj=io.BytesIO(control_bytes), mode="r:gz") as control:
                metadata = control.extractfile("./control").read().decode("utf-8")
                self.assertIn("Package: org.musicfox.touch", metadata)
                self.assertIn("Installed-Size:", metadata)
                self.assertNotIn("\nDepends:", metadata)
                self.assertIn("Requires system Qt6 >= 6.4", metadata)
                self.assertNotIn("./postinst", control.getnames())
            data_bytes = subprocess.check_output(["ar", "p", str(archive), "data.tar.gz"])
            with tarfile.open(fileobj=io.BytesIO(data_bytes), mode="r:gz") as data:
                self.assertTrue(all(member.uid == 0 and member.gid == 0 for member in data.getmembers()))
                self.assertIsNotNone(data.getmember("./usr/palm/applications/org.musicfox.touch/appinfo.json"))


class InstallTests(unittest.TestCase):
    def run_install(self, responses):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            sender = directory / "luna-send"
            sender.write_text(
                "#!" + sys.executable + "\n"
                "import json, select, sys\n"
                "ready = select.select([sys.stdin], [], [], 0)[0]\n"
                "if ready:\n"
                "    print(json.dumps({'returnValue': False, 'errorText': 'stdin closed'}))\n"
                "    sys.exit(1)\n"
                "for response in " + repr(responses) + ":\n"
                "    print(json.dumps(response), flush=True)\n"
            )
            sender.chmod(0o755)
            package = directory / "test.ipk"
            package.touch()
            environment = os.environ.copy()
            environment["PATH"] = str(directory) + os.pathsep + environment["PATH"]
            program = "import sys; sys.path.insert(0, " + repr(str(ROOT)) + "); import install; install.prepare = lambda package: None; sys.exit(install.main())"
            return subprocess.run(
                [sys.executable, "-c", program, str(package)],
                env=environment, capture_output=True, text=True, timeout=10,
            )

    def test_waits_for_installed_event(self):
        result = self.run_install([
            {"returnValue": True, "subscribed": True},
            {"id": "unrelated.app", "details": {"state": "installed"}},
            {"id": "org.musicfox.touch", "details": {"state": "installing"}},
            {"id": "org.musicfox.touch", "details": {"state": "installed"}},
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MusicFox install: installed", result.stdout)

    def test_acknowledgment_is_not_installation(self):
        result = self.run_install([{"returnValue": True, "subscribed": True}])
        self.assertEqual(result.returncode, 1)
        self.assertIn("without confirming installation", result.stderr)

    def test_reports_installation_error(self):
        result = self.run_install([
            {"returnValue": True, "subscribed": True},
            {"id": "org.musicfox.touch", "details": {"state": "install failed", "reason": "appId is wrong"}},
        ])
        self.assertEqual(result.returncode, 1)
        self.assertIn("appId is wrong", result.stderr)

    def test_reports_service_error(self):
        result = self.run_install([{"returnValue": False, "errorText": "Access denied"}])
        self.assertEqual(result.returncode, 1)
        self.assertIn("Access denied", result.stderr)


class InstallPreparationTests(unittest.TestCase):
    def run_prepare(self, architecture="aarch64", qt_version="6.12.0", configured=False):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        configuration = Path(directory.name) / "opkg.conf"
        configuration.write_text("option status_file /var/lib/opkg/status\n")
        original = configuration.read_bytes()
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as control:
            metadata = ("Package: org.musicfox.touch\nArchitecture: " + architecture + "\n").encode()
            member = tarfile.TarInfo("./control")
            member.size = len(metadata)
            control.addfile(member, io.BytesIO(metadata))
        installed = "\n".join(name + " - " + qt_version for name in installer.SYSTEM_PACKAGES)
        responses = [buffer.getvalue(), installed, "arch all 1\narch " + ("aarch64" if configured else "x86_64") + " 10\n"]
        if not configured:
            responses.append("arch all 1\narch aarch64 16\n")
        with patch.object(installer.platform, "machine", return_value="aarch64"), \
                patch.object(installer.subprocess, "check_output", side_effect=responses):
            installer.prepare(Path("test.ipk"), configuration)
        return configuration, original

    def test_adds_native_architecture_with_backup(self):
        configuration, original = self.run_prepare()
        self.assertIn("arch aarch64 16", configuration.read_text())
        self.assertEqual(configuration.with_name("opkg.conf.musicfox-backup").read_bytes(), original)

    def test_preserves_configured_installer(self):
        configuration, original = self.run_prepare(configured=True)
        self.assertEqual(configuration.read_bytes(), original)
        self.assertFalse(configuration.with_name("opkg.conf.musicfox-backup").exists())

    def test_rejects_wrong_architecture(self):
        with self.assertRaisesRegex(RuntimeError, "for aarch64"):
            self.run_prepare(architecture="x86_64")

    def test_rejects_qt5(self):
        with self.assertRaisesRegex(RuntimeError, "Qt6 >= 6.4"):
            self.run_prepare(qt_version="5.15.2")


if __name__ == "__main__":
    unittest.main()
