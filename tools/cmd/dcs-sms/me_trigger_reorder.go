package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("trigger", "reorder", meTriggerReorderCmd)
}

// meTriggerReorderCmd implements
//
//	dcs-sms me trigger reorder --name T { --before X | --after X
//	                                    | --to-index N | --to-start
//	                                    | --to-end }
//
// Moves a trigger to a new position in mission.trigrules. Exactly one
// position flag must be provided.
func meTriggerReorderCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger reorder", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "trigger name to move (the comment field)")
		flagBefore     = fs.String("before", "", "anchor: move source to just before this trigger name")
		flagAfter      = fs.String("after", "", "anchor: move source to just after this trigger name")
		flagToIndex    = fs.Int("to-index", 0, "1-based final position in mission.trigrules")
		flagToStart    = fs.Bool("to-start", false, "sugar for --to-index 1")
		flagToEnd      = fs.Bool("to-end", false, "sugar for --to-index #trigrules")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger reorder: --name is required")
		return 2
	}

	// Mutual exclusion: exactly one position flag.
	set := 0
	if *flagBefore != "" {
		set++
	}
	if *flagAfter != "" {
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
		fmt.Fprintln(stderr, "dcs-sms me trigger reorder: exactly one of "+
			"--before / --after / --to-index / --to-start / --to-end is required")
		return 2
	}

	// Build the Lua args literal.
	var b strings.Builder
	fmt.Fprintf(&b, "{ name = %q", *flagName)
	if *flagBefore != "" {
		fmt.Fprintf(&b, ", before = %q", *flagBefore)
	}
	if *flagAfter != "" {
		fmt.Fprintf(&b, ", after = %q", *flagAfter)
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

	resp, exitCode := runMeVerb("trigger_reorder", b.String(), *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
