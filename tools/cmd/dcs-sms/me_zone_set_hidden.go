package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("zone", "set-hidden", meZoneSetHiddenCmd)
}

// meZoneSetHiddenCmd implements `dcs-sms me zone set-hidden --name|--id <X> --hidden=true|false`.
//
// `--hidden` MUST be passed explicitly (`--hidden=true` or `--hidden=false`)
// — otherwise the verb has no way to distinguish "user wants false" from
// "user forgot the flag". Wraps Mission.TriggerZoneData.setTriggerZoneHidden.
func meZoneSetHiddenCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone set-hidden", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "zone name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "zone id (mutually exclusive with --name)")
		flagHidden     = fs.Bool("hidden", false, "hide (true) or show (false); pass explicitly")
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
		fmt.Fprintln(stderr, "dcs-sms me zone set-hidden: exactly one of --name or --id is required")
		return 2
	}
	hiddenSet := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "hidden" {
			hiddenSet = true
		}
	})
	if !hiddenSet {
		fmt.Fprintln(stderr, "dcs-sms me zone set-hidden: --hidden=true|false is required (pass explicitly)")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, hidden = %t }", idClause, *flagHidden)

	resp, exitCode := runMeVerb("zone_set_hidden", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
