import QtQuick 2.6

// Reusable spinning vinyl record + optional tonearm.
// Used by the player page and the desktop (cover) card.
// QtQuick 2.6 compatible: NumberAnimation / Behavior are fine.
Item {
    id: root
    width: 220; height: 220
    // square: caller sets width & height to the desired diameter

    // --- public properties ---
    property string coverSource      // album-art URL (may be empty)
    property bool playing: false
    property bool showTonearm: true
    property bool compact: false      // compact = smaller / less chrome (mini widget / cover)
    property int spinDuration: 14000  // ms per full revolution
    property bool pausedVisible: false// show a small II overlay while paused (compact mode)

    // disc radius (slightly smaller than the bounding box)
    readonly property real discR: Math.min(width, height) * (compact ? 0.50 : 0.44)

    // --- disc body + grooves + cover label ---
    Item {
        id: discRoot
        anchors.centerIn: parent
        width: discR * 2; height: width
        z: 2

        // whole disc rotates as a unit
        transformOrigin: Item.Center
        NumberAnimation on rotation {
            id: spinAnim
            from: 0; to: 360
            loops: Animation.Infinite
            duration: root.spinDuration
            running: root.playing
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#0b0b12"
            border.color: "#44ffffff"; border.width: 1
            opacity: 0.97
        }

        // grooves - concentric circles from inner to outer edge (14 full circles)
        Repeater {
            model: 14
            Rectangle {
                width: (parent.width - 8) * (0.08 + index * 0.06)
                height: width
                anchors.centerIn: parent
                radius: width / 2
                color: "transparent"
                border.color: "#ffffff"
                border.width: 1
                opacity: 0.12 + index * 0.04
            }
        }

        // outermost groove: arc with a gap at top (12 o'clock)
        Canvas {
            id: outerArc
            width: (parent.width - 8) * 0.92
            height: width
            anchors.centerIn: parent
            z: 4
            renderTarget: Canvas.Image
            onPaint: {
                var ctx = getContext("2d")
                var r = width / 2 - 1
                var cx = width / 2
                var cy = height / 2
                var gap = 0.22 * Math.PI
                ctx.lineWidth = 1
                ctx.strokeStyle = "#ffffff"
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.arc(cx, cy, r, gap, 2 * Math.PI - gap)
                ctx.stroke()
            }
            Timer {
                interval: 300; repeat: true; running: true
                onTriggered: outerArc.requestPaint()
            }
        }

        // light streak
        Rectangle {
            width: parent.width * 0.5; height: parent.height * 0.16
            anchors.centerIn: parent
            rotation: -34
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00ffffff" }
                GradientStop { position: 0.5; color: "#28ffffff" }
                GradientStop { position: 1.0; color: "#00ffffff" }
            }
        }

        // center label holds the cover art
        Rectangle {
            id: label
            width: parent.width * 0.40; height: width
            anchors.centerIn: parent
            radius: width / 2
            color: "#152942"
            border.color: "#aaffffff"; border.width: 2
            clip: true
            Image {
                id: cover
                anchors.fill: parent
                anchors.margins: 3
                source: root.coverSource || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
            Text {
                anchors.centerIn: parent
                text: "\u266B"
                font.pixelSize: Math.min(parent.width, 40) * 0.5
                color: "#4fc3f7"
                visible: (root.coverSource || "") === ""
            }
        }

        // spindle hole + pin glow
        Rectangle {
            width: Math.max(8, 10 * app.s); height: width
            anchors.centerIn: parent
            radius: width / 2
            color: "#e8e8e8"
            border.color: "#888888"; border.width: 1
        }

        // visible rotation pivot marker at disc center (crosshair, above cover)
        Item {
            width: Math.max(12, 14 * app.s); height: width
            anchors.centerIn: parent
            z: 5
            Rectangle {
                width: parent.width; height: Math.max(1, 2 * app.s)
                anchors.centerIn: parent
                color: "#ffcc00"
            }
            Rectangle {
                width: Math.max(1, 2 * app.s); height: parent.height
                anchors.centerIn: parent
                color: "#ffcc00"
            }
        }

        // optional paused badge (compact mode)
        Rectangle {
            anchors.centerIn: parent
            width: label.width * 0.58; height: width
            radius: width / 2
            color: "#66000000"
            border.color: "#ffffff"; border.width: 1
            visible: root.pausedVisible && root.compact
            Text {
                anchors.centerIn: parent
                text: "\u23F8"
                color: "#ffffff"
                font.pixelSize: 18 * app.s
            }
        }
    }

    // --- disc drop shadow ---
    Rectangle {
        z: 1
        opacity: 0.45
        visible: !root.compact
        anchors.centerIn: parent
        width: discR * 2; height: discR * 0.18
        radius: width / 2
        color: "#66000000"
    }

    // --- tonearm ---
    Item {
        id: tonearm
        anchors.fill: parent
        z: 3
        visible: root.showTonearm

        // pivot point: edge of the disc
        property real cx: parent.width * 0.5
        property real cy: parent.height * 0.5
        property real px: parent.cx + root.discR * 0.9
        property real py: parent.cy - root.discR * 0.62
        property real len: root.discR * 0.92
        // play = needle down at disc edge (72°); pause = needle raised (143°)
        property real ang: root.playing ? 72 : 143

        // smooth angle transition on play toggle
        Behavior on ang { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        Connections {
            target: root
            onPlayingChanged: tonearm.ang = root.playing ? 72 : 143
        }

        Rectangle {
            id: armBase
            x: parent.px - width * 0.5; y: parent.py - height * 0.5
            width: Math.max(14, 16 * app.s); height: width
            radius: width / 2
            color: "#14202b"
            border.color: "#55444444"; border.width: 1
            z: 1
        }

        Rectangle {
            id: arm
            x: parent.px; y: parent.py
            // pivot at its left centre
            transformOrigin: Item.TopLeft
            width: parent.len; height: Math.max(5, 6 * app.s)
            rotation: parent.ang
            color: "#303c4b"
            border.color: "#44333333"; border.width: 1
            radius: height / 2
        }

        Rectangle {
            id: headshell
            x: parent.px + parent.len * Math.cos(parent.ang * Math.PI / 180) - width * 0.5
            y: parent.py + parent.len * Math.sin(parent.ang * Math.PI / 180) - height * 0.5
            width: Math.max(12, 14 * app.s); height: width
            radius: width / 2
            color: "#cdd5e0"
            border.color: "#888888"; border.width: 1
            z: 2
            visible: root.showTonearm
        }

        Rectangle {
            id: counterweight
            x: parent.px - width * 0.85; y: parent.py * 0.6
            width: Math.max(16, 18 * app.s); height: width
            radius: width / 2
            color: "#1d2a3a"
            border.color: "#66ffffff"; border.width: 1
            z: 2
        }
    }
}
