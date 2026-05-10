package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("trigger", "reorder-action", meTriggerReorderActionCmd)
}

// meTriggerReorderActionCmd implements
//
//	dcs-sms me trigger reorder-action --trigger T --index N
//	  { --before M | --after M | --to-index M | --to-start | --to-end }
//
// Moves an action to a new position in t.actions. Anchor references
// (--before / --after) are 1-based indices into t.actions. Exactly one
// position flag must be provided.
func meTriggerReorderActionCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger reorder-action", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagTrigger    = fs.String("trigger", "", "parent trigger name")
		flagIndex      = fs.Int("index", 0, "1-based source action index in t.actions")
		flagBefore     = fs.Int("before", 0, "anchor: move source to just before this 1-based action index")
		flagAfter      = fs.Int("after", 0, "anchor: move source to just after this 1-based action index")
		flagToIndex    = fs.Int("to-index", 0, "1-based final position in t.actions")
		flagToStart    = fs.Bool("to-start", false, "sugar for --to-index 1")
		flagToEnd      = fs.Bool("to-end", false, "sugar for --to-index #actions")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagTrigger == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger reorder-action: --trigger is required")
		return 2
	}
	if *flagIndex < 1 {
		fmt.Fprintln(stderr, "dcs-sms me trigger reorder-action: --index (>= 1) is required")
		return 2
	}

	set := 0
	if *flagBefore != 0 {
		set++
	}
	if *flagAfter != 0 {
		set++
	}
	if *flagToIndex != 0 {
		set++
	}
	if *flagToStart {
		set++
	}
	if *flagToEnd {
		set++
	}
	if set != 1 {
		fmt.Fprintln(stderr, "dcs-sms me trigger reorder-action: exactly one of "+
			"--before / --after / --to-index / --to-start / --to-end is required")
		return 2
	}

	var b strings.Builder
	fmt.Fprintf(&b, "{ trigger = %q, index = %d", *flagTrigger, *flagIndex)
	if *flagBefore != 0 {
		fmt.Fprintf(&b, ", before = %d", *flagBefore)
	}
	if *flagAfter != 0 {
		fmt.Fprintf(&b, ", after = %d", *flagAfter)
	}
	if *flagToIndex != 0 {
		fmt.Fprintf(&b, ", to_index = %d", *flagToIndex)
	}
	if *flagToStart {
		b.WriteString(", to_start = true")
	}
	if *flagToEnd {
		b.WriteString(", to_end = true")
	}
	b.WriteString(" }")

	resp, exitCode := runMeVerb("trigger_reorder_action", b.String(), *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
