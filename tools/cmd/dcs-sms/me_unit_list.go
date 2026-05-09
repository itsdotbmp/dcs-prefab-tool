package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("unit", "list", meUnitListCmd)
}

// meUnitListCmd implements `dcs-sms me unit list [filters]`.
func meUnitListCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me unit list", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagSide       = fs.String("side", "", "filter by side: red | blue | neutrals")
		flagCountry    = fs.String("country", "", "filter by country (case-insensitive exact match)")
		flagCategory   = fs.String("category", "", "filter by category: plane | helicopter | vehicle | ship | static")
		flagGroup      = fs.String("group", "", "filter by group name (exact match)")
		flagName       = fs.String("name", "", "filter by unit-name substring (case-insensitive)")
		flagType       = fs.String("type", "", "filter by airframe / unit type (exact, e.g. F-16C_50)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	var parts []string
	if *flagSide != "" {
		parts = append(parts, fmt.Sprintf("side = %q", strings.ToLower(*flagSide)))
	}
	if *flagCountry != "" {
		parts = append(parts, fmt.Sprintf("country = %q", *flagCountry))
	}
	if *flagCategory != "" {
		parts = append(parts, fmt.Sprintf("category = %q", strings.ToLower(*flagCategory)))
	}
	if *flagGroup != "" {
		parts = append(parts, fmt.Sprintf("group = %q", *flagGroup))
	}
	if *flagName != "" {
		parts = append(parts, fmt.Sprintf("name = %q", *flagName))
	}
	if *flagType != "" {
		parts = append(parts, fmt.Sprintf("type = %q", *flagType))
	}
	luaArgs := "{ " + strings.Join(parts, ", ") + " }"

	resp, exitCode := runMeVerb("unit_list", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
