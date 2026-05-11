package main

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

func TestMeWaypointAddCmd_FailModes(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantMsg string
	}{
		{"no-id", []string{"--north", "1", "--east", "2"}, "exactly one of"},
		{"no-pos", []string{"--group-name", "x"}, "--north and --east"},
		{"bad-alt-type", []string{"--group-name", "x", "--north", "1", "--east", "2", "--alt", "5000", "--alt-type", "X"}, "BARO or RADIO"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stderr bytes.Buffer
			code := meWaypointAddCmd(tt.args, io.Discard, &stderr)
			if code != 2 {
				t.Errorf("exit code: got %d, want 2", code)
			}
			if !strings.Contains(stderr.String(), tt.wantMsg) {
				t.Errorf("stderr: %q (want substring %q)", stderr.String(), tt.wantMsg)
			}
		})
	}
}

func TestMeWaypointInsertCmd_FailModes(t *testing.T) {
	var stderr bytes.Buffer
	code := meWaypointInsertCmd([]string{"--group-name", "x", "--north", "1", "--east", "2"}, io.Discard, &stderr)
	if code != 2 {
		t.Errorf("missing --before should exit 2, got %d", code)
	}
	if !strings.Contains(stderr.String(), "--before") {
		t.Errorf("stderr: %q", stderr.String())
	}
}

func TestMeWaypointRemoveCmd_FailModes(t *testing.T) {
	var stderr bytes.Buffer
	code := meWaypointRemoveCmd([]string{"--group-name", "x"}, io.Discard, &stderr)
	if code != 2 {
		t.Errorf("missing --index should exit 2, got %d", code)
	}
}

func TestMeWaypointGetCmd_FailModes(t *testing.T) {
	var stderr bytes.Buffer
	code := meWaypointGetCmd([]string{"--group-name", "x"}, io.Discard, &stderr)
	if code != 2 {
		t.Errorf("missing --index should exit 2, got %d", code)
	}
}
