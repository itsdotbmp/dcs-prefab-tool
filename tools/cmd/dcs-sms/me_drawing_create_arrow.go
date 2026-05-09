package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("drawing", "create-arrow", meDrawingCreateArrowCmd)
}

// meDrawingCreateArrowCmd implements
// `dcs-sms me drawing create-arrow --north <m> --east <m> --length <m> [...]`.
//
// Arrow-shape polygon. The shape's runtime points are generated from
// length by polygonArrowMakePoints at load time, so the verb only needs
// length + angle (and standard color / style / layer args). --angle
// rotates the arrow tip around the anchor (0 = pointing north,
// clockwise positive in radians).
func meDrawingCreateArrowCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing create-arrow", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin (arrow anchor)")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin (arrow anchor)")
		flagLength     = fs.Float64("length", 0, "arrow length in meters")
		flagAngle      = fs.Float64("angle", 0, "rotation in degrees (0 = pointing north, CW positive)")
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
	if *flagLength <= 0 {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-arrow: --length is required (> 0)")
		return 2
	}

	colorLua, err := parseDrawingColorToHex(*flagColor, 0xFF)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-arrow:", err)
		return 2
	}
	fillLua, err := parseDrawingColorToHex(*flagFillColor, 0x80)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-arrow:", err)
		return 2
	}

	parts := []string{
		fmt.Sprintf("north = %g", *flagNorth),
		fmt.Sprintf("east = %g", *flagEast),
		fmt.Sprintf("length = %g", *flagLength),
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

	resp, exitCode := runMeVerb("drawing_create_arrow", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
