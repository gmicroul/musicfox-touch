#include <QGuiApplication>
#include <QQuickView>
#include <QUrl>
#include <QDir>
#include <QFile>
#include <QDebug>
#include "neteaseapi.h"
#include "mpvcontroller.h"
#include "playqueue.h"
#include "lyricsync.h"
#include "covercache.h"
#include "pulselevels.h"

// The standard sailfishapp.h header is not installed in this build
// environment, so declare the SailfishApp symbols we use manually.
// They are provided by libsailfishapp (linked via LIBS += -lsailfishapp).
namespace SailfishApp {
    QGuiApplication *application(int &argc, char **argv);
    QQuickView *createView();
    QUrl pathToMainQml();
}

// The mapplauncherd silica-qt5 booster looks this symbol up via dlsym()
// and calls it to bring up the application as a proper Silica app window
// (which is what connects our Cover to the lipstick desktop cards).
extern "C" int sailfishapp_main(int argc, char *argv[]);

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

int sailfishapp_main(int argc, char *argv[])
{
    logFile = new QFile("/tmp/musicfox.log");
    logFile->open(QIODevice::WriteOnly | QIODevice::Truncate);
    qInstallMessageHandler(messageHandler);

    qDebug() << "=== MusicFox starting (Silica) ===";

    QGuiApplication *app = SailfishApp::application(argc, argv);
    app->setApplicationName("harbour-musicfox");
    app->setOrganizationName("harbour-musicfox");

    qmlRegisterType<NeteaseApi>("harbour.musicfox", 1, 0, "NeteaseApi");
    qmlRegisterType<MpvController>("harbour.musicfox", 1, 0, "MpvController");
    qmlRegisterType<PlayQueue>("harbour.musicfox", 1, 0, "PlayQueue");
    qmlRegisterType<LyricSync>("harbour.musicfox", 1, 0, "LyricSync");
    qmlRegisterType<CoverCache>("harbour.musicfox", 1, 0, "CoverCache");
    qmlRegisterType<PulseLevels>("harbour.musicfox", 1, 0, "PulseLevels");

    qDebug() << "Types registered, creating Silica view...";

    QQuickView *view = SailfishApp::createView();
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    // The main QML file is embedded in the Qt resource bundle (qml.qrc),
    // not installed as a separate file, so load it from qrc directly.
    view->setSource(QUrl("qrc:///qml/harbour-musicfox.qml"));

    if (view->status() == QQuickView::Error) {
        qWarning() << "Failed to load QML";
        return -1;
    }

    view->showFullScreen();

    qDebug() << "View shown, entering event loop";
    return app->exec();
}

int main(int argc, char *argv[])
{
    return sailfishapp_main(argc, argv);
}
