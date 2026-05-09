package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "remove", meTriggerRemoveCmd)
}

// meTriggerRemoveCmd implements `dcs-sms me trigger remove --name X`.
//
// Deletes a trigger by name. Refuses cleanly if no trigger with that name
// exists.
func meTriggerRemoveCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger remove", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "trigger name (the comment field)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger remove: --name is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q }", *flagName)
	resp, exitCode := runMeVerb("trigger_remove", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
