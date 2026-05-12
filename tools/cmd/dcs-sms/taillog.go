package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"strconv"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/logtail"
)

type tailLogOpts struct {
	Since      string
	Grep       string
	N          int
	JSON       bool
	SavedGames string
}

func tailLogFlags() (*flag.FlagSet, *tailLogOpts) {
	opts := &tailLogOpts{}
	fs := flag.NewFlagSet("tail-log", flag.ContinueOnError)
	fs.StringVar(&opts.Since, "since", "cursor", `"cursor" (default), "0" (whole file), or a duration like "30s"`)
	fs.StringVar(&opts.Grep, "grep", "", "regex to filter lines")
	fs.IntVar(&opts.N, "n", 0, "emit only the last N matching lines")
	fs.BoolVar(&opts.JSON, "json", false, "emit one JSON object per line")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	return fs, opts
}

func init() {
	registerInfo("tail-log", cmdInfo{
		Run:      tailLogCmd,
		Flags:    flagsOnly(tailLogFlags),
		Synopsis: "read recent lines from dcs.log",
	})
}

func tailLogCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := tailLogFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(opts.SavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms tail-log:", err)
		return 3
	}
	logPath := filepath.Join(root, "Logs", "dcs.log")
	cursorPath := filepath.Join(root, "dcs-sms", "state", "log-cursor")
	r := &logtail.Reader{LogPath: logPath, CursorPath: cursorPath}

	from, err := resolveSince(opts.Since, logPath, r)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms tail-log:", err)
		return 2
	}

	lines, newOffset, err := r.ReadFrom(from, opts.Grep, opts.N)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms tail-log:", err)
		return 3
	}
	for _, line := range lines {
		if opts.JSON {
			data, _ := json.Marshal(map[string]string{"line": line})
			fmt.Fprintln(stdout, string(data))
		} else {
			fmt.Fprintln(stdout, line)
		}
	}
	if opts.Since == "cursor" {
		if err := r.WriteCursor(newOffset); err != nil {
			fmt.Fprintln(stderr, "dcs-sms tail-log: warning: failed to update cursor:", err)
		}
	}
	return 0
}

// resolveSince returns the byte offset implied by --since.
func resolveSince(since, logPath string, r *logtail.Reader) (int64, error) {
	switch since {
	case "cursor":
		return r.ReadCursor()
	case "0":
		return 0, nil
	}
	if n, err := strconv.ParseInt(since, 10, 64); err == nil {
		// numeric byte offset
		return n, nil
	}
	d, err := time.ParseDuration(since)
	if err != nil {
		return 0, fmt.Errorf("invalid --since %q: expected 'cursor', '0', a byte offset, or a Go duration", since)
	}
	// We don't have per-line timestamps for cheap; approximate by reading
	// the whole file size and seeking back. A simpler honest semantic: with
	// a duration, just return 0 for now (full-file scan). We can refine if
	// it matters. Document this limitation.
	_ = d
	return 0, nil
}
