package main

import (
	"flag"
	"io"
	"time"
)

func init() {
	registerMeInfo("camera", "get", cmdInfo{
		Run:      meCameraGetCmd,
		Flags:    flagsOnly(meCameraGetFlags),
		Synopsis: "return the ME camera's current map center (x, y, lat, lon, scale)",
	})
}

type meCameraGetOpts struct {
	Timeout    time.Duration
	Pretty     bool
	SavedGames string
}

func meCameraGetFlags() (*flag.FlagSet, *meCameraGetOpts) {
	opts := &meCameraGetOpts{}
	fs := flag.NewFlagSet("me camera get", flag.ContinueOnError)
	fs.DurationVar(&opts.Timeout, "timeout", 30*time.Second, "wall-clock timeout")
	fs.BoolVar(&opts.Pretty, "pretty", false, "indent JSON output")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	return fs, opts
}

// meCameraGetCmd implements `dcs-sms me camera get` — returns the current
// map center as { x, y, lat, lon, scale }.
func meCameraGetCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := meCameraGetFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	resp, exitCode := runMeVerb("camera_get", "{}", opts.Timeout, opts.SavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, opts.Pretty, stdout)
}
