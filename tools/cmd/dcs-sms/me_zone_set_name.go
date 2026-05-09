package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("zone", "set-name", meZoneSetNameCmd)
}

// meZoneSetNameCmd implements `dcs-sms me zone set-name --name|--id <X> --new-name <Y>`.
//
// `--name` selects the zone (paired with `--id` as mutually exclusive),
// `--new-name` supplies the value to write — same naming convention used for
// `me group set-name` etc. Wraps Mission.TriggerZoneData.setTriggerZoneName.
//
// The ME enforces uniqueness internally (makeTriggerZoneNameUnique) — if the
// requested name is already taken, the actual stored name will have a suffix
// (e.g. "X #001"). The verb returns the final stored name so callers can see
// what was applied.
func meZoneSetNameCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone set-name", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "zone name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "zone id (mutually exclusive with --name)")
		flagNewName    = fs.String("new-name", "", "new zone name")
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
		fmt.Fprintln(stderr, "dcs-sms me zone set-name: exactly one of --name or --id is required")
		return 2
	}
	if *flagNewName == "" {
		fmt.Fprintln(stderr, "dcs-sms me zone set-name: --new-name is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, new_name = %q }", idClause, *flagNewName)

	resp, exitCode := runMeVerb("zone_set_name", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
