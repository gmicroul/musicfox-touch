#include "models.h"
#include <QJsonArray>
#include <QJsonObject>
#include <QDebug>

SongListModel::SongListModel(QObject *parent) : QAbstractListModel(parent) {}

int SongListModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_songs.size();
}

QVariant SongListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_songs.size()) return QVariant();
    const QVariantMap &song = m_songs[index.row()];

    switch (role) {
    case IdRole: return song["id"];
    case TitleRole: return song["title"];
    case ArtistRole: return song["artist"];
    case AlbumRole: return song["album"];
    case DurationRole: return song["duration"];
    case FeeRole: return song["fee"];
    case CoverRole: return song["cover"];
    case UrlRole: return song["url"];
    case BrRole: return song["br"];
    case TypeRole: return song["type"];
    default: return QVariant();
    }
}

QHash<int, QByteArray> SongListModel::roleNames() const
{
    return {
        {IdRole, "songId"},
        {TitleRole, "title"},
        {ArtistRole, "artist"},
        {AlbumRole, "album"},
        {DurationRole, "duration"},
        {FeeRole, "fee"},
        {CoverRole, "cover"},
        {UrlRole, "url"},
        {BrRole, "bitrate"},
        {TypeRole, "type"}
    };
}

void SongListModel::setSongs(const QJsonArray &songs)
{
    beginResetModel();
    m_songs.clear();
    for (const QJsonValue &v : songs) {
        QJsonObject o = v.toObject();
        QVariantMap song;
        song["id"] = o["id"].toVariant().toLongLong();
        song["title"] = o["name"].toString();
        song["artist"] = o["artists"].toString();
        song["album"] = o["album"].toString();
        song["duration"] = o["duration"].toVariant().toLongLong();
        song["fee"] = o["fee"].toInt();
        song["cover"] = o["coverUrl"].toString();
        song["url"] = "";
        song["br"] = 0;
        song["type"] = "";
        m_songs.append(song);
    }
    endResetModel();
}

void SongListModel::appendSongs(const QJsonArray &songs)
{
    int start = m_songs.size();
    int count = songs.size();
    beginInsertRows(QModelIndex(), start, start + count - 1);
    for (const QJsonValue &v : songs) {
        QJsonObject o = v.toObject();
        QVariantMap song;
        song["id"] = o["id"].toVariant().toLongLong();
        song["title"] = o["name"].toString();
        song["artist"] = o["artists"].toString();
        song["album"] = o["album"].toString();
        song["duration"] = o["duration"].toVariant().toLongLong();
        song["fee"] = o["fee"].toInt();
        song["cover"] = o["coverUrl"].toString();
        song["url"] = "";
        song["br"] = 0;
        song["type"] = "";
        m_songs.append(song);
    }
    endInsertRows();
}

void SongListModel::clear()
{
    beginResetModel();
    m_songs.clear();
    endResetModel();
}

QVariantMap SongListModel::getSong(int row) const
{
    if (row >= 0 && row < m_songs.size()) return m_songs[row];
    return QVariantMap();
}

void SongListModel::onSearchSongsResult(const QJsonArray &songs)
{
    setSongs(songs);
}

PlaylistListModel::PlaylistListModel(QObject *parent) : QAbstractListModel(parent) {}

int PlaylistListModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_playlists.size();
}

QVariant PlaylistListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_playlists.size()) return QVariant();
    const QVariantMap &pl = m_playlists[index.row()];

    switch (role) {
    case PlIdRole: return pl["id"];
    case PlNameRole: return pl["name"];
    case PlCoverRole: return pl["cover"];
    case PlTrackCountRole: return pl["trackCount"];
    case PlPlayCountRole: return pl["playCount"];
    case PlCreatorRole: return pl["creator"];
    default: return QVariant();
    }
}

QHash<int, QByteArray> PlaylistListModel::roleNames() const
{
    return {
        {PlIdRole, "playlistId"},
        {PlNameRole, "name"},
        {PlCoverRole, "cover"},
        {PlTrackCountRole, "trackCount"},
        {PlPlayCountRole, "playCount"},
        {PlCreatorRole, "creator"}
    };
}

void PlaylistListModel::setPlaylists(const QJsonArray &playlists)
{
    beginResetModel();
    m_playlists.clear();
    for (const QJsonValue &v : playlists) {
        QJsonObject o = v.toObject();
        QVariantMap pl;
        pl["id"] = o["id"].toVariant().toLongLong();
        pl["name"] = o["name"].toString();
        pl["cover"] = o["coverUrl"].toString();
        pl["trackCount"] = o["trackCount"].toInt();
        pl["playCount"] = o["playCount"].toVariant().toLongLong();
        pl["creator"] = o["creatorName"].toString();
        m_playlists.append(pl);
    }
    endResetModel();
}

void PlaylistListModel::clear()
{
    beginResetModel();
    m_playlists.clear();
    endResetModel();
}

ToplistModel::ToplistModel(QObject *parent) : QAbstractListModel(parent) {}

int ToplistModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_lists.size();
}

QVariant ToplistModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_lists.size()) return QVariant();
    const QVariantMap &tl = m_lists[index.row()];

    switch (role) {
    case TlIdRole: return tl["id"];
    case TlNameRole: return tl["name"];
    case TlCoverRole: return tl["cover"];
    default: return QVariant();
    }
}

QHash<int, QByteArray> ToplistModel::roleNames() const
{
    return {
        {TlIdRole, "toplistId"},
        {TlNameRole, "name"},
        {TlCoverRole, "cover"}
    };
}

void ToplistModel::setToplist(const QJsonArray &toplist)
{
    beginResetModel();
    m_lists.clear();
    for (const QJsonValue &v : toplist) {
        QJsonObject o = v.toObject();
        QVariantMap tl;
        tl["id"] = o["id"].toVariant().toLongLong();
        tl["name"] = o["name"].toString();
        tl["cover"] = o["cover"].toString();
        m_lists.append(tl);
    }
    endResetModel();
}

void ToplistModel::clear()
{
    beginResetModel();
    m_lists.clear();
    endResetModel();
}

PlayQueueModel::PlayQueueModel(QObject *parent) : QAbstractListModel(parent), m_currentIndex(-1) {}

int PlayQueueModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_queue.size();
}

QVariant PlayQueueModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_queue.size()) return QVariant();
    const QVariantMap &song = m_queue[index.row()];

    switch (role) {
    case QIdRole: return song["id"];
    case QTitleRole: return song["title"];
    case QArtistRole: return song["artist"];
    case QAlbumRole: return song["album"];
    case QDurationRole: return song["duration"];
    case QCoverRole: return song["cover"];
    case QUrlRole: return song["url"];
    case QCurrentRole: return (index.row() == m_currentIndex);
    default: return QVariant();
    }
}

QHash<int, QByteArray> PlayQueueModel::roleNames() const
{
    return {
        {QIdRole, "songId"},
        {QTitleRole, "title"},
        {QArtistRole, "artist"},
        {QAlbumRole, "album"},
        {QDurationRole, "duration"},
        {QCoverRole, "cover"},
        {QUrlRole, "url"},
        {QCurrentRole, "isCurrent"}
    };
}

void PlayQueueModel::setQueue(const QList<QVariantMap> &queue, int currentIndex)
{
    beginResetModel();
    m_queue = queue;
    m_currentIndex = currentIndex;
    endResetModel();
    emit currentIndexChanged(m_currentIndex);
}

void PlayQueueModel::updateCurrentIndex(int newIndex)
{
    if (newIndex == m_currentIndex) return;
    int old = m_currentIndex;
    m_currentIndex = newIndex;
    if (old >= 0 && old < m_queue.size()) {
        emit dataChanged(createIndex(old, 0), createIndex(old, 0), {QCurrentRole});
    }
    if (newIndex >= 0 && newIndex < m_queue.size()) {
        emit dataChanged(createIndex(newIndex, 0), createIndex(newIndex, 0), {QCurrentRole});
    }
    emit currentIndexChanged(newIndex);
}

void PlayQueueModel::append(const QVariantMap &song)
{
    int row = m_queue.size();
    beginInsertRows(QModelIndex(), row, row);
    m_queue.append(song);
    endInsertRows();
}

void PlayQueueModel::removeAt(int index)
{
    if (index >= 0 && index < m_queue.size()) {
        beginRemoveRows(QModelIndex(), index, index);
        m_queue.removeAt(index);
        endRemoveRows();
        if (index <= m_currentIndex && m_currentIndex > 0) {
            m_currentIndex--;
            emit currentIndexChanged(m_currentIndex);
        }
    }
}

void PlayQueueModel::clear()
{
    beginResetModel();
    m_queue.clear();
    m_currentIndex = -1;
    endResetModel();
    emit currentIndexChanged(-1);
}

QVariantMap PlayQueueModel::getSong(int row) const
{
    if (row >= 0 && row < m_queue.size()) return m_queue[row];
    return QVariantMap();
}

LyricModel::LyricModel(QObject *parent) : QAbstractListModel(parent) {}

int LyricModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_lines.size();
}

QVariant LyricModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_lines.size()) return QVariant();
    const auto &line = m_lines[index.row()];

    switch (role) {
    case LyricTimeRole: return line.first;
    case LyricTextRole: return line.second;
    default: return QVariant();
    }
}

QHash<int, QByteArray> LyricModel::roleNames() const
{
    return {
        {LyricTimeRole, "time"},
        {LyricTextRole, "text"}
    };
}

void LyricModel::setLyric(const QJsonArray &lines)
{
    beginResetModel();
    m_lines.clear();
    for (const QJsonValue &v : lines) {
        QJsonObject o = v.toObject();
        qint64 time = o["time"].toDouble() * 1000;
        QString text = o["text"].toString();
        m_lines.append(qMakePair(time, text));
    }
    endResetModel();
}

void LyricModel::clear()
{
    beginResetModel();
    m_lines.clear();
    endResetModel();
}

int LyricModel::findCurrentLine(qint64 positionMs) const
{
    int idx = -1;
    for (int i = 0; i < m_lines.size(); ++i) {
        if (m_lines[i].first <= positionMs) {
            idx = i;
        } else {
            break;
        }
    }
    return idx;
}