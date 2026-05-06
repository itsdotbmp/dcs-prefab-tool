package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"runtime"
	"strings"
	"time"
)

func init() {
	register("update", updateCmd)
}

// updateCmd is the entry point for `dcs-sms update`.
//
// Flow:
//  1. Refuse on non-Windows.
//  2. Parse --check flag.
//  3. Hit GitHub Releases API for the latest release with a dcs-sms.exe.
//  4. Compare its tag-derived version against this binary's `version`.
//  5. If equal-or-newer locally: print "Up to date".
//     If --check: print availability.
//     Otherwise: download the asset and swap in place.
func updateCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("update", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagCheck := fs.Bool("check", false, "report whether an update is available without downloading")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	if runtime.GOOS != "windows" {
		fmt.Fprintln(stderr, "dcs-sms update: self-update is currently Windows-only.")
		fmt.Fprintln(stderr, "  On Linux/macOS, pull the latest source and rebuild via `go build ./cmd/dcs-sms`.")
		return 3
	}

	apiCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	apiClient := &http.Client{Timeout: 30 * time.Second}
	rel, err := findLatestRelease(apiCtx, apiClient, defaultReleasesURL)
	if err != nil {
		fmt.Fprintf(stderr, "dcs-sms update: %v\n", err)
		return 3
	}

	latestVer := tagToVersion(rel.TagName)
	cmp := compareVersion(version, latestVer)

	if cmp >= 0 {
		fmt.Fprintf(stdout, "Up to date (v%s)\n", version)
		return 0
	}

	if *flagCheck {
		fmt.Fprintf(stdout, "Update available: v%s → v%s\n", version, latestVer)
		fmt.Fprintln(stdout, "Run `dcs-sms.exe update` to install.")
		return 0
	}

	fmt.Fprintf(stdout, "Updating v%s → v%s...\n", version, latestVer)

	dlCtx, dlCancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer dlCancel()

	dlClient := &http.Client{Timeout: 5 * time.Minute}
	body, sizeMB, err := downloadAsset(dlCtx, dlClient, rel.AssetURL)
	if err != nil {
		fmt.Fprintf(stderr, "dcs-sms update: %v\n", err)
		return 3
	}
	defer body.Close()

	fmt.Fprintf(stdout, "Downloaded %.1f MB\n", sizeMB)

	exePath, err := os.Executable()
	if err != nil {
		fmt.Fprintf(stderr, "dcs-sms update: locate running binary: %v\n", err)
		return 3
	}

	if err := swapBinary(exePath, body); err != nil {
		fmt.Fprintf(stderr, "dcs-sms update: %v\n", err)
		fmt.Fprintln(stderr, "  The previous binary should still be in place. Re-run `dcs-sms update` to retry.")
		return 3
	}

	fmt.Fprintln(stdout, "Updated. Run `dcs-sms.exe install-me-mod` to apply.")
	return 0
}

// downloadAsset GETs url and returns a ReadCloser plus a size hint
// in MB (for the user-facing "Downloaded N.N MB" message). The caller
// must close the body.
func downloadAsset(ctx context.Context, client *http.Client, url string) (io.ReadCloser, float64, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, fmt.Errorf("build request: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("download %s: %w", url, err)
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		_ = resp.Body.Close()
		return nil, 0, fmt.Errorf("download returned %d: %s",
			resp.StatusCode, strings.TrimSpace(string(body)))
	}

	sizeMB := float64(resp.ContentLength) / (1024 * 1024)
	return resp.Body, sizeMB, nil
}

// tagToVersion strips the release-track prefix off a tag.
//
//	"me-mod-v0.2.0"      -> "0.2.0"
//	"framework-v0.10.0"  -> "0.10.0"
//	"v0.1.0"             -> "0.1.0"
//	"0.1.0"              -> "0.1.0"
func tagToVersion(tag string) string {
	if i := strings.LastIndex(tag, "-v"); i >= 0 {
		return tag[i+2:]
	}
	return strings.TrimPrefix(tag, "v")
}
