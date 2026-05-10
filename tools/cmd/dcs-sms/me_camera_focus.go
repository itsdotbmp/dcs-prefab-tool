package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("camera", "focus", meCameraFocusCmd)
}

// meCameraFocusCmd implements
//
//	dcs-sms me camera focus { --name N | --lat L --lon L | --x X --y Y } [--scale S]
//
// Pans the ME map to the requested point. Exactly one of:
//   - --name        — case-insensitive airdrome name (exact match preferred,
//                     substring fallback)
//   - --lat / --lon — decimal degrees
//   - --x / --y     — DCS world meters (x = north, y = east)
//
// --scale (meters per screen unit) is optional; if given, applied before the
// camera move.
func meCameraFocusCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me camera focus", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "airdrome name (case-insensitive, substring)")
		flagLat        = fs.Float64("lat", 0, "latitude (decimal degrees)")
		flagLon        = fs.Float64("lon", 0, "longitude (decimal degrees)")
		flagX          = fs.Float64("x", 0, "DCS world meters, north axis")
		flagY          = fs.Float64("y", 0, "DCS world meters, east axis")
		flagScale      = fs.Float64("scale", 0, "map scale (meters per screen unit; 0 = keep current)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	var hasLat, hasLon, hasX, hasY bool
	fs.Visit(func(f *flag.Flag) {
		switch f.Name {
		case "lat":
			hasLat = true
		case "lon":
			hasLon = true
		case "x":
			hasX = true
		case "y":
			hasY = true
		}
	})

	modeName := *flagName != ""
	modeLatLon := hasLat || hasLon
	modeXY := hasX || hasY
	set := 0
	if modeName {
		set++
	}
	if modeLatLon {
		set++
	}
	if modeXY {
		set++
	}
	if set != 1 {
		fmt.Fprintln(stderr, "dcs-sms me camera focus: exactly one of "+
			"--name / --lat+--lon / --x+--y is required")
		return 2
	}
	if modeLatLon && !(hasLat && hasLon) {
		fmt.Fprintln(stderr, "dcs-sms me camera focus: --lat and --lon must both be provided")
		return 2
	}
	if modeXY && !(hasX && hasY) {
		fmt.Fprintln(stderr, "dcs-sms me camera focus: --x and --y must both be provided")
		return 2
	}

	var b strings.Builder
	b.WriteString("{")
	first := true
	add := func(s string) {
		if !first {
			b.WriteString(", ")
		}
		b.WriteString(s)
		first = false
	}
	if modeName {
		add(fmt.Sprintf("name = %q", *flagName))
	}
	if modeLatLon {
		add(fmt.Sprintf("lat = %g, lon = %g", *flagLat, *flagLon))
	}
	if modeXY {
		add(fmt.Sprintf("x = %g, y = %g", *flagX, *flagY))
	}
	if *flagScale != 0 {
		add(fmt.Sprintf("scale = %g", *flagScale))
	}
	b.WriteString(" }")

	resp, exitCode := runMeVerb("camera_focus", b.String(), *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
