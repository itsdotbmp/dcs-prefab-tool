package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("zone", "remove", meZoneRemoveCmd)
}

// meZoneRemoveCmd implements `dcs-sms me zone remove --name <n> | --id <n>`.
//
// Walks the trigger zone list and calls Mission.TriggerZoneData.removeTriggerZone
// on the match. Exactly one of --name or --id is required.
func meZoneRemoveCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone remove", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "zone name (exact match)")
		flagID         = fs.Int("id", 0, "zoneId (numeric)")
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
		fmt.Fprintln(stderr, "dcs-sms me zone remove: pass exactly one of --name or --id")
		return 2
	}

	var luaArgs string
	if hasName {
		luaArgs = fmt.Sprintf("{ name = %q }", *flagName)
	} else {
		luaArgs = fmt.Sprintf("{ id = %d }", *flagID)
	}

	resp, exitCode := runMeVerb("zone_remove", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
