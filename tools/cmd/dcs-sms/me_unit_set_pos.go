package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-pos", meUnitSetPosCmd)
}

// meUnitSetPosCmd implements
// `dcs-sms me unit set-pos --name|--id <X> --north <m> --east <m>`.
//
// Moves a single unit only — does NOT translate the rest of the group. Use
// `me group set-pos` to move the whole group together. The Lua verb refreshes
// Mission.update_group_map_objects so the ME view reflects the move
// immediately.
//
// IMPORTANT for air groups: setting a per-unit position on a plane /
// helicopter unit is decorative — DCS overrides it at mission load and
// pins the unit to the group's formation_template. The new position
// shows up in the ME view and survives save, but at runtime the flight
// is laid out by the formation. For ground / ship / static units the
// position is honoured verbatim.
func meUnitSetPosCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-pos", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-pos: exactly one of --name or --id is required")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-pos: --north and --east are both required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, north = %g, east = %g }", idClause, *flagNorth, *flagEast)

	resp, exitCode := runMeVerb("unit_set_pos", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
