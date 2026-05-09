package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("group", "create-helicopter", meGroupCreateHelicopterCmd)
}

// meGroupCreateHelicopterCmd implements
// `dcs-sms me group create-helicopter --country <c> --type <t> --north --east [...]`.
//
// Same structural shape as create-plane (single unit, single waypoint with
// empty ComboTask, save-survives via Mission.fixWaypointForGroup), but with
// helo-typical defaults: lower altitude, slower speed, lower frequency.
func meGroupCreateHelicopterCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group create-helicopter", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagCountry    = fs.String("country", "", "country in current mission (e.g. USA, Russia)")
		flagType       = fs.String("type", "", "airframe id (e.g. UH-60L, Mi-8MT)")
		flagNorth      = fs.Float64("north", 0, "meters north of theatre origin")
		flagEast       = fs.Float64("east", 0, "meters east of theatre origin")
		flagName       = fs.String("name", "", "group name (auto-allocated if empty)")
		flagAlt        = fs.Float64("alt", 1000, "altitude in meters above sea level")
		flagAltType    = fs.String("alt-type", "BARO", "altitude reference: BARO or RADIO")
		flagSpeed      = fs.Float64("speed", 50, "speed in m/s")
		flagHeading    = fs.Float64("heading", 0, "heading in radians")
		flagSkill      = fs.String("skill", "Average", "AI skill")
		flagLivery     = fs.String("livery", "", "livery id")
		flagFreq       = fs.Float64("frequency", 127.5, "radio frequency MHz")
		flagOnboard    = fs.String("onboard-num", "010", "onboard number")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagCountry == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-helicopter: --country is required")
		return 2
	}
	if *flagType == "" {
		fmt.Fprintln(stderr, "dcs-sms me group create-helicopter: --type is required")
		return 2
	}

	luaArgs := fmt.Sprintf(
		"{ country = %q, type = %q, north = %g, east = %g, name = %q, "+
			"alt = %g, alt_type = %q, speed = %g, heading = %g, "+
			"skill = %q, livery = %q, frequency = %g, onboard_num = %q }",
		*flagCountry, *flagType, *flagNorth, *flagEast, *flagName,
		*flagAlt, *flagAltType, *flagSpeed, *flagHeading,
		*flagSkill, *flagLivery, *flagFreq, *flagOnboard,
	)

	resp, exitCode := runMeVerb("group_create_helicopter", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
