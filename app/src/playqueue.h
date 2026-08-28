#ifndef PLAYQUEUE_H
#define PLAYQUEUE_H

#include <QObject>
#include <QJsonArray>
#include <QJsonObject>

class PlayQueue : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int currentIndex READ currentIndex WRITE setCurrentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(QJsonObject currentSong READ currentSong NOTIFY currentSongChanged)

public:
    explicit PlayQueue(QObject *parent = nullptr);

    int currentIndex() const { return m_currentIndex; }
    int count() const { return m_songs.size(); }
    QJsonObject currentSong() const;

    Q_INVOKABLE void setSongs(const QJsonArray &songs);
    Q_INVOKABLE QJsonObject songAt(int index) const;
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE QJsonArray songs() const { return m_songs; }

signals:
    void currentIndexChanged();
    void countChanged();
    void currentSongChanged();
    void songChanged(const QJsonObject &song);

public slots:
    void setCurrentIndex(int index);

private:
    QJsonArray m_songs;
    int m_currentIndex;
};

#endif // PLAYQUEUE_H
