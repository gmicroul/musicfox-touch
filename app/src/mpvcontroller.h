#ifndef MPVCONTROLLER_H
#define MPVCONTROLLER_H

#include <QObject>
#include <QJsonObject>
#include <QJsonValue>
#include <QStringList>

#include <QLocalSocket>
#include <QProcess>
#include <QProcessEnvironment>

class QTimer;

// Drives an external `mpv` process over its JSON IPC socket. The QML-facing
// API mirrors what the old QMediaPlayer backend exposed (0=Stopped,
// 1=Playing, 2=Paused) so the UI needs no changes.
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
    ~MpvController();

    bool isConnected() const;
    double position() const { return m_position; }
    double duration() const { return m_duration; }
    int volume() const { return m_volume; }
    bool isPaused() const { return m_pause; }
    QString state() const { return m_state; }
    int playerState() const { return m_playerState; }

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
    void onSocketConnected();
    void onSocketDisconnected();
    void onSocketError();
    void onSocketReadyRead();
    void onMpvErrorOccurred();
    void onMpvFinished(int code, QProcess::ExitStatus status);
    void tryConnectSocket();
    void pollProperties();

private:
    static QString findMpv();
    static QProcessEnvironment mpvChildEnvironment(const QString &program);
    void startMpv();
    void sendCommand(const QStringList &args);
    int sendRequest(const QString &property);
    void applyReply(int requestId, const QJsonValue &data);
    void setPausedState(bool paused);
    void setIdleState();

    QProcess *m_proc;
    QLocalSocket *m_socket;
    QTimer *m_connectTimer;
    QTimer *m_pollTimer;
    QString m_socketPath;
    QByteArray m_buffer;

    int m_connectAttempts;
    int m_nextRequestId;
    int m_timePosId;
    int m_durationId;
    int m_pauseId;
    int m_volumeId;
    int m_idleId;

    double m_position;
    double m_duration;
    int m_volume;
    bool m_pause;
    bool m_coreIdle;
    int m_playerState;
    QString m_state;
};

#endif // MPVCONTROLLER_H