#include "playqueue.h"

PlayQueue::PlayQueue(QObject *parent)
    : QObject(parent)
    , m_currentIndex(-1)
{
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
