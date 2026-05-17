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

type updateOpts struct {
	Check bool
}

func updateFlags() (*flag.FlagSet, *updateOpts) {
	opts := &updateOpts{}
	fs := flag.NewFlagSet("update", flag.ContinueOnError)
	fs.BoolVar(&opts.Check, "check", false, "report whether an update is available without downloading")
	return fs, opts
}

func init() {
	registerInfo("update", cmdInfo{
		Run:      updateCmd,
		Flags:    flagsOnly(updateFlags),
		Synopsis: "download the latest dcs-sms.exe from GitHub and replace this binary",
	})
}

// runUpdate performs the same work as `dcs-sms update` and reports whether
// the binary on disk was swapped. Used by `setup` to decide whether to
// re-exec the new binary.
//
//	swapped == true   → a new binary was written; caller should re-exec.
//	swapped == false  → up-to-date, --check mode, or a recoverable error
//	                    that was reported to stderr (caller may proceed
//	                    with the currently-installed embedded content).
//	exitCode          → same 0/3 semantics as updateCmd.
func runUpdate(args []string, stdout, stderr io.Writer) (swapped bool, exitCode int) {
	fs, opts := updateFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return false, 2
	}

	// Dev builds (version string ends in "-dev") must never self-update.
	// Otherwise `setup` would download the latest release and overwrite
	// the unreleased binary the developer is testing, including the very
	// subcommands they're trying to use.
	if strings.HasSuffix(version, "-dev") {
		fmt.Fprintf(stdout, "Dev build (v%s) — skipping self-update.\n", version)
		return false, 0
	}

	if runtime.GOOS != "windows" {
		fmt.Fprintln(stderr, "dcs-sms update: self-update is currently Windows-only.")
		fmt.Fprintln(stderr, "  On Linux/macOS, pull the latest source and rebuild via `go build ./cmd/dcs-sms`.")
		return false, 3
	}

	apiCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	apiClient := &http.Client{Timeout: 30 * time.Second}
	rel, err := findLatestRelease(apiCtx, apiClient, defaultReleasesURL)
	if err != nil {
		fmt.Fprintf(stderr, "dcs-sms update: %v\n", err)
		return false, 3
	}

	latestVer := tagToVersion(rel.TagName)
	cmp := compareVersion(version, latestVer)

	if cmp >= 0 {
		fmt.Fprintf(stdout, "Up to date (v%s)\n", version)
		return false, 0
	}

	if opts.Check {
		fmt.Fprintf(stdout, "Update available: v%s → v%s\n", version, latestVer)
		fmt.Fprintln(stdout, "Run `dcs-sms.exe update` to install.")
		return false, 0
	}

	fmt.Fprintf(stdout, "Updating v%s → v%s...\n", version, latestVer)

	dlCtx, dlCancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer dlCancel()

	dlClient := &http.Client{Timeout: 5 * time.Minute}
	body, sizeMB, err := downloadAsset(dlCtx, dlClient, rel.AssetURL)
	if err != nil {
		fmt.Fprintf(stderr, "dcs-sms update: %v\n", err)
		return false, 3
	}
	defer body.Close()

	fmt.Fprintf(stdout, "Downloaded %.1f MB\n", sizeMB)

	exePath, err := os.Executable()
	if err != nil {
		fmt.Fprintf(stderr, "dcs-sms update: locate running binary: %v\n", err)
		return false, 3
	}

	if err := swapBinary(exePath, body); err != nil {
		fmt.Fprintf(stderr, "dcs-sms update: %v\n", err)
		fmt.Fprintln(stderr, "  The previous binary should still be in place. Re-run `dcs-sms update` to retry.")
		return false, 3
	}

	fmt.Fprintln(stdout, "Updated. Run `dcs-sms.exe install-me-mod` to apply.")
	return true, 0
}

// updateCmd is the entry point for `dcs-sms update`. See runUpdate for
// the full flow.
func updateCmd(args []string, stdout, stderr io.Writer) int {
	_, code := runUpdate(args, stdout, stderr)
	return code
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
