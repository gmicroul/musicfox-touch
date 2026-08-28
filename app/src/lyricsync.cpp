#include "lyricsync.h"

LyricSync::LyricSync(QObject *parent)
    : QObject(parent)
    , m_currentLine(-1)
{
}

QString LyricSync::currentText() const
{
    if (m_currentLine >= 0 && m_currentLine < m_lines.size()) {
        return m_lines.at(m_currentLine).toObject().value("text").toString();
    }
    return QString();
}

void LyricSync::setLyrics(const QJsonArray &lines)
{
    m_lines = lines;
    m_currentLine = -1;
    emit lyricsChanged();
    emit currentLineChanged();
}

void LyricSync::updatePosition(double seconds)
{
    if (m_lines.isEmpty()) return;

    int newLine = -1;
    for (int i = m_lines.size() - 1; i >= 0; --i) {
        double t = m_lines.at(i).toObject().value("time").toDouble();
        if (seconds >= t - 0.1) {
            newLine = i;
            break;
        }
    }

    if (newLine != m_currentLine) {
        m_currentLine = newLine;
        emit currentLineChanged();
    }
}
