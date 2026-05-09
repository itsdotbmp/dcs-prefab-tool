package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "create-ship", meGroupCreateShipCmd)
}

// meGroupCreateShipCmd implements
// `dcs-sms me group create-ship --country <c> --type <t> --north --east [--force]`.
//
// Synthesizes a stationary single-unit naval-vessel group. Same shape as
// create-vehicle, but the spawn point must be over water — the verb
// queries terrain.GetSurfaceType and refuses if the position is land
// (use --force to override, e.g. for spawning at a not-quite-coastal pier).
func meGroupCreateShipCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group create-ship", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagCountry    = fs.String("country", "", "country in current mission")
		flagType       = fs.String("type", "", "ship id (e.g. CVN_71_THEODORE_ROOSEVELT, FFG_7CL_OliverHazardPerry)")
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin")
		flagName       = fs.String("name", "", "group name (auto-allocated if empty)")
		flagHeading    = fs.Float64("heading", 0, "heading in radians")
		flagSkill      = fs.String("skill", "Average", "AI skill")
		flagForce      = fs.Bool("force", false, "skip the water-surface check")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagCountry == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-ship: --country is required")
		return 2
	}
	if *flagType == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-ship: --type is required")
		return 2
	}

	luaArgs := fmt.Sprintf(
		"{ country = %q, type = %q, north = %g, east = %g, name = %q, "+
			"heading = %g, skill = %q, force = %t }",
		*flagCountry, *flagType, *flagNorth, *flagEast, *flagName,
		*flagHeading, *flagSkill, *flagForce,
	)

	resp, exitCode := runMeVerb("group_create_ship", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
