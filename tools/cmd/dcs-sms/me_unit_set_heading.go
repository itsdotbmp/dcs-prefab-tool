package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-heading", meUnitSetHeadingCmd)
}

// meUnitSetHeadingCmd implements
// `dcs-sms me unit set-heading --name|--id <X> --heading <degrees>`.
//
// Takes degrees on the CLI (more natural than radians); the Lua verb
// converts to radians for storage. DCS uses radians internally with
// 0 = north and clockwise = positive (compass direction).
//
// Updates both u.heading and u.psi — they're stored separately but the ME
// keeps them in sync; we mirror that.
func meUnitSetHeadingCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-heading", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagHeading    = fs.Float64("heading", 0,
			"heading in degrees (0 = north, clockwise positive)")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-heading: exactly one of --name or --id is required")
		return 2
	}
	headingSet := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "heading" {
			headingSet = true
		}
	})
	if !headingSet {
		fmt.Fprintln(stderr, "dcs-sms me unit set-heading: --heading is required (degrees)")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, heading_deg = %g }", idClause, *flagHeading)

	resp, exitCode := runMeVerb("unit_set_heading", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
