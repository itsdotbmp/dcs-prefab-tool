package main

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

type setterCase struct {
	name string
	args []string
	want string // substring in stderr
}

func runFailCase(t *testing.T, fn func([]string, io.Writer, io.Writer) int, c setterCase) {
	t.Helper()
	var stderr bytes.Buffer
	code := fn(c.args, io.Discard, &stderr)
	if code != 2 {
		t.Errorf("exit code: got %d, want 2 (args=%v)", code, c.args)
	}
	if !strings.Contains(stderr.String(), c.want) {
		t.Errorf("stderr: %q (want substring %q)", stderr.String(), c.want)
	}
}

func TestMeWaypointSetPosCmd_FailModes(t *testing.T) {
	cases := []setterCase{
		{"no-id", []string{"--index", "0", "--north", "1", "--east", "2"}, "exactly one of"},
		{"no-index", []string{"--group-name", "x", "--north", "1", "--east", "2"}, "--index"},
		{"no-pos", []string{"--group-name", "x", "--index", "0"}, "--north and --east"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetPosCmd, c) })
	}
}

func TestMeWaypointSetAltCmd_FailModes(t *testing.T) {
	cases := []setterCase{
		{"no-id", []string{"--index", "0", "--alt", "1000"}, "exactly one of"},
		{"no-index", []string{"--group-name", "x", "--alt", "1000"}, "--index"},
		{"no-alt", []string{"--group-name", "x", "--index", "0"}, "--alt"},
		{"bad-alt-type", []string{"--group-name", "x", "--index", "0", "--alt", "1000", "--alt-type", "X"}, "BARO or RADIO"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetAltCmd, c) })
	}
}

func TestMeWaypointSetSpeedCmd_FailModes(t *testing.T) {
	cases := []setterCase{
		{"no-id", []string{"--index", "0", "--speed", "200"}, "exactly one of"},
		{"no-index", []string{"--group-name", "x", "--speed", "200"}, "--index"},
		{"no-speed", []string{"--group-name", "x", "--index", "0"}, "--speed"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetSpeedCmd, c) })
	}
}

func TestMeWaypointSetTypeCmd_FailModes(t *testing.T) {
	cases := []setterCase{
		{"no-id", []string{"--index", "0", "--type", "Land"}, "exactly one of"},
		{"no-type", []string{"--group-name", "x", "--index", "0"}, "--type"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetTypeCmd, c) })
	}
}

func TestMeWaypointSetActionCmd_FailModes(t *testing.T) {
	cases := []setterCase{
		{"no-id", []string{"--index", "0", "--action", "Turning Point"}, "exactly one of"},
		{"no-action", []string{"--group-name", "x", "--index", "0"}, "--action"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetActionCmd, c) })
	}
}
