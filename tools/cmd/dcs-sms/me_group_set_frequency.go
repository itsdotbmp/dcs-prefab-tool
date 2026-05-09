package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "set-frequency", meGroupSetFrequencyCmd)
}

// meGroupSetFrequencyCmd implements
// `dcs-sms me group set-frequency --name|--id <X> --frequency <MHz>`.
//
// Sets the group-level radio frequency. Stored as a number in MHz (e.g. 251,
// 305.5). The ME doesn't validate band/range — passing 1000 just stores it.
func meGroupSetFrequencyCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group set-frequency", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "group name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "group id (mutually exclusive with --name)")
		flagFrequency  = fs.Float64("frequency", 0, "frequency in MHz")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	hasName := *flagName != ""
	hasID := *flagID != 0
	if hasName == hasID {
		fmt.Fprintln(stderr, "dcs-sms me group set-frequency: exactly one of --name or --id is required")
		return 2
	}
	if *flagFrequency <= 0 {
		fmt.Fprintln(stderr, "dcs-sms me group set-frequency: --frequency is required (> 0 MHz)")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, frequency = %g }", idClause, *flagFrequency)

	resp, exitCode := runMeVerb("group_set_frequency", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
