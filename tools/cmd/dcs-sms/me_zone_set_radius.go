package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("zone", "set-radius", meZoneSetRadiusCmd)
}

// meZoneSetRadiusCmd implements `dcs-sms me zone set-radius --name|--id <X> --radius <m>`.
//
// For circle zones, this sets the trigger radius. For quad zones, this sets
// the icon radius (the circle drawn at center; the quad shape itself is
// defined by --vertices, not --radius). Wraps
// Mission.TriggerZoneData.setTriggerZoneRadius.
func meZoneSetRadiusCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone set-radius", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "zone name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "zone id (mutually exclusive with --name)")
		flagRadius     = fs.Float64("radius", 0, "radius in meters")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	hasName := *flagName != ""
	hasID := *flagID != 0
	if hasName == hasID {
		fmt.Fprintln(stderr, "dcs-sms me zone set-radius: exactly one of --name or --id is required")
		return 2
	}
	if *flagRadius <= 0 {
		fmt.Fprintln(stderr, "dcs-sms me zone set-radius: --radius is required (> 0)")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, radius = %g }", idClause, *flagRadius)

	resp, exitCode := runMeVerb("zone_set_radius", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
