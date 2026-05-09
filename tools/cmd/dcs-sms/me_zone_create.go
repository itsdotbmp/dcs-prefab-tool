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
		flagColor      = fs.String("color", "",
			"color: name (red/green/blue/yellow/cyan/magenta/white/black/orange/purple), "+
				"hex \"#rrggbb\" (alpha 0.15), or \"#rrggbbaa\"; default = translucent white")
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

	colorLua, err := parseColorToLua(*flagColor)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me zone create:", err)
		return 2
	}
	colorClause := ""
	if colorLua != "" {
		colorClause = ", color = " + colorLua
	}

	switch strings.ToLower(*flagType) {
	case "circle":
		if *flagRadius <= 0 {
			fmt.Fprintln(stderr, "dcs-sms me zone create --type circle: --radius is required (> 0)")
			return 2
		}
		luaArgs := fmt.Sprintf(
			"{ name = %q, north = %g, east = %g, radius = %g, hidden = %t%s }",
			*flagName, *flagNorth, *flagEast, *flagRadius, *flagHidden, colorClause,
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
			"{ name = %q, vertices = %s, radius = %g, hidden = %t%s }",
			*flagName, verticesLua, *flagRadius, *flagHidden, colorClause,
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

// namedZoneColors holds the named-color presets we accept for --color.
// All defaults use alpha = 0.15 (matches DCS's default translucent fill, set
// by TriggerZone.construct in MissionEditor/modules/Mission/TriggerZone.lua).
// User can override alpha via #rrggbbaa hex.
var namedZoneColors = map[string][4]float64{
	"red":     {1, 0, 0, 0.15},
	"green":   {0, 1, 0, 0.15},
	"blue":    {0, 0, 1, 0.15},
	"yellow":  {1, 1, 0, 0.15},
	"cyan":    {0, 1, 1, 0.15},
	"magenta": {1, 0, 1, 0.15},
	"white":   {1, 1, 1, 0.15},
	"black":   {0, 0, 0, 0.15},
	"orange":  {1, 0.5, 0, 0.15},
	"purple":  {0.5, 0, 1, 0.15},
}

// parseColorToLua converts the --color flag value to a "{r, g, b, a}" Lua
// table expression with floats 0..1. Returns "" if the flag is empty (caller
// should then omit the color clause and let the Lua verb apply the default).
//
// Accepts:
//   - named: red, green, blue, yellow, cyan, magenta, white, black, orange, purple
//   - "#rrggbb"   — alpha defaults to 0.15
//   - "#rrggbbaa" — explicit alpha
//   - hex without "#" prefix is also accepted
func parseColorToLua(s string) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", nil
	}
	if rgba, ok := namedZoneColors[strings.ToLower(s)]; ok {
		return fmt.Sprintf("{ %g, %g, %g, %g }", rgba[0], rgba[1], rgba[2], rgba[3]), nil
	}
	hex := strings.TrimPrefix(s, "#")
	switch len(hex) {
	case 6, 8:
	default:
		return "", fmt.Errorf("--color %q: expected name or #rrggbb / #rrggbbaa", s)
	}
	r, err := strconv.ParseUint(hex[0:2], 16, 8)
	if err != nil {
		return "", fmt.Errorf("--color %q: invalid red byte: %w", s, err)
	}
	g, err := strconv.ParseUint(hex[2:4], 16, 8)
	if err != nil {
		return "", fmt.Errorf("--color %q: invalid green byte: %w", s, err)
	}
	b, err := strconv.ParseUint(hex[4:6], 16, 8)
	if err != nil {
		return "", fmt.Errorf("--color %q: invalid blue byte: %w", s, err)
	}
	a := uint64(38) // 0.15 * 255 ≈ 38; preserves the DCS-default alpha when only RGB is given
	if len(hex) == 8 {
		av, err := strconv.ParseUint(hex[6:8], 16, 8)
		if err != nil {
			return "", fmt.Errorf("--color %q: invalid alpha byte: %w", s, err)
		}
		a = av
	}
	rf := float64(r) / 255
	gf := float64(g) / 255
	bf := float64(b) / 255
	af := float64(a) / 255
	if len(hex) == 6 {
		af = 0.15 // exact DCS default rather than 38/255
	}
	return fmt.Sprintf("{ %g, %g, %g, %g }", rf, gf, bf, af), nil
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
