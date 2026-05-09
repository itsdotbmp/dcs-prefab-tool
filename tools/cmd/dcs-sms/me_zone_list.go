package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("zone", "list", meZoneListCmd)
}

// meZoneListCmd implements `dcs-sms me zone list [--shape --name]`.
func meZoneListCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone list", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagShape      = fs.String("shape", "", "filter by shape: circle | quad")
		flagName       = fs.String("name", "", "filter by zone-name substring (case-insensitive)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	var parts []string
	if *flagShape != "" {
		parts = append(parts, fmt.Sprintf("shape = %q", strings.ToLower(*flagShape)))
	}
	if *flagName != "" {
		parts = append(parts, fmt.Sprintf("name = %q", *flagName))
	}
	luaArgs := "{ " + strings.Join(parts, ", ") + " }"

	resp, exitCode := runMeVerb("zone_list", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
