package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/buger/jsonparser"
	sdk "github.com/go-musicfox/netease-music/service"
)

// ========== Protocol Types ==========

type Request struct {
	ID     int64           `json:"id"`
	Method string          `json:"method"`
	Params json.RawMessage `json:"params,omitempty"`
}

type Response struct {
	ID     int64           `json:"id"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *Error          `json:"error,omitempty"`
}

type Error struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type Song struct {
	ID       int64  `json:"id"`
	Name     string `json:"name"`
	Artists  string `json:"artists"`
	Album    string `json:"album"`
	AlbumID  int64  `json:"albumId"`
	Duration int64  `json:"duration"`
	Fee      int    `json:"fee"`
	URL      string `json:"url,omitempty"`
	Br       int    `json:"br,omitempty"`
	Type     string `json:"type,omitempty"`
	CoverURL string `json:"coverUrl,omitempty"`
}

type Playlist struct {
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	CoverURL    string `json:"coverUrl"`
	TrackCount  int    `json:"trackCount"`
	PlayCount   int64  `json:"playCount"`
	CreatorName string `json:"creatorName"`
}

type SearchResult struct {
	Songs     []Song     `json:"songs,omitempty"`
	Playlists []Playlist `json:"playlists,omitempty"`
}

type LyricLine struct {
	Time float64 `json:"time"`
	Text string  `json:"text"`
}

type LyricResult struct {
	Lines []LyricLine `json:"lines"`
}

// ========== Helpers ==========

func writeResponse(id int64, result interface{}, err *Error) {
	resp := Response{ID: id}
	if err != nil {
		resp.Error = err
	} else {
		b, marshalErr := json.Marshal(result)
		if marshalErr != nil {
			resp.Error = &Error{-32603, "marshal error: " + marshalErr.Error()}
		} else {
			resp.Result = b
		}
	}
	out, _ := json.Marshal(resp)
	fmt.Println(string(out))
}

func parseParams(raw json.RawMessage, v interface{}) error {
	return json.Unmarshal(raw, v)
}

// ========== Song parsing from raw JSON ==========

func parseSongFromJSON(data []byte) Song {
	id, _ := jsonparser.GetInt(data, "id")
	name, _ := jsonparser.GetString(data, "name")

	// artists are in "ar" array
	var artistNames []string
	jsonparser.ArrayEach(data, func(value []byte, dataType jsonparser.ValueType, offset int, err error) {
		if n, e := jsonparser.GetString(value, "name"); e == nil {
			artistNames = append(artistNames, n)
		}
	}, "ar")

	// album is in "al" object
	albumName, _ := jsonparser.GetString(data, "al", "name")
	albumID, _ := jsonparser.GetInt(data, "al", "id")
	coverURL, _ := jsonparser.GetString(data, "al", "picUrl")
	fee, _ := jsonparser.GetInt(data, "fee")

	// duration is in "dt" (milliseconds)
	durationMs, _ := jsonparser.GetInt(data, "dt")

	return Song{
		ID:       id,
		Name:     name,
		Artists:  strings.Join(artistNames, ", "),
		Album:    albumName,
		AlbumID:  albumID,
		Duration: durationMs,
		Fee:      int(fee),
		CoverURL: coverURL,
	}
}

func parseSongsFromBody(data []byte, jsonPath ...string) []Song {
	songsData, _, _, _ := jsonparser.Get(data, jsonPath...)
	if len(songsData) == 0 {
		return nil
	}
	var songs []Song
	jsonparser.ArrayEach(songsData, func(value []byte, dataType jsonparser.ValueType, offset int, err error) {
		songs = append(songs, parseSongFromJSON(value))
	})
	return songs
}

func parsePlaylistsFromBody(data []byte, jsonPath ...string) []Playlist {
	plData, _, _, _ := jsonparser.Get(data, jsonPath...)
	if len(plData) == 0 {
		return nil
	}
	var pls []Playlist
	jsonparser.ArrayEach(plData, func(value []byte, dataType jsonparser.ValueType, offset int, err error) {
		id, _ := jsonparser.GetInt(value, "id")
		name, _ := jsonparser.GetString(value, "name")
		cover, _ := jsonparser.GetString(value, "coverImgUrl")
		tc, _ := jsonparser.GetInt(value, "trackCount")
		pc, _ := jsonparser.GetInt(value, "playCount")
		creator, _ := jsonparser.GetString(value, "creator", "nickname")
		pls = append(pls, Playlist{
			ID: id, Name: name, CoverURL: cover,
			TrackCount: int(tc), PlayCount: pc, CreatorName: creator,
		})
	})
	return pls
}

// ========== API Handlers ==========

func handleSearch(params json.RawMessage, id int64) {
	type p struct {
		Keyword string `json:"keyword"`
		Type    int    `json:"type"`
		Limit   int    `json:"limit"`
	}
	var pp p
	if err := parseParams(params, &pp); err != nil {
		writeResponse(id, nil, &Error{-32602, err.Error()})
		return
	}
	if pp.Limit == 0 {
		pp.Limit = 30
	}

	searchType := "1"
	if pp.Type == 1000 {
		searchType = "1000"
	}

	s := sdk.SearchService{
		S:      pp.Keyword,
		Type:   searchType,
		Limit:  strconv.Itoa(pp.Limit),
		Offset: "0",
	}
	code, body := s.Search()
	if code != 200 {
		writeResponse(id, nil, &Error{-32000, fmt.Sprintf("search failed code %v", code)})
		return
	}

	var result SearchResult
	if pp.Type == 1 {
		result.Songs = parseSongsFromBody(body, "result", "songs")
	} else if pp.Type == 1000 {
		result.Playlists = parsePlaylistsFromBody(body, "result", "playlists")
	}
	writeResponse(id, result, nil)
}

func handleSongDetail(params json.RawMessage, id int64) {
	type p struct {
		IDs []int64 `json:"ids"`
	}
	var pp p
	if err := parseParams(params, &pp); err != nil {
		writeResponse(id, nil, &Error{-32602, err.Error()})
		return
	}
	if len(pp.IDs) == 0 {
		writeResponse(id, []Song{}, nil)
		return
	}

	idsStr := make([]string, len(pp.IDs))
	for i, v := range pp.IDs {
		idsStr[i] = strconv.FormatInt(v, 10)
	}
	s := sdk.SongDetailService{Ids: strings.Join(idsStr, ",")}
	code, body := s.SongDetail()
	if code != 200 {
		writeResponse(id, nil, &Error{-32000, fmt.Sprintf("song detail failed code %v", code)})
		return
	}

	songs := parseSongsFromBody(body, "songs")
	writeResponse(id, songs, nil)
}

func handleSongURL(params json.RawMessage, id int64) {
	type p struct {
		ID int64 `json:"id"`
		Br int   `json:"br"`
	}
	var pp p
	if err := parseParams(params, &pp); err != nil {
		writeResponse(id, nil, &Error{-32602, err.Error()})
		return
	}
	if pp.Br == 0 {
		pp.Br = 320000
	}

	s := sdk.SongUrlService{
		ID: strconv.FormatInt(pp.ID, 10),
		Br: strconv.Itoa(pp.Br),
	}
	_, body := s.SongUrl()

	url, _ := jsonparser.GetString(body, "data", "[0]", "url")
	br, _ := jsonparser.GetInt(body, "data", "[0]", "br")
	tp, _ := jsonparser.GetString(body, "data", "[0]", "type")
	code, _ := jsonparser.GetInt(body, "data", "[0]", "code")

	writeResponse(id, map[string]interface{}{
		"url": url, "br": br, "type": tp, "code": code,
	}, nil)
}

func handlePlaylistDetail(params json.RawMessage, id int64) {
	type p struct {
		ID     int64 `json:"id"`
		GetAll bool  `json:"getAll"`
	}
	var pp p
	if err := parseParams(params, &pp); err != nil {
		writeResponse(id, nil, &Error{-32602, err.Error()})
		return
	}

	idStr := strconv.FormatInt(pp.ID, 10)

	// Always get playlist meta first
	metaService := sdk.PlaylistDetailService{Id: idStr, S: "0"}
	_, metaBody := metaService.PlaylistDetail()

	plName, _ := jsonparser.GetString(metaBody, "playlist", "name")
	plCover, _ := jsonparser.GetString(metaBody, "playlist", "coverImgUrl")
	plCount, _ := jsonparser.GetInt(metaBody, "playlist", "trackCount")
	plPlayCount, _ := jsonparser.GetInt(metaBody, "playlist", "playCount")
	creatorNick, _ := jsonparser.GetString(metaBody, "playlist", "creator", "nickname")

	// Get songs
	var songs []Song
	if pp.GetAll {
		allTrack := sdk.PlaylistTrackAllService{Id: idStr}
		code, body := allTrack.AllTracks()
		if code != 200 {
			writeResponse(id, nil, &Error{-32000, fmt.Sprintf("playlist tracks failed code %v", code)})
			return
		}
		songs = parseSongsFromBody(body, "playlist", "tracks")
	} else {
		songs = parseSongsFromBody(metaBody, "playlist", "tracks")
	}

	writeResponse(id, map[string]interface{}{
		"playlist": Playlist{
			ID: pp.ID, Name: plName, CoverURL: plCover,
			TrackCount: int(plCount), PlayCount: plPlayCount, CreatorName: creatorNick,
		},
		"songs": songs,
	}, nil)
}

func handleToplist(params json.RawMessage, id int64) {
	s := sdk.ToplistService{}
	code, body := s.Toplist()
	if code != 200 {
		writeResponse(id, nil, &Error{-32000, fmt.Sprintf("toplist failed code %v", code)})
		return
	}

	type TL struct {
		ID    int64  `json:"id"`
		Name  string `json:"name"`
		Cover string `json:"cover"`
	}
	var lists []TL
	jsonparser.ArrayEach(body, func(value []byte, dataType jsonparser.ValueType, offset int, err error) {
		idVal, _ := jsonparser.GetInt(value, "id")
		name, _ := jsonparser.GetString(value, "name")
		cover, _ := jsonparser.GetString(value, "coverImgUrl")
		lists = append(lists, TL{ID: idVal, Name: name, Cover: cover})
	}, "list")
	writeResponse(id, lists, nil)
}

func handleTopPlaylists(params json.RawMessage, id int64) {
	type p struct {
		Cat   string `json:"cat"`
		Limit int    `json:"limit"`
	}
	var pp p
	if err := parseParams(params, &pp); err != nil {
		writeResponse(id, nil, &Error{-32602, err.Error()})
		return
	}
	if pp.Limit == 0 {
		pp.Limit = 30
	}
	if pp.Cat == "" {
		pp.Cat = "全部"
	}

	s := sdk.TopPlaylistService{
		Cat:   pp.Cat,
		Limit: strconv.Itoa(pp.Limit),
	}
	code, body := s.TopPlaylist()
	if code != 200 {
		writeResponse(id, nil, &Error{-32000, fmt.Sprintf("top playlist failed code %v", code)})
		return
	}

	pls := parsePlaylistsFromBody(body, "playlists")
	writeResponse(id, pls, nil)
}

func handleLyric(params json.RawMessage, id int64) {
	type p struct {
		ID int64 `json:"id"`
	}
	var pp p
	if err := parseParams(params, &pp); err != nil {
		writeResponse(id, nil, &Error{-32602, err.Error()})
		return
	}

	s := sdk.LyricService{ID: strconv.FormatInt(pp.ID, 10)}
	code, body := s.Lyric()
	if code != 200 {
		writeResponse(id, nil, &Error{-32000, fmt.Sprintf("lyric failed code %v", code)})
		return
	}
	lrc, _ := jsonparser.GetString(body, "lrc", "lyric")

	var lines []LyricLine
	for _, line := range strings.Split(lrc, "\n") {
		line = strings.TrimSpace(line)
		if len(line) < 10 || line[0] != '[' {
			continue
		}
		end := strings.Index(line, "]")
		if end == -1 {
			continue
		}
		ts := line[1:end]
		text := strings.TrimSpace(line[end+1:])

		parts := strings.Split(ts, ":")
		if len(parts) == 2 {
			m, _ := strconv.ParseFloat(parts[0], 64)
			s, _ := strconv.ParseFloat(parts[1], 64)
			lines = append(lines, LyricLine{Time: m*60 + s, Text: text})
		}
	}
	writeResponse(id, LyricResult{Lines: lines}, nil)
}

// ========== Main ==========

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var req Request
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			writeResponse(0, nil, &Error{-32700, "parse error"})
			continue
		}

		switch req.Method {
		case "search":
			handleSearch(req.Params, req.ID)
		case "songDetail":
			handleSongDetail(req.Params, req.ID)
		case "songURL":
			handleSongURL(req.Params, req.ID)
		case "playlistDetail":
			handlePlaylistDetail(req.Params, req.ID)
		case "toplist":
			handleToplist(req.Params, req.ID)
		case "topPlaylists":
			handleTopPlaylists(req.Params, req.ID)
		case "lyric":
			handleLyric(req.Params, req.ID)
		default:
			writeResponse(req.ID, nil, &Error{-32601, "method not found: " + req.Method})
		}
	}
}
