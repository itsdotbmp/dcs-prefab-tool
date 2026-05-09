package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "create-vehicle", meGroupCreateVehicleCmd)
}

// meGroupCreateVehicleCmd implements
// `dcs-sms me group create-vehicle --country <c> --type <t> --north --east [...]`.
//
// Synthesizes a stationary single-unit ground vehicle group: single
// "Off Road" waypoint at the spawn point with speed=0, speed_locked.
// task = "Ground Nothing".
func meGroupCreateVehicleCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group create-vehicle", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagCountry    = fs.String("country", "", "country in current mission")
		flagType       = fs.String("type", "", "vehicle id (e.g. M-1 Abrams, T-72B)")
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin")
		flagName       = fs.String("name", "", "group name (auto-allocated if empty)")
		flagHeading    = fs.Float64("heading", 0, "heading in radians")
		flagSkill      = fs.String("skill", "Average", "AI skill")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagCountry == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-vehicle: --country is required")
		return 2
	}
	if *flagType == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-vehicle: --type is required")
		return 2
	}

	luaArgs := fmt.Sprintf(
		"{ country = %q, type = %q, north = %g, east = %g, name = %q, "+
			"heading = %g, skill = %q }",
		*flagCountry, *flagType, *flagNorth, *flagEast, *flagName,
		*flagHeading, *flagSkill,
	)

	resp, exitCode := runMeVerb("group_create_vehicle", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
