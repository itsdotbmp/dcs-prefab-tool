package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("drawing", "create-circle", meDrawingCreateCircleCmd)
}

// meDrawingCreateCircleCmd implements
// `dcs-sms me drawing create-circle --north <m> --east <m> --radius <m> [...]`.
//
// Disk-shape polygon — filled disc with outline. Colors accept the same
// shapes as `me zone create --color`: name (red / blue / ...),
// "#rrggbb", or "#rrggbbaa". Outline default alpha is 0xFF (opaque),
// fill default alpha is 0x80 (half) — matches the ME's own new-primitive
// defaults. Layer defaults to Common.
func meDrawingCreateCircleCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing create-circle", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin")
		flagRadius     = fs.Float64("radius", 0, "radius in meters")
		flagName       = fs.String("name", "", "drawing name (auto-allocated if empty)")
		flagColor      = fs.String("color", "", "outline color: name, #rrggbb (alpha=0xff), or #rrggbbaa")
		flagFillColor  = fs.String("fill-color", "", "fill color: name, #rrggbb (alpha=0x80), or #rrggbbaa")
		flagThickness  = fs.Float64("thickness", 0, "outline thickness in pixels (default 2)")
		flagStyle      = fs.String("style", "", "line style: solid|solid2|dot|dot2|dotdash|dash|cross|square|strongpoint|triangle|wirefence|boundry1..5 (default solid)")
		flagLayer      = fs.String("layer", "", "layer: Red|Blue|Neutral|Common|Author (default Common)")
		flagHiddenPln  = fs.Bool("hidden-on-planner", false, "hide on mission planner")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagRadius <= 0 {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-circle: --radius is required (> 0)")
		return 2
	}

	colorLua, err := parseDrawingColorToHex(*flagColor, 0xFF)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-circle:", err)
		return 2
	}
	fillLua, err := parseDrawingColorToHex(*flagFillColor, 0x80)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-circle:", err)
		return 2
	}

	parts := []string{
		fmt.Sprintf("north = %g", *flagNorth),
		fmt.Sprintf("east = %g", *flagEast),
		fmt.Sprintf("radius = %g", *flagRadius),
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

	resp, exitCode := runMeVerb("drawing_create_circle", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
