package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "create-static", meGroupCreateStaticCmd)
}

// meGroupCreateStaticCmd implements
// `dcs-sms me group create-static --country <c> --type <t> --north --east [...]`.
//
// Statics are fixed-position, non-AI objects (cargo crates, fortifications,
// warehouses, etc.). They live under country.static.group same as other
// categories but with a minimal shape: one unit, one position, no AI
// behavior. The category flag corresponds to DCS's static class
// ("Cargos" / "Fortifications" / "Warehouses" / "Trucks") — picking the
// wrong one for a given shape may render strangely.
func meGroupCreateStaticCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group create-static", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagCountry    = fs.String("country", "", "country in current mission")
		flagType       = fs.String("type", "", "static id (e.g. \"Container red 1\", \"FARP_Tent\")")
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin")
		flagName       = fs.String("name", "", "group name (auto-allocated if empty)")
		flagHeading    = fs.Float64("heading", 0, "heading in radians")
		flagCategory   = fs.String("category", "Fortifications",
			"static class: Cargos | Fortifications | Warehouses | Trucks")
		flagShapeName  = fs.String("shape-name", "", "model id (often required; varies per static type)")
		flagDead       = fs.Bool("dead", false, "spawn already-destroyed")
		flagCanCargo   = fs.Bool("can-cargo", false, "make cargo-pickup-able by helos")
		flagMass       = fs.Float64("mass", 0, "cargo mass in kg (when --can-cargo)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagCountry == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-static: --country is required")
		return 2
	}
	if *flagType == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-static: --type is required")
		return 2
	}

	luaArgs := fmt.Sprintf(
		"{ country = %q, type = %q, north = %g, east = %g, name = %q, "+
			"heading = %g, category = %q, shape_name = %q, dead = %t, "+
			"can_cargo = %t, mass = %g }",
		*flagCountry, *flagType, *flagNorth, *flagEast, *flagName,
		*flagHeading, *flagCategory, *flagShapeName, *flagDead,
		*flagCanCargo, *flagMass,
	)

	resp, exitCode := runMeVerb("group_create_static", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
