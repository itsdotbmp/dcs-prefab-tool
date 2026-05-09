package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "set-name", meTriggerSetNameCmd)
}

// meTriggerSetNameCmd implements
// `dcs-sms me trigger set-name --name X --to Y`.
//
// Renames a trigger (mutates its comment field). Refuses cleanly if the
// target name is already taken by a different trigger.
func meTriggerSetNameCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger set-name", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "current trigger name")
		flagTo         = fs.String("to", "", "new trigger name")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger set-name: --name is required")
		return 2
	}
	if *flagTo == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger set-name: --to is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, to = %q }", *flagName, *flagTo)
	resp, exitCode := runMeVerb("trigger_set_name", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
