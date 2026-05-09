package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-gun", meUnitSetGunCmd)
}

// meUnitSetGunCmd implements
// `dcs-sms me unit set-gun --name|--id <X> --percent <0-100>`.
//
// Sets unit.payload.gun (gun ammunition percent). Plane / helicopter only.
func meUnitSetGunCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-gun", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagPercent    = fs.Float64("percent", -1, "gun ammo percent (0-100)")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-gun: exactly one of --name or --id is required")
		return 2
	}
	if *flagPercent < 0 || *flagPercent > 100 {
		fmt.Fprintln(stderr, "dcs-sms me unit set-gun: --percent (0-100) is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, percent = %g }", idClause, *flagPercent)

	resp, exitCode := runMeVerb("unit_set_gun", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
