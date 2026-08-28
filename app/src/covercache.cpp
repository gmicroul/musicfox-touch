#include "covercache.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QDir>
#include <QStandardPaths>
#include <QCryptographicHash>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <QDebug>

CoverCache::CoverCache(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this))
    , m_downloading(new QSet<QString>())
{
}

QString CoverCache::cacheDir() const
{
    QString base = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (base.isEmpty())
        base = QDir::homePath() + "/.cache/harbour-musicfox";
    QDir d;
    if (!d.exists(base))
        d.mkpath(base);
    return base;
}

// Base (no extension) local path for a URL
static QString basePathFor(const QString &cacheBase, const QString &url)
{
    QByteArray hash = QCryptographicHash::hash(url.toUtf8(), QCryptographicHash::Md5).toHex();
    return cacheBase + QDir::separator() + QString::fromLatin1(hash);
}

QString CoverCache::localFileFor(const QString &url) const
{
    return basePathFor(cacheDir(), url);
}

// Detect image type from its magic bytes so we save with the right extension.
// A previous version hard-coded ".jpg", which broke PNG covers on the lock
// screen.
QString CoverCache::extensionFor(const QByteArray &data) const
{
    if (data.startsWith("\x89PNG"))
        return "png";
    if (data.startsWith("\xFF\xD8\xFF"))
        return "jpg";
    if (data.startsWith("GIF8"))
        return "gif";
    if (data.startsWith("BM"))
        return "bmp";
    if (data.startsWith("RIFF") && data.mid(8, 4) == "WEBP")
        return "webp";
    return "jpg";
}

// Return an existing cached file for the URL (any extension), or empty.
QString CoverCache::findExisting(const QString &url) const
{
    if (url.isEmpty())
        return QString();
    QString base = basePathFor(cacheDir(), url);
    const char *exts[] = { "jpg", "png", "gif", "bmp", "webp" };
    for (const char *e : exts) {
        QString f = base + "." + e;
        if (QFileInfo::exists(f))
            return QUrl::fromLocalFile(f).toString();
    }
    return QString();
}

QString CoverCache::coverUrl(const QString &url) const
{
    if (url.isEmpty())
        return QString();
    if (url.startsWith("file://") || url.startsWith("qrc:"))
        return url;
    return findExisting(url);
}

void CoverCache::cache(const QString &url)
{
    if (url.isEmpty() || url.startsWith("file://") || url.startsWith("qrc:"))
        return;
    if (!findExisting(url).isEmpty())
        return;
    if (m_downloading->contains(url))
        return;

    m_urlToFile.insert(url, basePathFor(cacheDir(), url));
    m_downloading->insert(url);

    QUrl urlEnc(url);
    QNetworkRequest req(urlEnc);
    req.setAttribute(QNetworkRequest::FollowRedirectsAttribute, true);
    QNetworkReply *reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        this->onFinished(reply);
    });
}

void CoverCache::onFinished(QNetworkReply *reply)
{
    reply->deleteLater();
    QUrl requested = reply->request().url();
    QString url = requested.toString();

    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();
        QString base = m_urlToFile.value(url);
        if (!base.isEmpty() && !data.isEmpty()) {
            // Save with the extension that matches the actual image content
            QString local = base + "." + extensionFor(data);
            QFile f(local);
            if (f.open(QIODevice::WriteOnly)) {
                f.write(data);
                f.close();
                qDebug() << "CoverCache saved" << local << data.size() << "bytes";
                emit coverReady(url, QUrl::fromLocalFile(local).toString());
            }
        } else {
            qDebug() << "CoverCache download empty for" << url;
        }
    } else {
        qDebug() << "CoverCache download error for" << url << reply->errorString();
    }

    m_downloading->remove(url);
    m_urlToFile.remove(url);
}
