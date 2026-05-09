package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-callsign", meUnitSetCallsignCmd)
}

// meUnitSetCallsignCmd implements
// `dcs-sms me unit set-callsign --name|--id <X> --callsign <name>`
//   [--squadron <n>] [--flight <n>] [--plane <n>].
//
// Sets the radio-callsign struct on the unit. The internal shape DCS uses is
//
//   callsign = { squadron, flight, plane, name = "Enfield11" }
//
// The callsign name (the radio-readable label) is the most-commonly-changed
// field; --squadron/--flight/--plane indices default to leaving the existing
// numeric values untouched if not passed (current values preserved).
func meUnitSetCallsignCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-callsign", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagCallsign   = fs.String("callsign", "", "callsign label (e.g. \"Enfield11\")")
		flagSquadron   = fs.Int("squadron", 0, "squadron number (optional; preserves existing if 0)")
		flagFlight     = fs.Int("flight", 0, "flight number (optional; preserves existing if 0)")
		flagPlane      = fs.Int("plane", 0, "plane number (optional; preserves existing if 0)")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-callsign: exactly one of --name or --id is required")
		return 2
	}
	if *flagCallsign == "" {
		fmt.Fprintln(stderr, "dcs-sms me unit set-callsign: --callsign is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf(
		"{ %s, callsign = %q, squadron = %d, flight = %d, plane = %d }",
		idClause, *flagCallsign, *flagSquadron, *flagFlight, *flagPlane,
	)

	resp, exitCode := runMeVerb("unit_set_callsign", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
