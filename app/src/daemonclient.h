#ifndef DAEMONCLIENT_H
#define DAEMONCLIENT_H

#include <QObject>
#include <QProcess>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QMap>

class DaemonClient : public QObject
{
    Q_OBJECT
public:
    explicit DaemonClient(QObject *parent = nullptr);
    ~DaemonClient();

    void start();
    void stop();

    void searchSongs(const QString &keyword, int limit = 30);
    void searchPlaylists(const QString &keyword, int limit = 30);
    void songDetail(const QList<qint64> &ids);
    void songURL(qint64 id, int bitrate = 320000);
    void playlistDetail(qint64 id, bool getAll = false);
    void toplist();
    void topPlaylists(const QString &cat = "华语", int limit = 30);
    void lyric(qint64 id);

signals:
    void searchSongsResult(QJsonArray songs);
    void searchPlaylistsResult(QJsonArray playlists);
    void songDetailResult(QJsonArray songs);
    void songURLResult(const QString &url, int br, const QString &type, int code);
    void playlistDetailResult(QJsonObject playlist, QJsonArray songs);
    void toplistResult(QJsonArray toplist);
    void topPlaylistsResult(QJsonArray playlists);
    void lyricResult(QJsonArray lines);
    void daemonError(const QString &message);

private slots:
    void onReadyReadStdout();
    void onProcessError(QProcess::ProcessError error);
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    void sendRequest(const QString &method, const QJsonObject &params);
    void parseResponse(const QJsonObject &resp);

    QProcess *m_process;
    qint64 m_requestId;
    QMap<qint64, QString> m_pendingMethods;
    QByteArray m_buffer;
};

#endif // DAEMONCLIENT_H