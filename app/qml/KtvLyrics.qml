import QtQuick 2.6

// KTV-style lyric stage: shows the line before, the current line (with a
// karaoke-style progress fill) and the line after. Driven by a QJsonArray
// whose entries each carry { "time": seconds, "text": "..." }.
Item {
    id: root
    width: parent ? parent.width : 320
    height: 190 * app.s

    property var lines: []
    property int currentLine: -1
    property double position: 0.0
    property double duration: 0.0
    property bool playing: false
    property color accent: "#4fc3f7"
    property bool compact: false    // smaller type when embedded in the player page
    property bool showHint: true

    readonly property bool hasLyrics: root.lines.length > 0

    function textAt(i) {
        if (i < 0 || i >= root.lines.length) return ""
        var l = root.lines[i]
        return (l && l.text !== undefined) ? l.text : ""
    }
    function timeAt(i) {
        if (i < 0 || i >= root.lines.length) return 0
        var l = root.lines[i]
        return (l && l.time !== undefined) ? Number(l.time) : 0
    }
    // 0..1 progress of the current line, based on next line's time.
    function lineProgress(i) {
        if (i < 0 || i >= root.lines.length) return 0
        var t0 = timeAt(i)
        var t1 = (i + 1 < root.lines.length) ? timeAt(i + 1) : (t0 + 6)
        if (t1 <= t0) return 0
        return Math.max(0, Math.min(1, (root.position - t0) / (t1 - t0)))
    }

    // fallback glow pulse when no lyrics
    SequentialAnimation {
        running: !root.hasLyrics && root.playing
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "_glow"; from: 0.25; to: 0.45; duration: 700 }
        NumberAnimation { target: root; property: "_glow"; from: 0.45; to: 0.25; duration: 700 }
    }
    property real _glow: 0.35

    Rectangle {
        anchors.fill: parent
        anchors.margins: 8 * app.s
        radius: 16
        color: root.hasLyrics ? "#22ffffff" : "#18ffffff"
        border.color: "#55ffffff"
        border.width: 1
        visible: !root.hasLyrics
        opacity: 0.9
        Text {
            anchors.centerIn: parent
            text: root.playing ? "\u266B Waiting for lyrics…" : "\u23F8 Paused"
            color: root.accent
            font.pixelSize: 20 * app.s
            font.bold: true
        }
        // little spectrum dots while idle
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 18 * app.s
            spacing: 4 * app.s
            Repeater {
                model: 8
                Rectangle {
                    width: 5 * app.s; height: 5 * app.s
                    radius: 2.5 * app.s
                    color: root.accent
                    opacity: 0.25 + (root._glow - 0.35) * 0.7 + Math.sin(root._glow * 6 + index * 0.6) * 0.3
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.leftMargin: 12 * app.s
        anchors.rightMargin: 12 * app.s
        spacing: 6 * app.s
        visible: root.hasLyrics

        // prev line
        Text {
            width: root.width - 24 * app.s
            text: root.textAt(root.currentLine - 1)
            color: "#8b98a8"
            font.pixelSize: root.compact ? 14 * app.s : 17 * app.s
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight; wrapMode: Text.WordWrap
            opacity: root.currentLine > 0 ? 1 : 0.0
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }

        // current line with karaoke fill.
        // NOTE: the lit layer keeps full-line width and is revealed
        // through a clipped window, so centered text never squeezes
        // or shifts while the fill grows.
        Item {
            id: curWrap
            width: root.width - 24 * app.s; height: root.compact ? 44 * app.s : 52 * app.s
            clip: false
            // full line in dim color
            Text {
                id: curBase
                anchors.fill: parent
                text: root.textAt(root.currentLine)
                color: "#d0d7e0"
                font.pixelSize: root.compact ? 20 * app.s : 23 * app.s; font.bold: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight; wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
            // lit portion grows with progress (clipped window, full-width text)
            Item {
                id: curFill
                width: curWrap.width * root.lineProgress(root.currentLine)
                height: curWrap.height
                clip: true
                Text {
                    width: curWrap.width; height: curWrap.height
                    text: root.textAt(root.currentLine)
                    color: root.accent
                    font.pixelSize: root.compact ? 20 * app.s : 23 * app.s; font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight; wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
            }
        }

        // next line
        Text {
            width: root.width - 24 * app.s
            text: root.textAt(root.currentLine + 1)
            color: "#6a7992"
            font.pixelSize: root.compact ? 14 * app.s : 17 * app.s
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight; wrapMode: Text.WordWrap
            opacity: root.hasLyrics ? 1 : 0.0
            Behavior on opacity { NumberAnimation { duration: 220 } }
        }
    }

    Text {
        anchors.left: parent.left; anchors.leftMargin: 16 * app.s
        anchors.bottom: parent.bottom; anchors.bottomMargin: 10 * app.s
        text: root.playing ? qsTr("Sing along…") : qsTr("Paused")
        color: root.accent; font.pixelSize: 12 * app.s; opacity: 0.6
        visible: root.hasLyrics && root.showHint
    }
}
