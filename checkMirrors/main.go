package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

type releases struct {
	LatestVersion string `json:"latest_version"`
}

type mirrorStatus struct {
	Protocol string `json:"protocol"`
	Url      string `json:"url"`
	Active   bool   `json:"active"`
	Isos     bool   `json:"isos"`
}

type mirrorStatusList struct {
	Urls []mirrorStatus `json:"urls"`
}

func main() {
	// disable debug logging (e.g. used by the http client)
	log.SetOutput(io.Discard)

	isoVersion := fetchLatestVersion()
	fmt.Printf("Latest version is %s\n", isoVersion)
	mirrorUrlList := fetchMirrorUrls()

	var isoUrls []string
	for _, s := range mirrorUrlList.Urls {
		if s.Protocol == "https" && s.Active && s.Isos {
			isoUrls = append(isoUrls, fmt.Sprintf("%siso/%s/archlinux-%s-x86_64.iso", s.Url, isoVersion, isoVersion))
		}
	}

	status := make(chan bool)
	for _, isoUrl := range isoUrls {
		go CheckUrl(isoUrl, status)
	}

	okStatus := 0
	failStatus := 0
	numberOfUrls := len(isoUrls)
	for i := 0; i < numberOfUrls; i++ {
		if <-status {
			okStatus++
		} else {
			failStatus++
		}
		fmt.Printf("\rTesting %d of %d servers - OK: %d, Failure: %d", okStatus+failStatus, numberOfUrls, okStatus, failStatus)
	}
	fmt.Println("")
}

func CheckUrl(url string, status chan bool) {
	t := http.DefaultTransport.(*http.Transport).Clone()
	t.DisableKeepAlives = true
	t.MaxConnsPerHost = 1

	c := &http.Client{
		Timeout:   time.Duration(20) * time.Second,
		Transport: t,
	}
	response, err := c.Head(url)
	if err != nil {
		status <- false
		return
	}
	defer response.Body.Close()

	if response.StatusCode == http.StatusOK {
		status <- true
		return
	}

	status <- false
}

func fetchLatestVersion() string {
	response, err := http.Get("https://archlinux.org/releng/releases/json/")
	if err != nil {
		log.Fatal(err)
	}
	defer response.Body.Close()
	releasesJson, err := io.ReadAll(response.Body)
	if err != nil {
		log.Fatal(err)
	}
	var m releases
	err = json.Unmarshal(releasesJson, &m)
	if err != nil {
		log.Fatal(err)
	}

	return m.LatestVersion
}

func fetchMirrorUrls() mirrorStatusList {
	response, err := http.Get("https://www.archlinux.org/mirrors/status/json/")
	if err != nil {
		log.Fatal(err)
	}
	defer response.Body.Close()
	mirrorStatusJson, err := io.ReadAll(response.Body)
	if err != nil {
		log.Fatal(err)
	}
	var m mirrorStatusList
	err = json.Unmarshal(mirrorStatusJson, &m)
	if err != nil {
		log.Fatal(err)
	}

	return m
}
