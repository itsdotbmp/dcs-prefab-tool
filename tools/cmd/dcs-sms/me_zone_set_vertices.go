package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("zone", "set-vertices", meZoneSetVerticesCmd)
}

// meZoneSetVerticesCmd implements
// `dcs-sms me zone set-vertices --name|--id <X> --vertices "n1,e1;n2,e2;..."`.
//
// Quad-zone reshape. Reuses the same --vertices string format as
// `me zone create --type quad`. The Lua verb computes a new center (average
// of supplied vertices) and emits relative points + a new position — same
// shape `zone_create_quad` produces, so save+reload behavior is identical.
//
// Refuses to operate on circle zones (those don't have vertices). Use
// set-radius for those.
func meZoneSetVerticesCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone set-vertices", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "zone name (mutually exclusive with --id)")
		flagID         = fs.Int("id", 0, "zone id (mutually exclusive with --name)")
		flagVertices   = fs.String("vertices", "",
			"4 corners as \"n1,e1;n2,e2;n3,e3;n4,e4\" (>= 3 corners actually allowed)")
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
		fmt.Fprintln(stderr, "dcs-sms me zone set-vertices: exactly one of --name or --id is required")
		return 2
	}
	if *flagVertices == "" {
		fmt.Fprintln(stderr, "dcs-sms me zone set-vertices: --vertices is required (\"n1,e1;n2,e2;n3,e3;n4,e4\")")
		return 2
	}
	verticesLua, err := parseVerticesToLua(*flagVertices)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me zone set-vertices:", err)
		return 2
	}

	var idClause string
	if hasName {
		idClause = fmt.Sprintf("name = %q", *flagName)
	} else {
		idClause = fmt.Sprintf("id = %d", *flagID)
	}
	luaArgs := fmt.Sprintf("{ %s, vertices = %s }", idClause, verticesLua)

	resp, exitCode := runMeVerb("zone_set_vertices", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
