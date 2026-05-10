package main

import (
	"flag"
	"io"
	"time"
)

func init() {
	registerMe("camera", "get", meCameraGetCmd)
}

// meCameraGetCmd implements `dcs-sms me camera get` — returns the current
// map center as { x, y, lat, lon, scale }.
func meCameraGetCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me camera get", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	resp, exitCode := runMeVerb("camera_get", "{}", *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
