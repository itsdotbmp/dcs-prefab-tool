package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-fuel", meUnitSetFuelCmd)
}

// meUnitSetFuelCmd implements
// `dcs-sms me unit set-fuel --name|--id <X> --fuel <kg>`.
//
// Sets unit.payload.fuel (kg). Plane / helicopter only. No max validation —
// per-airframe max is in DB.unit_by_type[type], but we mirror the panel's
// behavior of clamping silently rather than refusing.
func meUnitSetFuelCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-fuel", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagFuel       = fs.Float64("fuel", -1, "fuel mass in kg (>= 0)")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-fuel: exactly one of --name or --id is required")
		return 2
	}
	if *flagFuel < 0 {
		fmt.Fprintln(stderr, "dcs-sms me unit set-fuel: --fuel (>= 0 kg) is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, fuel = %g }", idClause, *flagFuel)

	resp, exitCode := runMeVerb("unit_set_fuel", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
