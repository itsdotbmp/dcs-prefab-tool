package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("drawing", "remove", meDrawingRemoveCmd)
}

// meDrawingRemoveCmd implements `dcs-sms me drawing remove --name <X>`.
//
// Wraps me_draw_panel.objectDelete. Drawing names are unique across all
// layers (verifyName at panel level enforces this), so --name is enough
// to disambiguate.
func meDrawingRemoveCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing remove", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "drawing name")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing remove: --name is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q }", *flagName)

	resp, exitCode := runMeVerb("drawing_remove", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
