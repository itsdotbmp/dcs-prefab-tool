package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("drawing", "create-polygon", meDrawingCreatePolygonCmd)
}

// meDrawingCreatePolygonCmd implements
// `dcs-sms me drawing create-polygon --vertices "n1,e1;n2,e2;..." [...]`.
//
// Free-shape polygon (closed, filled). For analytic shapes (circle,
// rect, oval, arrow) use the dedicated create-* verbs which take
// dimension fields instead of explicit vertices.
func meDrawingCreatePolygonCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing create-polygon", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagVertices   = fs.String("vertices", "",
			"vertices as \"n1,e1;n2,e2;...\" (>= 3 absolute world-meter pairs)")
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
	if *flagVertices == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-polygon: --vertices is required")
		return 2
	}
	verticesLua, err := parseVerticesToLua(*flagVertices)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-polygon:", err)
		return 2
	}

	colorLua, err := parseDrawingColorToHex(*flagColor, 0xFF)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-polygon:", err)
		return 2
	}
	fillLua, err := parseDrawingColorToHex(*flagFillColor, 0x80)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-polygon:", err)
		return 2
	}

	parts := []string{
		"vertices = " + verticesLua,
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

	resp, exitCode := runMeVerb("drawing_create_polygon", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
