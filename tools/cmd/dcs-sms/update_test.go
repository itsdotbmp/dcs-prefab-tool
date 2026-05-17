package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestRunUpdate_SkipsOnDevBuild(t *testing.T) {
	prev := version
	t.Cleanup(func() { version = prev })
	version = "0.1.1-dev"

	var stdout, stderr bytes.Buffer
	swapped, code := runUpdate(nil, &stdout, &stderr)
	if swapped {
		t.Error("dev build should not swap binary")
	}
	if code != 0 {
		t.Errorf("exit code %d, want 0 (dev build is up-to-date by definition)", code)
	}
	if !strings.Contains(stdout.String(), "Dev build") {
		t.Errorf("expected 'Dev build' notice in stdout, got %q", stdout.String())
	}
	if stderr.Len() != 0 {
		t.Errorf("expected empty stderr, got %q", stderr.String())
	}
}

func TestTagToVersion(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"me-mod-v0.2.0", "0.2.0"},
		{"framework-v0.10.0", "0.10.0"},
		{"v0.1.0", "0.1.0"},
		{"0.1.0", "0.1.0"},
		{"unknown-track-v1.2.3", "1.2.3"},
		{"", ""},
	}

	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			got := tagToVersion(tc.in)
			if got != tc.want {
				t.Errorf("tagToVersion(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}
