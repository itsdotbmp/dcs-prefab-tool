package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestFindLatestReleaseSelectsFirstWithAsset(t *testing.T) {
	releases := []ghRelease{
		{TagName: "framework-v0.10.0", Assets: nil}, // skipped: no .exe
		{
			TagName: "me-mod-v0.2.0",
			Assets: []ghAsset{
				{Name: "dcs-sms.exe", Size: 6_300_000, BrowserDownloadURL: "https://example/0.2.0/dcs-sms.exe"},
			},
		},
		{
			TagName: "me-mod-v0.1.0",
			Assets: []ghAsset{
				{Name: "dcs-sms.exe", Size: 6_000_000, BrowserDownloadURL: "https://example/0.1.0/dcs-sms.exe"},
			},
		},
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(releases)
	}))
	defer srv.Close()

	got, err := findLatestRelease(context.Background(), srv.Client(), srv.URL)
	if err != nil {
		t.Fatalf("findLatestRelease: %v", err)
	}
	if got.TagName != "me-mod-v0.2.0" {
		t.Errorf("TagName = %q, want %q", got.TagName, "me-mod-v0.2.0")
	}
	if got.AssetSize != 6_300_000 {
		t.Errorf("AssetSize = %d, want 6300000", got.AssetSize)
	}
	if got.AssetURL != "https://example/0.2.0/dcs-sms.exe" {
		t.Errorf("AssetURL = %q", got.AssetURL)
	}
}

func TestFindLatestReleaseSkipsDrafts(t *testing.T) {
	releases := []ghRelease{
		{
			TagName: "me-mod-v0.3.0", Draft: true,
			Assets: []ghAsset{{Name: "dcs-sms.exe", Size: 1, BrowserDownloadURL: "https://example/0.3.0"}},
		},
		{
			TagName: "me-mod-v0.2.0",
			Assets:  []ghAsset{{Name: "dcs-sms.exe", Size: 2, BrowserDownloadURL: "https://example/0.2.0"}},
		},
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(releases)
	}))
	defer srv.Close()

	got, err := findLatestRelease(context.Background(), srv.Client(), srv.URL)
	if err != nil {
		t.Fatalf("findLatestRelease: %v", err)
	}
	if got.TagName != "me-mod-v0.2.0" {
		t.Errorf("expected non-draft release, got %q", got.TagName)
	}
}

func TestFindLatestReleaseNoAsset(t *testing.T) {
	releases := []ghRelease{
		{TagName: "me-mod-v0.1.0", Assets: []ghAsset{{Name: "other.zip"}}},
	}

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(releases)
	}))
	defer srv.Close()

	_, err := findLatestRelease(context.Background(), srv.Client(), srv.URL)
	if err == nil || !strings.Contains(err.Error(), "no release with") {
		t.Errorf("expected 'no release with' error, got %v", err)
	}
}

func TestFindLatestReleaseAPIError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "rate limited", http.StatusForbidden)
	}))
	defer srv.Close()

	_, err := findLatestRelease(context.Background(), srv.Client(), srv.URL)
	if err == nil || !strings.Contains(err.Error(), "403") {
		t.Errorf("expected 403 in error, got %v", err)
	}
}
