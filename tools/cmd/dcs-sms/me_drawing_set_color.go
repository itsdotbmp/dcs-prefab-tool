package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("drawing", "set-color", meDrawingSetColorCmd)
}

// meDrawingSetColorCmd implements
// `dcs-sms me drawing set-color --name <X> --color <c>`.
//
// Changes the colorString field on the drawing (outline / line / text
// color depending on shape — for fills use set-fill-color). Color
// accepts the same shapes as create-* `--color`: name, "#rrggbb",
// "#rrggbbaa". Default alpha 0xFF.
func meDrawingSetColorCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing set-color", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "drawing name")
		flagColor      = fs.String("color", "", "color: name, #rrggbb, or #rrggbbaa")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-color: --name is required")
		return 2
	}
	if *flagColor == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-color: --color is required")
		return 2
	}
	colorLua, err := parseDrawingColorToHex(*flagColor, 0xFF)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-color:", err)
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, color = %s }", *flagName, colorLua)

	resp, exitCode := runMeVerb("drawing_set_color", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
