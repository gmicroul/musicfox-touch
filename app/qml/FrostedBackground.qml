import QtQuick 2.6

// Animated frosted-glass backdrop for the whole app (pages are transparent).
Item {
    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0f0c29" }
            GradientStop { position: 0.5; color: "#2a2052" }
            GradientStop { position: 1.0; color: "#24243e" }
        }
    }

    // soft color blobs (fake frosted-glass light spots) + slow breathing
    Rectangle {
        id: b1
        x: -90; y: -70; width: 360; height: 360; radius: 180
        color: "#7f5af0"; opacity: 0.50
        SequentialAnimation { loops: Animation.Infinite; running: true
            NumberAnimation { target: b1; property: "x"; from: -100; to: -60; duration: 24000 }
            NumberAnimation { target: b1; property: "x"; from: -60; to: -100; duration: 24000 }
        }
        SequentialAnimation { loops: Animation.Infinite; running: true
            NumberAnimation { target: b1; property: "y"; from: -80; to: -50; duration: 28000 }
            NumberAnimation { target: b1; property: "y"; from: -50; to: -80; duration: 28000 }
        }
    }
    Rectangle {
        id: b2
        x: parent.width - 210; y: parent.height * 0.35; width: 440; height: 440; radius: 220
        color: "#ff6a88"; opacity: 0.42
        SequentialAnimation { loops: Animation.Infinite; running: true
            NumberAnimation { target: b2; property: "x"; from: b2.x; to: b2.x-30; duration: 34000 }
            NumberAnimation { target: b2; property: "x"; from: b2.x-30; to: b2.x; duration: 34000 }
        }
        SequentialAnimation { loops: Animation.Infinite; running: true
            NumberAnimation { target: b2; property: "y"; from: b2.y; to: b2.y+30; duration: 30000 }
            NumberAnimation { target: b2; property: "y"; from: b2.y+30; to: b2.y; duration: 30000 }
        }
    }
    Rectangle {
        id: b3
        x: parent.width * 0.25; y: parent.height - 190; width: 500; height: 300; radius: 150
        color: "#2cb4ff"; opacity: 0.32
        SequentialAnimation { loops: Animation.Infinite; running: true
            NumberAnimation { target: b3; property: "x"; from: b3.x; to: b3.x+40; duration: 32000 }
            NumberAnimation { target: b3; property: "x"; from: b3.x+40; to: b3.x; duration: 32000 }
        }
        SequentialAnimation { loops: Animation.Infinite; running: true
            NumberAnimation { target: b3; property: "y"; from: b3.y; to: b3.y-25; duration: 36000 }
            NumberAnimation { target: b3; property: "y"; from: b3.y-25; to: b3.y; duration: 36000 }
        }
    }

    // bottom vignette for readable lists
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "#66000000" }
        }
    }
}
