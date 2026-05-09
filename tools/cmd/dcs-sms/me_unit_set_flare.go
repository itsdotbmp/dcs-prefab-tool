package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-flare", meUnitSetFlareCmd)
}

// meUnitSetFlareCmd implements
// `dcs-sms me unit set-flare --name|--id <X> --count <N>`.
//
// Sets unit.payload.flare (count). Plane / helicopter only.
func meUnitSetFlareCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-flare", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagCount      = fs.Int("count", -1, "flare count (>= 0)")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-flare: exactly one of --name or --id is required")
		return 2
	}
	if *flagCount < 0 {
		fmt.Fprintln(stderr, "dcs-sms me unit set-flare: --count (>= 0) is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, count = %d }", idClause, *flagCount)

	resp, exitCode := runMeVerb("unit_set_flare", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
