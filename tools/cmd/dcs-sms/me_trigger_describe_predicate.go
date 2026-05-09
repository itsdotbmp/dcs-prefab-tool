package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "describe-predicate", meTriggerDescribePredicateCmd)
}

// meTriggerDescribePredicateCmd implements
// `dcs-sms me trigger describe-predicate --name <canonical-or-alias>`.
//
// Returns the same shape as one entry from `list-predicates`, but for a
// single named predicate — useful when an agent has narrowed to one verb
// and wants the full schema without scanning the whole dump.
func meTriggerDescribePredicateCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger describe-predicate", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "predicate canonical name (e.g. c_flag_is_true) or alias (flag-is-true)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger describe-predicate: --name is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q }", *flagName)
	resp, exitCode := runMeVerb("trigger_describe_predicate", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
