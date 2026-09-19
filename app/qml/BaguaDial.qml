import QtQuick 2.6

// Decorative Bagua (eight-trigram) dial in gold-on-black ink style.
// Static ring (does not rotate); the VinylDisc spins inside it.
// Order of trigrams (clockwise from top) follows the reference mockup:
// 乾 坤 艮 巽 坎 震 离 兑
// QtQuick 2.6 compatible: only Rectangle / Text / Repeater.
Item {
    id: root
    // square: caller sets width & height to the stage size

    property color gold: "#e3b959"
    property color dimGold: "#9a7d33"

    property var names: ["乾", "坤", "艮", "巽", "坎", "震", "离", "兑"]
    property var subs:  ["天", "地", "山", "风", "水", "雷", "火", "泽"]

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real outerR: Math.min(width, height) / 2 - 2 * app.s
    readonly property real tickR: outerR - 7 * app.s
    readonly property real labelR: outerR - 34 * app.s

    // outer thin gold ring
    Rectangle {
        anchors.centerIn: parent
        width: outerR * 2; height: width
        radius: width / 2
        color: "transparent"
        border.color: root.gold
        border.width: Math.max(1, 1.5 * app.s)
        opacity: 0.85
    }

    // inner thin gold ring (frames the disc)
    Rectangle {
        anchors.centerIn: parent
        width: (outerR - 16 * app.s) * 2; height: width
        radius: width / 2
        color: "transparent"
        border.color: root.gold
        border.width: 1
        opacity: 0.45
    }

    // 48 tick marks around the ring
    Repeater {
        model: 48
        Rectangle {
            property real angDeg: index * 7.5
            property real ang: angDeg * Math.PI / 180
            property bool major: (index % 6 === 0)
            width: Math.max(1, (major ? 2 : 1) * app.s)
            height: (major ? 9 : 5) * app.s
            radius: width / 2
            color: root.gold
            opacity: major ? 0.9 : 0.4
            x: root.cx + root.tickR * Math.cos(ang) - width / 2
            y: root.cy + root.tickR * Math.sin(ang) - height / 2
            rotation: angDeg + 90
        }
    }

    // 8 trigram labels (name + nature), upright, no rotation
    Repeater {
        model: 8
        Item {
            property real ang: (-90 + index * 45) * Math.PI / 180
            width: 52 * app.s; height: 56 * app.s
            x: root.cx + root.labelR * Math.cos(ang) - width / 2
            y: root.cy + root.labelR * Math.sin(ang) - height / 2
            Column {
                anchors.centerIn: parent
                spacing: 1
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.names[index]
                    font.pixelSize: 19 * app.s
                    font.bold: true
                    color: root.gold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.subs[index]
                    font.pixelSize: 11 * app.s
                    color: root.dimGold
                }
            }
        }
    }
}
