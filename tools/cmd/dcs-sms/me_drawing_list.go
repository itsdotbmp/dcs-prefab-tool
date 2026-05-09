package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("drawing", "list", meDrawingListCmd)
}

// meDrawingListCmd implements `dcs-sms me drawing list [filters]`.
//
// Returns concise summaries of all drawings across all 5 layers
// (Red / Blue / Neutral / Common / Author). Optional filters narrow by
// layer, primitive type, polygon/line sub-mode, or substring name match.
func meDrawingListCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing list", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagLayer      = fs.String("layer", "", "Red | Blue | Neutral | Common | Author")
		flagType       = fs.String("type", "", "Line | Polygon | TextBox | Icon")
		flagMode       = fs.String("mode", "", "circle | oval | rect | free | arrow | segments | segment")
		flagName       = fs.String("name", "", "name substring (case-insensitive)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	var parts []string
	if *flagLayer != "" {
		parts = append(parts, fmt.Sprintf("layer = %q", *flagLayer))
	}
	if *flagType != "" {
		parts = append(parts, fmt.Sprintf("type = %q", *flagType))
	}
	if *flagMode != "" {
		parts = append(parts, fmt.Sprintf("mode = %q", *flagMode))
	}
	if *flagName != "" {
		parts = append(parts, fmt.Sprintf("name = %q", *flagName))
	}
	luaArgs := "{ " + strings.Join(parts, ", ") + " }"

	resp, exitCode := runMeVerb("drawing_list", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
