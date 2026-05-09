package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "add-action", meTriggerAddActionCmd)
}

// meTriggerAddActionCmd implements
// `dcs-sms me trigger add-action --trigger T --predicate P [k=v ...]`.
//
// Appends an action to the named trigger. Predicate accepts canonical
// (a_set_flag) or alias (set-flag). Field values are positional key=value
// pairs after the known flags.
func meTriggerAddActionCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger add-action", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagTrigger    = fs.String("trigger", "", "trigger name")
		flagPredicate  = fs.String("predicate", "", "action predicate (a_*) or alias")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagTrigger == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger add-action: --trigger is required")
		return 2
	}
	if *flagPredicate == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger add-action: --predicate is required")
		return 2
	}
	fields, err := parseTriggerFieldArgs(fs.Args())
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me trigger add-action:", err)
		return 2
	}
	luaArgs := fmt.Sprintf(
		"{ trigger = %q, predicate = %q, fields = %s }",
		*flagTrigger, *flagPredicate, buildLuaFieldsExpr(fields))
	resp, exitCode := runMeVerb("trigger_add_action", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
