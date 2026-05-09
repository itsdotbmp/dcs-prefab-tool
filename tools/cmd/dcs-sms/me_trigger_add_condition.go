package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "add-condition", meTriggerAddConditionCmd)
}

// meTriggerAddConditionCmd implements
// `dcs-sms me trigger add-condition --trigger T --predicate P [k=v ...]`.
//
// Appends a condition to the named trigger. Predicate accepts canonical
// (c_flag_is_true) or alias (flag-is-true). Field values are positional
// key=value pairs after the known flags.
func meTriggerAddConditionCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger add-condition", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagTrigger    = fs.String("trigger", "", "trigger name")
		flagPredicate  = fs.String("predicate", "", "condition predicate (c_*) or alias")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagTrigger == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger add-condition: --trigger is required")
		return 2
	}
	if *flagPredicate == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger add-condition: --predicate is required")
		return 2
	}
	fields, err := parseTriggerFieldArgs(fs.Args())
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me trigger add-condition:", err)
		return 2
	}
	luaArgs := fmt.Sprintf(
		"{ trigger = %q, predicate = %q, fields = %s }",
		*flagTrigger, *flagPredicate, buildLuaFieldsExpr(fields))
	resp, exitCode := runMeVerb("trigger_add_condition", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
