import argparse
from pathlib import Path
import shutil


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError("Shared source has changed; expected exactly one occurrence of: " + old)
    return source.replace(old, new, 1)


def replace_section(source, beginning, ending, replacement=""):
    if source.count(beginning) != 1 or source.count(ending) != 1:
        raise ValueError("Shared QML section boundaries have changed")
    start = source.index(beginning)
    finish = source.index(ending, start)
    return source[:start] + replacement + source[finish:]


def main():
    parser = argparse.ArgumentParser(description="Generate LuneOS sources without modifying Sailfish files")
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    source_directory = arguments.source.resolve()
    output_directory = arguments.output.resolve()
    if output_directory == source_directory or source_directory in output_directory.parents:
        parser.error("The output directory must not be inside the shared Sailfish app directory")
    qml_directory = arguments.output / "qml"
    qml_directory.mkdir(parents=True, exist_ok=True)
    source = (arguments.source / "qml/harbour-musicfox.qml").read_text(encoding="utf-8")
    source = replace_once(source, "import Sailfish.Silica 1.0\n", "")
    source = replace_once(source, "import org.nemomobile.mpris 1.0\n", "")
    source = replace_once(source, "ApplicationWindow {", "Item {")
    source = replace_once(source, "    allowedOrientations: Orientation.All\n", "")
    source = replace_once(source, "    property int mprisDbg: 1\n", "")
    source = replace_section(source, "    // Cover shown on the system desktop card", "    NeteaseApi { id: api }")
    source = replace_section(source, "    // MPRIS interface: lets the system", "    property var pageHistory: []")
    source = source.replace("for Sailfish OS", "for LuneOS")
    (qml_directory / "main.qml").write_text(source, encoding="utf-8")
    for name in [
        "FrostedBackground.qml", "GlassPanel.qml", "VinylDisc.qml", "BaguaDial.qml",
        "KtvLyrics.qml", "SpectrumBars.qml", "kitty-dark.png", "trigram-recolored2.png", "taiji-disc.png",
    ]:
        shutil.copyfile(arguments.source / "qml" / name, qml_directory / name)
    pulse = (arguments.source / "src/pulselevels.cpp").read_text(encoding="utf-8")
    pulse = replace_once(
        pulse,
        'if (!name.startsWith("sink.") || !name.endsWith(".monitor")) continue;',
        'if (name != qEnvironmentVariable("MUSICFOX_PULSE_MONITOR", "pcm_output.monitor")) continue;',
    )
    (arguments.output / "pulselevels.cpp").write_text(pulse, encoding="utf-8")
    cover = (arguments.source / "src/covercache.cpp").read_text(encoding="utf-8")
    cover = replace_once(
        cover,
        "req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);",
        "req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);",
    )
    (arguments.output / "covercache.cpp").write_text(cover, encoding="utf-8")
    api = (arguments.source / "src/neteaseapi.cpp").read_text(encoding="utf-8")
    api = replace_section(
        api,
        '    QString daemonPath = "/usr/local/bin/musicfox-daemon";',
        "    connect(m_process, SIGNAL(readyReadStandardOutput())",
        '    const QString bundledDaemon = QCoreApplication::applicationDirPath() + "/../libexec/musicfox-daemon";\n'
        '    QString daemonPath = qEnvironmentVariable("MUSICFOX_DAEMON", bundledDaemon);\n\n',
    )
    (arguments.output / "neteaseapi.cpp").write_text(api, encoding="utf-8")


if __name__ == "__main__":
    main()
