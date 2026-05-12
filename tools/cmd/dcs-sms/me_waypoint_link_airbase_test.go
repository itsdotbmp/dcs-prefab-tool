package main

import (
	"testing"
)

func TestMeWaypointLinkAirbaseCmd_FailModes(t *testing.T) {
	cases := []setterCase{
		{"no-id", []string{"--index", "0", "--airbase", "Rene Mouawad"}, "exactly one of"},
		{"no-index", []string{"--group-name", "x", "--airbase", "Rene Mouawad"}, "--index"},
		{"no-airbase", []string{"--group-name", "x", "--index", "3"}, "--airbase"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointLinkAirbaseCmd, c) })
	}
}
