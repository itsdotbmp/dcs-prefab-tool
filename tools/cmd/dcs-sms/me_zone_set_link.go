package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("zone", "set-link", meZoneSetLinkCmd)
}

// meZoneSetLinkCmd implements
// `dcs-sms me zone set-link --name|--id <Z> [--unit <U> | --unit-id <N> | --clear]`.
//
// Links a trigger zone to a unit (the zone's center follows the unit at
// runtime), or clears an existing link. Wraps TZD.linkToUnit /
// TZD.unlinkToUnit. Linking captures the unit's position + heading at
// the moment of the call; runtime then updates the zone as the unit
// moves. Useful for "patrol area follows AWACS" or "no-fly zone around
// this carrier" patterns.
//
// Exactly one action is required:
//   --unit <name>      link to a unit selected by name
//   --unit-id <id>     link to a unit selected by id
//   --clear            unlink the zone
func meZoneSetLinkCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone set-link", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "zone name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "zone id (mutually exclusive with --name)")
		flagUnit       = fs.String("unit", "", "target unit name (link by name)")
		flagUnitID     = fs.Int("unit-id", 0, "target unit id (link by id)")
		flagClear      = fs.Bool("clear", false, "unlink the zone")
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
		fmt.Fprintln(stderr, "dcs-sms me zone set-link: exactly one of --name or --id is required")
		return 2
	}

	hasUnit := *flagUnit != ""
	hasUnitID := *flagUnitID != 0
	hasClear := *flagClear
	actionCount := 0
	if hasUnit {
		actionCount++
	}
	if hasUnitID {
		actionCount++
	}
	if hasClear {
		actionCount++
	}
	if actionCount != 1 {
		fmt.Fprintln(stderr, "dcs-sms me zone set-link: exactly one of --unit, --unit-id, or --clear is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}

	var actionClause string
	switch {
	case hasUnit:
		actionClause = fmt.Sprintf("unit = %q", *flagUnit)
	case hasUnitID:
		actionClause = fmt.Sprintf("unit_id = %d", *flagUnitID)
	case hasClear:
		actionClause = "clear = true"
	}

	luaArgs := fmt.Sprintf("{ %s, %s }", idClause, actionClause)

	resp, exitCode := runMeVerb("zone_set_link", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
