package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "remove", meGroupRemoveCmd)
}

// meGroupRemoveCmd implements `dcs-sms me group remove --name <name> | --id <n>`.
//
// Walks the mission coalition tree, finds the matching group, and calls
// Mission.remove_group on it. Exactly one of --name or --id is required.
// Note: groupIds and unitIds are NOT reused after remove (they increment
// monotonically), so a fresh inject afterwards will land at id+1, not id.
func meGroupRemoveCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group remove", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "group name (exact match)")
		flagID         = fs.Int("id", 0, "groupId (numeric)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	hasName := *flagName != ""
	hasID := *flagID != 0
	if hasName == hasID { // both or neither
		fmt.Fprintln(stderr, "dcs-sms me group remove: pass exactly one of --name or --id")
		return 2
	}

	var luaArgs string
	if hasName {
		luaArgs = fmt.Sprintf("{ name = %q }", *flagName)
	} else {
		luaArgs = fmt.Sprintf("{ id = %d }", *flagID)
	}

	resp, exitCode := runMeVerb("group_remove", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
