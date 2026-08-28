#include "mpvcontroller.h"
#include <QDebug>

MpvController::MpvController(QObject *parent)
    : QObject(parent)
    , m_player(new QMediaPlayer(this))
    , m_position(0)
    , m_duration(0)
    , m_volume(80)
    , m_pause(false)
    , m_state("idle")
{
    m_player->setVolume(m_volume);

    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, &MpvController::onMediaStatusChanged);
    connect(m_player, &QMediaPlayer::stateChanged, this, &MpvController::onStateChanged);
    connect(m_player, &QMediaPlayer::positionChanged, this, &MpvController::onPositionChanged);
    connect(m_player, &QMediaPlayer::durationChanged, this, &MpvController::onDurationChanged);
    connect(m_player, SIGNAL(error(QMediaPlayer::Error,QString)),
            this, SLOT(onError(QMediaPlayer::Error,QString)));
}

MpvController::~MpvController()
{
}

bool MpvController::isConnected() const
{
    return m_player->mediaStatus() != QMediaPlayer::NoMedia;
}

void MpvController::loadFile(const QString &url)
{
    qDebug() << "MpvController::loadFile" << url;
    m_player->setMedia(QMediaContent(QUrl(url)));
    m_player->play();
    m_state = "loading";
    emit stateChanged();
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
    if (m_player->state() == QMediaPlayer::PlayingState)
        m_player->pause();
    else
        m_player->play();
}

void MpvController::seek(double seconds)
{
    m_player->setPosition(static_cast<qint64>(seconds * 1000));
}

void MpvController::doStop()
{
    m_player->stop();
    m_position = 0;
    m_duration = 0;
    m_state = "idle";
    emit positionChanged();
    emit durationChanged();
    emit stateChanged();
}

void MpvController::setVolume(int vol)
{
    m_volume = qBound(0, vol, 150);
    m_player->setVolume(qMin(m_volume, 100));
    emit volumeChanged();
}

void MpvController::setPaused(bool p)
{
    if (p)
        m_player->pause();
    else
        m_player->play();
}

void MpvController::connectToMpv(const QString &socketPath)
{
    Q_UNUSED(socketPath);
}

void MpvController::getProperty(const QString &name)
{
    Q_UNUSED(name);
}

void MpvController::onMediaStatusChanged(QMediaPlayer::MediaStatus status)
{
    qDebug() << "MediaStatus changed:" << status;
    if (status == QMediaPlayer::EndOfMedia) {
        emit endOfFile();
    }
}

void MpvController::onStateChanged(QMediaPlayer::State state)
{
    switch (state) {
    case QMediaPlayer::PlayingState:
        m_pause = false;
        m_state = "playing";
        break;
    case QMediaPlayer::PausedState:
        m_pause = true;
        m_state = "paused";
        break;
    case QMediaPlayer::StoppedState:
        m_pause = false;
        m_state = "idle";
        break;
    }
    qDebug() << "MpvController::onStateChanged ->" << m_state;
    emit pauseChanged();
    emit stateChanged();
    emit playerStateChanged();
}

void MpvController::onPositionChanged(qint64 position)
{
    m_position = position / 1000.0;
    emit positionChanged();
}

void MpvController::onDurationChanged(qint64 duration)
{
    m_duration = duration / 1000.0;
    emit durationChanged();
}

void MpvController::onError(QMediaPlayer::Error error, const QString &errorString)
{
    qWarning() << "MpvController error:" << error << errorString;
    emit mpvError(errorString);
}
