#ifndef MODELS_H
#define MODELS_H

#include <QAbstractListModel>
#include <QVariantMap>

class SongListModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        ArtistRole,
        AlbumRole,
        DurationRole,
        FeeRole,
        CoverRole,
        UrlRole,
        BrRole,
        TypeRole
    };

    explicit SongListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setSongs(const QJsonArray &songs);
    void appendSongs(const QJsonArray &songs);
    void clear();
    QVariantMap getSong(int row) const;

public slots:
    void onSearchSongsResult(const QJsonArray &songs);

private:
    QList<QVariantMap> m_songs;
};

class PlaylistListModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        PlIdRole = Qt::UserRole + 1,
        PlNameRole,
        PlCoverRole,
        PlTrackCountRole,
        PlPlayCountRole,
        PlCreatorRole
    };

    explicit PlaylistListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setPlaylists(const QJsonArray &playlists);
    void clear();

private:
    QList<QVariantMap> m_playlists;
};

class ToplistModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        TlIdRole = Qt::UserRole + 1,
        TlNameRole,
        TlCoverRole
    };

    explicit ToplistModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setToplist(const QJsonArray &toplist);
    void clear();

private:
    QList<QVariantMap> m_lists;
};

class PlayQueueModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        QIdRole = Qt::UserRole + 1,
        QTitleRole,
        QArtistRole,
        QAlbumRole,
        QDurationRole,
        QCoverRole,
        QUrlRole,
        QCurrentRole
    };

    explicit PlayQueueModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setQueue(const QList<QVariantMap> &queue, int currentIndex);
    void updateCurrentIndex(int index);
    void append(const QVariantMap &song);
    void removeAt(int index);
    void clear();

    QVariantMap getSong(int row) const;

signals:
    void currentIndexChanged(int);

private:
    QList<QVariantMap> m_queue;
    int m_currentIndex;
};

class LyricModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        LyricTimeRole = Qt::UserRole + 1,
        LyricTextRole
    };

    explicit LyricModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setLyric(const QJsonArray &lines);
    void clear();
    int findCurrentLine(qint64 positionMs) const;

private:
    QList<QPair<qint64, QString>> m_lines;
};

#endif // MODELS_H