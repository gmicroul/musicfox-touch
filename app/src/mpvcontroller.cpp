#include "mpvcontroller.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QLocalSocket>
#include <QProcess>
#include <QTimer>

namespace {
const int kPollMs = 250;
const int kSocketRetryMs = 200;
const int kMaxSocketAttempts = 25;  // give up after ~5 s instead of spamming forever
}

QString MpvController::findMpv()
{
    const QByteArray fromEnv = qgetenv("MUSICFOX_MPV");
    if (!fromEnv.isEmpty() && QFileInfo::exists(QString::fromLocal8Bit(fromEnv)))
        return QString::fromLocal8Bit(fromEnv);

    const QString home = QDir::homePath();
    const QString appDir = QCoreApplication::applicationDirPath();
    const QString candidates[] = {
        // The bundled mpv is preferred: startMpv() then points the child at
        // its own library directory without relying on the launcher script.
        appDir + "/mpv/usr/bin/mpv",
        appDir + "/musicfox-mpv",
        home + "/.local/bin/musicfox-touch-mpv",
        home + "/opt/mpv/usr/bin/mpv",
        "/usr/local/bin/musicfox-mpv",
        "/usr/bin/mpv",
    };
    for (const QString &c : candidates) {
        if (QFileInfo::exists(c))
            return c;
    }
    return QStringLiteral("mpv"); // last resort: rely on PATH
}

MpvController::MpvController(QObject *parent)
    : QObject(parent)
    , m_proc(nullptr)
    , m_socket(nullptr)
    , m_connectTimer(nullptr)
    , m_pollTimer(nullptr)
    , m_connectAttempts(0)
    , m_nextRequestId(1)
    , m_timePosId(0)
    , m_durationId(0)
    , m_pauseId(0)
    , m_volumeId(0)
    , m_idleId(0)
    , m_position(0)
    , m_duration(0)
    , m_volume(80)
    , m_pause(false)
    , m_coreIdle(true)
    , m_playerState(0)
    , m_state("idle")
{
    startMpv();
}

MpvController::~MpvController()
{
    if (m_pollTimer) m_pollTimer->stop();
    if (m_connectTimer) m_connectTimer->stop();
    if (m_socket && m_socket->state() != QLocalSocket::UnconnectedState) {
        sendCommand(QStringList() << "quit");
        m_socket->flush();
        m_socket->waitForBytesWritten(500);
        m_socket->disconnectFromServer();
    }
    if (m_proc && m_proc->state() != QProcess::NotRunning) {
        m_proc->terminate();
        if (!m_proc->waitForFinished(1500))
            m_proc->kill();
    }
}

void MpvController::startMpv()
{
    const QString mpvPath = findMpv();
    m_socketPath = QString("%1/musicfox-mpv-%2.sock")
                       .arg(QDir::tempPath())
                       .arg(QCoreApplication::applicationPid());
    QFile::remove(m_socketPath);

    const QStringList args = {
        "--no-video",
        "--idle=yes",
        "--no-terminal",
        "--keep-open=no",
        "--audio-client-name=MusicFox",
        "--cache=yes",
        "--demuxer-max-bytes=32MiB",
        "--demuxer-max-back-bytes=8MiB",
        QString("--input-ipc-server=%1").arg(m_socketPath),
    };

    qDebug() << "MpvController: starting" << mpvPath << args;
    m_proc = new QProcess(this);
    m_proc->setProcessChannelMode(QProcess::MergedChannels);
    // Bundled mpv ships its own ffmpeg/placebo libraries; make sure the child
    // finds them no matter how this app itself was started.
    m_proc->setProcessEnvironment(mpvChildEnvironment(mpvPath));
    m_proc->setProgram(mpvPath);
    m_proc->setArguments(args);
    connect(m_proc, QOverload<QProcess::ProcessError>::of(&QProcess::errorOccurred),
            this, &MpvController::onMpvErrorOccurred);
    connect(m_proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &MpvController::onMpvFinished);
    connect(m_proc, &QProcess::readyReadStandardOutput, this, [this]() {
        const QString out = QString::fromUtf8(m_proc->readAllStandardOutput()).trimmed();
        if (!out.isEmpty())
            qDebug() << "mpv:" << out;
    });
    m_proc->start();

    m_socket = new QLocalSocket(this);
    connect(m_socket, &QLocalSocket::connected, this, &MpvController::onSocketConnected);
    connect(m_socket, &QLocalSocket::disconnected, this, &MpvController::onSocketDisconnected);
    connect(m_socket, &QLocalSocket::errorOccurred, this, &MpvController::onSocketError);
    connect(m_socket, &QLocalSocket::readyRead, this, &MpvController::onSocketReadyRead);

    m_connectTimer = new QTimer(this);
    m_connectTimer->setInterval(kSocketRetryMs);
    connect(m_connectTimer, &QTimer::timeout, this, &MpvController::tryConnectSocket);
    m_connectTimer->start();
    tryConnectSocket();

    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(kPollMs);
    connect(m_pollTimer, &QTimer::timeout, this, &MpvController::pollProperties);
}

QProcessEnvironment MpvController::mpvChildEnvironment(const QString &program)
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();

    const QString appDir = QCoreApplication::applicationDirPath();
    QStringList libDirs;
    const QStringList candidates = {
        appDir + "/mpv/usr/lib/aarch64-linux-gnu",
        appDir + "/mpv/usr/lib",
        appDir + "/../mpv/usr/lib/aarch64-linux-gnu",
        QStringLiteral("/usr/lib/musicfox-touch/mpv/usr/lib/aarch64-linux-gnu"),
    };
    for (const QString &d : candidates) {
        if (QFileInfo::exists(d) && !libDirs.contains(d))
            libDirs << d;
    }
    if (libDirs.isEmpty())
        return env;

    const QString existing = env.value(QStringLiteral("LD_LIBRARY_PATH"));
    env.insert(QStringLiteral("LD_LIBRARY_PATH"),
               existing.isEmpty() ? libDirs.join(QLatin1Char(':'))
                                  : libDirs.join(QLatin1Char(':')) + QLatin1Char(':') + existing);
    qDebug().noquote() << "MpvController: child LD_LIBRARY_PATH =" << env.value("LD_LIBRARY_PATH");
    return env;
}

void MpvController::connectToMpv(const QString &socketPath)
{
    if (socketPath.isEmpty() || socketPath == m_socketPath)
        return;
    Q_UNUSED(socketPath)
}

bool MpvController::isConnected() const
{
    return m_socket && m_socket->state() == QLocalSocket::ConnectedState;
}

void MpvController::tryConnectSocket()
{
    if (!m_socket || isConnected())
        return;
    if (m_connectAttempts >= kMaxSocketAttempts) {
        if (m_connectTimer && m_connectTimer->isActive()) {
            m_connectTimer->stop();
            qWarning() << "MpvController: no IPC socket at" << m_socketPath << "- giving up";
            emit mpvError("mpv IPC unavailable (mpv process not running?)");
        }
        return;
    }
    ++m_connectAttempts;
    if (m_socket->state() == QLocalSocket::UnconnectedState)
        m_socket->connectToServer(m_socketPath, QIODevice::ReadWrite);
}

void MpvController::onSocketConnected()
{
    qDebug() << "MpvController: IPC connected at" << m_socketPath << "after"
             << m_connectAttempts << "attempt(s)";
    if (m_connectTimer) m_connectTimer->stop();
    sendCommand(QStringList() << "set_property" << "volume" << QString::number(qMin(m_volume, 100)));
    pollProperties();
    if (m_pollTimer && !m_pollTimer->isActive())
        m_pollTimer->start();
    emit connectedChanged();
}

void MpvController::onSocketDisconnected()
{
    qDebug() << "MpvController: IPC disconnected";
    setIdleState();
    emit connectedChanged();
}

void MpvController::onSocketError()
{
    // The socket shows up a moment after mpv is spawned, so the first few
    // failures are expected; only the first and the last are worth logging.
    if (m_socket && m_connectAttempts == 1)
        qDebug() << "MpvController: waiting for IPC socket" << m_socketPath;
}

void MpvController::onMpvErrorOccurred()
{
    if (!m_proc)
        return;
    qWarning() << "MpvController: mpv process error" << m_proc->errorString();
    if (m_proc->error() == QProcess::FailedToStart) {
        emit mpvError("Failed to start mpv: " + m_proc->program()
                      + " (install it or set MUSICFOX_MPV)");
    }
}

void MpvController::onMpvFinished(int code, QProcess::ExitStatus status)
{
    qWarning() << "MpvController: mpv exited code" << code << "status" << status;
    setIdleState();
    emit connectedChanged();
}

int MpvController::sendRequest(const QString &property)
{
    if (!isConnected())
        return 0;
    const int id = m_nextRequestId++;
    QJsonObject obj;
    obj.insert("command", QJsonArray() << "get_property" << property);
    obj.insert("request_id", id);
    m_socket->write(QJsonDocument(obj).toJson(QJsonDocument::Compact) + "\n");
    return id;
}

void MpvController::sendCommand(const QStringList &args)
{
    if (!isConnected()) {
        qDebug() << "MpvController: command dropped (no IPC)" << args;
        return;
    }
    QJsonObject obj;
    QJsonArray arr;
    for (const QString &a : args)
        arr.append(a);
    obj.insert("command", arr);
    m_socket->write(QJsonDocument(obj).toJson(QJsonDocument::Compact) + "\n");
}

void MpvController::onSocketReadyRead()
{
    m_buffer += m_socket->readAll();
    while (true) {
        const int nl = m_buffer.indexOf('\n');
        if (nl < 0)
            break;
        const QByteArray line = m_buffer.left(nl).trimmed();
        m_buffer.remove(0, nl + 1);
        if (line.isEmpty())
            continue;
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(line, &err);
        if (err.error != QJsonParseError::NoError || !doc.isObject()) {
            qWarning() << "MpvController: bad JSON from mpv:" << err.errorString() << line;
            continue;
        }
        const QJsonObject obj = doc.object();
        const QString event = obj.value("event").toString();
        if (event == "file-loaded") {
            m_coreIdle = false;
        } else if (event == "end-file") {
            const QString reason = obj.value("reason").toString();
            qDebug() << "MpvController: end-file" << reason;
            if (reason == "eof") {
                setIdleState();
                emit endOfFile();
            } else if (reason == "error") {
                emit mpvError("mpv playback error");
            }
            continue;
        }
        if (!event.isEmpty())
            continue;
        if (!obj.contains("request_id"))
            continue;
        const QString replyError = obj.value("error").toString();
        if (!replyError.isEmpty() && replyError != QLatin1String("success")) {
            qDebug() << "MpvController: mpv error reply" << replyError;
            continue;
        }
        applyReply(obj.value("request_id").toInt(), obj.value("data"));
    }
}

void MpvController::applyReply(int requestId, const QJsonValue &data)
{
    if (requestId == m_timePosId) {
        const double pos = data.toDouble();
        if (!qFuzzyCompare(m_position + 1.0, pos + 1.0)) {
            m_position = pos;
            emit positionChanged();
        }
    } else if (requestId == m_durationId) {
        const double dur = data.toDouble();
        if (!qFuzzyCompare(m_duration + 1.0, dur + 1.0)) {
            m_duration = dur;
            emit durationChanged();
        }
    } else if (requestId == m_pauseId) {
        setPausedState(data.toBool());
    } else if (requestId == m_volumeId) {
        const int vol = qRound(data.toDouble());
        if (m_volume != vol) {
            m_volume = vol;
            emit volumeChanged();
        }
    } else if (requestId == m_idleId) {
        const bool idle = data.toBool();
        if (idle != m_coreIdle) {
            m_coreIdle = idle;
            if (idle && !m_pause)
                setIdleState();
        }
    }
}

void MpvController::pollProperties()
{
    if (!isConnected())
        return;
    // time-pos / duration do not exist while mpv is idle, so asking for them
    // then just yields "property unavailable" replies.
    m_timePosId = m_coreIdle ? 0 : sendRequest(QStringLiteral("time-pos"));
    m_durationId = m_coreIdle ? 0 : sendRequest(QStringLiteral("duration"));
    m_pauseId = sendRequest(QStringLiteral("pause"));
    m_volumeId = sendRequest(QStringLiteral("volume"));
    m_idleId = sendRequest(QStringLiteral("core-idle"));
}

void MpvController::setPausedState(bool paused)
{
    m_pause = paused;
    m_playerState = paused ? 2 : 1;
    m_state = paused ? "paused" : "playing";
    emit pauseChanged();
    emit stateChanged();
    emit playerStateChanged();
}

void MpvController::setIdleState()
{
    m_pause = false;
    m_playerState = 0;
    m_state = "idle";
    m_position = 0;
    m_duration = 0;
    emit pauseChanged();
    emit stateChanged();
    emit playerStateChanged();
    emit positionChanged();
    emit durationChanged();
}

void MpvController::loadFile(const QString &url)
{
    qDebug() << "MpvController::loadFile" << url;
    sendCommand(QStringList() << "loadfile" << url << "replace");
    sendCommand(QStringList() << "set_property" << "pause" << "false");
}

void MpvController::play()
{
    sendCommand(QStringList() << "set_property" << "pause" << "false");
}

void MpvController::doPause()
{
    sendCommand(QStringList() << "set_property" << "pause" << "true");
}

void MpvController::togglePause()
{
    sendCommand(QStringList() << "cycle" << "pause");
}

void MpvController::seek(double seconds)
{
    sendCommand(QStringList() << "seek" << QString::number(seconds) << "absolute");
}

void MpvController::doStop()
{
    sendCommand(QStringList() << "stop");
    setIdleState();
}

void MpvController::setVolume(int vol)
{
    m_volume = qBound(0, vol, 150);
    emit volumeChanged();
    sendCommand(QStringList() << "set_property" << "volume"
                              << QString::number(qMin(m_volume, 100)));
}

void MpvController::setPaused(bool p)
{
    if (p)
        doPause();
    else
        play();
}

void MpvController::getProperty(const QString &name)
{
    sendCommand(QStringList() << "get_property" << name);
}