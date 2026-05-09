package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "set-country", meGroupSetCountryCmd)
}

// meGroupSetCountryCmd implements
// `dcs-sms me group set-country --name|--id <X> --country <name>`.
//
// Moves a group between countries (and possibly coalitions). Replicates the
// data-side flow of me_aircraft.changeCountry: removes from old country list,
// updates boss/color, inserts into new country list, fixes liveries (air
// groups), and re-attracts takeoff/landing waypoints if needed.
//
// Target country must already exist in the mission tree (i.e. was added via
// the new-mission default coalitions or explicitly). Refuses cleanly if not.
//
// ME does not refuse moves that leave unit types orphaned (Su-27 → USA);
// liveries go empty but the data is otherwise valid. The verb mirrors that.
func meGroupSetCountryCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group set-country", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "group name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "group id (mutually exclusive with --name)")
		flagCountry    = fs.String("country", "", "target country name (case-insensitive)")
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
		fmt.Fprintln(stderr, "dcs-sms me group set-country: exactly one of --name or --id is required")
		return 2
	}
	if *flagCountry == "" {
		fmt.Fprintln(stderr, "dcs-sms me group set-country: --country is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, country = %q }", idClause, *flagCountry)

	resp, exitCode := runMeVerb("group_set_country", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
