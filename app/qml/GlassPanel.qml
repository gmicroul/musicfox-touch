import QtQuick 2.6

// Glass panel card, adapted from harbour-pi.
// Translucent tint + light border + top highlight edge.
// Children go into the clipped inner item (default property).
Item {
    id: root
    property int radius: 16
    property color tint: "#2effffff"
    property color borderColor: "#55ffffff"
    default property alias content: inner.data

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.radius
        color: root.tint
        border.color: root.borderColor
        border.width: 1
    }
    // highlight top edge
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 1
        anchors.leftMargin: root.radius / 2
        anchors.rightMargin: root.radius / 2
        height: 1
        color: "white"
        opacity: 0.22
    }
    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: 1
        clip: true
    }
}
