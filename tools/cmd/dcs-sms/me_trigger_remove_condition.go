package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "remove-condition", meTriggerRemoveConditionCmd)
}

// meTriggerRemoveConditionCmd implements
// `dcs-sms me trigger remove-condition --trigger T --index N`.
//
// Removes the rule at the given 1-based index.
func meTriggerRemoveConditionCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger remove-condition", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagTrigger    = fs.String("trigger", "", "trigger name")
		flagIndex      = fs.Int("index", 0, "1-based condition index to remove")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagTrigger == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger remove-condition: --trigger is required")
		return 2
	}
	if *flagIndex < 1 {
		fmt.Fprintln(stderr, "dcs-sms me trigger remove-condition: --index (>= 1) is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ trigger = %q, index = %d }", *flagTrigger, *flagIndex)
	resp, exitCode := runMeVerb("trigger_remove_condition", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
