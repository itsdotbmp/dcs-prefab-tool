package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-loadout", meUnitSetLoadoutCmd)
}

// meUnitSetLoadoutCmd implements
// `dcs-sms me unit set-loadout --name|--id <X> --loadout "<name>"`.
//
// Applies a named loadout (e.g. "CAP", "CAS", "Empty") to a plane/heli unit.
// The loadout name must match one of the airframe's pre-defined loadouts —
// inspect them in MissionEditor/data/scripts/UnitPayloads/<type>.lua or the
// ME's payload-panel dropdown.
//
// Replaces all pylons. Does not touch chaff / flare / fuel / gun — use
// `me unit set-chaff` etc. for those.
func meUnitSetLoadoutCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-loadout", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagLoadout    = fs.String("loadout", "", "loadout name (e.g. \"CAP\", \"CAS\", \"Empty\")")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-loadout: exactly one of --name or --id is required")
		return 2
	}
	if *flagLoadout == "" {
		fmt.Fprintln(stderr, "dcs-sms me unit set-loadout: --loadout is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, loadout = %q }", idClause, *flagLoadout)

	resp, exitCode := runMeVerb("unit_set_loadout", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
