#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickView>
#include <QScreen>
#include <QTimer>
#include <QDebug>
#include "neteaseapi.h"
#include "mpvcontroller.h"
#include "playqueue.h"
#include "lyricsync.h"
#include "covercache.h"
#include "pulselevels.h"

int main(int argc, char *argv[])
{
    bool smokeTest = false;
    QString audioTest;
    QString searchTest;
    for (int index = 1; index < argc; ++index) {
        const QString argument = QString::fromLocal8Bit(argv[index]);
        if (argument == "--smoke-test")
            smokeTest = true;
        if (argument == "--test-audio" && index + 1 < argc)
            audioTest = QString::fromLocal8Bit(argv[++index]);
        if (argument == "--test-search" && index + 1 < argc)
            searchTest = QString::fromLocal8Bit(argv[++index]);
    }
    if (smokeTest || !audioTest.isEmpty() || !searchTest.isEmpty()) {
        qputenv("QT_QPA_PLATFORM", "offscreen");
        qputenv("QT_QUICK_BACKEND", "software");
    }
    QGuiApplication application(argc, argv);
    application.setApplicationName("musicfox-touch");
    application.setOrganizationName("MusicFox.LuneOS");
    application.setDesktopFileName("org.musicfox.touch");
    application.setApplicationVersion("0.5.0");

    qmlRegisterType<NeteaseApi>("harbour.musicfox", 1, 0, "NeteaseApi");
    qmlRegisterType<MpvController>("harbour.musicfox", 1, 0, "MpvController");
    qmlRegisterType<PlayQueue>("harbour.musicfox", 1, 0, "PlayQueue");
    qmlRegisterType<LyricSync>("harbour.musicfox", 1, 0, "LyricSync");
    qmlRegisterType<CoverCache>("harbour.musicfox", 1, 0, "CoverCache");
    qmlRegisterType<PulseLevels>("harbour.musicfox", 1, 0, "PulseLevels");

    QQuickView view;
    view.setTitle("MusicFox");
    view.setProperty("appId", "org.musicfox.touch");
    view.setProperty("_WEBOS_WINDOW_TYPE", "card");
    view.setResizeMode(QQuickView::SizeRootObjectToView);
    if (application.primaryScreen())
        view.resize(application.primaryScreen()->size());
    else
        view.resize(540, 960);
    view.setSource(QUrl("qrc:/qml/main.qml"));
    if (view.status() == QQuickView::Error || !view.rootObject())
        return 1;
    view.showFullScreen();

    if (!audioTest.isEmpty()) {
        auto *player = view.rootObject()->findChild<MpvController *>();
        if (!player)
            return 1;
        player->setVolume(0);
        QObject::connect(player, &MpvController::positionChanged, &application, [player, &application] {
            if (player->position() >= 0.25) {
                qInfo() << "MUSICFOX_AUDIO_OK position" << player->position();
                application.exit(0);
            }
        });
        QObject::connect(player, &MpvController::endOfFile, &application, [&application] {
            qInfo() << "MUSICFOX_AUDIO_OK";
            application.exit(0);
        });
        QObject::connect(player, &MpvController::mpvError, &application, [&application] {
            application.exit(1);
        });
        QTimer::singleShot(15000, &application, [&application] { application.exit(1); });
        QTimer::singleShot(0, player, [player, audioTest] { player->loadFile(audioTest); });
    } else if (!searchTest.isEmpty()) {
        auto *api = view.rootObject()->findChild<NeteaseApi *>();
        if (!api || !api->ready())
            return 1;
        QMetaObject::invokeMethod(view.rootObject(), "showPage", Q_ARG(QVariant, QVariant("search")));
        QObject::connect(api, &NeteaseApi::searchResult, &application, [&application](const QJsonObject &result) {
            const int count = result.value("songs").toArray().size();
            qInfo() << "MUSICFOX_SEARCH_OK songs" << count;
            QTimer::singleShot(500, &application, [&application, count] { application.exit(count > 0 ? 0 : 1); });
        });
        QObject::connect(api, &NeteaseApi::apiError, &application, [&application](const QString &message) {
            qWarning() << message;
            application.exit(1);
        });
        QTimer::singleShot(20000, &application, [&application] { application.exit(1); });
        QTimer::singleShot(0, api, [api, searchTest] { api->search(searchTest, 1, 3); });
    } else if (smokeTest) {
        QTimer::singleShot(1500, &application, [&application, &view] {
            auto *api = view.rootObject()->findChild<NeteaseApi *>();
            if (api && api->ready()) {
                qInfo() << "MUSICFOX_SMOKE_OK Qt" << qVersion();
                application.exit(0);
            } else {
                qWarning() << "MusicFox daemon did not start";
                application.exit(1);
            }
        });
    }
    qInfo() << "MusicFox LuneOS started, Qt" << qVersion();
    return application.exec();
}
