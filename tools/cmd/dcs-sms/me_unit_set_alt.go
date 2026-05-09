package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("unit", "set-alt", meUnitSetAltCmd)
}

// meUnitSetAltCmd implements
// `dcs-sms me unit set-alt --name|--id <X> --alt <m> [--alt-type BARO|RADIO]`.
//
// Sets both u.alt (meters) and u.alt_type. Default --alt-type is BARO
// (most common for fixed-wing). For helicopters operating in low-level
// terrain-following, RADIO altitude is typical.
//
// Only updates the unit's altitude — not the route's. If you also need to
// update waypoint altitudes you'll have to issue a separate verb (not yet
// shipped — open question whether unit-vs-waypoint should auto-sync).
func meUnitSetAltCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-alt", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagAlt        = fs.Float64("alt", 0, "altitude in meters above sea level")
		flagAltType    = fs.String("alt-type", "BARO", "altitude type: BARO | RADIO")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-alt: exactly one of --name or --id is required")
		return 2
	}
	altSet := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "alt" {
			altSet = true
		}
	})
	if !altSet {
		fmt.Fprintln(stderr, "dcs-sms me unit set-alt: --alt is required (meters)")
		return 2
	}
	altType := strings.ToUpper(*flagAltType)
	if altType != "BARO" && altType != "RADIO" {
		fmt.Fprintln(stderr, "dcs-sms me unit set-alt: --alt-type must be BARO or RADIO")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, alt = %g, alt_type = %q }", idClause, *flagAlt, altType)

	resp, exitCode := runMeVerb("unit_set_alt", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
