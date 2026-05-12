package main

import (
	"flag"
	"io"
	"time"
)

type meTriggerListOpts struct {
	Timeout    time.Duration
	Pretty     bool
	SavedGames string
}

func meTriggerListFlags() (*flag.FlagSet, *meTriggerListOpts) {
	opts := &meTriggerListOpts{}
	fs := flag.NewFlagSet("me trigger list", flag.ContinueOnError)
	fs.DurationVar(&opts.Timeout, "timeout", 30*time.Second, "wall-clock timeout")
	fs.BoolVar(&opts.Pretty, "pretty", false, "indent JSON output")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	return fs, opts
}

func init() {
	registerMeInfo("trigger", "list", cmdInfo{
		Run:      meTriggerListCmd,
		Flags:    flagsOnly(meTriggerListFlags),
		Synopsis: "list all triggers in the open mission",
	})
}

// meTriggerListCmd implements `dcs-sms me trigger list`.
//
// Returns a compact one-row-per-trigger summary: name, type, condition
// count, action count, event filter. For full trigger detail use
// `me trigger get --name X`.
func meTriggerListCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := meTriggerListFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	resp, exitCode := runMeVerb("trigger_list", "{}", opts.Timeout, opts.SavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, opts.Pretty, stdout)
}
