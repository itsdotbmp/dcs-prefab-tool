package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "set-hidden", meGroupSetHiddenCmd)
}

// meGroupSetHiddenCmd implements `dcs-sms me group set-hidden --name|--id <X> --hidden=true|false`.
//
// Toggles g.hidden. Same explicit-bool convention as `me zone set-hidden`:
// --hidden MUST be passed (--hidden=true or --hidden=false) so we can
// distinguish "user wants false" from "user forgot".
//
// Note: this only sets the master `hidden` field. The ME also has
// `hiddenOnPlanner` and `hiddenOnMFD` (per-coalition) toggles. Those aren't
// exposed yet — add separate verbs if you need to flip them independently.
func meGroupSetHiddenCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group set-hidden", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "group name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "group id (mutually exclusive with --name)")
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
		fmt.Fprintln(stderr, "dcs-sms me group set-hidden: exactly one of --name or --id is required")
		return 2
	}
	hiddenSet := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "hidden" {
			hiddenSet = true
		}
	})
	if !hiddenSet {
		fmt.Fprintln(stderr, "dcs-sms me group set-hidden: --hidden=true|false is required (pass explicitly)")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, hidden = %t }", idClause, *flagHidden)

	resp, exitCode := runMeVerb("group_set_hidden", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
