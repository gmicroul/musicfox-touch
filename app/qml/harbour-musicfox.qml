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
        onEndOfFile: queue.next()
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

        Item {
            id: playerView
            anchors.top: playerTopBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16 * app.s
            visible: !playerPage.showLyrics

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
                        font.pixelSize: 22 * app.s; font.bold: true; color: "#ffffff"
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

            // ---- spinning vinyl + tonearm ----
            VinylDisc {
                id: playerDisc
                anchors.top: metaRow.bottom
                anchors.topMargin: 12 * app.s
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width * 0.60, 300 * app.s)
                height: width
                coverSource: queue.currentSong.coverUrl || ""
                playing: !mpv.isPaused && queue.count > 0
                showTonearm: true
                spinDuration: 16000
            }

            // ---- spectrum visualizer (cava style) ----
            Item {
                id: spectrumBox
                anchors.top: playerDisc.bottom
                anchors.topMargin: 14 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 92 * app.s
                SpectrumBars {
                    anchors.fill: parent
                    playing: !mpv.isPaused && queue.count > 0
                    volume: mpv.volume
                    lineLength: playerDisc.width * 2
                }
            }

            // ---- live lyric preview (below the disc) ----
            Text {
                id: liveLyric
                anchors.top: spectrumBox.bottom
                anchors.topMargin: 8 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 22 * app.s
                text: lyricSync.hasLyrics ? (lyricSync.currentText || "") : ""
                color: "#4fc3f7"
                font.pixelSize: 15 * app.s
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight; maximumLineCount: 1
                visible: lyricSync.hasLyrics
            }

            // ---- progress + time ----
            Item {
                id: progressScrubber
                anchors.top: liveLyric.visible ? liveLyric.bottom : spectrumBox.bottom
                anchors.topMargin: 8 * app.s
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
                        height: parent.height; radius: 3; color: "#4fc3f7"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (mpv.duration > 0) {
                                var pct = mouse.x / width
                                mpv.seek(pct * mpv.duration)
                            }
                        }
                    }
                }
            }

            // ---- play / prev / next ----
            Item {
                id: ctrlBox
                anchors.top: progressScrubber.bottom
                anchors.topMargin: 12 * app.s
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, 380 * app.s); height: 84 * app.s

                // shadow under the play button
                Rectangle {
                    anchors.centerIn: parent
                    width: 76 * app.s; height: 24 * app.s
                    radius: 12 * app.s
                    color: "#66000000"
                }

                Rectangle {
                    id: prevBtn
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14 * app.s
                    width: 48 * app.s; height: 48 * app.s; radius: 24 * app.s
                    color: "#28ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: "\u25C0"
                        font.pixelSize: 24 * app.s; color: "#ffffff"
                        font.bold: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: queue.previous() }
                }

                Rectangle {
                    id: playBtn
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 48 * app.s; height: 48 * app.s; radius: 24 * app.s
                    color: "#4fc3f7"
                    border.color: "#ffffff"; border.width: 2
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#6ed0f8" }
                        GradientStop { position: 1.0; color: "#4fc3f7" }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: mpv.isPaused ? "\u25B6" : "\u23F8"
                        color: "#001828"; font.pixelSize: 26 * app.s
                    }
                    MouseArea { anchors.fill: parent; onClicked: mpv.togglePause() }
                }

                Rectangle {
                    id: nextBtn
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 14 * app.s
                    width: 48 * app.s; height: 48 * app.s; radius: 24 * app.s
                    color: "#28ffffff"
                    Text {
                        anchors.centerIn: parent
                        text: "\u25B6"
                        font.pixelSize: 24 * app.s; color: "#ffffff"
                        font.bold: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: queue.next() }
                }
            }

            // ---- volume ----
            Item {
                id: volBox
                anchors.top: ctrlBox.bottom
                anchors.topMargin: 12 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                height: 24 * app.s
                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    text: "Vol"; font.pixelSize: 12 * app.s; color: "#aab6c4" }
                Rectangle {
                    anchors.left: parent.left; anchors.leftMargin: 36 * app.s
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    height: 6 * app.s; radius: 3; color: "#55ffffff"
                    Rectangle {
                        width: parent.width * (mpv.volume / 150.0)
                        height: parent.height; radius: 3; color: "#4fc3f7"
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

            // ---- upcoming queue ----
            ListView {
                id: queueList
                anchors.top: volBox.bottom
                anchors.topMargin: 10 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                model: queue.count
                clip: true
                delegate: Rectangle {
                    width: parent.width; height: 44 * app.s
                    color: index === queue.currentIndex ? "#1a2a3a" : "#22ffffff"
                    radius: 6
                    border.color: "#22ffffff"; border.width: 1
                    Row {
                        anchors.left: parent.left; anchors.leftMargin: 8 * app.s
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: 8 * app.s
                        spacing: 8 * app.s
                        Text {
                            text: { var song = queue.songAt(index); return (index + 1) + ". " + (song.name || "unknown") }
                            font.pixelSize: 15 * app.s
                            color: index === queue.currentIndex ? "#4fc3f7" : "#ffffff"
                            elide: Text.ElideRight; width: parent.width - 44 * app.s
                        }
                        Text {
                            text: { var song = queue.songAt(index); return song.artists || "" }
                            font.pixelSize: 12 * app.s
                            color: index === queue.currentIndex ? "#6ed0f8" : "#b9c6d4"
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

            KtvLyrics {
                id: ktvLyrics
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 170 * app.s
                currentLine: lyricSync.currentLine
                position: mpv.position
                duration: mpv.duration
                playing: !mpv.isPaused && queue.count > 0
                accent: "#4fc3f7"
            }

            // full lyric list (auto-scrolls with the current line)
            ListView {
                id: lyricListView
                anchors.top: ktvLyrics.bottom
                anchors.topMargin: 10 * app.s
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: lyricSpectrum.top
                anchors.bottomMargin: 10 * app.s
                clip: true
                model: lyricSync.hasLyrics ? lyricSync.lines().length : 0
                currentIndex: lyricSync.currentLine
                delegate: Item {
                    width: parent.width; height: 36 * app.s
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 3 * app.s
                        radius: 8
                        color: index === lyricSync.currentLine ? "#1a2a3a" : "#22ffffff"
                        border.color: index === lyricSync.currentLine ? "#4fc3f7" : "#22ffffff"
                        border.width: 1
                    }
                    Text {
                        anchors.centerIn: parent
                        text: { var l = lyricSync.lines(); return (index >= 0 && index < l.length) ? (l[index].text || "") : "" }
                        font.pixelSize: index === lyricSync.currentLine ? 16 * app.s : 15 * app.s
                        color: index === lyricSync.currentLine ? "#4fc3f7" : "#b9c6d4"
                        elide: Text.ElideRight; width: parent.width - 16 * app.s
                    }
                }
            }

            // Keep the KTV stage + list in sync when lyrics load / line changes
            Connections {
                target: lyricSync
                onLyricsChanged: ktvLyrics.lines = lyricSync.lines()
                onCurrentLineChanged: {
                    if (lyricListView.currentIndex !== lyricSync.currentLine)
                        lyricListView.currentIndex = lyricSync.currentLine
                    if (lyricListView.currentIndex >= 0)
                        lyricListView.positionViewAtIndex(lyricListView.currentIndex, ListView.Center)
                }
            }
            Component.onCompleted: {
                if (lyricSync.hasLyrics) ktvLyrics.lines = lyricSync.lines()
            }

            Item {
                id: lyricSpectrum
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 92 * app.s
                SpectrumBars {
                    anchors.fill: parent
                    playing: !mpv.isPaused && queue.count > 0
                    volume: mpv.volume
                    lineLength: playerDisc.width * 2
                    accentColor: "#2cb4ff"
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
