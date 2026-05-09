package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "set-pos", meGroupSetPosCmd)
}

// meGroupSetPosCmd implements
// `dcs-sms me group set-pos --name|--id <X> --north <m> --east <m>`.
//
// Translates the entire group — group ref + every unit + every waypoint —
// by the delta from current g.x/g.y to the new (north, east). This is what
// dragging a group does in the ME UI.
//
// For multi-unit groups, the relative offsets between units are preserved
// (CAP four-ship stays in formation; SAM ring stays as a ring). For unit-
// level moves use `me unit set-pos` instead.
func meGroupSetPosCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group set-pos", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "group name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "group id (mutually exclusive with --name)")
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
		fmt.Fprintln(stderr, "dcs-sms me group set-pos: exactly one of --name or --id is required")
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
		fmt.Fprintln(stderr, "dcs-sms me group set-pos: --north and --east are both required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, north = %g, east = %g }", idClause, *flagNorth, *flagEast)

	resp, exitCode := runMeVerb("group_set_pos", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
