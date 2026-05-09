package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("file", "new", meFileNewCmd)
}

// meFileNewCmd implements `dcs-sms me file new --map <theatre>`.
//
// Calls dcs_sms_me.verbs.file_new(args) on the ME-mod side, which bypasses the
// "New Mission Settings" UI dialog and reproduces its OK-button effect
// directly: setDefaultCoalitions → selectTheatreOfWar → MapWindow.initTerrain
// → module_mission.create_new_mission. The terrain init runs on a later tick
// (scheduled via ProgressBarDialog), so the response confirms dispatch, not
// completion.
func meFileNewCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me file new", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagMap        = fs.String("map", "", "theatre name (e.g. Syria, Caucasus)")
		flagForce      = fs.Bool("force", false, "discard unsaved changes in the current mission")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagMap == "" {
		fmt.Fprintln(stderr, "dcs-sms me file new: --map is required")
		return 2
	}

	luaArgs := fmt.Sprintf("{ map = %q, force = %t }", *flagMap, *flagForce)

	resp, exitCode := runMeVerb("file_new", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
