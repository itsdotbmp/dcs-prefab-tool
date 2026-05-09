package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("drawing", "set-fill-color", meDrawingSetFillColorCmd)
}

// meDrawingSetFillColorCmd implements
// `dcs-sms me drawing set-fill-color --name <X> --color <c>`.
//
// Polygon shapes (circle / rect / oval / arrow / free) and TextBox have a
// fill color. Line and Icon don't — the verb refuses on those. Default
// alpha 0x80 (half) matches create-time defaults.
func meDrawingSetFillColorCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing set-fill-color", flag.ContinueOnError)
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
		fmt.Fprintln(stderr, "dcs-sms me drawing set-fill-color: --name is required")
		return 2
	}
	if *flagColor == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-fill-color: --color is required")
		return 2
	}
	colorLua, err := parseDrawingColorToHex(*flagColor, 0x80)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-fill-color:", err)
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, color = %s }", *flagName, colorLua)

	resp, exitCode := runMeVerb("drawing_set_fill_color", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
