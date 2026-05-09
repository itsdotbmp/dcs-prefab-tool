package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "set-name", meGroupSetNameCmd)
}

// meGroupSetNameCmd implements `dcs-sms me group set-name --name|--id <X> --new-name <Y>`.
//
// Uses Mission.renameGroup which refuses on collision (returns false). The
// verb propagates that as an error rather than silently uniquifying — if the
// user picks a colliding name we want them to know, not get back "Foo-1".
func meGroupSetNameCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group set-name", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "group name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "group id (mutually exclusive with --name)")
		flagNewName    = fs.String("new-name", "", "new group name")
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
		fmt.Fprintln(stderr, "dcs-sms me group set-name: exactly one of --name or --id is required")
		return 2
	}
	if *flagNewName == "" {
		fmt.Fprintln(stderr, "dcs-sms me group set-name: --new-name is required")
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, new_name = %q }", idClause, *flagNewName)

	resp, exitCode := runMeVerb("group_set_name", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
