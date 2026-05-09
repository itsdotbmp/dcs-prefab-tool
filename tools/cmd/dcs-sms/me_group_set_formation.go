package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "set-formation", meGroupSetFormationCmd)
}

// meGroupSetFormationCmd implements
// `dcs-sms me group set-formation --name|--id <X> --formation <name> [--waypoint N]`.
//
// Vehicle groups only. Sets the per-waypoint formation action.
//   --formation accepts a built-in alias (off-road, on-road, rank, cone, vee,
//   diamond, echelon-left, echelon-right, custom) or a DB.templates name
//   (e.g. "Hawk SAM Battery") which is resolved to action=customForm and
//   stored in wp.formation_template.
//
// Refused on plane / helicopter (formation is per-task, not yet exposed),
// ship (only turningPoint is valid), and static (no route).
func meGroupSetFormationCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group set-formation", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "group name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "group id (mutually exclusive with --name)")
		flagFormation  = fs.String("formation", "", "formation alias (vee/cone/rank/...) or a DB.templates name (Custom)")
		flagWaypoint   = fs.Int("waypoint", 1, "waypoint index (1-based); default 1")
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
		fmt.Fprintln(stderr, "dcs-sms me group set-formation: exactly one of --name or --id is required")
		return 2
	}
	if *flagFormation == "" {
		fmt.Fprintln(stderr, "dcs-sms me group set-formation: --formation is required")
		return 2
	}
	if *flagWaypoint < 1 {
		fmt.Fprintln(stderr, "dcs-sms me group set-formation: --waypoint must be >= 1")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, formation = %q, waypoint = %d }",
		idClause, *flagFormation, *flagWaypoint)

	resp, exitCode := runMeVerb("group_set_formation", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
