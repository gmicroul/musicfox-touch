import QtQuick 2.6

// Wave-style audio visualizer.
// Draws a horizontal sine wave line, centered vertically,
// with configurable length (defaults to parent width).
// Amplitude is driven by playback energy with a beat pulse.
Item {
    id: root
    width: 240; height: 50
    property bool playing: false
    property int volume: 80          // 0..150
    property color accentColor: "#4fc3f7"
    property real lineLength: parent.width   // length of the wave line

    readonly property real energy: playing ? (0.30 + (Math.min(volume,100)/100.0)*0.60) : 0.05
    readonly property real amp: root._amp
    property real _amp: 0.0
    property real phase: 0.0
    property real beat: 0.0

    property real step: root.lineLength / 100

    Repeater {
        id: waveRepeater
        model: 100
        delegate: Rectangle {
            width: root.step * 0.8; height: root.step * 0.8
            radius: width / 2
            color: root.accentColor
            x: index * root.step
            y: parent.height / 2 + Math.sin(index * 0.30 + root.phase) * parent.amp * 22
                  + Math.sin(index * 0.70 + root.beat * 3.0) * parent.amp * 8
            opacity: 0.3 + 0.7 * Math.abs(Math.cos(index * 0.30 + root.phase))
        }
    }

    Timer {
        interval: 35; repeat: true; running: true
        onTriggered: {
            var target = energy * 0.85
            _amp = 0.70 * _amp + 0.30 * target
            beat = 0.85 * beat + 0.15 * Math.sin(Date.now() / 1000 * 2.5)
            phase += 0.20
        }
    }
}
