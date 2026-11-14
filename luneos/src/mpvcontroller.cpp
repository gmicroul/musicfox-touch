#include "mpvcontroller.h"
#include <QDebug>
#include <QtMath>

MpvController::MpvController(QObject *parent)
    : QObject(parent), m_player(new QMediaPlayer(this)), m_audio(new QAudioOutput(this))
{
    m_player->setAudioOutput(m_audio);
    m_audio->setVolume(m_volume / 100.0);
    connect(m_player, &QMediaPlayer::positionChanged, this, &MpvController::positionChanged);
    connect(m_player, &QMediaPlayer::durationChanged, this, &MpvController::durationChanged);
    connect(m_player, &QMediaPlayer::playbackStateChanged, this, [this](QMediaPlayer::PlaybackState state) {
        setState(state == QMediaPlayer::PlayingState ? "playing" :
                 state == QMediaPlayer::PausedState ? "paused" : "idle");
        emit pauseChanged();
        emit playerStateChanged();
    });
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus status) {
        emit connectedChanged();
        if (status == QMediaPlayer::EndOfMedia)
            emit endOfFile();
    });
    connect(m_player, &QMediaPlayer::errorOccurred, this, [this](QMediaPlayer::Error, const QString &message) {
        setState("error");
        qWarning() << "Playback error:" << message;
        emit mpvError(message);
    });
}

bool MpvController::isConnected() const
{
    return !m_player->source().isEmpty() && m_player->mediaStatus() != QMediaPlayer::InvalidMedia;
}

void MpvController::setState(const QString &state)
{
    if (m_state == state)
        return;
    m_state = state;
    emit stateChanged();
}

void MpvController::loadFile(const QString &url)
{
    const QUrl source(url);
    if (!source.isValid() || source.isEmpty()) {
        emit mpvError(QStringLiteral("Invalid audio URL"));
        return;
    }
    setState("loading");
    m_player->setSource(source);
    m_player->play();
}

void MpvController::play()
{
    m_player->play();
}

void MpvController::doPause()
{
    m_player->pause();
}

void MpvController::togglePause()
{
    if (isPaused() || m_player->playbackState() == QMediaPlayer::StoppedState)
        play();
    else
        doPause();
}

void MpvController::seek(double seconds)
{
    if (!qIsFinite(seconds))
        return;
    seconds = qMax(0.0, seconds);
    if (duration() > 0)
        seconds = qMin(seconds, duration());
    m_player->setPosition(qRound64(seconds * 1000.0));
}

void MpvController::doStop()
{
    m_player->stop();
    setState("idle");
}

void MpvController::setVolume(int volume)
{
    volume = qBound(0, volume, 150);
    if (volume == m_volume)
        return;
    m_volume = volume;
    m_audio->setVolume(qMin(volume, 100) / 100.0);
    emit volumeChanged();
}

void MpvController::setPaused(bool paused)
{
    if (paused)
        doPause();
    else
        play();
}

void MpvController::connectToMpv(const QString &socketPath)
{
    Q_UNUSED(socketPath);
}

void MpvController::getProperty(const QString &name)
{
    const QVariant value = property(name.toUtf8().constData());
    if (value.isValid())
        emit propertyChanged(name, value);
}
