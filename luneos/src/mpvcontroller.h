#ifndef MUSICFOX_LUNEOS_MPVCONTROLLER_H
#define MUSICFOX_LUNEOS_MPVCONTROLLER_H

#include <QAudioOutput>
#include <QMediaPlayer>
#include <QObject>
#include <QUrl>

class MpvController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool isPaused READ isPaused NOTIFY pauseChanged)
    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(int playerState READ playerState NOTIFY playerStateChanged)

public:
    explicit MpvController(QObject *parent = nullptr);
    bool isConnected() const;
    double position() const { return m_player->position() / 1000.0; }
    double duration() const { return m_player->duration() / 1000.0; }
    int volume() const { return m_volume; }
    bool isPaused() const { return m_player->playbackState() == QMediaPlayer::PausedState; }
    QString state() const { return m_state; }
    int playerState() const { return static_cast<int>(m_player->playbackState()); }

    Q_INVOKABLE void loadFile(const QString &url);
    Q_INVOKABLE void play();
    Q_INVOKABLE void doPause();
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void seek(double seconds);
    Q_INVOKABLE void doStop();
    Q_INVOKABLE void connectToMpv(const QString &socketPath = QString());
    Q_INVOKABLE void getProperty(const QString &name);

public slots:
    void setVolume(int volume);
    void setPaused(bool paused);

signals:
    void connectedChanged();
    void positionChanged();
    void durationChanged();
    void volumeChanged();
    void pauseChanged();
    void stateChanged();
    void playerStateChanged();
    void endOfFile();
    void propertyChanged(const QString &name, const QVariant &value);
    void mpvError(const QString &message);

private:
    void setState(const QString &state);
    QMediaPlayer *m_player;
    QAudioOutput *m_audio;
    int m_volume = 80;
    QString m_state = "idle";
};

#endif
