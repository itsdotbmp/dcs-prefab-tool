package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestDispatchVersion(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := dispatch([]string{"--version"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), version) {
		t.Errorf("expected version in stdout, got %q", stdout.String())
	}
}

func TestDispatchUnknownCommand(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := dispatch([]string{"snurfle"}, &stdout, &stderr)
	if code == 0 {
		t.Error("expected non-zero exit for unknown command")
	}
	if !strings.Contains(stderr.String(), "unknown") {
		t.Errorf("expected 'unknown' in stderr, got %q", stderr.String())
	}
}

func TestDispatchNoArgsShowsHelp(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := dispatch(nil, &stdout, &stderr)
	if code == 0 {
		t.Error("expected non-zero exit when no command given")
	}
	if !strings.Contains(stderr.String(), "Usage") {
		t.Errorf("expected usage banner in stderr, got %q", stderr.String())
	}
}
