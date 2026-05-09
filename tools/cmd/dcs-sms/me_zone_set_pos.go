package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("zone", "set-pos", meZoneSetPosCmd)
}

// meZoneSetPosCmd implements `dcs-sms me zone set-pos --name|--id <X> --north <m> --east <m>`.
//
// For circle zones, this moves the center of the zone. For quad zones, this
// also moves the center — but since the underlying points are stored relative
// to center, the quad shape moves with it (translation only, no rotation/
// scale). Use `me zone set-vertices` to reshape a quad in place.
//
// Coords use the project --north/--east meters convention (see top of
// verbs.lua). Wraps Mission.TriggerZoneData.setTriggerZonePosition.
func meZoneSetPosCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone set-pos", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "zone name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "zone id (mutually exclusive with --name)")
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin (north positive)")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin (east positive)")
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
		fmt.Fprintln(stderr, "dcs-sms me zone set-pos: exactly one of --name or --id is required")
		return 2
	}
	northSet, eastSet := false, false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "north" {
			northSet = true
		}
		if f.Name == "east" {
			eastSet = true
		}
	})
	if !northSet || !eastSet {
		fmt.Fprintln(stderr, "dcs-sms me zone set-pos: --north and --east are both required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, north = %g, east = %g }", idClause, *flagNorth, *flagEast)

	resp, exitCode := runMeVerb("zone_set_pos", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
