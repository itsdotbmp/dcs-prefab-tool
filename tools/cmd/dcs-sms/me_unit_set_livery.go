package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-livery", meUnitSetLiveryCmd)
}

// meUnitSetLiveryCmd implements `dcs-sms me unit set-livery --name|--id <X> --livery <L>`.
//
// Livery id is a string matching the airframe's livery folder name (e.g.
// "Aggressors USAF" / "USAF Standard" — depends on airframe). Empty string
// "" means default. The ME does not validate the value — an unknown livery
// just falls back to default at runtime.
func meUnitSetLiveryCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-livery", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagLivery     = fs.String("livery", "", "livery id (airframe-specific; empty = default)")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-livery: exactly one of --name or --id is required")
		return 2
	}
	// --livery may be empty string explicitly (means "default") — require fs.Visit.
	liverySet := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "livery" {
			liverySet = true
		}
	})
	if !liverySet {
		fmt.Fprintln(stderr, "dcs-sms me unit set-livery: --livery is required (use --livery=\"\" for default)")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, livery = %q }", idClause, *flagLivery)

	resp, exitCode := runMeVerb("unit_set_livery", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
