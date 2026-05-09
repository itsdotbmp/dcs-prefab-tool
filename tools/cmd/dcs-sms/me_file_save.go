package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("file", "save", meFileSaveCmd)
}

// meFileSaveCmd implements `dcs-sms me file save`.
//
// Saves the current mission to its existing path. Errors if the mission
// hasn't been saved before — use `me file save-as --path X.miz` for that.
//
// --reopen (default true) controls whether DCS re-loads the file post-save
// (DCS-native behavior — refreshes the title bar and editor state). Pass
// --reopen=false to skip the reload, e.g. when groups have been injected but
// Mission.fixWaypointForGroup hasn't run yet (the reload would crash).
func meFileSaveCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me file save", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagReopen     = fs.Bool("reopen", true, "re-open the file after save (matches DCS-native; refreshes title bar)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	luaArgs := fmt.Sprintf("{ reopen = %t }", *flagReopen)

	resp, exitCode := runMeVerb("file_save", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
