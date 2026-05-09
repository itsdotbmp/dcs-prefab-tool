package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "set-eventlist", meTriggerSetEventlistCmd)
}

// meTriggerSetEventlistCmd implements
// `dcs-sms me trigger set-eventlist --name X [--event E]`.
//
// Sets the trigger's event filter. Pass --event "" or omit it to clear.
func meTriggerSetEventlistCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger set-eventlist", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "trigger name")
		flagEvent      = fs.String("event", "", "event id (empty to clear)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger set-eventlist: --name is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, event = %q }", *flagName, *flagEvent)
	resp, exitCode := runMeVerb("trigger_set_eventlist", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
