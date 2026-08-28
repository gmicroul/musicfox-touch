#include "daemonclient.h"
#include <QDebug>
#include <QCoreApplication>
#include <QFile>

DaemonClient::DaemonClient(QObject *parent)
    : QObject(parent)
    , m_process(new QProcess(this))
    , m_requestId(0)
{
    connect(m_process, SIGNAL(readyReadStandardOutput()), this, SLOT(onReadyReadStdout()));
    connect(m_process, SIGNAL(errorOccurred(QProcess::ProcessError)), this, SLOT(onProcessError(QProcess::ProcessError)));
    connect(m_process, SIGNAL(finished(int,QProcess::ExitStatus)), this, SLOT(onProcessFinished(int,QProcess::ExitStatus)));
}

DaemonClient::~DaemonClient()
{
    stop();
}

void DaemonClient::start()
{
    QString daemonPath = QCoreApplication::applicationDirPath() + "/musicfox-daemon";
    if (!QFile::exists(daemonPath)) {
        daemonPath = "musicfox-daemon";
    }
    m_process->start(daemonPath);
    if (!m_process->waitForStarted(3000)) {
        qWarning() << "Failed to start daemon:" << m_process->errorString();
        emit daemonError("Failed to start musicfox-daemon: " + m_process->errorString());
    } else {
        qDebug() << "Daemon started successfully";
    }
}

void DaemonClient::stop()
{
    if (m_process->state() != QProcess::NotRunning) {
        m_process->terminate();
        m_process->waitForFinished(1000);
    }
}

void DaemonClient::sendRequest(const QString &method, const QJsonObject &params)
{
    qint64 id = ++m_requestId;
    m_pendingMethods[id] = method;

    QJsonObject req;
    req["id"] = static_cast<qint64>(id);
    req["method"] = method;
    if (!params.isEmpty()) {
        req["params"] = params;
    }

    QJsonDocument doc(req);
    QByteArray data = doc.toJson(QJsonDocument::Compact) + "\n";
    m_process->write(data);
}

void DaemonClient::searchSongs(const QString &keyword, int limit)
{
    QJsonObject params;
    params["keyword"] = keyword;
    params["type"] = 1;
    params["limit"] = limit;
    sendRequest("search", params);
}

void DaemonClient::searchPlaylists(const QString &keyword, int limit)
{
    QJsonObject params;
    params["keyword"] = keyword;
    params["type"] = 1000;
    params["limit"] = limit;
    sendRequest("search", params);
}

void DaemonClient::songDetail(const QList<qint64> &ids)
{
    QJsonObject params;
    QJsonArray idsArr;
    for (qint64 id : ids) idsArr.append(id);
    params["ids"] = idsArr;
    sendRequest("songDetail", params);
}

void DaemonClient::songURL(qint64 id, int bitrate)
{
    QJsonObject params;
    params["id"] = id;
    params["br"] = bitrate;
    sendRequest("songURL", params);
}

void DaemonClient::playlistDetail(qint64 id, bool getAll)
{
    QJsonObject params;
    params["id"] = id;
    params["getAll"] = getAll;
    sendRequest("playlistDetail", params);
}

void DaemonClient::toplist()
{
    sendRequest("toplist", QJsonObject());
}

void DaemonClient::topPlaylists(const QString &cat, int limit)
{
    QJsonObject params;
    params["cat"] = cat;
    params["limit"] = limit;
    sendRequest("topPlaylists", params);
}

void DaemonClient::lyric(qint64 id)
{
    QJsonObject params;
    params["id"] = id;
    sendRequest("lyric", params);
}

void DaemonClient::onReadyReadStdout()
{
    m_buffer += m_process->readAllStandardOutput();

    int newlinePos;
    while ((newlinePos = m_buffer.indexOf('\n')) != -1) {
        QByteArray line = m_buffer.left(newlinePos).trimmed();
        m_buffer.remove(0, newlinePos + 1);

        if (line.isEmpty()) continue;

        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            qWarning() << "JSON parse error:" << parseError.errorString() << "line:" << line;
            continue;
        }
        parseResponse(doc.object());
    }
}

void DaemonClient::parseResponse(const QJsonObject &resp)
{
    qint64 id = resp["id"].toVariant().toLongLong();
    QString method = m_pendingMethods.take(id);

    if (resp.contains("error") && !resp["error"].isNull()) {
        QJsonObject err = resp["error"].toObject();
        emit daemonError(QString("Daemon %1: %2").arg(method).arg(err["message"].toString()));
        return;
    }

    QJsonValue result = resp["result"];

    if (method == "search") {
        if (result.isObject()) {
            QJsonObject obj = result.toObject();
            if (obj.contains("songs")) {
                emit searchSongsResult(obj["songs"].toArray());
            } else if (obj.contains("playlists")) {
                emit searchPlaylistsResult(obj["playlists"].toArray());
            }
        }
    } else if (method == "songDetail") {
        if (result.isArray()) {
            emit songDetailResult(result.toArray());
        }
    } else if (method == "songURL") {
        if (result.isObject()) {
            QJsonObject obj = result.toObject();
            emit songURLResult(
                obj["url"].toString(),
                obj["br"].toInt(),
                obj["type"].toString(),
                obj["code"].toInt()
            );
        }
    } else if (method == "playlistDetail") {
        if (result.isObject()) {
            QJsonObject obj = result.toObject();
            emit playlistDetailResult(
                obj["playlist"].toObject(),
                obj["songs"].toArray()
            );
        }
    } else if (method == "toplist") {
        if (result.isArray()) {
            emit toplistResult(result.toArray());
        }
    } else if (method == "topPlaylists") {
        if (result.isArray()) {
            emit topPlaylistsResult(result.toArray());
        }
    } else if (method == "lyric") {
        if (result.isObject() && result.toObject().contains("lines")) {
            emit lyricResult(result.toObject()["lines"].toArray());
        }
    }
}

void DaemonClient::onProcessError(QProcess::ProcessError processError)
{
    qWarning() << "Daemon process error:" << processError;
    emit daemonError("Daemon process error: " + m_process->errorString());
}

void DaemonClient::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    qWarning() << "Daemon finished unexpectedly:" << exitCode << exitStatus;
    emit daemonError("Daemon process exited unexpectedly");
}