#ifndef COVERCACHE_H
#define COVERCACHE_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QSet>

class QNetworkAccessManager;
class QNetworkReply;

// Downloads album-art URLs to a local cache directory so that they can be
// referenced via file:// URLs. Needed because the MPRIS lock-screen/media
// UI does not load remote (http) artwork.
class CoverCache : public QObject
{
    Q_OBJECT

public:
    explicit CoverCache(QObject *parent = nullptr);

    Q_INVOKABLE QString coverUrl(const QString &url) const;
    Q_INVOKABLE void cache(const QString &url);

signals:
    void coverReady(const QString &url, const QString &fileUrl);

private slots:
    void onFinished(QNetworkReply *reply);

private:
    QString cacheDir() const;
    QString localFileFor(const QString &url) const;
    QString extensionFor(const QByteArray &data) const;
    QString findExisting(const QString &url) const;

    QNetworkAccessManager *m_nam;
    QHash<QString, QString> m_urlToFile;
    QSet<QString> *m_downloading;
};

#endif // COVERCACHE_H
