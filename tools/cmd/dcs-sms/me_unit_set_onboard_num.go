package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-onboard-num", meUnitSetOnboardNumCmd)
}

// meUnitSetOnboardNumCmd implements
// `dcs-sms me unit set-onboard-num --name|--id <X> --onboard-num <NNN>`.
//
// Onboard number is a 3-character string painted on the airframe (e.g.
// "010", "210", "TC1"). Stored as `u.onboard_num`.
func meUnitSetOnboardNumCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-onboard-num", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagOnboardNum = fs.String("onboard-num", "", "onboard number string (e.g. \"010\")")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-onboard-num: exactly one of --name or --id is required")
		return 2
	}
	if *flagOnboardNum == "" {
		fmt.Fprintln(stderr, "dcs-sms me unit set-onboard-num: --onboard-num is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, onboard_num = %q }", idClause, *flagOnboardNum)

	resp, exitCode := runMeVerb("unit_set_onboard_num", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
