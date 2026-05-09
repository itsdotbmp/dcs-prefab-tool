package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "get", meTriggerGetCmd)
}

// meTriggerGetCmd implements `dcs-sms me trigger get --name X [--raw]`.
//
// Returns the full structured detail of a single trigger: rules and actions
// expanded with field values, dict-key text resolved to literals, reference
// ids enriched with *_name companions. --raw returns the on-disk trigrules
// entry verbatim (for debugging).
func meTriggerGetCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger get", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "trigger name (the comment field)")
		flagRaw        = fs.Bool("raw", false, "return verbatim trigrules entry (no enrichment)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger get: --name is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, raw = %t }", *flagName, *flagRaw)
	resp, exitCode := runMeVerb("trigger_get", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
