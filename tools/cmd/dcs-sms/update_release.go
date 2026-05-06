package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// defaultReleasesURL is the production GitHub Releases endpoint. Tests
// pass a different URL (an httptest server) directly to findLatestRelease.
const defaultReleasesURL = "https://api.github.com/repos/nielsvaes/dcs-sms/releases"

// assetName is the asset filename we look for in each release.
const assetName = "dcs-sms.exe"

// Release is the subset of a GitHub Release record we use.
type Release struct {
	TagName   string
	AssetName string
	AssetURL  string // browser_download_url for direct binary fetch
	AssetSize int64
}

// ghAsset and ghRelease mirror the JSON shape returned by the GitHub
// Releases API, with only the fields we read.
type ghAsset struct {
	Name               string `json:"name"`
	Size               int64  `json:"size"`
	BrowserDownloadURL string `json:"browser_download_url"`
}

type ghRelease struct {
	TagName    string    `json:"tag_name"`
	Draft      bool      `json:"draft"`
	Prerelease bool      `json:"prerelease"`
	Assets     []ghAsset `json:"assets"`
}

// findLatestRelease GETs releasesURL and returns the first non-draft
// release with a `dcs-sms.exe` asset. The GitHub API returns releases
// in newest-first order, so the first match is the "latest" release
// that ships the binary we care about.
//
// releasesURL is taken verbatim — the caller passes either the real
// API URL or an httptest server URL.
func findLatestRelease(ctx context.Context, client *http.Client, releasesURL string) (*Release, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, releasesURL, nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("contact GitHub: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		return nil, fmt.Errorf("GitHub API returned %d: %s",
			resp.StatusCode, strings.TrimSpace(string(body)))
	}

	var releases []ghRelease
	if err := json.NewDecoder(resp.Body).Decode(&releases); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	for _, r := range releases {
		if r.Draft {
			continue
		}
		for _, a := range r.Assets {
			if a.Name == assetName {
				return &Release{
					TagName:   r.TagName,
					AssetName: a.Name,
					AssetURL:  a.BrowserDownloadURL,
					AssetSize: a.Size,
				}, nil
			}
		}
	}

	return nil, fmt.Errorf("no release with a %q asset found", assetName)
}
