#include "neteaseapi.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QCoreApplication>
#include <QFile>
#include <QDir>
#include <QDebug>

NeteaseApi::NeteaseApi(QObject *parent)
    : QObject(parent)
    , m_process(nullptr)
    , m_ready(false)
    , m_nextId(1)
{
    startDaemon();
}

NeteaseApi::~NeteaseApi()
{
    if (m_process) {
        m_process->terminate();
        m_process->waitForFinished(2000);
        delete m_process;
    }
}

void NeteaseApi::startDaemon()
{
    m_process = new QProcess(this);

    QString daemonPath = "/usr/local/bin/musicfox-daemon";
    if (!QFile::exists(daemonPath)) {
        daemonPath = QCoreApplication::applicationDirPath() + "/../libexec/musicfox-daemon";
    }
    if (!QFile::exists(daemonPath)) {
        daemonPath = QDir::homePath() + "/go/bin/musicfox-daemon";
    }
    if (!QFile::exists(daemonPath)) {
        daemonPath = QDir::homePath() + "/musicfox-touch/daemon/musicfox-daemon";
    }

    connect(m_process, SIGNAL(readyReadStandardOutput()), this, SLOT(onReadyRead()));
    connect(m_process, SIGNAL(errorOccurred(QProcess::ProcessError)), this, SLOT(onErrorOccurred(QProcess::ProcessError)));
    connect(m_process, SIGNAL(finished(int,QProcess::ExitStatus)), this, SLOT(onFinished(int,QProcess::ExitStatus)));

    m_process->start(daemonPath);
    if (m_process->waitForStarted(5000)) {
        m_ready = true;
        emit readyChanged();
    } else {
        emit apiError("Failed to start daemon: " + daemonPath);
    }
}

void NeteaseApi::onReadyRead()
{
    m_buffer.append(m_process->readAllStandardOutput());
    while (m_buffer.contains('\n')) {
        int idx = m_buffer.indexOf('\n');
        QByteArray line = m_buffer.left(idx).trimmed();
        m_buffer.remove(0, idx + 1);

        if (line.isEmpty()) continue;

        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            emit apiError("Parse error: " + parseError.errorString());
            continue;
        }

        QJsonObject resp = doc.object();

        if (resp.contains("error")) {
            emit apiError(resp.value("error").toObject().value("message").toString());
            continue;
        }

        QJsonValue result = resp.value("result");

        if (result.isObject()) {
            QJsonObject robj = result.toObject();
            if (robj.contains("lines")) {
                emit lyricResult(robj);
            } else if (robj.contains("url")) {
                emit songUrlResult(robj);
            } else if (robj.contains("playlist")) {
                emit playlistDetailResult(robj);
            } else if (robj.contains("songs")) {
                emit searchResult(robj);
            } else {
                emit searchResult(robj);
            }
        } else if (result.isArray()) {
            QJsonArray arr = result.toArray();
            if (!arr.isEmpty()) {
                QJsonObject first = arr.first().toObject();
                if (first.contains("cover")) {
                    emit toplistResult(arr);
                } else {
                    emit topPlaylistsResult(arr);
                }
            }
        }
    }
}

void NeteaseApi::onErrorOccurred(QProcess::ProcessError error)
{
    Q_UNUSED(error);
    m_ready = false;
    emit readyChanged();
    emit apiError("Daemon process error: " + m_process->errorString());
}

void NeteaseApi::onFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitCode);
    Q_UNUSED(exitStatus);
    m_ready = false;
    emit readyChanged();
}

void NeteaseApi::search(const QString &keyword, int type, int limit)
{
    QJsonObject params;
    params["keyword"] = keyword;
    params["type"] = type;
    params["limit"] = limit;
    sendRequest("search", params);
}

void NeteaseApi::getSongUrl(qint64 id, int br)
{
    QJsonObject params;
    params["id"] = static_cast<double>(id);
    params["br"] = br;
    sendRequest("songURL", params);
}

void NeteaseApi::getPlaylistDetail(qint64 id, bool getAll)
{
    QJsonObject params;
    params["id"] = static_cast<double>(id);
    params["getAll"] = getAll;
    sendRequest("playlistDetail", params);
}

void NeteaseApi::getToplist()
{
    sendRequest("toplist", QJsonObject());
}

void NeteaseApi::getTopPlaylists(const QString &cat, int limit)
{
    QJsonObject params;
    if (!cat.isEmpty()) params["cat"] = cat;
    params["limit"] = limit;
    sendRequest("topPlaylists", params);
}

void NeteaseApi::getLyric(qint64 id)
{
    QJsonObject params;
    params["id"] = static_cast<double>(id);
    sendRequest("lyric", params);
}

void NeteaseApi::getSongDetail(const QList<qint64> &ids)
{
    QJsonObject params;
    QJsonArray idsArray;
    for (qint64 id : ids) {
        idsArray.append(static_cast<double>(id));
    }
    params["ids"] = idsArray;
    sendRequest("songDetail", params);
}

void NeteaseApi::sendRequest(const QString &method, const QJsonObject &params)
{
    if (!m_process || m_process->state() != QProcess::Running) {
        emit apiError("Daemon not running");
        return;
    }

    QJsonObject req;
    req["id"] = static_cast<double>(m_nextId++);
    req["method"] = method;
    if (!params.isEmpty()) {
        req["params"] = params;
    }

    QByteArray line = QJsonDocument(req).toJson(QJsonDocument::Compact) + "\n";
    m_process->write(line);
}
