package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("trigger", "reorder-condition", meTriggerReorderConditionCmd)
}

// meTriggerReorderConditionCmd implements
//
//	dcs-sms me trigger reorder-condition --trigger T --index N
//	  { --before M | --after M | --to-index M | --to-start | --to-end }
//
// Moves a condition to a new position in t.rules. Anchor references
// (--before / --after) are 1-based indices into t.rules. Exactly one
// position flag must be provided.
func meTriggerReorderConditionCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger reorder-condition", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagTrigger    = fs.String("trigger", "", "parent trigger name")
		flagIndex      = fs.Int("index", 0, "1-based source condition index in t.rules")
		flagBefore     = fs.Int("before", 0, "anchor: move source to just before this 1-based condition index")
		flagAfter      = fs.Int("after", 0, "anchor: move source to just after this 1-based condition index")
		flagToIndex    = fs.Int("to-index", 0, "1-based final position in t.rules")
		flagToStart    = fs.Bool("to-start", false, "sugar for --to-index 1")
		flagToEnd      = fs.Bool("to-end", false, "sugar for --to-index #rules")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagTrigger == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger reorder-condition: --trigger is required")
		return 2
	}
	if *flagIndex < 1 {
		fmt.Fprintln(stderr, "dcs-sms me trigger reorder-condition: --index (>= 1) is required")
		return 2
	}

	// Mutual exclusion: exactly one position flag. Note --before/--after
	// are int flags here (vs string in `me trigger reorder`); 0 means unset.
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
		fmt.Fprintln(stderr, "dcs-sms me trigger reorder-condition: exactly one of "+
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

	resp, exitCode := runMeVerb("trigger_reorder_condition", b.String(), *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
