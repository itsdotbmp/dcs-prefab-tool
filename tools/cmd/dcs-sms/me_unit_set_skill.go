package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("unit", "set-skill", meUnitSetSkillCmd)
}

// meUnitSetSkillCmd implements `dcs-sms me unit set-skill --name|--id <X> --skill <S>`.
//
// AI skill levels: Average, Good, High, Excellent, Random, Player, Client.
// (No validation here — DCS stores the string verbatim. Misspellings will
// surface at mission-load time.)
func meUnitSetSkillCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit set-skill", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "unit name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "unit id (mutually exclusive with --name)")
		flagSkill      = fs.String("skill", "",
			"skill: Average | Good | High | Excellent | Random | Player | Client")
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
		fmt.Fprintln(stderr, "dcs-sms me unit set-skill: exactly one of --name or --id is required")
		return 2
	}
	if *flagSkill == "" {
		fmt.Fprintln(stderr, "dcs-sms me unit set-skill: --skill is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, skill = %q }", idClause, *flagSkill)

	resp, exitCode := runMeVerb("unit_set_skill", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
