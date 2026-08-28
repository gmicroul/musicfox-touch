#ifndef PLAYBACK_H
#define PLAYBACK_H

#include <QObject>
#include <QMediaPlayer>
#include <QList>
#include <QVariantMap>

class Playback : public QObject
{
    Q_OBJECT
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentSongChanged)
    Q_PROPERTY(QString currentArtist READ currentArtist NOTIFY currentSongChanged)
    Q_PROPERTY(QString currentCover READ currentCover NOTIFY currentSongChanged)
    Q_PROPERTY(qint64 currentId READ currentId NOTIFY currentSongChanged)
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(int playlistCount READ playlistCount NOTIFY playlistChanged)

public:
    explicit Playback(QObject *parent = nullptr);
    ~Playback();

    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    int volume() const { return m_volume; }
    bool playing() const { return m_playing; }
    QString currentTitle() const { return m_currentTitle; }
    QString currentArtist() const { return m_currentArtist; }
    QString currentCover() const { return m_currentCover; }
    qint64 currentId() const { return m_currentId; }
    int currentIndex() const { return m_currentIndex; }
    int playlistCount() const { return m_playlistCount; }

    void setVolume(int vol);
    void play();
    void pause();
    void toggle();
    void seek(qint64 ms);
    void next();
    void previous();

    void setPlaylist(const QList<QVariantMap> &songs, int startIndex = 0);
    void appendSong(const QVariantMap &song);
    void removeAt(int index);
    void clear();

signals:
    void positionChanged(qint64);
    void durationChanged(qint64);
    void volumeChanged(int);
    void playingChanged(bool);
    void currentSongChanged();
    void currentIndexChanged(int);
    void playlistChanged();
    void playbackError(const QString &msg);

private slots:
    void onStateChanged(QMediaPlayer::State state);
    void onPositionChanged(qint64 pos);
    void onDurationChanged(qint64 dur);
    void onMediaStatusChanged(QMediaPlayer::MediaStatus status);
    void onError(QMediaPlayer::Error err);

private:
    void loadCurrent();

    QMediaPlayer *m_player;
    QList<QVariantMap> m_playlist;
    int m_currentIndex;
    int m_playlistCount;
    qint64 m_position;
    qint64 m_duration;
    int m_volume;
    bool m_playing;
    qint64 m_currentId;
    QString m_currentTitle;
    QString m_currentArtist;
    QString m_currentCover;
};

#endif // PLAYBACK_H