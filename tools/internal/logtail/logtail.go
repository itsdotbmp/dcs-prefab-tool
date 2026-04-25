// Package logtail reads DCS's dcs.log with optional cursor, regex filter,
// and tail-N support. The CLI uses this for `dcs-sms tail-log`.
package logtail

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"regexp"
	"strconv"
	"strings"
)

// Reader reads dcs.log incrementally. CursorPath is where ReadCursor /
// WriteCursor persist the last byte offset across CLI invocations.
type Reader struct {
	LogPath    string
	CursorPath string
}

// ReadFrom reads dcs.log from byte offset `from` to EOF. If grep is non-empty
// it's applied as a regex filter (case-sensitive). If tailN > 0, only the
// last tailN matching lines are returned. Returns the lines and the new EOF
// offset (suitable for passing as `from` next time).
func (r *Reader) ReadFrom(from int64, grep string, tailN int) ([]string, int64, error) {
	f, err := os.Open(r.LogPath)
	if err != nil {
		return nil, 0, fmt.Errorf("open %s: %w", r.LogPath, err)
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		return nil, 0, err
	}
	// If the file shrank (rotation/truncation), restart from 0.
	if from > stat.Size() {
		from = 0
	}
	if _, err := f.Seek(from, 0); err != nil {
		return nil, 0, err
	}

	var pattern *regexp.Regexp
	if grep != "" {
		pattern, err = regexp.Compile(grep)
		if err != nil {
			return nil, 0, fmt.Errorf("invalid grep pattern: %w", err)
		}
	}

	var lines []string
	scanner := bufio.NewScanner(f)
	// dcs.log can have very long lines (huge stack traces).
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if pattern != nil && !pattern.MatchString(line) {
			continue
		}
		lines = append(lines, line)
	}
	if err := scanner.Err(); err != nil {
		return nil, 0, err
	}

	if tailN > 0 && len(lines) > tailN {
		lines = lines[len(lines)-tailN:]
	}
	return lines, stat.Size(), nil
}

// ReadCursor returns the byte offset previously persisted, or 0 if missing.
func (r *Reader) ReadCursor() (int64, error) {
	data, err := os.ReadFile(r.CursorPath)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return 0, nil
		}
		return 0, err
	}
	v, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse cursor: %w", err)
	}
	return v, nil
}

// WriteCursor persists offset to CursorPath atomically (write tmp, rename).
func (r *Reader) WriteCursor(offset int64) error {
	tmp := r.CursorPath + ".tmp"
	if err := os.WriteFile(tmp, []byte(strconv.FormatInt(offset, 10)), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, r.CursorPath)
}
