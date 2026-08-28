package main

import (
	"encoding/json"
	"fmt"

	sdk "github.com/go-musicfox/netease-music/service"
)

func main() {
	s := sdk.SearchService{S: "周杰伦", Type: "1", Limit: "2", Offset: "0"}
	_, body := s.Search()
	var m map[string]interface{}
	json.Unmarshal(body, &m)
	result := m["result"].(map[string]interface{})
	songs := result["songs"].([]interface{})
	for i, song := range songs {
		b, _ := json.MarshalIndent(song, "", "  ")
		fmt.Printf("Song %d:\n%s\n", i, string(b))
	}
}
