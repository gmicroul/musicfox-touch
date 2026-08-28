#ifndef NETEASEAPI_H
#define NETEASEAPI_H

#include <QObject>
#include <QProcess>
#include <QJsonArray>
#include <QJsonObject>

class NeteaseApi : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)

public:
    explicit NeteaseApi(QObject *parent = nullptr);
    ~NeteaseApi();

    bool ready() const { return m_ready; }

    Q_INVOKABLE void search(const QString &keyword, int type = 1, int limit = 30);
    Q_INVOKABLE void getSongUrl(qint64 id, int br = 320000);
    Q_INVOKABLE void getPlaylistDetail(qint64 id, bool getAll = false);
    Q_INVOKABLE void getToplist();
    Q_INVOKABLE void getTopPlaylists(const QString &cat = QString(), int limit = 30);
    Q_INVOKABLE void getLyric(qint64 id);
    Q_INVOKABLE void getSongDetail(const QList<qint64> &ids);

signals:
    void readyChanged();
    void searchResult(const QJsonObject &result);
    void songUrlResult(const QJsonObject &result);
    void playlistDetailResult(const QJsonObject &result);
    void toplistResult(const QJsonArray &result);
    void topPlaylistsResult(const QJsonArray &result);
    void lyricResult(const QJsonObject &result);
    void songDetailResult(const QJsonArray &result);
    void apiError(const QString &message);

private slots:
    void onReadyRead();
    void onErrorOccurred(QProcess::ProcessError error);
    void onFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    void startDaemon();
    void sendRequest(const QString &method, const QJsonObject &params);

    QProcess *m_process;
    bool m_ready;
    QByteArray m_buffer;
    qint64 m_nextId;
};

#endif // NETEASEAPI_H
