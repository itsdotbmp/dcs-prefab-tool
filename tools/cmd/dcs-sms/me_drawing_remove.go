package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

type meDrawingRemoveOpts struct {
	Name       string
	Timeout    time.Duration
	Pretty     bool
	SavedGames string
}

func meDrawingRemoveFlags() (*flag.FlagSet, *meDrawingRemoveOpts) {
	opts := &meDrawingRemoveOpts{}
	fs := flag.NewFlagSet("me drawing remove", flag.ContinueOnError)
	fs.StringVar(&opts.Name, "name", "", "drawing name")
	fs.DurationVar(&opts.Timeout, "timeout", 30*time.Second, "wall-clock timeout")
	fs.BoolVar(&opts.Pretty, "pretty", false, "indent JSON output")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	return fs, opts
}

func init() {
	registerMeInfo("drawing", "remove", cmdInfo{
		Run:      meDrawingRemoveCmd,
		Flags:    flagsOnly(meDrawingRemoveFlags),
		Synopsis: "delete a drawing from the open mission",
	})
}

// meDrawingRemoveCmd implements `dcs-sms me drawing remove --name <X>`.
//
// Wraps me_draw_panel.objectDelete. Drawing names are unique across all
// layers (verifyName at panel level enforces this), so --name is enough
// to disambiguate.
func meDrawingRemoveCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := meDrawingRemoveFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if opts.Name == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing remove: --name is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q }", opts.Name)

	resp, exitCode := runMeVerb("drawing_remove", luaArgs, opts.Timeout, opts.SavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, opts.Pretty, stdout)
}
