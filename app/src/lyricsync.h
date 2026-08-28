#ifndef LYRICSYNC_H
#define LYRICSYNC_H

#include <QObject>
#include <QJsonArray>
#include <QJsonObject>
#include <QTimer>

class LyricSync : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int currentLine READ currentLine NOTIFY currentLineChanged)
    Q_PROPERTY(QString currentText READ currentText NOTIFY currentLineChanged)
    Q_PROPERTY(bool hasLyrics READ hasLyrics NOTIFY lyricsChanged)

public:
    explicit LyricSync(QObject *parent = nullptr);

    int currentLine() const { return m_currentLine; }
    QString currentText() const;
    bool hasLyrics() const { return m_lines.size() > 0; }

    Q_INVOKABLE void setLyrics(const QJsonArray &lines);
    Q_INVOKABLE void updatePosition(double seconds);
    Q_INVOKABLE QJsonArray lines() const { return m_lines; }

signals:
    void currentLineChanged();
    void lyricsChanged();

private:
    QJsonArray m_lines;
    int m_currentLine;
};

#endif // LYRICSYNC_H
