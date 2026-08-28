package main

import (
	"encoding/json"
	"fmt"
	"os"

	sdk "github.com/go-musicfox/netease-music/service"
)

func main() {
	s := sdk.SongUrlService{ID: os.Args[1], Br: "320000"}
	_, body := s.SongUrl()
	var r struct {
		Data []struct {
			URL  string `json:"url"`
			Type string `json:"type"`
			Br   int    `json:"br"`
		} `json:"data"`
	}
	json.Unmarshal(body, &r)
	if len(r.Data) > 0 && r.Data[0].URL != "" {
		fmt.Println(r.Data[0].URL)
	}
}
