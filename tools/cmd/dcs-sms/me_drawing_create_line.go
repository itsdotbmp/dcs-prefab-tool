package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("drawing", "create-line", meDrawingCreateLineCmd)
}

// meDrawingCreateLineCmd implements
// `dcs-sms me drawing create-line --vertices "n1,e1;n2,e2;..." [--closed --line-mode --color ...]`.
//
// Multi-segment line / polyline drawing. The verb computes the center
// (anchor) as the average of the supplied vertices and stores the
// points relative to that center — same convention as
// `me zone create --type quad --vertices`.
func meDrawingCreateLineCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing create-line", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagVertices   = fs.String("vertices", "",
			"vertices as \"n1,e1;n2,e2;...\" (>= 2 absolute world-meter pairs)")
		flagClosed     = fs.Bool("closed", false, "close the polyline back to the first vertex")
		flagLineMode   = fs.String("line-mode", "", "segments | segment | free (default segments)")
		flagName       = fs.String("name", "", "drawing name (auto-allocated if empty)")
		flagColor      = fs.String("color", "", "line color (default red, opaque)")
		flagThickness  = fs.Float64("thickness", 0, "line thickness in pixels (default 2)")
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
		fmt.Fprintln(stderr, "dcs-sms me drawing create-line: --vertices is required")
		return 2
	}
	verticesLua, err := parseVerticesToLua(*flagVertices)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-line:", err)
		return 2
	}

	colorLua, err := parseDrawingColorToHex(*flagColor, 0xFF)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-line:", err)
		return 2
	}

	parts := []string{
		"vertices = " + verticesLua,
	}
	if *flagClosed {
		parts = append(parts, "closed = true")
	}
	if *flagLineMode != "" {
		parts = append(parts, fmt.Sprintf("line_mode = %q", *flagLineMode))
	}
	if *flagName != "" {
		parts = append(parts, fmt.Sprintf("name = %q", *flagName))
	}
	if colorLua != "" {
		parts = append(parts, "color = "+colorLua)
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

	resp, exitCode := runMeVerb("drawing_create_line", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
