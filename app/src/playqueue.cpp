#include "playqueue.h"
#include <QSettings>
#include <QStringList>

PlayQueue::PlayQueue(QObject *parent)
    : QObject(parent)
    , m_currentIndex(-1)
    , m_playMode(0)
{
    loadState();
}

QJsonObject PlayQueue::currentSong() const
{
    if (m_currentIndex >= 0 && m_currentIndex < m_songs.size()) {
        return m_songs.at(m_currentIndex).toObject();
    }
    return QJsonObject();
}

void PlayQueue::setSongs(const QJsonArray &songs)
{
    m_songs = songs;
    emit countChanged();
    if (m_currentIndex >= 0) {
        m_currentIndex = -1;
        emit currentIndexChanged();
    }
}

QJsonObject PlayQueue::songAt(int index) const
{
    if (index >= 0 && index < m_songs.size()) {
        return m_songs.at(index).toObject();
    }
    return QJsonObject();
}

void PlayQueue::setCurrentIndex(int index)
{
    if (index >= 0 && index < m_songs.size() && index != m_currentIndex) {
        m_currentIndex = index;
        emit currentIndexChanged();
        emit currentSongChanged();
        emit songChanged(currentSong());
    }
}

void PlayQueue::next()
{
    if (m_currentIndex < m_songs.size() - 1) {
        setCurrentIndex(m_currentIndex + 1);
    }
}

void PlayQueue::previous()
{
    if (m_currentIndex > 0) {
        setCurrentIndex(m_currentIndex - 1);
    }
}

void PlayQueue::replayCurrent()
{
    if (m_currentIndex >= 0 && m_currentIndex < m_songs.size()) {
        emit currentSongChanged();
        emit songChanged(currentSong());
    }
}

void PlayQueue::setPlayMode(int mode)
{
    if (mode < 0 || mode > 1) return;
    if (mode == m_playMode) return;
    m_playMode = mode;
    saveState();
    emit playModeChanged();
}

void PlayQueue::togglePlayMode()
{
    setPlayMode(m_playMode == 0 ? 1 : 0);
}

bool PlayQueue::isFavorite(qint64 id) const
{
    return m_favorites.contains(id);
}

void PlayQueue::toggleFavorite(qint64 id)
{
    if (id <= 0) return;
    if (m_favorites.contains(id)) m_favorites.remove(id);
    else m_favorites.insert(id);
    saveState();
    emit favoritesChanged();
}

void PlayQueue::loadState()
{
    QSettings s;
    m_playMode = s.value("player/playMode", 0).toInt();
    if (m_playMode < 0 || m_playMode > 1) m_playMode = 0;
    m_favorites.clear();
    const QStringList ids = s.value("player/favorites").toStringList();
    for (const QString &t : ids) {
        bool ok = false;
        qint64 id = t.toLongLong(&ok);
        if (ok && id > 0) m_favorites.insert(id);
    }
}

void PlayQueue::saveState()
{
    QSettings s;
    s.setValue("player/playMode", m_playMode);
    QStringList ids;
    for (qint64 id : m_favorites) ids << QString::number(id);
    s.setValue("player/favorites", ids);
}
