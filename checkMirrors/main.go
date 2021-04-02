package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
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
}

type mirrorStatusList struct {
	Urls []mirrorStatus `json:"urls"`
}

func main() {
	isoVersion := fetchLatestVersion()
	fmt.Printf("Latest version is %s\n", isoVersion)
	mirrorUrlList := fetchMirrorUrls()

	var isoUrls []string
	for _, s := range mirrorUrlList.Urls {
		if s.Protocol == "https" || s.Protocol == "http" {
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
		select {
		case s := <-status:
			if s {
				okStatus++
			} else {
				failStatus++
			}
			fmt.Printf("\rTesting %d of %d servers - OK: %d, Failure: %d", okStatus+failStatus, numberOfUrls, okStatus, failStatus)
		}
	}
	fmt.Println("")
}

func CheckUrl(url string, status chan bool) {
	c := &http.Client{
		Timeout: 20 * time.Second,
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
	releasesJson, err := ioutil.ReadAll(response.Body)
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
	mirrorStatusJson, err := ioutil.ReadAll(response.Body)
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
