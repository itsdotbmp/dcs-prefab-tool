package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "list-predicates", meTriggerListPredicatesCmd)
}

// meTriggerListPredicatesCmd implements
// `dcs-sms me trigger list-predicates [--kind condition|action|trigger] [--search <substr>]`.
//
// Dumps every predicate ED knows about — names, aliases, field schemas,
// generated CLI examples — by reading me_trigrules.predicates.descrs and
// triggersDescr at runtime. Always current to the user's installed DCS,
// including any modded predicates.
func meTriggerListPredicatesCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger list-predicates", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagKind       = fs.String("kind", "", "filter: condition|action|trigger")
		flagSearch     = fs.String("search", "", "substring to match against name or alias")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	switch *flagKind {
	case "", "condition", "action", "trigger":
	default:
		fmt.Fprintln(stderr, `dcs-sms me trigger list-predicates: --kind must be condition|action|trigger`)
		return 2
	}
	luaArgs := fmt.Sprintf("{ kind = %q, search = %q }", *flagKind, *flagSearch)
	resp, exitCode := runMeVerb("trigger_list_predicates", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
