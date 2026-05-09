package main

import (
	"flag"
	"fmt"
	"io"
	"strconv"
	"strings"
	"time"
)

func init() {
	registerMe("zone", "create", meZoneCreateCmd)
}

// meZoneCreateCmd implements `dcs-sms me zone create --type circle|quad ...`.
//
// Two shapes share one subcommand because a zone is conceptually one thing
// with a shape variant; the --type flag picks circle (radius around a point)
// or quad (4-vertex polygon).
//
// Coordinates use the project's standard --north / --east meters convention
// (see top of verbs.lua for rationale). Circle takes --north / --east /
// --radius; quad takes --vertices "n1,e1;n2,e2;n3,e3;n4,e4".
func meZoneCreateCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me zone create", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagType       = fs.String("type", "", "shape: circle | quad")
		flagName       = fs.String("name", "", "zone name (uniquified by ME if duplicate)")
		flagNorth      = fs.Float64("north", 0, "circle: meters north of theatre origin (north positive)")
		flagEast       = fs.Float64("east", 0, "circle: meters east of theatre origin (east positive)")
		flagRadius     = fs.Float64("radius", 0, "circle: radius in meters; quad: optional icon radius")
		flagVertices   = fs.String("vertices", "",
			"quad: 4 corners as \"n1,e1;n2,e2;n3,e3;n4,e4\" (>= 3 corners actually allowed)")
		flagHidden     = fs.Bool("hidden", false, "hide the zone in the ME view")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me zone create: --name is required")
		return 2
	}

	switch strings.ToLower(*flagType) {
	case "circle":
		if *flagRadius <= 0 {
			fmt.Fprintln(stderr, "dcs-sms me zone create --type circle: --radius is required (> 0)")
			return 2
		}
		luaArgs := fmt.Sprintf(
			"{ name = %q, north = %g, east = %g, radius = %g, hidden = %t }",
			*flagName, *flagNorth, *flagEast, *flagRadius, *flagHidden,
		)
		resp, exitCode := runMeVerb("zone_create_circle", luaArgs, *flagTimeout, *flagSavedGames, stderr)
		if exitCode != 0 {
			return exitCode
		}
		return emitMeResponse(resp, *flagPretty, stdout)

	case "quad":
		if *flagVertices == "" {
			fmt.Fprintln(stderr, "dcs-sms me zone create --type quad: --vertices is required (\"n1,e1;n2,e2;n3,e3;n4,e4\")")
			return 2
		}
		verticesLua, err := parseVerticesToLua(*flagVertices)
		if err != nil {
			fmt.Fprintln(stderr, "dcs-sms me zone create --type quad:", err)
			return 2
		}
		// --radius is optional for quad; pass 0 → verb computes default.
		luaArgs := fmt.Sprintf(
			"{ name = %q, vertices = %s, radius = %g, hidden = %t }",
			*flagName, verticesLua, *flagRadius, *flagHidden,
		)
		resp, exitCode := runMeVerb("zone_create_quad", luaArgs, *flagTimeout, *flagSavedGames, stderr)
		if exitCode != 0 {
			return exitCode
		}
		return emitMeResponse(resp, *flagPretty, stdout)

	case "":
		fmt.Fprintln(stderr, "dcs-sms me zone create: --type is required (circle | quad)")
		return 2
	default:
		fmt.Fprintf(stderr, "dcs-sms me zone create: unknown --type %q (expected circle or quad)\n", *flagType)
		return 2
	}
}

// parseVerticesToLua converts "n1,e1;n2,e2;n3,e3;n4,e4" into a Lua table
// expression "{ {north=n1,east=e1}, {north=n2,east=e2}, ... }".
func parseVerticesToLua(s string) (string, error) {
	parts := strings.Split(s, ";")
	if len(parts) < 3 {
		return "", fmt.Errorf("--vertices needs >= 3 corner pairs separated by ';' (got %d)", len(parts))
	}
	var b strings.Builder
	b.WriteString("{ ")
	for i, p := range parts {
		coords := strings.Split(strings.TrimSpace(p), ",")
		if len(coords) != 2 {
			return "", fmt.Errorf("vertex %d: expected \"north,east\", got %q", i+1, p)
		}
		north, err := strconv.ParseFloat(strings.TrimSpace(coords[0]), 64)
		if err != nil {
			return "", fmt.Errorf("vertex %d north: %w", i+1, err)
		}
		east, err := strconv.ParseFloat(strings.TrimSpace(coords[1]), 64)
		if err != nil {
			return "", fmt.Errorf("vertex %d east: %w", i+1, err)
		}
		if i > 0 {
			b.WriteString(", ")
		}
		fmt.Fprintf(&b, "{ north = %g, east = %g }", north, east)
	}
	b.WriteString(" }")
	return b.String(), nil
}
