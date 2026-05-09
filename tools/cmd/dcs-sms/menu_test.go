package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestMenuQuit(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader("q\n"), &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), "DCS-SMS") {
		t.Errorf("expected banner in stdout, got %q", stdout.String())
	}
}

func TestMenuQuitUppercase(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader("Q\n"), &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
}

func TestMenuInvalidThenQuit(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader("zz\nq\n"), &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	// Should reprompt at least twice (initial + after invalid).
	if c := strings.Count(stdout.String(), "Choose ["); c < 2 {
		t.Errorf("expected at least 2 prompts, got %d in %q", c, stdout.String())
	}
}

func TestMenuThreeInvalidExits(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader("a\nb\nc\n"), &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
}

func TestMenuEOFExits(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader(""), &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
}
