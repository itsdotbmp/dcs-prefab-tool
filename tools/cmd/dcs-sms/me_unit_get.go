package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "get", meUnitGetCmd)
}

// meUnitGetCmd implements `dcs-sms me unit get --name <n> | --id <n>`.
func meUnitGetCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit get", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (exact match)")
		flagID         = fs.Int("id", 0, "unitId (numeric)")
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
		fmt.Fprintln(stderr, "dcs-sms me unit get: pass exactly one of --name or --id")
		return 2
	}
	var luaArgs string
	if hasName {
		luaArgs = fmt.Sprintf("{ name = %q }", *flagName)
	} else {
		luaArgs = fmt.Sprintf("{ id = %d }", *flagID)
	}
	resp, exitCode := runMeVerb("unit_get", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
