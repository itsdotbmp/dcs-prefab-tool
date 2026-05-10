package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

type meFileSaveOpts struct {
	Reopen     bool
	Timeout    time.Duration
	Pretty     bool
	SavedGames string
}

func meFileSaveFlags() (*flag.FlagSet, *meFileSaveOpts) {
	opts := &meFileSaveOpts{}
	fs := flag.NewFlagSet("me file save", flag.ContinueOnError)
	fs.BoolVar(&opts.Reopen, "reopen", true, "re-open the file after save (matches DCS-native; refreshes title bar)")
	fs.DurationVar(&opts.Timeout, "timeout", 30*time.Second, "wall-clock timeout")
	fs.BoolVar(&opts.Pretty, "pretty", false, "indent JSON output")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	return fs, opts
}

func init() {
	registerMeInfo("file", "save", cmdInfo{
		Run:      meFileSaveCmd,
		Flags:    flagsOnly(meFileSaveFlags),
		Synopsis: "save the open mission to its current path",
	})
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
	fs, opts := meFileSaveFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	luaArgs := fmt.Sprintf("{ reopen = %t }", opts.Reopen)

	resp, exitCode := runMeVerb("file_save", luaArgs, opts.Timeout, opts.SavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, opts.Pretty, stdout)
}
