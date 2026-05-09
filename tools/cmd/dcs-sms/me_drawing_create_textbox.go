package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("drawing", "create-textbox", meDrawingCreateTextboxCmd)
}

// meDrawingCreateTextboxCmd implements
// `dcs-sms me drawing create-textbox --north <m> --east <m> --text <S> [...]`.
//
// Text label drawn at a map point. The text color (--color) is the
// foreground (default green opaque, matching the ME's own new-textbox
// default), --fill-color is the background (default red 50% alpha).
// Default font is DejaVuLGCSansCondensed.ttf — same one the ME uses
// internally for new textboxes.
func meDrawingCreateTextboxCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing create-textbox", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin (textbox anchor)")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin (textbox anchor)")
		flagText       = fs.String("text", "", "text content")
		flagFontSize   = fs.Int("font-size", 0, "font size in pixels (default 24)")
		flagBorder     = fs.Int("border-thickness", -1, "border thickness in pixels (default 4)")
		flagAngle      = fs.Float64("angle", 0, "rotation in radians")
		flagFont       = fs.String("font", "", "font ttf filename (default DejaVuLGCSansCondensed.ttf)")
		flagName       = fs.String("name", "", "drawing name (auto-allocated if empty)")
		flagColor      = fs.String("color", "", "text color (default green, opaque)")
		flagFillColor  = fs.String("fill-color", "", "background fill (default red, half alpha)")
		flagLayer      = fs.String("layer", "", "Red|Blue|Neutral|Common|Author (default Common)")
		flagHiddenPln  = fs.Bool("hidden-on-planner", false, "hide on mission planner")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagText == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-textbox: --text is required")
		return 2
	}

	colorLua, err := parseDrawingColorToHex(*flagColor, 0xFF)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-textbox:", err)
		return 2
	}
	fillLua, err := parseDrawingColorToHex(*flagFillColor, 0x80)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-textbox:", err)
		return 2
	}

	parts := []string{
		fmt.Sprintf("north = %g", *flagNorth),
		fmt.Sprintf("east = %g", *flagEast),
		fmt.Sprintf("text = %q", *flagText),
		fmt.Sprintf("angle = %g", *flagAngle),
	}
	if *flagFontSize > 0 {
		parts = append(parts, fmt.Sprintf("font_size = %d", *flagFontSize))
	}
	if *flagBorder >= 0 {
		parts = append(parts, fmt.Sprintf("border_thickness = %d", *flagBorder))
	}
	if *flagFont != "" {
		parts = append(parts, fmt.Sprintf("font = %q", *flagFont))
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
	if *flagLayer != "" {
		parts = append(parts, fmt.Sprintf("layer = %q", *flagLayer))
	}
	if *flagHiddenPln {
		parts = append(parts, "hidden_on_planner = true")
	}
	luaArgs := "{ " + strings.Join(parts, ", ") + " }"

	resp, exitCode := runMeVerb("drawing_create_textbox", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
