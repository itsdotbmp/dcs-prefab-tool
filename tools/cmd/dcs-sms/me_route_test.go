package main

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

// Each test invokes the verb's Cmd function with bad args; the function must
// return exit code 2 and write a discriminating message to stderr WITHOUT
// reaching runMeVerb (which would block on the bridge mailbox).

func TestMeRouteListCmd_FailModes(t *testing.T) {
	tests := []struct {
		name    string
		args    []string
		wantMsg string
	}{
		{"no-id", []string{}, "exactly one of"},
		{"both-ids", []string{"--group-name", "x", "--group-id", "1"}, "exactly one of"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stderr bytes.Buffer
			code := meRouteListCmd(tt.args, io.Discard, &stderr)
			if code != 2 {
				t.Errorf("exit code: got %d, want 2", code)
			}
			if !strings.Contains(stderr.String(), tt.wantMsg) {
				t.Errorf("stderr: got %q, want substring %q", stderr.String(), tt.wantMsg)
			}
		})
	}
}

func TestMeRouteGetCmd_FailModes(t *testing.T) {
	var stderr bytes.Buffer
	code := meRouteGetCmd([]string{}, io.Discard, &stderr)
	if code != 2 {
		t.Errorf("exit code: got %d, want 2", code)
	}
	if !strings.Contains(stderr.String(), "exactly one of") {
		t.Errorf("stderr: got %q", stderr.String())
	}
}

func TestMeRouteClearCmd_FailModes(t *testing.T) {
	var stderr bytes.Buffer
	code := meRouteClearCmd([]string{}, io.Discard, &stderr)
	if code != 2 {
		t.Errorf("exit code: got %d, want 2", code)
	}
}
