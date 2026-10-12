#include <QGuiApplication>
#include <QQuickView>
#include <QUrl>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QDebug>
#include "neteaseapi.h"
#include "mpvcontroller.h"
#include "playqueue.h"
#include "lyricsync.h"
#include "covercache.h"
#include "pulselevels.h"

static QFile *logFile = nullptr;

void messageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    Q_UNUSED(type);
    Q_UNUSED(context);
    QByteArray ba = msg.toUtf8() + "\n";
    if (logFile && logFile->isOpen()) {
        logFile->write(ba);
        logFile->flush();
    }
    fprintf(stderr, "%s", ba.constData());
}

int main(int argc, char *argv[])
{
    QString logDir = QDir::homePath() + "/.local/share";
    QDir().mkpath(logDir);
    logFile = new QFile(logDir + "/musicfox.log");
    logFile->open(QIODevice::WriteOnly | QIODevice::Truncate);
    qInstallMessageHandler(messageHandler);

    qDebug() << "=== MusicFox starting (Lomiri / Qt5) ===";

    QGuiApplication app(argc, argv);
    app.setApplicationName("musicfox");
    app.setApplicationDisplayName("MusicFox");
    app.setOrganizationName("musicfox");
    app.setApplicationVersion("0.5.0");

    qmlRegisterType<NeteaseApi>("harbour.musicfox", 1, 0, "NeteaseApi");
    qmlRegisterType<MpvController>("harbour.musicfox", 1, 0, "MpvController");
    qmlRegisterType<PlayQueue>("harbour.musicfox", 1, 0, "PlayQueue");
    qmlRegisterType<LyricSync>("harbour.musicfox", 1, 0, "LyricSync");
    qmlRegisterType<CoverCache>("harbour.musicfox", 1, 0, "CoverCache");
    qmlRegisterType<PulseLevels>("harbour.musicfox", 1, 0, "PulseLevels");

    qDebug() << "Types registered, creating view...";

    QQuickView view;
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    // The main QML file is embedded in the Qt resource bundle (qml.qrc),
    // not installed as a separate file, so load it from qrc directly.
    view.setSource(QUrl("qrc:///qml/harbour-musicfox.qml"));

    if (view.status() == QQuickView::Error) {
        qWarning() << "Failed to load QML";
        return -1;
    }

    view.showFullScreen();

    qDebug() << "View shown, entering event loop";
    return app.exec();
}