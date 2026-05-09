package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("drawing", "set-pos", meDrawingSetPosCmd)
}

// meDrawingSetPosCmd implements
// `dcs-sms me drawing set-pos --name <X> --north <m> --east <m>`.
//
// Moves the drawing's anchor. For shapes with relative-to-anchor points
// (line, free polygon), the shape moves rigidly with the anchor. For
// analytic shapes (circle / rect / oval / arrow), only the center
// moves; the dimensions are unchanged.
func meDrawingSetPosCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing set-pos", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "drawing name")
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-pos: --name is required")
		return 2
	}
	northSet, eastSet := false, false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "north" {
			northSet = true
		}
		if f.Name == "east" {
			eastSet = true
		}
	})
	if !northSet || !eastSet {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-pos: --north and --east are both required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, north = %g, east = %g }", *flagName, *flagNorth, *flagEast)

	resp, exitCode := runMeVerb("drawing_set_pos", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
