import QtQuick 2.6
import Sailfish.Silica 1.0
import org.nemomobile.mpris 1.0
import harbour.musicfox 1.0

ApplicationWindow {
    id: app
    visible: true
    allowedOrientations: Orientation.All

    property real s: height > 0 ? height / 960.0 : 1.0
    property int mprisDbg: 1

    // Cover shown on the system desktop card (task switcher / home).
    // Standard Sailfish Silica: the OS renders this as the app's card on
    // the home screen, with the quick-action buttons below. The cover is an
    // inline Component (same pattern as working Harbour apps), and it
    // receives the controller objects explicitly via properties so that it
    // can always reach them regardless of its own QML context.
    cover: Component {
        CoverBackground {
            property var playback: mpv
            property var songs: queue
            property var lyrics: lyricSync

            // gradient background
            Rectangle { anchors.fill: parent; z: 0
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#0f0c29" }
                    GradientStop { position: 1.0; color: "#302b52" }
                }
            }

            // Quick actions displayed on the desktop card
            CoverActionList {
                CoverAction {
                    iconSource: "image://theme/icon-cover-previous"
                    onTriggered: songs.previous()
                }
                CoverAction {
                    iconSource: playback.isPaused ? "image://theme/icon-cover-play"
                                                  : "image://theme/icon-cover-pause"
                    onTriggered: playback.togglePause()
                }
                CoverAction {
                    iconSource: "image://theme/icon-cover-next"
                    onTriggered: songs.next()
                }
                CoverAction {
                    iconSource: "image://theme/icon-cover-shuffle"
                    onTriggered: {
                        if (songs.count > 0) {
                            songs.setCurrentIndex(Math.floor(Math.random() * songs.count))
                        }
                    }
                }
            }

            // Dynamic turntable: the cover rotates when playing and drops
            // the tonearm on play — a miniature of the player screen.
            VinylDisc {
                id: coverTurntable
                anchors.centerIn: parent
                width: Math.min(parent.width * 0.93, parent.height * 0.70)
                height: width
                coverSource: songs.currentSong.coverUrl || ""
                playing: songs.count > 0
                showTonearm: false
                compact: true
                spinDuration: playback.isPaused ? 26000 : 16000
            }

            Column {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 10 * app.s
                spacing: 4 * app.s
                width: parent.width - 24 * app.s

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: songs.currentSong.name || qsTr("MusicFox")
                    color: "white"
                    font.pixelSize: Theme.fontSizeMedium
                    maximumLineCount: 1
                    truncationMode: TruncationMode.Fade
                    width: parent.width
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: songs.currentSong.artists
                          || (playback.isPaused ? qsTr("Paused") : qsTr("Playing"))
                    color: "#b9c6d4"
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                    width: parent.width
                }
            }
        }
    }

    NeteaseApi { id: api }
    MpvController { id: mpv }
    PlayQueue { id: queue }
    LyricSync { id: lyricSync }
    PulseLevels { id: pulseLevels }

    // Downloads remote album art to a local cache so the MPRIS lock-screen
    // media UI (which refuses remote http:// images) can show it via file://
    CoverCache { id: coverCache }

    // MPRIS interface: lets the system (lock screen, media button shortcuts,
    // Bluetooth/headphone controls, other players) remote-control MusicFox.
    // The OS lock screen shows cover + title + artist + control buttons from
    // this interface automatically.
    MprisPlayer {
        id: mpris
        serviceName: "musicfox"
        identity: "MusicFox"
        desktopEntry: "harbour-musicfox"
        canControl: true
        canGoNext: true
        canGoPrevious: true
        canPlay: true
        canPause: true
        canSeek: true
        shuffle: false

        function song() { return queue.currentSong || ({}) }

        // Playback status is pushed explicitly (mpv can be idle before any
        // song starts, matching the "Stopped" state).
        function updateStatus() {
            // mpv.playerState mirrors QMediaPlayer::State directly:
            // 0=Stopped, 1=Playing, 2=Paused
            var ps = mpv.playerState
            if (ps === 1) {
                playbackStatus = Mpris.Playing
            } else if (ps === 2) {
                playbackStatus = Mpris.Paused
            } else {
                playbackStatus = Mpris.Stopped
            }
            // MPRIS position is in microseconds
            position = Math.round(mpv.position * 1000000)
            volume = mpv.volume / 100.0
            if (mprisDbg > 0)
                console.log("updateStatus playerState=" + ps + " state=" + mpv.state
                            + " isPaused=" + mpv.isPaused
                            + " pos=" + Math.round(mpv.position) + " v=" + mpv.volume)
        }

        function updateMetadata() {
            var s = song()
            // artUrl: use the raw cover URL, forcing https. The lock-screen
            // media UI loads cover images over https but rejects plain http
            // (mirrors how harbour-qqmusic feeds an https address).
            var art = s.coverUrl ? s.coverUrl : ""
            if (art.indexOf("http://") === 0)
                art = "https://" + art.substring(7)
            // Download a local cached copy of the cover so the lock screen can
            // render a file:// image (most reliable). coverageCache.coverUrl
            // returns the existing local file path, or empty while the download
            // is in flight; coverReady() re-runs this so the metadata is pushed
            // again once the cache file is available.
            if (art.length > 0) {
                coverCache.cache(art)
                var local = coverCache.coverUrl(art)
                if (local.length > 0)
                    art = local
            }
            // amber/libmpris-qt5 map Metadata.artUrl from mpris:artUrl (the
            // MPRIS standard field), NOT xesam:artUrl. Both are fed to cover
            // both the lock screen and any xesam-based consumers.
            metadata = {
                "mpris:trackid": "/org/mpris/MediaPlayer2/Track/" + (s.id ? s.id : "0"),
                "mpris:length": Math.round(mpv.duration * 1000000),
                "mpris:artUrl": art,
                "xesam:title": s.name ? s.name : "",
                "xesam:artist": s.artists ? [s.artists] : [],
                "xesam:albumArtist": s.artists ? [s.artists] : [],
                "xesam:album": s.album ? s.album : "",
                "xesam:artUrl": art
            }
        }

        onPlayPauseRequested: mpv.togglePause()
        onPlayRequested: mpv.play()
        onPauseRequested: mpv.doPause()
        onStopRequested: mpv.doStop()
        onNextRequested: queue.next()
        onPreviousRequested: queue.previous()
    }

    // MPRIS refresh hooks. These Connections live at the window level
    // (MprisPlayer is a C++ QObject without a default child property, so
    // Connections cannot be nested inside it).
    Connections {
        target: queue
        onCurrentSongChanged: mpris.updateMetadata()
    }
    Connections {
        target: coverCache
        onCoverReady: mpris.updateMetadata()
    }
    Connections {
        target: mpv
        onDurationChanged: mpris.updateMetadata()
        onPauseChanged: mpris.updateStatus()
        onStateChanged: mpris.updateStatus()
        onPositionChanged: mpris.updateStatus()
        onVolumeChanged: mpris.updateStatus()
    }

    Component.onCompleted: {
        mpris.updateStatus()
        mpris.updateMetadata()
    }

    // Periodically refresh MPRIS status so lock screen stays in sync even if
    // individual QMediaPlayer signals don't fire.
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: mpris.updateStatus()
    }

    property var pageHistory: []
    property string currentPage: "main"

    function showPage(name) {
        currentPage = name
        mainSearchInput.focus = false
        searchInput.focus = false
        mainPage.visible = (name === "main")
        searchPage.visible = (name === "search")
        toplistPage.visible = (name === "toplist")
        topPlaylistsPage.visible = (name === "topPlaylists")
        playlistDetailPage.visible = (name === "playlistDetail")
        playerPage.visible = (name === "player")
        aboutPage.visible = (name === "about")
        console.log("showPage: " + name)
    }

    function pushPage(name) {
        pageHistory.push(name)
        showPage(name)
    }

    function popPage() {
        if (pageHistory.length > 0) pageHistory.pop()
        var name = pageHistory.length > 0 ? pageHistory[pageHistory.length - 1] : "main"
        showPage(name)
        console.log("popPage → " + name)
    }

    Connections {
        target: queue
        onSongChanged: {
            api.getSongUrl(song.id, 320000)
            api.getLyric(song.id)
        }
    }

    Connections {
        target: api
        onSearchResult: {
            if (currentPage === "search") searchPage.handleSearchResult(result)
        }
        onToplistResult: {
            console.log("onToplistResult: currentPage=" + currentPage + " resultLen=" + (result ? result.length : 0))
            if (currentPage === "toplist") toplistPage.handleToplistResult(result)
        }
        onTopPlaylistsResult: {
            console.log("onTopPlaylistsResult: currentPage=" + currentPage + " resultLen=" + (result ? result.length : 0))
            if (currentPage === "topPlaylists") topPlaylistsPage.handleTopPlaylistsResult(result)
        }
        onPlaylistDetailResult: {
            if (currentPage === "playlistDetail") playlistDetailPage.handlePlaylistDetailResult(result)
        }
        onSongUrlResult: {
            if (result.url && result.url.toString().length > 0) {
                mpv.loadFile(result.url)
                mpv.play()
            }
        }
        onLyricResult: {
            lyricSync.setLyrics(result.lines)
        }
        onApiError: {
            console.log("API error:", message)
        }
    }

    Connections {
        target: mpv
        onPositionChanged: lyricSync.updatePosition(mpv.position)
        onEndOfFile: {
            if (queue.count <= 0) return
            if (queue.playMode === 1) {
                queue.replayCurrent()
            } else if (queue.currentIndex >= queue.count - 1) {
                queue.setCurrentIndex(0)
            } else {
                queue.next()
            }
        }
    }

    // Frosted glass backdrop for the whole app (pages are transparent)
    FrostedBackground {}

    // ===================== MAIN PAGE =====================
    Rectangle {
        id: mainPage
        anchors.fill: parent
        color: "transparent"
        visible: true


        Column {
            anchors.fill: parent
            anchors.leftMargin: 16 * app.s
            anchors.rightMargin: 16 * app.s
            anchors.bottomMargin: 16 * app.s
            anchors.topMargin: 48 * app.s
            spacing: 12 * app.s

            Text {
                text: "MusicFox"
                font.pixelSize: 28 * app.s
                font.bold: true
                color: "#ffffff"
            }

            GlassPanel {
                width: parent.width
                height: 48 * app.s
                radius: 12
                TextInput {
                    id: mainSearchInput
                    anchors.fill: parent
                    anchors.margins: 12 * app.s
                    color: "#ffffff"
                    font.pixelSize: 18 * app.s
                    clip: true
                    property string placeholderText: "Search songs..."
                    Text {
                        anchors.fill: parent
                        anchors.verticalCenter: parent.verticalCenter
                        text: mainSearchInput.placeholderText
                        color: "#aab6c4"
                        font.pixelSize: 18 * app.s
                        visible: !mainSearchInput.text && !mainSearchInput.focus
                    }
                    onAccepted: {
                        if (text.length > 0) {
                            searchPage.keyword = text
                            pushPage("search")
                            api.search(text, 1, 50)
                        }
                    }
                }
            }

            Repeater {
                model: ListModel {
                    ListElement { title: "Search"; desc: "Find songs, artists, playlists"; idx: 0 }
                    ListElement { title: "Top Charts"; desc: "Official rankings"; idx: 1 }
                    ListElement { title: "Hot Playlists"; desc: "Popular playlists"; idx: 2 }
                    ListElement { title: "About / Disclaimer"; desc: "Legal notice"; idx: 3 }
                }
                delegate: Rectangle {
                    width: parent.width
                    height: 68 * app.s
                    color: dm.pressed ? "#40ffffff" : "#28ffffff"
                    radius: 8
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 16 * app.s
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: title; font.pixelSize: 20 * app.s; color: "#ffffff" }
                        Text { text: desc; font.pixelSize: 14 * app.s; color: "#b9c6d4" }
                    }
                    MouseArea {
                        id: dm
                        anchors.fill: parent
                        onClicked: {
                            if (idx === 0) {
                                pushPage("search")
                            } else if (idx === 1) {
                                pushPage("toplist")
                                api.getToplist()
                            } else if (idx === 2) {
                                pushPage("topPlaylists")
                                api.getTopPlaylists()
                            } else {
                                pushPage("about")
                            }
                        }
                    }
                }
            }

            // --- Now Playing widget ---
            Item {
                id: nowPlayingWidget
                width: parent.width
                height: 136 * app.s
                visible: queue.count > 0

                GlassPanel {
                    anchors.fill: parent
                    radius: 16
                }

                // Mini spinning vinyl (desktop-card feel in the widget)
                VinylDisc {
                    id: miniVinyl
                    z: 2
                    anchors.left: parent.left
                    anchors.leftMargin: 14 * app.s
                    anchors.verticalCenter: parent.verticalCenter
                    width: 112 * app.s; height: 112 * app.s
                    coverSource: queue.currentSong.coverUrl || ""
                    playing: !mpv.isPaused && queue.count > 0
                    showTonearm: false
                    compact: true
                    spinDuration: 16000

                    // "now playing" ring pulse
                    Rectangle {
                        anchors.fill: parent; anchors.margins: -2 * app.s
                        radius: width / 2
                        color: "transparent"
                        border.color: mpv.isPaused ? "#4fc3f7" : "#80d8ff"
                        border.width: 2
                        opacity: mpv.isPaused ? 0.6 : 1.0
                    }
                }

                Column {
                    z: 2
                    anchors.left: miniVinyl.right
                    anchors.leftMargin: 14 * app.s
                    anchors.right: parent.right
                    anchors.rightMargin: 12 * app.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * app.s

                    Text {
                        width: parent.width
                        text: queue.currentSong.name || "No song"
                        font.pixelSize: 17 * app.s; font.bold: true
                        color: "#ffffff"
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: queue.currentSong.artists || ""
                        font.pixelSize: 12 * app.s; color: "#b9c6d4"
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: lyricSync.hasLyrics ? (lyricSync.currentText || "...") : (mpv.isPaused ? "Paused" : "Playing")
                        font.pixelSize: 13 * app.s
                        color: "#4fc3f7"
                        elide: Text.ElideRight
                    }
                    Item {
                        width: parent.width
                        height: 40 * app.s
                        Row {
                            anchors.centerIn: parent
                            spacing: 40 * app.s
                            Text {
                                text: "\u23EE"; font.pixelSize: 26 * app.s; color: "#ffffff"
                                MouseArea { anchors.fill: parent; onClicked: queue.previous() }
                            }
                            Rectangle {
                                width: 40 * app.s; height: 40 * app.s; radius: 20 * app.s
                                color: "#4fc3f7"
                                Text {
                                    anchors.centerIn: parent
                                    text: mpv.isPaused ? "\u25B6" : "\u23F8"
                                    font.pixelSize: 22 * app.s; color: "#001018"
                                }
                                MouseArea { anchors.fill: parent; onClicked: mpv.togglePause() }
                            }
                            Text {
                                text: "\u23ED"; font.pixelSize: 26 * app.s; color: "#ffffff"
                                MouseArea { anchors.fill: parent; onClicked: queue.next() }
                            }
                        }
                    }
                }

                Item {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 24 * app.s
                    opacity: queue.count > 0 ? 1 : 0
                    SpectrumBars {
                        anchors.fill: parent
                        playing: !mpv.isPaused && queue.count > 0
                        volume: mpv.volume
                        accentColor: "#2cb4ff"
                    }
                }

                MouseArea {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 80 * app.s
                    onClicked: pushPage("player")
                }
            }
        }
    }

    // ===================== SEARCH PAGE =====================
    Rectangle {
        id: searchPage
        anchors.fill: parent
        color: "transparent"
        visible: false
        property string keyword: ""

        function handleSearchResult(result) {
            searchModel.clear()
            var songs = result.songs
            if (songs) {
                for (var i = 0; i < songs.length; i++) {
                    searchModel.append({
                        type: "song", itemId: songs[i].id, name: songs[i].name,
                        artists: songs[i].artists, album: songs[i].album,
                        duration: songs[i].duration, coverUrl: songs[i].coverUrl || ""
                    })
                }
            }
            var playlists = result.playlists
            if (playlists) {
                for (var i = 0; i < playlists.length; i++) {
                    searchModel.append({
                        type: "playlist", itemId: playlists[i].id, name: playlists[i].name,
                        creatorName: playlists[i].creatorName, trackCount: playlists[i].trackCount,
                        playCount: playlists[i].playCount, coverUrl: playlists[i].coverUrl || ""
                    })
                }
            }
        }

        ListModel { id: searchModel }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 16 * app.s
            anchors.rightMargin: 16 * app.s
            anchors.bottomMargin: 16 * app.s
            anchors.topMargin: 48 * app.s

            Row {
                id: searchHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 36 * app.s
                spacing: 8 * app.s

                Text {
                    text: "Search"
                    font.pixelSize: 26 * app.s
                    font.bold: true
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: parent.width - 180 * app.s; height: 1 }
                Item {
                    width: 80 * app.s; height: 36 * app.s
                    Text {
                        anchors.centerIn: parent
                        text: "\u2190 Back"
                        color: "#4fc3f7"
                        font.pixelSize: 18 * app.s
                    }
                    MouseArea { anchors.fill: parent; onClicked: popPage() }
                }
            }

            GlassPanel {
                id: searchInputBox
                anchors.top: searchHeader.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 48 * app.s
                radius: 12
                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.margins: 12 * app.s
                    color: "#ffffff"
                    font.pixelSize: 18 * app.s
                    clip: true
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search songs..."
                        color: "#aab6c4"
                        font.pixelSize: 18 * app.s
                        visible: !searchInput.text && !searchInput.focus
                    }
                    onAccepted: {
                        if (text.length > 0) {
                            searchPage.keyword = text
                            api.search(text, 1, 50)
                        }
                    }
                }
            }

            ListView {
                id: searchList
                anchors.top: searchInputBox.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                model: searchModel
                clip: true
                delegate: Rectangle {
                    width: searchList.width
                    height: 72 * app.s
                    property bool isCurrent: (type === "song") && (queue.currentIndex >= 0) && (itemId === queue.songAt(queue.currentIndex).id)
                    color: sm.pressed ? "#40ffffff" : (isCurrent ? "#2a3a4a" : "#28ffffff")
                    radius: 8
                    border.color: isCurrent ? "#4fc3f7" : "transparent"
                    border.width: isCurrent ? 2 : 0
                    Row {
                        anchors.fill: parent
                        anchors.margins: 8 * app.s
                        spacing: 12 * app.s
                        Rectangle {
                            width: 52 * app.s; height: 52 * app.s
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#663a3f52"; radius: 6; border.color: "#33ffffff"; border.width: 1
                            Image { anchors.fill: parent; source: coverUrl; fillMode: Image.PreserveAspectFit }
                        }
                        Column {
                            width: parent.width - 76 * app.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3 * app.s
                            Text {
                                width: parent.width
                                text: (isCurrent ? "\u25B6 " : "") + (name || "")
                                font.pixelSize: 17 * app.s; color: isCurrent ? "#4fc3f7" : "#ffffff"
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: type === "song" ?
                                    ((artists || "") + (album ? " \u00B7 " + album : "")) :
                                    ((creatorName || "") + (trackCount ? " \u00B7 " + trackCount + " tracks" : ""))
                                font.pixelSize: 13 * app.s; color: "#b9c6d4"
                                elide: Text.ElideRight
                            }
                        }
                    }
                    MouseArea {
                        id: sm
                        anchors.fill: parent
                        onClicked: {
                            if (type === "song") {
                                var songs = []
                                for (var i = 0; i < searchModel.count; i++) {
                                    var m = searchModel.get(i)
                                    if (m.type === "song") songs.push({
                                        id: m.itemId, name: m.name, artists: m.artists,
                                        album: m.album, duration: m.duration, coverUrl: m.coverUrl, type: "song"
                                    })
                                }
                                queue.setSongs(songs)
                                var idx = 0
                                for (var j = 0; j < songs.length; j++) {
                                    if (songs[j].id === itemId) { idx = j; break }
                                }
                                queue.setCurrentIndex(idx)
                                pushPage("player")
                            } else {
                                playlistDetailPage.playlistId = itemId
                                playlistDetailPage.playlistName = name
                                pushPage("playlistDetail")
                                api.getPlaylistDetail(itemId, true)
                            }
                        }
                    }
                }
            }
        }
    }

    // ===================== TOPLIST PAGE =====================
    Rectangle {
        id: toplistPage
        anchors.fill: parent
        color: "transparent"
        visible: false

        function handleToplistResult(result) {
            toplistModel.clear()
            for (var i = 0; i < result.length; i++) {
                toplistModel.append({
                    type: "playlist", itemId: result[i].id, name: result[i].name,
                    creatorName: "", trackCount: 0, playCount: 0, coverUrl: result[i].cover || ""
                })
            }
            console.log("toplistPage model count=" + toplistModel.count)
        }

        ListModel { id: toplistModel }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 16 * app.s
            anchors.rightMargin: 16 * app.s
            anchors.bottomMargin: 16 * app.s
            anchors.topMargin: 48 * app.s

            Item {
                id: toplistHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 36 * app.s

                Text {
                    text: "Top Charts"
                    font.pixelSize: 26 * app.s
                    font.bold: true
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80 * app.s; height: 36 * app.s
                    Rectangle {
                        anchors.fill: parent
                        color: "#2effffff"
                        radius: 8
                        border.color: "#55ffffff"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "\u2190 Back"
                        color: "#4fc3f7"
                        font.pixelSize: 18 * app.s
                    }
                    MouseArea { anchors.fill: parent; onClicked: popPage() }
                }
            }

            ListView {
                id: toplistList
                anchors.top: toplistHeader.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                model: toplistModel
                clip: true
                delegate: Rectangle {
                    width: toplistList.width
                    height: 72 * app.s
                    color: tdm.pressed ? "#40ffffff" : "#28ffffff"
                    radius: 8
                    Row {
                        anchors.fill: parent
                        anchors.margins: 8 * app.s
                        spacing: 12 * app.s
                        Rectangle {
                            width: 52 * app.s; height: 52 * app.s
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#663a3f52"; radius: 6; border.color: "#33ffffff"; border.width: 1
                            Image { anchors.fill: parent; source: coverUrl; fillMode: Image.PreserveAspectFit }
                        }
                        Column {
                            width: parent.width - 76 * app.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3 * app.s
                            Text { width: parent.width; text: name || ""; font.pixelSize: 17 * app.s; color: "#ffffff"; elide: Text.ElideRight }
                            Text { width: parent.width; text: (creatorName || "") + (trackCount ? " \u00B7 " + trackCount + " tracks" : ""); font.pixelSize: 13 * app.s; color: "#b9c6d4"; elide: Text.ElideRight }
                        }
                    }
                    MouseArea {
                        id: tdm
                        anchors.fill: parent
                        onClicked: {
                            playlistDetailPage.playlistId = itemId
                            playlistDetailPage.playlistName = name
                            pushPage("playlistDetail")
                            api.getPlaylistDetail(itemId, true)
                        }
                    }
                }
            }
        }
    }

    // ===================== TOP PLAYLISTS PAGE =====================
    Rectangle {
        id: topPlaylistsPage
        anchors.fill: parent
        color: "transparent"
        visible: false

        function handleTopPlaylistsResult(result) {
            topPlModel.clear()
            for (var i = 0; i < result.length; i++) {
                topPlModel.append({
                    type: "playlist", itemId: result[i].id, name: result[i].name,
                    creatorName: result[i].creatorName || "", trackCount: result[i].trackCount || 0,
                    playCount: result[i].playCount || 0, coverUrl: result[i].coverUrl || ""
                })
            }
            console.log("topPlaylists model count=" + topPlModel.count)
        }

        ListModel { id: topPlModel }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 16 * app.s
            anchors.rightMargin: 16 * app.s
            anchors.bottomMargin: 16 * app.s
            anchors.topMargin: 48 * app.s

            Item {
                id: topPlHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 36 * app.s

                Text {
                    text: "Hot Playlists"
                    font.pixelSize: 26 * app.s
                    font.bold: true
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80 * app.s; height: 36 * app.s
                    Rectangle {
                        anchors.fill: parent
                        color: "#2effffff"
                        radius: 8
                        border.color: "#55ffffff"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "\u2190 Back"
                        color: "#4fc3f7"
                        font.pixelSize: 18 * app.s
                    }
                    MouseArea { anchors.fill: parent; onClicked: popPage() }
                }
            }

            ListView {
                id: topPlList
                anchors.top: topPlHeader.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                model: topPlModel
                clip: true
                delegate: Rectangle {
                    width: topPlList.width
                    height: 72 * app.s
                    color: tpm.pressed ? "#40ffffff" : "#28ffffff"
                    radius: 8
                    Row {
                        anchors.fill: parent
                        anchors.margins: 8 * app.s
                        spacing: 12 * app.s
                        Rectangle {
                            width: 52 * app.s; height: 52 * app.s
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#663a3f52"; radius: 6; border.color: "#33ffffff"; border.width: 1
                            Image { anchors.fill: parent; source: coverUrl; fillMode: Image.PreserveAspectFit }
                        }
                        Column {
                            width: parent.width - 76 * app.s
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3 * app.s
                            Text { width: parent.width; text: name || ""; font.pixelSize: 17 * app.s; color: "#ffffff"; elide: Text.ElideRight }
                            Text { width: parent.width; text: (creatorName || "") + (trackCount ? " \u00B7 " + trackCount + " tracks" : ""); font.pixelSize: 13 * app.s; color: "#b9c6d4"; elide: Text.ElideRight }
                        }
                    }
                    MouseArea {
                        id: tpm
                        anchors.fill: parent
                        onClicked: {
                            playlistDetailPage.playlistId = itemId
                            playlistDetailPage.playlistName = name
                            pushPage("playlistDetail")
                            api.getPlaylistDetail(itemId, true)
                        }
                    }
                }
            }
        }
    }

    // ===================== PLAYLIST DETAIL PAGE =====================
    Rectangle {
        id: playlistDetailPage
        anchors.fill: parent
        color: "transparent"
        visible: false
        property int playlistId: 0
        property string playlistName: ""

        function handlePlaylistDetailResult(result) {
            plDetailModel.clear()
            var pl = result.playlist
            if (pl) playlistName = pl.name
            var songs = result.songs
            if (songs) {
                for (var i = 0; i < songs.length; i++) {
                    plDetailModel.append({
                        itemId: songs[i].id, name: songs[i].name, artists: songs[i].artists,
                        album: songs[i].album, duration: songs[i].duration,
                        coverUrl: songs[i].coverUrl || "", type: "song"
                    })
                }
            }
            console.log("playlistDetail model count=" + plDetailModel.count)
        }

        ListModel { id: plDetailModel }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 16 * app.s
            anchors.rightMargin: 16 * app.s
            anchors.bottomMargin: 16 * app.s
            anchors.topMargin: 48 * app.s

            Item {
                id: plDetailHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 36 * app.s

                Text {
                    text: playlistDetailPage.playlistName
                    font.pixelSize: 26 * app.s; font.bold: true; color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 90 * app.s; elide: Text.ElideRight
                }
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80 * app.s; height: 36 * app.s
                    Rectangle {
                        anchors.fill: parent
                        color: "#2effffff"
                        radius: 8
                        border.color: "#55ffffff"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "\u2190 Back"
                        color: "#4fc3f7"; font.pixelSize: 18 * app.s
                    }
                    MouseArea { anchors.fill: parent; onClicked: popPage() }
                }
            }

            Text {
                id: plDetailLoading
                anchors.top: plDetailHeader.bottom
                anchors.topMargin: 8 * app.s
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Loading..."
                visible: plDetailModel.count === 0
                color: "#b9c6d4"
                font.pixelSize: 16 * app.s
            }

            ListView {
                id: plDetailList
                anchors.top: plDetailHeader.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                model: plDetailModel
                clip: true
                delegate: Rectangle {
                    width: plDetailList.width; height: 72 * app.s
                    property bool isCurrent: (queue.currentIndex >= 0) && (itemId === queue.songAt(queue.currentIndex).id)
                    color: pdm.pressed ? "#40ffffff" : (isCurrent ? "#2a3a4a" : "#28ffffff"); radius: 8
                    border.color: isCurrent ? "#4fc3f7" : "transparent"
                    border.width: isCurrent ? 2 : 0
                    Row {
                        anchors.fill: parent; anchors.margins: 8 * app.s; spacing: 12 * app.s
                        Rectangle {
                            width: 52 * app.s; height: 52 * app.s
                            anchors.verticalCenter: parent.verticalCenter
                            color: "#663a3f52"; radius: 6; border.color: "#33ffffff"; border.width: 1
                            Image { anchors.fill: parent; source: coverUrl; fillMode: Image.PreserveAspectFit }
                        }
                        Column {
                            width: parent.width - 76 * app.s; anchors.verticalCenter: parent.verticalCenter; spacing: 3 * app.s
                            Text { width: parent.width; text: (isCurrent ? "\u25B6 " : "") + (name || ""); font.pixelSize: 17 * app.s; color: isCurrent ? "#4fc3f7" : "#ffffff"; elide: Text.ElideRight }
                            Text { width: parent.width; text: (artists || "") + (album ? " \u00B7 " + album : ""); font.pixelSize: 13 * app.s; color: "#b9c6d4"; elide: Text.ElideRight }
                        }
                    }
                    MouseArea {
                        id: pdm
                        anchors.fill: parent
                        onClicked: {
                            var songs = []
                            for (var i = 0; i < plDetailModel.count; i++) {
                                var m = plDetailModel.get(i)
                                songs.push({ id: m.itemId, name: m.name, artists: m.artists, album: m.album,
                                    duration: m.duration, coverUrl: m.coverUrl, type: "song" })
                            }
                            queue.setSongs(songs)
                            queue.setCurrentIndex(index)
                            pushPage("player")
                        }
                    }
                }
            }
        }
    }

    // ===================== PLAYER PAGE =====================
    Rectangle {
        id: playerPage
        anchors.fill: parent
        color: "transparent"
        visible: false
        property bool showLyrics: false


        GlassPanel {
            id: playerTopBar
            anchors.top: parent.top
            anchors.topMargin: 40 * app.s
            anchors.left: parent.left
            anchors.leftMargin: 12 * app.s
            anchors.right: parent.right
            anchors.rightMargin: 12 * app.s
            height: 56 * app.s
            radius: 16
            z: 10
            visible: playerPage.showLyrics

            Item {
                anchors.left: parent.left; anchors.leftMargin: 16 * app.s
                anchors.verticalCenter: parent.verticalCenter
                width: 80 * app.s; height: 36 * app.s
                Rectangle {
                    anchors.fill: parent
                    color: "#28ffffff"
                    radius: 6
                }
                Text {
                    anchors.centerIn: parent
                    text: "\u2190 Back"
                    color: "#4fc3f7"; font.pixelSize: 18 * app.s
                }
                MouseArea { anchors.fill: parent; onClicked: {
                    playerPage.showLyrics = false
                    popPage()
                } }
            }

            Item {
                anchors.right: parent.right; anchors.rightMargin: 16 * app.s
                anchors.verticalCenter: parent.verticalCenter
                width: 80 * app.s; height: 36 * app.s
                Rectangle {
                    anchors.fill: parent
                    color: "#28ffffff"
                    radius: 6
                }
                Text {
                    anchors.centerIn: parent
                    text: playerPage.showLyrics ? "Player" : "Lyrics"
                    color: "#4fc3f7"; font.pixelSize: 18 * app.s
                }
                MouseArea { anchors.fill: parent; onClicked: playerPage.showLyrics = !playerPage.showLyrics }
            }
        }

        // ---- Phase-1 static replica of the gold-ink mockup ----
        // Bundled player-bagua.jpg as backdrop; transparent hotspots on the
        // painted buttons + dynamic overlays (title / times / progress / fav).
        Item {
            id: replicaView
            anchors.fill: parent
            visible: !playerPage.showLyrics
            clip: true

            property bool favNow: false
            property bool showQueue: false
            property bool showVol: false
            property bool showMode: false
            // letterbox bars when the image is shorter than the screen
            property real topBarH: Math.max(0, (height - replicaBg.height) / 2)
            property real bottomBarH: Math.max(0, (height - replicaBg.height) / 2)

            // solid black backdrop: blends the letterbox bars with the image's black
            Rectangle { anchors.fill: parent; color: "#000000" }

            function calcFav() {
                if (queue.count <= 0 || queue.currentIndex < 0) return false
                var s = queue.currentSong
                return (s && s.id) ? queue.isFavorite(s.id) : false
            }
            Component.onCompleted: {
                replicaView.favNow = replicaView.calcFav()
                if (lyricSync.hasLyrics) replicaKtv.lines = lyricSync.lines()
            }
            Connections {
                target: queue
                onCurrentSongChanged: replicaView.favNow = replicaView.calcFav()
                onFavoritesChanged: replicaView.favNow = replicaView.calcFav()
            }
            Connections {
                target: lyricSync
                onLyricsChanged: replicaKtv.lines = lyricSync.lines()
            }

            Image {
                id: replicaBg
                property real iw: 1080
                property real ih: 1807
                // horizontal fill: width locked, height proportional, centered
                width: parent.width
                height: width * ih / iw
                anchors.centerIn: parent
                source: "trigram-recolored2.png"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true

                // ---- cut-out taiji disc: spins while playing ----
                // Same pixels as the baked center, so it blends seamlessly;
                // rotation makes the whole disc turn inside the progress ring.
                Image {
                    id: taijiDisc
                    property real rr: 0.2315 * replicaBg.width + 2
                    x: 0.5 * replicaBg.width - width / 2
                    y: 0.4804 * replicaBg.height - height / 2
                    width: rr * 2; height: width
                    source: "taiji-disc.png"
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    transformOrigin: Item.Center
                    NumberAnimation on rotation {
                        from: 0; to: 360
                        loops: Animation.Infinite
                        duration: 16000
                        running: !mpv.isPaused && queue.count > 0
                    }
                }

                // ---- rhythm overlay: 40 trigram bars glow with the music ----
                // [cx, cy, lenW, tangentDeg, group, band]  (fractions of replicaBg;
                // band: 0 low, 1 mid, 2 high). Transparent at rest so the baked
                // cyan shows; lights up toward white-hot with band energy.
                Canvas {
                    id: rhythmOverlay
                    anchors.fill: parent
                    renderTarget: Canvas.Image
                    property var bars: [
    [0.5324, 0.2355, 0.0492, 4.1, 0, 2],
    [0.5324, 0.2482, 0.0492, 4.3, 0, 2],
    [0.6847, 0.2734, 0.0501, 28.1, 0, 2],
    [0.6958, 0.2620, 0.0506, 28.2, 0, 2],
    [0.7074, 0.2510, 0.0514, 28.4, 0, 2],
    [0.7546, 0.2673, 0.0519, 35.7, 1, 2],
    [0.7431, 0.2784, 0.0511, 35.9, 1, 2],
    [0.7315, 0.2894, 0.0504, 36.1, 1, 2],
    [0.8356, 0.3486, 0.0483, 57.3, 1, 1],
    [0.8569, 0.3417, 0.0491, 57.6, 2, 1],
    [0.8829, 0.3691, 0.0483, 64.8, 2, 1],
    [0.8620, 0.3755, 0.0485, 64.9, 2, 1],
    [0.8620, 0.5802, 0.0470, 116.0, 2, 1],
    [0.8829, 0.5872, 0.0483, 116.1, 2, 1],
    [0.8569, 0.6134, 0.0491, 123.1, 3, 1],
    [0.8361, 0.6068, 0.0496, 123.4, 3, 1],
    [0.7356, 0.6688, 0.0502, 144.3, 3, 0],
    [0.7481, 0.6804, 0.0509, 144.5, 3, 0],
    [0.7023, 0.6967, 0.0496, 151.7, 4, 0],
    [0.6903, 0.6851, 0.0496, 151.9, 4, 0],
    [0.3148, 0.6848, 0.0498, 208.4, 4, 0],
    [0.3028, 0.6967, 0.0504, 208.5, 4, 0],
    [0.2565, 0.6804, 0.0509, 215.9, 4, 0],
    [0.2690, 0.6691, 0.0496, 216.0, 5, 0],
    [0.1676, 0.6071, 0.0504, 236.9, 5, 1],
    [0.1468, 0.6140, 0.0491, 237.1, 5, 1],
    [0.1213, 0.5872, 0.0478, 244.0, 5, 1],
    [0.1421, 0.5805, 0.0473, 244.2, 6, 1],
    [0.1440, 0.3758, 0.0483, 295.0, 6, 1],
    [0.1227, 0.3688, 0.0491, 295.2, 6, 1],
    [0.1491, 0.3417, 0.0496, 302.3, 6, 1],
    [0.1704, 0.3486, 0.0489, 302.6, 6, 1],
    [0.2741, 0.2900, 0.0504, 323.6, 7, 2],
    [0.2625, 0.2786, 0.0517, 323.8, 7, 2],
    [0.2509, 0.2678, 0.0519, 324.0, 7, 2],
    [0.2991, 0.2512, 0.0519, 331.4, 7, 2],
    [0.3102, 0.2620, 0.0514, 331.6, 8, 2],
    [0.3208, 0.2737, 0.0506, 331.6, 8, 2],
    [0.4727, 0.2482, 0.0501, 355.3, 8, 2],
    [0.4727, 0.2355, 0.0501, 355.6, 8, 2],

                    ]
                    function bandLevel(b) {
                        return b === 0 ? pulseLevels.lowLevel
                             : (b === 1 ? pulseLevels.midLevel : pulseLevels.highLevel)
                    }
                    onPaint: {
                        var ctx = getContext("2d")
                        var w = width, h = height
                        ctx.clearRect(0, 0, w, h)
                        if (queue.count <= 0) return
                        ctx.lineCap = "round"
                        ctx.lineWidth = Math.max(3, w * 0.013)
                        for (var i = 0; i < bars.length; i++) {
                            var b = bars[i]
                            var v = bandLevel(b[5])
                            if (v < 0.03) continue
                            var a = b[3] * Math.PI / 180
                            var hl = b[2] * w * 0.5
                            var cx = b[0] * w, cy = b[1] * h
                            var dx = Math.cos(a) * hl, dy = Math.sin(a) * hl
                            var r = Math.round(27 + v * 228)
                            var g = Math.round(111 + v * 137)
                            var bl = Math.round(125 + v * 99)
                            ctx.strokeStyle = "rgba(" + r + "," + g + "," + bl + "," + v.toFixed(2) + ")"
                            ctx.beginPath()
                            ctx.moveTo(cx - dx, cy - dy)
                            ctx.lineTo(cx + dx, cy + dy)
                            ctx.stroke()
                        }
                    }
                }
                Connections {
                    target: pulseLevels
                    onLevelsChanged: rhythmOverlay.requestPaint()
                }

                // ---- top: big MusicFox branding (in the filled top bar) + song info ----
                Text {
                    id: musicFoxBrand
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: replicaView.topBarH > 20
                       ? (-replicaView.topBarH + (replicaView.topBarH - paintedHeight) / 2)
                       : 0.026 * parent.height
                    width: 0.80 * parent.width
                    text: "MusicFox"
                    font.pixelSize: replicaView.topBarH > 20
                                    ? Math.min(parent.width * 0.075, replicaView.topBarH * 0.62)
                                    : parent.width * 0.075
                    font.bold: true
                    color: "#f0d488"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight; maximumLineCount: 1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0.066 * parent.height
                    width: 0.70 * parent.width
                    text: queue.currentSong.name || ""
                    font.pixelSize: parent.width * 0.068; font.bold: true
                    color: "#f0d488"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight; maximumLineCount: 1
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0.066 * parent.height + parent.width * 0.068 * 1.15
                    width: 0.70 * parent.width
                    text: queue.currentSong.artists || ""
                    font.pixelSize: parent.width * 0.048
                    color: "#b9c6d4"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight; maximumLineCount: 1
                }

                // ---- top buttons: back / lyrics menu ----
                Item {
                    x: 0.077 * parent.width - width / 2
                    y: 0.050 * parent.height - height / 2
                    width: 0.10 * parent.width; height: width
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { playerPage.showLyrics = false; popPage() }
                    }
                }
                Item {
                    x: 0.921 * parent.width - width / 2
                    y: 0.050 * parent.height - height / 2
                    width: 0.10 * parent.width; height: width
                    MouseArea {
                        anchors.fill: parent
                        onClicked: playerPage.showLyrics = !playerPage.showLyrics
                    }
                }

                // ---- prev / next (dial sides, above the progress ring) ----
                Item {
                    x: 0.1037 * parent.width - width / 2
                    y: 0.4483 * parent.height - height / 2
                    width: 0.13 * parent.width; height: width
                    z: 5
                    MouseArea { anchors.fill: parent; onClicked: queue.previous() }
                }
                Item {
                    x: 0.8963 * parent.width - width / 2
                    y: 0.4505 * parent.height - height / 2
                    width: 0.13 * parent.width; height: width
                    z: 5
                    MouseArea { anchors.fill: parent; onClicked: queue.next() }
                }

                // ---- pause button (own gold ring over dial top) ----
                Rectangle {
                    id: rpPauseBtn
                    x: 0.5 * parent.width - width / 2
                    y: 0.1793 * parent.height - height / 2
                    width: 0.104 * parent.width; height: width
                    radius: width / 2
                    color: "#ff000000"
                    border.color: "#e3b959"; border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: mpv.isPaused ? "▶" : "⏸"
                        font.pixelSize: parent.width * 0.45
                        color: "#e3b959"
                    }
                    MouseArea { anchors.fill: parent; onClicked: mpv.togglePause() }
                }

                // ---- volume hotspot + popup slider ----
                Item {
                    x: 0.1926 * parent.width - width / 2
                    y: 0.8489 * parent.height - height / 2
                    width: 0.15 * parent.width; height: width
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            replicaView.showVol = !replicaView.showVol
                            volHideTimer.restart()
                        }
                    }
                }
                Rectangle {
                    id: volPopup
                    visible: replicaView.showVol
                    x: 0.0226 * replicaBg.width
                    y: 0.779 * replicaBg.height
                    width: 0.34 * replicaBg.width; height: 0.062 * replicaBg.height
                    radius: 8 * app.s
                    color: "#e6000000"
                    border.color: "#e3b959"; border.width: 1
                    Text {
                        id: volPopLabel
                        anchors.left: parent.left; anchors.leftMargin: 8 * app.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: "音量"; font.pixelSize: 12 * app.s; color: "#e3b959"
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 8 * app.s
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(mpv.volume); font.pixelSize: 12 * app.s; color: "#e3b959"
                    }
                    Rectangle {
                        id: volPopBar
                        anchors.left: volPopLabel.right; anchors.leftMargin: 8 * app.s
                        anchors.right: parent.right; anchors.rightMargin: 40 * app.s
                        anchors.verticalCenter: parent.verticalCenter
                        height: 6 * app.s; radius: 3; color: "#55ffffff"
                        Rectangle {
                            width: parent.width * (mpv.volume / 150.0)
                            height: parent.height; radius: 3; color: "#e3b959"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPositionChanged: {
                                if (pressed) {
                                    var pct = Math.max(0, Math.min(1, mouse.x / width))
                                    mpv.setVolume(Math.round(pct * 150))
                                    volHideTimer.restart()
                                }
                            }
                            onClicked: {
                                var pct = Math.max(0, Math.min(1, mouse.x / width))
                                mpv.setVolume(Math.round(pct * 150))
                                volHideTimer.restart()
                            }
                        }
                    }
                }
                Timer {
                    id: volHideTimer
                    interval: 4000; repeat: false
                    onTriggered: replicaView.showVol = false
                }

                // ---- cycle mode hotspot (no label per request) ----
                Item {
                    x: 0.5 * parent.width - width / 2
                    y: 0.8666 * parent.height - height / 2
                    width: 0.15 * parent.width; height: width
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            queue.togglePlayMode()
                            replicaView.showMode = true
                            modeHideTimer.restart()
                        }
                    }
                }
                // transient mode hint above the cycle button
                Rectangle {
                    visible: replicaView.showMode
                    x: 0.5 * parent.width - width / 2
                    y: 0.788 * parent.height
                    width: modeHintText.paintedWidth + 32 * app.s
                    height: 30 * app.s
                    radius: 8 * app.s
                    color: "#e6000000"
                    border.color: "#e3b959"; border.width: 1
                    Text {
                        id: modeHintText
                        anchors.centerIn: parent
                        text: queue.playMode === 1 ? "单曲循环" : "列表循环"
                        font.pixelSize: 14 * app.s; color: "#f0d488"
                    }
                }
                Timer {
                    id: modeHideTimer
                    interval: 2000; repeat: false
                    onTriggered: replicaView.showMode = false
                }
                // (cycle mode label removed per request; hotspot still toggles)

                // ---- favorite overlay + hotspot ----
                Text {
                    x: 0.8056 * parent.width - width / 2
                    y: 0.8451 * parent.height - height / 2
                    width: 0.10 * parent.width; height: width
                    text: replicaView.favNow ? "♥" : "♡"
                    font.pixelSize: parent.width * 0.060
                    color: replicaView.favNow ? "#e3b959" : "#8a6d2f"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                Item {
                    x: 0.8056 * parent.width - width / 2
                    y: 0.8511 * parent.height - height / 2
                    width: 0.15 * parent.width; height: width
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var s = queue.currentSong
                            if (s && s.id) queue.toggleFavorite(s.id)
                        }
                    }
                }

                // ---- circular progress ring around the dial + traveling knob ----
                Canvas {
                    id: progressArc
                    anchors.fill: parent
                    renderTarget: Canvas.Image
                    onPaint: {
                        var ctx = getContext("2d")
                        var w = width, h = height
                        var cx = 0.5 * w, cy = 0.4804 * h, r = 0.2315 * w + 2
                        var a0 = 117.8 * Math.PI / 180
                        var full = 2 * Math.PI
                        var p = mpv.duration > 0
                            ? Math.max(0, Math.min(1, mpv.position / mpv.duration)) : 0
                        ctx.clearRect(0, 0, w, h)
                        ctx.lineCap = "round"
                        // full dim track ring
                        ctx.strokeStyle = "#5a4a22"
                        ctx.lineWidth = Math.max(2, w * 0.006)
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, full)
                        ctx.stroke()
                        // gold progress sweep (clockwise from lower-left)
                        if (p > 0.003) {
                            ctx.strokeStyle = "#e3b959"
                            ctx.lineWidth = Math.max(2, w * 0.008)
                            ctx.beginPath()
                            ctx.arc(cx, cy, r, a0, a0 - p * full, true)
                            ctx.stroke()
                        }
                        // knob dot traveling on the ring
                        var a = a0 - p * full
                        ctx.fillStyle = "#f0d488"
                        ctx.beginPath()
                        ctx.arc(cx + r * Math.cos(a), cy + r * Math.sin(a),
                                Math.max(3, w * 0.014), 0, Math.PI * 2)
                        ctx.fill()
                    }
                }
                Connections {
                    target: mpv
                    onPositionChanged: progressArc.requestPaint()
                    onDurationChanged: progressArc.requestPaint()
                }
                MouseArea {
                    id: arcScrub
                    x: 0; width: parent.width
                    y: 0.30 * parent.height; height: 0.45 * parent.height
                    z: 4
                    function seekAt(mx, my) {
                        // mouse.x/y are local to arcScrub; map to parent coords
                        var px = mx + arcScrub.x
                        var py = my + arcScrub.y
                        var cx = 0.5 * parent.width
                        var cy = 0.4804 * parent.height
                        var r = 0.2315 * parent.width + 2
                        var dx = px - cx, dy = py - cy
                        if (Math.abs(Math.sqrt(dx * dx + dy * dy) - r) > parent.width * 0.09) return
                        var deg = Math.atan2(dy, dx) * 180 / Math.PI
                        if (deg < 0) deg += 360
                        var d = (117.8 - deg) % 360
                        if (d < 0) d += 360
                        var p = d / 360
                        if (mpv.duration > 0) mpv.seek(p * mpv.duration)
                    }
                    onPressed: seekAt(mouse.x, mouse.y)
                    onClicked: seekAt(mouse.x, mouse.y)
                    onPositionChanged: { if (pressed) seekAt(mouse.x, mouse.y) }
                }

                // ---- time (dynamic): below the buttons when there is room,
                // else just under the arc (a +150 drop would cover the cycle button) ----
                Rectangle {
                    x: 0.35 * parent.width
                    y: replicaView.bottomBarH > 20 ? 0.912 * parent.height : 0.722 * parent.height + 75
                    width: 0.30 * parent.width; height: 0.030 * parent.height
                    color: "#000000"
                }
                Text {
                    x: 0.35 * parent.width
                    y: replicaView.bottomBarH > 20 ? 0.912 * parent.height : 0.722 * parent.height + 75
                    width: 0.30 * parent.width; height: 0.030 * parent.height
                    text: playerPage.fmtTime(mpv.position) + " / " + playerPage.fmtTime(mpv.duration)
                    font.pixelSize: parent.width * 0.026; color: "#e8e4d8"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // ---- queue row: above lyrics, below the buttons (1.5x font) ----
                Text {
                    x: replicaView.bottomBarH > 20 ? 0.06 * parent.width : 0.70 * parent.width
                    y: replicaView.bottomBarH > 20 ? 0.948 * parent.height : 0.150 * parent.height
                    width: replicaView.bottomBarH > 20 ? 0.34 * parent.width : 0.26 * parent.width
                    height: 0.030 * parent.height
                    text: "播放队列 (" + queue.count + ") >"
                    font.pixelSize: parent.width * 0.039; color: "#e3b959"
                    horizontalAlignment: replicaView.bottomBarH > 20 ? Text.AlignLeft : Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight; maximumLineCount: 1
                }
                Item {
                    x: replicaView.bottomBarH > 20 ? 0.06 * parent.width : 0.70 * parent.width
                    y: replicaView.bottomBarH > 20 ? 0.948 * parent.height : 0.150 * parent.height
                    width: replicaView.bottomBarH > 20 ? 0.34 * parent.width : 0.26 * parent.width
                    height: 0.030 * parent.height
                    MouseArea { anchors.fill: parent; onClicked: replicaView.showQueue = true }
                }
                Text {
                    x: replicaView.bottomBarH > 20 ? 0.60 * parent.width : 0.04 * parent.width
                    y: replicaView.bottomBarH > 20 ? 0.948 * parent.height : 0.150 * parent.height
                    width: replicaView.bottomBarH > 20 ? 0.34 * parent.width : 0.26 * parent.width
                    height: 0.030 * parent.height
                    text: "♪ 共 " + queue.count + " 首"
                    font.pixelSize: parent.width * 0.039
                    color: replicaView.bottomBarH > 20 ? "#b9c6d4" : "#8a6d2f"
                    horizontalAlignment: replicaView.bottomBarH > 20 ? Text.AlignRight : Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight; maximumLineCount: 1
                }

                // (音量 / 收藏 labels removed per request; icons stay, hotspots work)

                // ---- KTV three lines (in the filled bottom bar, else image bottom) ----
                KtvLyrics {
                    id: replicaKtv
                    x: 0.04 * parent.width
                    y: replicaView.bottomBarH > 20
                       ? parent.height + (replicaView.bottomBarH - height) / 2
                       : 0.880 * parent.height
                    width: 0.92 * parent.width
                    height: replicaView.bottomBarH > 20
                            ? Math.min(0.108 * parent.height, replicaView.bottomBarH * 0.95)
                            : 0.108 * parent.height
                    compact: true
                    showHint: false
                    accent: "#e3b959"
                    currentLine: lyricSync.currentLine
                    position: mpv.position
                    duration: mpv.duration
                    playing: !mpv.isPaused && queue.count > 0
                }

                // ---- queue overlay panel ----
                Item {
                    id: queuePanel
                    anchors.fill: parent
                    visible: replicaView.showQueue
                    Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.94 }
                    Text {
                        x: 0.06 * parent.width; y: 0.05 * parent.height
                        text: "播放队列 (" + queue.count + ")"
                        font.pixelSize: parent.width * 0.042; font.bold: true
                        color: "#f0d488"
                    }
                    Item {
                        x: parent.width - width - 0.06 * parent.width
                        y: 0.045 * parent.height
                        width: 0.20 * parent.width; height: 0.045 * parent.height
                        Rectangle {
                            anchors.fill: parent; radius: 6 * app.s
                            color: "transparent"
                            border.color: "#e3b959"; border.width: 1
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "关闭"
                            font.pixelSize: parent.width * 0.16; color: "#e3b959"
                        }
                        MouseArea { anchors.fill: parent; onClicked: replicaView.showQueue = false }
                    }
                    ListView {
                        id: replicaQueueList
                        x: 0.06 * parent.width; y: 0.11 * parent.height
                        width: 0.88 * parent.width; height: 0.84 * parent.height
                        clip: true
                        model: queue.count
                        delegate: Rectangle {
                            property var qs: queue.songAt(index)
                            width: replicaQueueList.width; height: 44 * app.s
                            color: index === queue.currentIndex ? "#2a3a4a" : "#14ffffff"
                            radius: 6
                            border.color: index === queue.currentIndex ? "#e3b959" : "transparent"
                            border.width: 1
                            Text {
                                anchors.left: parent.left; anchors.leftMargin: 8 * app.s
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 16 * app.s
                                text: (index + 1) + ". " + (qs.name || "unknown")
                                      + (qs.artists ? " — " + qs.artists : "")
                                font.pixelSize: 15 * app.s
                                color: index === queue.currentIndex ? "#f0d488" : "#ffffff"
                                elide: Text.ElideRight; maximumLineCount: 1
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    queue.setCurrentIndex(index)
                                    replicaView.showQueue = false
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: playerView
            anchors.top: playerTopBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16 * app.s
            visible: false   // phase-1: replicaView below replaces it (kept as phase-2 base)

            // ---- title / artist ----
            Item {
                id: metaRow
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 48 * app.s
                Column {
                    anchors.centerIn: parent
                    width: parent.width; spacing: 3 * app.s
                    Text {
                        width: parent.width
                        text: queue.currentSong.name || "No song"
                        font.pixelSize: 24 * app.s; font.bold: true; color: "#f0d488"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight; maximumLineCount: 1
                    }
                    Text {
                        width: parent.width
                        text: queue.currentSong.artists || ""
                        font.pixelSize: 15 * app.s; color: "#b9c6d4"
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight; maximumLineCount: 1
                    }
                }
            }

            // ---- Bagua stage: gold dial ring + spinning cover disc ----
            // Layout follows the gold-ink reference: round dial in the middle,
            // prev / next round buttons flanking it at mid height.
            Item {
                id: discStage
                anchors.top: metaRow.bottom
                anchors.topMargin: 4 * app.s
                anchors.horizontalCenter: parent.horizontalCenter
                property real discD: Math.min(parent.width * 0.60, 300 * app.s)
                width: Math.min(parent.width, discD + 150 * app.s)
                height: width

                BaguaDial {
                    anchors.fill: parent
                }

                VinylDisc {
                    id: playerDisc
                    anchors.centerIn: parent
                    width: discStage.discD
                    height: width
                    coverSource: queue.currentSong.coverUrl || ""
                    playing: !mpv.isPaused && queue.count > 0
                    showTonearm: false
                    spinDuration: 16000
                }

                // prev button, mid-left of the dial
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 2 * app.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * app.s
                    Rectangle {
                        id: prevBtn
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 54 * app.s; height: 54 * app.s; radius: 27 * app.s
                        color: "#1a000000"
                        border.color: "#e3b959"; border.width: 2
                        Text {
                            anchors.centerIn: parent
                            text: "◀"
                            font.pixelSize: 24 * app.s; color: "#e3b959"
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: queue.previous() }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "上一曲"
                        font.pixelSize: 12 * app.s; color: "#e3b959"
                    }
                }

                // next button, mid-right of the dial
                Column {
                    anchors.right: parent.right
                    anchors.rightMargin: 2 * app.s
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * app.s
                    Rectangle {
                        id: nextBtn
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 54 * app.s; height: 54 * app.s; radius: 27 * app.s
                        color: "#1a000000"
                        border.color: "#e3b959"; border.width: 2
                        Text {
                            anchors.centerIn: parent
                            text: "▶"
                            font.pixelSize: 24 * app.s; color: "#e3b959"
                            font.bold: true
                        }
                        MouseArea { anchors.fill: parent; onClicked: queue.next() }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "下一曲"
                        font.pixelSize: 12 * app.s; color: "#e3b959"
                    }
                }
            }

            // ---- spectrum visualizer: hugs the disc, disc rolls on waves ----
            Item {
                id: spectrumBox
                anchors.top: discStage.bottom
                anchors.topMargin: -38 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 64 * app.s
                SpectrumBars {
                    anchors.fill: parent
                    playing: !mpv.isPaused && queue.count > 0
                    volume: mpv.volume
                    lineLength: playerDisc.width * 2
                    accentColor: "#e3b959"
                }
            }

            // ---- KTV stage: prev / current / next line (below the disc) ----
            KtvLyrics {
                id: ktvPlayer
                anchors.top: spectrumBox.bottom
                anchors.topMargin: 6 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 104 * app.s
                visible: lyricSync.hasLyrics
                compact: true
                showHint: false
                currentLine: lyricSync.currentLine
                position: mpv.position
                duration: mpv.duration
                playing: !mpv.isPaused && queue.count > 0
                accent: "#e3b959"
            }
            Connections {
                target: lyricSync
                onLyricsChanged: ktvPlayer.lines = lyricSync.lines()
            }
            Component.onCompleted: {
                if (lyricSync.hasLyrics) ktvPlayer.lines = lyricSync.lines()
            }

            // ---- progress + time ----
            Item {
                id: progressScrubber
                anchors.top: ctrlBox.bottom
                anchors.topMargin: 6 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 28 * app.s

                Text { id: posLabel; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: playerPage.fmtTime(mpv.position); font.pixelSize: 12 * app.s; color: "#aab6c4" }
                Text { id: durLabel; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: playerPage.fmtTime(mpv.duration); font.pixelSize: 12 * app.s; color: "#aab6c4" }
                Rectangle {
                    anchors.left: posLabel.right; anchors.leftMargin: 8
                    anchors.right: durLabel.left; anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6 * app.s; radius: 3; color: "#55ffffff"
                    Rectangle {
                        width: parent.width * (mpv.duration > 0 ? mpv.position / mpv.duration : 0)
                        height: parent.height; radius: 3; color: "#e3b959"
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.topMargin: -11 * app.s
                        anchors.bottomMargin: -11 * app.s
                        function scrubTo(mx) {
                            if (mpv.duration > 0) {
                                var pct = Math.max(0, Math.min(1, mx / width))
                                mpv.seek(pct * mpv.duration)
                            }
                        }
                        onPressed: scrubTo(mouse.x)
                        onClicked: scrubTo(mouse.x)
                        onPositionChanged: { if (pressed) scrubTo(mouse.x) }
                    }
                }
            }

            // ---- big play / pause button (gold ring, reference style) ----
            Item {
                id: ctrlBox
                anchors.top: ktvPlayer.visible ? ktvPlayer.bottom : spectrumBox.bottom
                anchors.topMargin: 8 * app.s
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120 * app.s; height: 100 * app.s

                // shadow under the play button
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 36 * app.s
                    width: 76 * app.s; height: 24 * app.s
                    radius: 12 * app.s
                    color: "#66000000"
                }

                Rectangle {
                    id: playBtn
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: 68 * app.s; height: 68 * app.s; radius: 34 * app.s
                    color: "#1a000000"
                    border.color: "#e3b959"; border.width: 2
                    Text {
                        anchors.centerIn: parent
                        text: mpv.isPaused ? "▶" : "⏸"
                        color: "#e3b959"; font.pixelSize: 30 * app.s
                    }
                    MouseArea { anchors.fill: parent; onClicked: mpv.togglePause() }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: playBtn.bottom
                    anchors.topMargin: 4 * app.s
                    text: "播放／暂停"
                    font.pixelSize: 12 * app.s; color: "#9a7d33"
                }
            }

            // ---- volume ----
            Item {
                id: volBox
                anchors.top: progressScrubber.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 24 * app.s
                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "音量"; font.pixelSize: 12 * app.s; color: "#9a7d33" }
                Rectangle {
                    anchors.left: parent.left; anchors.leftMargin: 36 * app.s
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    height: 6 * app.s; radius: 3; color: "#55ffffff"
                    Rectangle {
                        width: parent.width * (mpv.volume / 150.0)
                        height: parent.height; radius: 3; color: "#e3b959"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPositionChanged: {
                            if (pressed) {
                                var pct = Math.max(0, Math.min(1, mouse.x / width))
                                mpv.setVolume(Math.round(pct * 150))
                            }
                        }
                        onClicked: {
                            var pct = Math.max(0, Math.min(1, mouse.x / width))
                            mpv.setVolume(Math.round(pct * 150))
                        }
                    }
                }
                Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(mpv.volume); font.pixelSize: 12 * app.s; color: "#aab6c4" }
            }

            // ---- upcoming queue (reference bottom bar: queue entry) ----
            Item {
                id: queueHeader
                anchors.top: volBox.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 22 * app.s
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "播放队列 (" + queue.count + ") >"
                    font.pixelSize: 14 * app.s; color: "#e3b959"
                }
            }
            ListView {
                id: queueList
                anchors.top: queueHeader.bottom
                anchors.topMargin: 4 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                model: queue.count
                clip: true
                delegate: Rectangle {
                    width: parent.width; height: 44 * app.s
                    color: index === queue.currentIndex ? "#2a3a4a" : "#22ffffff"
                    radius: 6
                    border.color: index === queue.currentIndex ? "#e3b959" : "#22ffffff"; border.width: 1
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 8 * app.s
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: 8 * app.s
                        spacing: 8 * app.s
                        Text {
                            text: { var song = queue.songAt(index); return (index + 1) + ". " + (song.name || "unknown") }
                            font.pixelSize: 15 * app.s
                            color: index === queue.currentIndex ? "#f0d488" : "#ffffff"
                            elide: Text.ElideRight; width: parent.width - 44 * app.s
                        }
                        Text {
                            text: { var song = queue.songAt(index); return song.artists || "" }
                            font.pixelSize: 12 * app.s
                            color: index === queue.currentIndex ? "#e3b959" : "#b9c6d4"
                            elide: Text.ElideRight; width: 44 * app.s
                            horizontalAlignment: Text.AlignRight
                            visible: !!song.artists
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: queue.setCurrentIndex(index) }
                }
            }
        }
        Item {
            anchors.top: playerTopBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16 * app.s
            visible: playerPage.showLyrics

            // Full lyric list: clean centered text, no per-row boxes.
            // Current line is bright + larger; neighbours fade by distance.
            ListView {
                id: lyricListView
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6 * app.s
                clip: true
                spacing: 4 * app.s
                cacheBuffer: 400 * app.s
                model: lyricSync.hasLyrics ? lyricSync.lines().length : 0
                currentIndex: lyricSync.currentLine
                // smooth auto-centering on the current line
                preferredHighlightBegin: height / 2 - 30 * app.s
                preferredHighlightEnd: height / 2 + 30 * app.s
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightMoveDuration: 450
                delegate: Item {
                    width: lyricListView.width; height: lyricTxt.paintedHeight + 16 * app.s
                    property bool isCur: index === lyricSync.currentLine
                    property int dist: Math.abs(index - lyricSync.currentLine)
                    Text {
                        id: lyricTxt
                        anchors.centerIn: parent
                        width: parent.width - 40 * app.s
                        text: { var l = lyricSync.lines(); return (index >= 0 && index < l.length) ? (l[index].text || "") : "" }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        font.pixelSize: isCur ? 19 * app.s : 15 * app.s
                        font.bold: isCur
                        color: isCur ? "#ffffff" : "#9aa7b8"
                        opacity: isCur ? 1.0 : (dist === 1 ? 0.72 : (dist === 2 ? 0.48 : 0.30))
                        Behavior on opacity { NumberAnimation { duration: 300 } }
                    }
                }
            }

            // Keep the list in sync when the line changes.
            // ListView follows currentIndex automatically via highlightRangeMode;
            // this just pushes the new index in.
            Connections {
                target: lyricSync
                onCurrentLineChanged: {
                    if (lyricListView.currentIndex !== lyricSync.currentLine)
                        lyricListView.currentIndex = lyricSync.currentLine
                }
            }
        }

        function fmtTime(sec) {
            if (!sec || sec < 0) return "00:00"
            var m = Math.floor(sec / 60)
            var s = Math.floor(sec % 60)
            return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
        }
    }

    // ===================== ABOUT / DISCLAIMER PAGE =====================
    Rectangle {
        id: aboutPage
        anchors.fill: parent
        color: "transparent"
        visible: false

        Item {
            anchors.fill: parent
            anchors.leftMargin: 16 * app.s
            anchors.rightMargin: 16 * app.s
            anchors.bottomMargin: 16 * app.s
            anchors.topMargin: 48 * app.s

            Item {
                id: aboutHeader
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 40 * app.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "About / Disclaimer"
                    font.pixelSize: 26 * app.s; font.bold: true; color: "#ffffff"
                }
                Item {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 80 * app.s; height: 36 * app.s
                    Rectangle {
                        anchors.fill: parent
                        color: "#2effffff"
                        radius: 8
                        border.color: "#55ffffff"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "\u2190 Back"
                        color: "#4fc3f7"; font.pixelSize: 18 * app.s
                    }
                    MouseArea { anchors.fill: parent; onClicked: popPage() }
                }
            }

            Flickable {
                anchors.top: aboutHeader.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                contentWidth: width
                contentHeight: aboutText.height + 20 * app.s
                clip: true

                Text {
                    id: aboutText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: qsTr(
"MusicFox — a touch-friendly music player for Sailfish OS, powered by NetEase Cloud Music.

This is an independent third-party client. It is not affiliated with, endorsed by, or connected to NetEase / NetEase Cloud Music.

LICENSE & DISCLAIMER

1. Trademark
The app name and design are original. If they happen to resemble any existing trademark, it is coincidental.

2. Copyright
This app does not copy, store, or download songs, audio, covers, or lyrics. Covers, lyrics, and streaming links are served by network services and remain the property of their owners. Audio streams are played live only, never persisted.

3. Interface use
To satisfy personal use, this app may rely on unofficial interfaces. This may breach the provider's Terms of Service. The provider may change, restrict, or revoke access at any time; availability is not guaranteed.

4. User responsibility
Use this app for personal, non-commercial purposes only. Comply with local law and applicable service terms. Redistribution or commercial use is not permitted.

5. No warranty / liability
This app is provided AS IS, without warranty of any kind. The author is not liable for any direct or indirect loss, disputes, API restrictions, or service unavailability arising from its use.

For private study, development, and entertainment only. Use within the bounds of the law.")
                    font.pixelSize: 15 * app.s
                    color: "#cccccc"
                    wrapMode: Text.Wrap
                    lineHeight: 1.3
                }
            }
        }
    }
}
