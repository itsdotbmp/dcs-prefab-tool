package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("drawing", "create-icon", meDrawingCreateIconCmd)
}

// meDrawingCreateIconCmd implements
// `dcs-sms me drawing create-icon --north <m> --east <m> --file <F> [...]`.
//
// Icon drawing at a map point. The icon `file` is a filename within
// the active icon folder ('./MissionEditor/data/NewMap/images/<theme>/'
// where theme is 'nato' or 'russian' per the user's options). Pass the
// bare filename (e.g. 'aaa_air_neutral.png'); the runtime resolves the
// theme prefix.
func meDrawingCreateIconCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing create-icon", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin (icon anchor)")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin (icon anchor)")
		flagFile       = fs.String("file", "", "icon filename within the icons folder")
		flagScale      = fs.Float64("scale", 1, "icon scale (default 1)")
		flagAngle      = fs.Float64("angle", 0, "rotation in radians")
		flagName       = fs.String("name", "", "drawing name (auto-allocated if empty)")
		flagColor      = fs.String("color", "", "tint color (default white, opaque)")
		flagLayer      = fs.String("layer", "", "Red|Blue|Neutral|Common|Author (default Common)")
		flagHiddenPln  = fs.Bool("hidden-on-planner", false, "hide on mission planner")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagFile == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-icon: --file is required")
		return 2
	}

	colorLua, err := parseDrawingColorToHex(*flagColor, 0xFF)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing create-icon:", err)
		return 2
	}

	parts := []string{
		fmt.Sprintf("north = %g", *flagNorth),
		fmt.Sprintf("east = %g", *flagEast),
		fmt.Sprintf("file = %q", *flagFile),
		fmt.Sprintf("scale = %g", *flagScale),
		fmt.Sprintf("angle = %g", *flagAngle),
	}
	if *flagName != "" {
		parts = append(parts, fmt.Sprintf("name = %q", *flagName))
	}
	if colorLua != "" {
		parts = append(parts, "color = "+colorLua)
	}
	if *flagLayer != "" {
		parts = append(parts, fmt.Sprintf("layer = %q", *flagLayer))
	}
	if *flagHiddenPln {
		parts = append(parts, "hidden_on_planner = true")
	}
	luaArgs := "{ " + strings.Join(parts, ", ") + " }"

	resp, exitCode := runMeVerb("drawing_create_icon", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
