package main

import (
	"flag"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "list", meTriggerListCmd)
}

// meTriggerListCmd implements `dcs-sms me trigger list`.
//
// Returns a compact one-row-per-trigger summary: name, type, condition
// count, action count, event filter. For full trigger detail use
// `me trigger get --name X`.
func meTriggerListCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger list", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	resp, exitCode := runMeVerb("trigger_list", "{}", *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
