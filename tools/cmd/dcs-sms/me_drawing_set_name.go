package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("drawing", "set-name", meDrawingSetNameCmd)
}

// meDrawingSetNameCmd implements
// `dcs-sms me drawing set-name --name <X> --new-name <Y>`.
//
// Refuses on name collision — drawing names are unique across all
// layers (verifyName at panel level enforces this).
func meDrawingSetNameCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing set-name", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "current drawing name")
		flagNewName    = fs.String("new-name", "", "new drawing name")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-name: --name is required")
		return 2
	}
	if *flagNewName == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-name: --new-name is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, new_name = %q }", *flagName, *flagNewName)

	resp, exitCode := runMeVerb("drawing_set_name", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
