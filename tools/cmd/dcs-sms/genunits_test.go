package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestGenUnitsCmd_unknownDatamine(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := dispatch([]string{"gen-units", "--datamine", "/no/such/path"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("expected exit 2 for missing datamine, got %d", code)
	}
	if !strings.Contains(stderr.String(), "datamine path not found") {
		t.Errorf("stderr missing 'datamine path not found': %s", stderr.String())
	}
}

func TestGenUnitsCmd_helpFlagDoesNotCrash(t *testing.T) {
	var stdout, stderr bytes.Buffer
	// `--help` causes flag.ContinueOnError to print usage and return ErrHelp;
	// our code should exit 2 and print to stderr, not panic.
	code := dispatch([]string{"gen-units", "--help"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("expected exit 2 for --help, got %d", code)
	}
}

func TestGenUnitsCmd_appearsInUsage(t *testing.T) {
	var stdout, stderr bytes.Buffer
	dispatch([]string{"--help"}, &stdout, &stderr)
	if !strings.Contains(stdout.String(), "gen-units") {
		t.Errorf("--help output missing gen-units listing: %s", stdout.String())
	}
}
