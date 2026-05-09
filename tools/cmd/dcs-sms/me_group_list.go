package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("group", "list", meGroupListCmd)
}

// meGroupListCmd implements `dcs-sms me group list [--side --country --category --name]`.
//
// Returns concise group summaries. All filter flags are optional and AND-combined.
// For full mission-table detail of one group, use `me group get`.
func meGroupListCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group list", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagSide       = fs.String("side", "", "filter by side: red | blue | neutrals")
		flagCountry    = fs.String("country", "", "filter by country (case-insensitive exact match)")
		flagCategory   = fs.String("category", "", "filter by category: plane | helicopter | vehicle | ship | static")
		flagName       = fs.String("name", "", "filter by group-name substring (case-insensitive)")
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
	if *flagName != "" {
		parts = append(parts, fmt.Sprintf("name = %q", *flagName))
	}
	luaArgs := "{ " + strings.Join(parts, ", ") + " }"

	resp, exitCode := runMeVerb("group_list", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
