package main

import (
	"testing"
)

func TestMeWaypointSetModeCmd_FailModes(t *testing.T) {
	cases := []setterCase{
		{"no-id", []string{"--index", "0", "--mode", "Landing"}, "exactly one of"},
		{"no-index", []string{"--group-name", "x", "--mode", "Landing"}, "--index"},
		{"no-mode", []string{"--group-name", "x", "--index", "0"}, "--mode"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetModeCmd, c) })
	}
}
