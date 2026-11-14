#include <QDataStream>
#include <QFile>
#include <QJsonArray>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>
#include "lyricsync.h"
#include "mpvcontroller.h"
#include "playqueue.h"

class CoreTests : public QObject
{
    Q_OBJECT

private slots:
    void volumeLimits()
    {
        MpvController player;
        QCOMPARE(player.volume(), 80);
        QSignalSpy changes(&player, &MpvController::volumeChanged);
        player.setVolume(200);
        QCOMPARE(player.volume(), 150);
        player.setVolume(-10);
        QCOMPARE(player.volume(), 0);
        player.setVolume(0);
        QCOMPARE(changes.count(), 2);
    }

    void invalidAudioUrl()
    {
        MpvController player;
        QSignalSpy errors(&player, &MpvController::mpvError);
        player.loadFile(QString());
        QCOMPARE(errors.count(), 1);
        QVERIFY(!player.isConnected());
    }

    void queueAndLyrics()
    {
        PlayQueue queue;
        queue.setSongs(QJsonArray{QJsonObject{{"id", 1}, {"name", "first"}}, QJsonObject{{"id", 2}, {"name", "second"}}});
        queue.setCurrentIndex(0);
        QCOMPARE(queue.currentSong().value("name").toString(), QString("first"));
        queue.next();
        QCOMPARE(queue.currentIndex(), 1);
        queue.previous();
        QCOMPARE(queue.currentIndex(), 0);
        LyricSync lyrics;
        lyrics.setLyrics(QJsonArray{QJsonObject{{"time", 0}, {"text", "first"}}, QJsonObject{{"time", 2}, {"text", "second"}}});
        lyrics.updatePosition(0.5);
        QCOMPARE(lyrics.currentText(), QString("first"));
        lyrics.updatePosition(2.5);
        QCOMPARE(lyrics.currentText(), QString("second"));
    }

    void mutedPlayback()
    {
        QTemporaryDir directory;
        QVERIFY(directory.isValid());
        QFile recording(directory.filePath("silence.wav"));
        QVERIFY(recording.open(QIODevice::WriteOnly));
        QDataStream writer(&recording);
        writer.setByteOrder(QDataStream::LittleEndian);
        writer.writeRawData("RIFF", 4);
        writer << quint32(44100 + 36);
        writer.writeRawData("WAVEfmt ", 8);
        writer << quint32(16) << quint16(1) << quint16(1) << quint32(22050)
               << quint32(44100) << quint16(2) << quint16(16);
        writer.writeRawData("data", 4);
        writer << quint32(44100);
        writer.writeRawData(QByteArray(44100, '\0').constData(), 44100);
        recording.close();

        MpvController player;
        player.setVolume(0);
        QSignalSpy finished(&player, &MpvController::endOfFile);
        QSignalSpy errors(&player, &MpvController::mpvError);
        player.loadFile(QUrl::fromLocalFile(recording.fileName()).toString());
        QTRY_VERIFY_WITH_TIMEOUT(player.duration() > 0, 5000);
        QTRY_VERIFY_WITH_TIMEOUT(finished.count() > 0, 8000);
        QCOMPARE(errors.count(), 0);
        QCOMPARE(player.playerState(), int(QMediaPlayer::StoppedState));
    }
};

QTEST_GUILESS_MAIN(CoreTests)
#include "core-tests.moc"
