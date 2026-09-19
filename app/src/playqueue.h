#ifndef PLAYQUEUE_H
#define PLAYQUEUE_H

#include <QObject>
#include <QJsonArray>
#include <QJsonObject>
#include <QSet>

class PlayQueue : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int currentIndex READ currentIndex WRITE setCurrentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QJsonObject currentSong READ currentSong NOTIFY currentSongChanged)
    Q_PROPERTY(int playMode READ playMode WRITE setPlayMode NOTIFY playModeChanged)

public:
    explicit PlayQueue(QObject *parent = nullptr);

    int currentIndex() const { return m_currentIndex; }
    int count() const { return m_songs.size(); }
    QJsonObject currentSong() const;
    int playMode() const { return m_playMode; }  // 0 = list loop, 1 = single loop

    Q_INVOKABLE void setSongs(const QJsonArray &songs);
    Q_INVOKABLE QJsonObject songAt(int index) const;
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE QJsonArray songs() const { return m_songs; }
    Q_INVOKABLE void replayCurrent();
    Q_INVOKABLE void setPlayMode(int mode);
    Q_INVOKABLE void togglePlayMode();
    Q_INVOKABLE bool isFavorite(qint64 id) const;
    Q_INVOKABLE void toggleFavorite(qint64 id);

signals:
    void currentIndexChanged();
    void countChanged();
    void currentSongChanged();
    void songChanged(const QJsonObject &song);
    void playModeChanged();
    void favoritesChanged();

public slots:
    void setCurrentIndex(int index);

private:
    void loadState();
    void saveState();

    QJsonArray m_songs;
    int m_currentIndex;
    int m_playMode;
    QSet<qint64> m_favorites;
};

#endif // PLAYQUEUE_H
