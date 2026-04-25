package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeLogRoot creates a fake Saved Games root with a dcs.log at the
// expected path (<root>/Logs/dcs.log).
func fakeLogRoot(t *testing.T, lines ...string) string {
	t.Helper()
	root := t.TempDir()
	logsDir := filepath.Join(root, "Logs")
	smsDir := filepath.Join(root, "dcs-sms", "state")
	if err := os.MkdirAll(logsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(smsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	logPath := filepath.Join(logsDir, "dcs.log")
	if err := os.WriteFile(logPath, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestTailLogPrintsAll(t *testing.T) {
	root := fakeLogRoot(t, "first", "second", "third")
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := tailLogCmd([]string{"--since", "0"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, want 0; stderr=%s", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "first") || !strings.Contains(stdout.String(), "third") {
		t.Errorf("expected all lines, got %q", stdout.String())
	}
}

func TestTailLogGrep(t *testing.T) {
	root := fakeLogRoot(t, "INFO: a", "WARN: b", "INFO: c")
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := tailLogCmd([]string{"--since", "0", "--grep", "WARN"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	if !strings.Contains(stdout.String(), "WARN: b") {
		t.Errorf("missing WARN line: %s", stdout.String())
	}
	if strings.Contains(stdout.String(), "INFO: a") {
		t.Errorf("INFO line should be filtered out: %s", stdout.String())
	}
}

func TestTailLogN(t *testing.T) {
	root := fakeLogRoot(t, "a", "b", "c", "d", "e")
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := tailLogCmd([]string{"--since", "0", "-n", "2"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	out := strings.TrimSpace(stdout.String())
	if strings.Count(out, "\n") != 1 {
		t.Errorf("expected 2 lines, got %q", stdout.String())
	}
}

func TestTailLogCursorAdvances(t *testing.T) {
	root := fakeLogRoot(t, "first")
	t.Setenv("DCS_SMS_SAVED_GAMES", root)

	var stdout, stderr bytes.Buffer
	code := tailLogCmd([]string{"--since", "cursor"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("first call exit %d", code)
	}
	// Append a line and re-run with cursor; should only see the new line.
	logPath := filepath.Join(root, "Logs", "dcs.log")
	f, _ := os.OpenFile(logPath, os.O_APPEND|os.O_WRONLY, 0o644)
	_, _ = f.WriteString("second\n")
	_ = f.Close()

	var stdout2, stderr2 bytes.Buffer
	code = tailLogCmd([]string{"--since", "cursor"}, &stdout2, &stderr2)
	if code != 0 {
		t.Fatalf("second call exit %d", code)
	}
	if strings.Contains(stdout2.String(), "first") {
		t.Errorf("cursor failed to advance — saw 'first' on second call: %s", stdout2.String())
	}
	if !strings.Contains(stdout2.String(), "second") {
		t.Errorf("expected 'second' on second call, got %s", stdout2.String())
	}
}
