package logtail

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeLog(t *testing.T, path string, lines ...string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestReadAll(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "dcs.log")
	writeLog(t, logPath, "line one", "line two", "line three")

	r := &Reader{LogPath: logPath, CursorPath: filepath.Join(dir, "cursor")}
	lines, _, err := r.ReadFrom(0, "", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) != 3 {
		t.Fatalf("got %d lines, want 3", len(lines))
	}
}

func TestReadFromOffsetAdvancesCursor(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "dcs.log")
	writeLog(t, logPath, "line one", "line two")

	r := &Reader{LogPath: logPath, CursorPath: filepath.Join(dir, "cursor")}
	_, newOffset, err := r.ReadFrom(0, "", 0)
	if err != nil {
		t.Fatal(err)
	}

	// Append a line.
	f, err := os.OpenFile(logPath, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString("line three\n"); err != nil {
		t.Fatal(err)
	}
	f.Close()

	// Resume from previous offset.
	lines, _, err := r.ReadFrom(newOffset, "", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) != 1 || lines[0] != "line three" {
		t.Errorf("expected only 'line three', got %v", lines)
	}
}

func TestReadFromGrep(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "dcs.log")
	writeLog(t, logPath, "INFO: hello", "WARN: oops", "INFO: ok")

	r := &Reader{LogPath: logPath, CursorPath: filepath.Join(dir, "cursor")}
	lines, _, err := r.ReadFrom(0, "WARN", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) != 1 || lines[0] != "WARN: oops" {
		t.Errorf("grep filter wrong: %v", lines)
	}
}

func TestReadFromTailN(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "dcs.log")
	writeLog(t, logPath, "a", "b", "c", "d", "e")

	r := &Reader{LogPath: logPath, CursorPath: filepath.Join(dir, "cursor")}
	lines, _, err := r.ReadFrom(0, "", 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) != 2 || lines[0] != "d" || lines[1] != "e" {
		t.Errorf("tail-N wrong: %v", lines)
	}
}

func TestCursorRoundTrip(t *testing.T) {
	dir := t.TempDir()
	r := &Reader{CursorPath: filepath.Join(dir, "cursor")}
	if err := r.WriteCursor(12345); err != nil {
		t.Fatal(err)
	}
	got, err := r.ReadCursor()
	if err != nil {
		t.Fatal(err)
	}
	if got != 12345 {
		t.Errorf("cursor mismatch: got %d", got)
	}
}

func TestReadCursorMissingReturnsZero(t *testing.T) {
	dir := t.TempDir()
	r := &Reader{CursorPath: filepath.Join(dir, "missing-cursor")}
	got, err := r.ReadCursor()
	if err != nil {
		t.Fatalf("expected nil error for missing cursor, got %v", err)
	}
	if got != 0 {
		t.Errorf("expected 0, got %d", got)
	}
}
