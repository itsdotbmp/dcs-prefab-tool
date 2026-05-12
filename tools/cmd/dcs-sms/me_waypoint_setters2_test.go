package main

import (
	"io"
	"testing"
)

func TestMeWaypointSetNameCmd_FailModes(t *testing.T) {
	for _, c := range []setterCase{
		{"no-id", []string{"--index", "0", "--name", "WP"}, "exactly one of"},
		{"no-index", []string{"--group-name", "x", "--name", "WP"}, "--index"},
	} {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetNameCmd, c) })
	}
}

func TestMeWaypointSetEtaCmd_FailModes(t *testing.T) {
	for _, c := range []setterCase{
		{"no-id", []string{"--index", "0", "--eta", "300"}, "exactly one of"},
		{"no-eta", []string{"--group-name", "x", "--index", "0"}, "--eta"},
		{"neg-eta", []string{"--group-name", "x", "--index", "0", "--eta", "-1"}, "eta"},
	} {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetEtaCmd, c) })
	}
}

func TestMeWaypointSetSpeedLockedCmd_FailModes(t *testing.T) {
	for _, c := range []setterCase{
		{"no-id", []string{"--index", "0", "--locked", "true"}, "exactly one of"},
		{"no-locked", []string{"--group-name", "x", "--index", "0"}, "--locked"},
		{"bad-locked", []string{"--group-name", "x", "--index", "0", "--locked", "maybe"}, "true or false"},
	} {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetSpeedLockedCmd, c) })
	}
}

func TestMeWaypointSetEtaLockedCmd_FailModes(t *testing.T) {
	var stderr io.Writer = io.Discard
	_ = stderr
	for _, c := range []setterCase{
		{"no-locked", []string{"--group-name", "x", "--index", "0"}, "--locked"},
	} {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetEtaLockedCmd, c) })
	}
}

func TestMeWaypointSetFormationCmd_FailModes(t *testing.T) {
	for _, c := range []setterCase{
		{"no-id", []string{"--index", "0", "--formation-template", "Diamond"}, "exactly one of"},
	} {
		t.Run(c.name, func(t *testing.T) { runFailCase(t, meWaypointSetFormationCmd, c) })
	}
}
