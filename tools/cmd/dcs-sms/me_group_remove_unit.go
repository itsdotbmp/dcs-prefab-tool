package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "remove-unit", meGroupRemoveUnitCmd)
}

// meGroupRemoveUnitCmd implements `dcs-sms me group remove-unit --name|--id <X>`.
//
// Removes a single unit from its parent group, mirroring the ME UI's
// per-unit "x" button. Selection is by unit name or unit id (mutually
// exclusive) — the verb walks the coalition tree to find the unit and
// determine its parent.
//
// Refuses to remove the last unit in a group; use `me group remove` for
// that case (an empty group breaks the ME's Unit List panel and other
// invariants downstream). The remove dance — symbol, warehouse,
// waypoint linkChildren, trigger zone refs, panel refresh — is handled
// by Mission.remove_unit.
func meGroupRemoveUnitCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group remove-unit", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
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
		fmt.Fprintln(stderr, "dcs-sms me group remove-unit: exactly one of --name or --id is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s }", idClause)

	resp, exitCode := runMeVerb("group_remove_unit", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
