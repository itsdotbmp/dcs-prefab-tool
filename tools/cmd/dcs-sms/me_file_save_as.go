package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("file", "save-as", meFileSaveAsCmd)
}

// meFileSaveAsCmd implements `dcs-sms me file save-as --path <X.miz>`.
//
// Saves the current mission to a new path and updates the ME's tracked
// mission path so subsequent bare `me file save` calls target the new file.
//
// --reopen (default true) controls whether DCS re-loads the file post-save
// (DCS-native behavior — refreshes the title bar and editor state). Pass
// --reopen=false to skip the reload (see `me file save --help` for when).
func meFileSaveAsCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me file save-as", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagPath       = fs.String("path", "", "absolute path to write (.miz)")
		flagReopen     = fs.Bool("reopen", true, "re-open the file after save (matches DCS-native; refreshes title bar)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagPath == "" {
		fmt.Fprintln(stderr, "dcs-sms me file save-as: --path is required")
		return 2
	}

	pathLua := strings.ReplaceAll(*flagPath, "\\", "/")
	luaArgs := fmt.Sprintf("{ path = %q, reopen = %t }", pathLua, *flagReopen)

	resp, exitCode := runMeVerb("file_save_as", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
