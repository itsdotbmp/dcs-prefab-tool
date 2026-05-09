package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "payload", meUnitPayloadCmd)
}

// meUnitPayloadCmd implements `dcs-sms me unit payload <set|clear> [flags]`.
// Sub-dispatches on args[0] (the third token after `me unit payload`):
//   set   --pylon N --weapon CLSID|name   set a pylon's weapon
//   clear --pylon N                       remove a pylon's weapon
//
// `me unit set-loadout` is the verb for applying a whole named loadout —
// these per-pylon ops are for fine-tuning after.
func meUnitPayloadCmd(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 || args[0] == "--help" || args[0] == "-h" || args[0] == "help" {
		printPayloadUsage(stdout)
		if len(args) == 0 {
			return 2
		}
		return 0
	}
	switch args[0] {
	case "set":
		return meUnitPayloadSetCmd(args[1:], stdout, stderr)
	case "clear":
		return meUnitPayloadClearCmd(args[1:], stdout, stderr)
	default:
		fmt.Fprintf(stderr, "dcs-sms me unit payload: unknown sub-verb %q (expected set|clear)\n", args[0])
		printPayloadUsage(stderr)
		return 2
	}
}

func printPayloadUsage(w io.Writer) {
	fmt.Fprintln(w, "Usage: dcs-sms me unit payload <set|clear> --name|--id <X> --pylon N [--weapon ...]")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Sub-verbs:")
	fmt.Fprintln(w, "  set    Set a single pylon's weapon (--weapon accepts CLSID or display name).")
	fmt.Fprintln(w, "  clear  Remove a single pylon's weapon entry.")
}

func meUnitPayloadSetCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit payload set", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagPylon      = fs.Int("pylon", 0, "pylon number (per-airframe, see DB.unit_by_type[type].Pylons)")
		flagWeapon     = fs.String("weapon", "", "weapon CLSID (e.g. \"{GUID}\") or display name")
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
		fmt.Fprintln(stderr, "dcs-sms me unit payload set: exactly one of --name or --id is required")
		return 2
	}
	if *flagPylon < 1 {
		fmt.Fprintln(stderr, "dcs-sms me unit payload set: --pylon (>= 1) is required")
		return 2
	}
	if *flagWeapon == "" {
		fmt.Fprintln(stderr, "dcs-sms me unit payload set: --weapon is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, pylon = %d, weapon = %q }",
		idClause, *flagPylon, *flagWeapon)

	resp, exitCode := runMeVerb("unit_payload_set", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}

func meUnitPayloadClearCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit payload clear", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagPylon      = fs.Int("pylon", 0, "pylon number")
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
		fmt.Fprintln(stderr, "dcs-sms me unit payload clear: exactly one of --name or --id is required")
		return 2
	}
	if *flagPylon < 1 {
		fmt.Fprintln(stderr, "dcs-sms me unit payload clear: --pylon (>= 1) is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, pylon = %d }", idClause, *flagPylon)

	resp, exitCode := runMeVerb("unit_payload_clear", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
