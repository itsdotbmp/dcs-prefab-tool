package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("zone", "set-color", meZoneSetColorCmd)
}

// meZoneSetColorCmd implements `dcs-sms me zone set-color --name|--id <X> --color <c>`.
//
// Routes through the same `parseColorToLua` accepted by `me zone create
// --color` (named / hex RGB / hex RGBA). Calls into the Lua verb
// `zone_set_color` which wraps `Mission.TriggerZoneData.setTriggerZoneColor`.
func meZoneSetColorCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone set-color", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "zone name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "zone id (mutually exclusive with --name)")
		flagColor      = fs.String("color", "",
			"color: name (red/green/blue/yellow/cyan/magenta/white/black/orange/purple), "+
				"hex \"#rrggbb\" (alpha 0.15), or \"#rrggbbaa\"")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	hasName := *flagName != ""
	hasID := *flagID != 0
	if hasName == hasID {
		fmt.Fprintln(stderr, "dcs-sms me zone set-color: exactly one of --name or --id is required")
		return 2
	}
	if *flagColor == "" {
		fmt.Fprintln(stderr, "dcs-sms me zone set-color: --color is required")
		return 2
	}
	colorLua, err := parseColorToLua(*flagColor)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me zone set-color:", err)
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, color = %s }", idClause, colorLua)

	resp, exitCode := runMeVerb("zone_set_color", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
