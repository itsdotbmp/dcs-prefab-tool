package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("drawing", "set-thickness", meDrawingSetThicknessCmd)
}

// meDrawingSetThicknessCmd implements
// `dcs-sms me drawing set-thickness --name <X> --thickness <px>`.
//
// Line and Polygon shapes only. TextBox has its own border-thickness
// concept (separate verb if/when needed); Icon has scale instead.
func meDrawingSetThicknessCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing set-thickness", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "drawing name (Line / Polygon only)")
		flagThickness  = fs.Float64("thickness", 0, "thickness in pixels (positive)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-thickness: --name is required")
		return 2
	}
	if *flagThickness <= 0 {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-thickness: --thickness is required (> 0)")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, thickness = %g }", *flagName, *flagThickness)

	resp, exitCode := runMeVerb("drawing_set_thickness", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
