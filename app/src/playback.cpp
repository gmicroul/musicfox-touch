#include "playback.h"
#include <QDebug>
#include <QMediaContent>

Playback::Playback(QObject *parent)
    : QObject(parent)
    , m_player(new QMediaPlayer(this))
    , m_currentIndex(-1)
    , m_playlistCount(0)
    , m_position(0)
    , m_duration(0)
    , m_volume(70)
    , m_playing(false)
    , m_currentId(0)
{
    m_player->setVolume(m_volume);
    m_player->setNotifyInterval(200);

    connect(m_player, SIGNAL(stateChanged(QMediaPlayer::State)), this, SLOT(onStateChanged(QMediaPlayer::State)));
    connect(m_player, SIGNAL(positionChanged(qint64)), this, SLOT(onPositionChanged(qint64)));
    connect(m_player, SIGNAL(durationChanged(qint64)), this, SLOT(onDurationChanged(qint64)));
    connect(m_player, SIGNAL(mediaStatusChanged(QMediaPlayer::MediaStatus)), this, SLOT(onMediaStatusChanged(QMediaPlayer::MediaStatus)));
    connect(m_player, SIGNAL(error(QMediaPlayer::Error)), this, SLOT(onError(QMediaPlayer::Error)));
}

Playback::~Playback()
{
    m_player->stop();
}

void Playback::setVolume(int vol)
{
    vol = qBound(0, vol, 100);
    if (m_volume != vol) {
        m_volume = vol;
        m_player->setVolume(vol);
        emit volumeChanged(vol);
    }
}

void Playback::play()
{
    if (m_currentIndex >= 0 && m_currentIndex < m_playlist.size()) {
        m_player->play();
    }
}

void Playback::pause()
{
    m_player->pause();
}

void Playback::toggle()
{
    if (m_player->state() == QMediaPlayer::PlayingState) {
        pause();
    } else {
        play();
    }
}

void Playback::seek(qint64 ms)
{
    m_player->setPosition(ms);
}

void Playback::next()
{
    if (m_playlist.isEmpty()) return;
    m_currentIndex = (m_currentIndex + 1) % m_playlist.size();
    loadCurrent();
}

void Playback::previous()
{
    if (m_playlist.isEmpty()) return;
    m_currentIndex = (m_currentIndex - 1 + m_playlist.size()) % m_playlist.size();
    loadCurrent();
}

void Playback::setPlaylist(const QList<QVariantMap> &songs, int startIndex)
{
    m_playlist = songs;
    m_playlistCount = songs.size();
    m_currentIndex = qBound(0, startIndex, m_playlistCount - 1);
    loadCurrent();
    emit playlistChanged();
    emit currentIndexChanged(m_currentIndex);
}

void Playback::appendSong(const QVariantMap &song)
{
    m_playlist.append(song);
    m_playlistCount = m_playlist.size();
    emit playlistChanged();
}

void Playback::removeAt(int index)
{
    if (index >= 0 && index < m_playlist.size()) {
        bool wasCurrent = (index == m_currentIndex);
        m_playlist.removeAt(index);
        m_playlistCount = m_playlist.size();
        if (m_playlist.isEmpty()) {
            m_currentIndex = -1;
            m_player->stop();
            m_currentId = 0;
            m_currentTitle.clear();
            m_currentArtist.clear();
            m_currentCover.clear();
            emit currentSongChanged();
        } else if (wasCurrent) {
            if (m_currentIndex >= m_playlist.size()) m_currentIndex = 0;
            loadCurrent();
        } else if (index < m_currentIndex) {
            m_currentIndex--;
        }
        emit playlistChanged();
        emit currentIndexChanged(m_currentIndex);
    }
}

void Playback::clear()
{
    m_playlist.clear();
    m_playlistCount = 0;
    m_currentIndex = -1;
    m_player->stop();
    m_currentId = 0;
    m_currentTitle.clear();
    m_currentArtist.clear();
    m_currentCover.clear();
    emit playlistChanged();
    emit currentSongChanged();
    emit currentIndexChanged(-1);
}

void Playback::loadCurrent()
{
    if (m_currentIndex < 0 || m_currentIndex >= m_playlist.size()) return;

    const QVariantMap &song = m_playlist[m_currentIndex];
    QString url = song["url"].toString();
    if (url.isEmpty()) {
        emit playbackError("No URL for song: " + song["title"].toString());
        next();
        return;
    }

    m_currentId = song["id"].toLongLong();
    m_currentTitle = song["title"].toString();
    m_currentArtist = song["artist"].toString();
    m_currentCover = song["cover"].toString();
    emit currentSongChanged();

    m_player->setMedia(QMediaContent(QUrl(url)));
    m_player->play();
}

void Playback::onStateChanged(QMediaPlayer::State state)
{
    bool wasPlaying = m_playing;
    m_playing = (state == QMediaPlayer::PlayingState);
    if (m_playing != wasPlaying) emit playingChanged(m_playing);
}

void Playback::onPositionChanged(qint64 pos)
{
    if (m_position != pos) {
        m_position = pos;
        emit positionChanged(pos);
    }
}

void Playback::onDurationChanged(qint64 dur)
{
    if (m_duration != dur) {
        m_duration = dur;
        emit durationChanged(dur);
    }
}

void Playback::onMediaStatusChanged(QMediaPlayer::MediaStatus status)
{
    if (status == QMediaPlayer::EndOfMedia) {
        next();
    } else if (status == QMediaPlayer::InvalidMedia) {
        emit playbackError("Invalid media, skipping");
        next();
    }
}

void Playback::onError(QMediaPlayer::Error err)
{
    if (err != QMediaPlayer::NoError) {
        QString msg = m_player->errorString();
        qWarning() << "Playback error:" << msg;
        emit playbackError(msg);
        next();
    }
}