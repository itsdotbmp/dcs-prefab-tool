package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "create-plane", meGroupCreatePlaneCmd)
}

// meGroupCreatePlaneCmd implements
// `dcs-sms me group create-plane --country <c> --type <t> --north <m> --east <m> [...]`.
//
// Synthesizes and injects a single-unit fixed-wing aircraft group at
// the given map position, single waypoint at the spawn point with an empty
// ComboTask. Survives save (runs Mission.fixWaypointForGroup), is fully
// selectable in the ME, and runs in mission. Sequence implemented in
// dcs_sms_me/verbs.lua follows the canonical 11-step injection from
// research/me-bridge-discovery-2026-05-08.md.
//
// Coordinates: --north is meters north of theatre origin (north positive),
// --east is meters east (east positive), --alt is altitude above sea level.
// We use north/east because DCS's internal naming is contradictory — the
// mission table stores the ground as (x = N–S, y = E–W) while the runtime 3D
// engine uses (x = N–S, y = altitude, z = E–W). See the comment block at the
// top of verbs.lua for the full rationale.
//
// Country must already exist in the mission's coalition tree — `me file new
// --map <theatre>` sets DCS defaults that include the usual Red/Blue
// countries for that theatre.
func meGroupCreatePlaneCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group create-plane", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagCountry    = fs.String("country", "", "country name in current mission (e.g. USA, Russia)")
		flagType       = fs.String("type", "", "airframe id (e.g. F-16C_50, Su-27)")
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin (north positive)")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin (east positive)")
		flagName       = fs.String("name", "", "group name (auto-allocated if empty)")
		flagAlt        = fs.Float64("alt", 8000, "altitude in meters above sea level")
		flagAltType    = fs.String("alt-type", "BARO", "altitude reference: BARO or RADIO")
		flagSpeed      = fs.Float64("speed", 220, "speed in m/s")
		flagHeading    = fs.Float64("heading", 0, "heading in radians")
		flagSkill      = fs.String("skill", "Average", "AI skill: Average, Good, High, Excellent, Random, Player")
		flagLivery     = fs.String("livery", "", "livery id ('' = default)")
		flagFreq       = fs.Float64("frequency", 251, "radio frequency MHz")
		flagOnboard    = fs.String("onboard-num", "010", "onboard number (display only)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagCountry == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-plane: --country is required")
		return 2
	}
	if *flagType == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-plane: --type is required")
		return 2
	}
	// north/east default to 0; we don't reject (0,0) because some theatres
	// have meaningful origin near 0,0.

	luaArgs := fmt.Sprintf(
		"{ country = %q, type = %q, north = %g, east = %g, name = %q, "+
			"alt = %g, alt_type = %q, speed = %g, heading = %g, "+
			"skill = %q, livery = %q, frequency = %g, onboard_num = %q }",
		*flagCountry, *flagType, *flagNorth, *flagEast, *flagName,
		*flagAlt, *flagAltType, *flagSpeed, *flagHeading,
		*flagSkill, *flagLivery, *flagFreq, *flagOnboard,
	)

	resp, exitCode := runMeVerb("group_create_plane", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
