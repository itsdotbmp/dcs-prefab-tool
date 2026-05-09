package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "set-task", meGroupSetTaskCmd)
}

// meGroupSetTaskCmd implements `dcs-sms me group set-task --name|--id <X> --task <T>`.
//
// Sets the group-level mission task (g.task). Common values: "Nothing",
// "CAS", "CAP", "Intercept", "Escort", "Reconnaissance", "AWACS", "Tanker",
// "Refueling", "Ground Attack", "SEAD", "Anti-ship Strike", "Pinpoint
// Strike", "Runway Attack", "Fighter Sweep", "Transport". Note: this is the
// *group* task, not a waypoint task — waypoints carry their own ComboTask.
//
// The ME does not range-check the value; passing an unknown task string just
// stores it as-is. The discoverable list is in
// MissionEditor/modules/Mission/CoalitionPanel.lua.
func meGroupSetTaskCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group set-task", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "group name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "group id (mutually exclusive with --name)")
		flagTask       = fs.String("task", "", "group task (e.g. CAP, CAS, Escort, Nothing)")
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
		fmt.Fprintln(stderr, "dcs-sms me group set-task: exactly one of --name or --id is required")
		return 2
	}
	if *flagTask == "" {
		fmt.Fprintln(stderr, "dcs-sms me group set-task: --task is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, task = %q }", idClause, *flagTask)

	resp, exitCode := runMeVerb("group_set_task", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
