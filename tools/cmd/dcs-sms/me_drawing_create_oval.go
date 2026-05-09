package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("drawing", "create-oval", meDrawingCreateOvalCmd)
}

// meDrawingCreateOvalCmd implements
// `dcs-sms me drawing create-oval --north <m> --east <m> --r1 <m> --r2 <m> [...]`.
//
// Ellipse with semi-axes r1 (along local X / north before rotation) and
// r2 (along local Y / east before rotation). Setting r1 = r2 produces a
// circle but with the oval-shape control surface; for plain circles use
// create-circle which only takes one radius.
func meDrawingCreateOvalCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing create-oval", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin (oval center)")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin (oval center)")
		flagR1         = fs.Float64("r1", 0, "first semi-axis in meters (along local north pre-rotation)")
		flagR2         = fs.Float64("r2", 0, "second semi-axis in meters (along local east pre-rotation)")
		flagAngle      = fs.Float64("angle", 0, "rotation in degrees (CW around center, 0 = aligned with north/east)")
		flagName       = fs.String("name", "", "drawing name (auto-allocated if empty)")
		flagColor      = fs.String("color", "", "outline color (default red, opaque)")
		flagFillColor  = fs.String("fill-color", "", "fill color (default red, half alpha)")
		flagThickness  = fs.Float64("thickness", 0, "outline thickness in pixels (default 2)")
		flagStyle      = fs.String("style", "", "line style (default solid)")
		flagLayer      = fs.String("layer", "", "Red|Blue|Neutral|Common|Author (default Common)")
		flagHiddenPln  = fs.Bool("hidden-on-planner", false, "hide on mission planner")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagR1 <= 0 || *flagR2 <= 0 {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-oval: --r1 and --r2 are required (> 0)")
		return 2
	}

	colorLua, err := parseDrawingColorToHex(*flagColor, 0xFF)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-oval:", err)
		return 2
	}
	fillLua, err := parseDrawingColorToHex(*flagFillColor, 0x80)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-oval:", err)
		return 2
	}

	parts := []string{
		fmt.Sprintf("north = %g", *flagNorth),
		fmt.Sprintf("east = %g", *flagEast),
		fmt.Sprintf("r1 = %g", *flagR1),
		fmt.Sprintf("r2 = %g", *flagR2),
		fmt.Sprintf("angle_deg = %g", *flagAngle),
	}
	if *flagName != "" {
		parts = append(parts, fmt.Sprintf("name = %q", *flagName))
	}
	if colorLua != "" {
		parts = append(parts, "color = "+colorLua)
	}
	if fillLua != "" {
		parts = append(parts, "fill_color = "+fillLua)
	}
	if *flagThickness > 0 {
		parts = append(parts, fmt.Sprintf("thickness = %g", *flagThickness))
	}
	if *flagStyle != "" {
		parts = append(parts, fmt.Sprintf("style = %q", *flagStyle))
	}
	if *flagLayer != "" {
		parts = append(parts, fmt.Sprintf("layer = %q", *flagLayer))
	}
	if *flagHiddenPln {
		parts = append(parts, "hidden_on_planner = true")
	}
	luaArgs := "{ " + strings.Join(parts, ", ") + " }"

	resp, exitCode := runMeVerb("drawing_create_oval", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
