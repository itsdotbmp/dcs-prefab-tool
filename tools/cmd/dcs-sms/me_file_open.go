package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("file", "open", meFileOpenCmd)
}

// meFileOpenCmd implements `dcs-sms me file open --path <X.miz>`.
//
// Calls dcs_sms_me.verbs.file_open(args) on the ME-mod side, which wraps
// me_toolbar.loadMission. The load is async (ED's progressBar schedules the
// actual file read on a later tick), so the response confirms the call was
// dispatched, not that the load has completed.
func meFileOpenCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me file open", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagPath       = fs.String("path", "", "absolute path to a .miz file")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagPath == "" {
		fmt.Fprintln(stderr, "dcs-sms me file open: --path is required")
		return 2
	}

	// Forward-slash the path. Lua tolerates / on Windows and it dodges the
	// well-documented backslash-escape pain documented in the discovery log.
	pathLua := strings.ReplaceAll(*flagPath, "\\", "/")

	// Build the Lua args table inline. %q emits a double-quoted Go string
	// literal which is also valid Lua (both use C-style escapes).
	luaArgs := fmt.Sprintf("{ path = %q }", pathLua)

	resp, exitCode := runMeVerb("file_open", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
