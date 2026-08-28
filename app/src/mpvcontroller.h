#ifndef MPVCONTROLLER_H
#define MPVCONTROLLER_H

#include <QObject>
#include <QMediaPlayer>
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
    // Live playback state straight from QMediaPlayer (0=Stopped,1=Playing,2=Paused)
    Q_PROPERTY(int playerState READ playerState NOTIFY playerStateChanged)

public:
    explicit MpvController(QObject *parent = nullptr);
    ~MpvController();

    bool isConnected() const;
    double position() const { return m_position; }
    double duration() const { return m_duration; }
    int volume() const { return m_volume; }
    bool isPaused() const { return m_pause; }
    QString state() const { return m_state; }
    int playerState() const { return static_cast<int>(m_player->state()); }

    Q_INVOKABLE void loadFile(const QString &url);
    Q_INVOKABLE void play();
    Q_INVOKABLE void doPause();
    Q_INVOKABLE void togglePause();
    Q_INVOKABLE void seek(double seconds);
    Q_INVOKABLE void doStop();
    Q_INVOKABLE void connectToMpv(const QString &socketPath = QString());
    Q_INVOKABLE void getProperty(const QString &name);

public slots:
    void setVolume(int vol);
    void setPaused(bool p);

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

private slots:
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);
    void onStateChanged(QMediaPlayer::State state);
    void onPositionChanged(qint64 position);
    void onDurationChanged(qint64 duration);
    void onError(QMediaPlayer::Error error, const QString &errorString);

private:
    QMediaPlayer *m_player;
    double m_position;
    double m_duration;
    int m_volume;
    bool m_pause;
    QString m_state;
};

#endif // MPVCONTROLLER_H
