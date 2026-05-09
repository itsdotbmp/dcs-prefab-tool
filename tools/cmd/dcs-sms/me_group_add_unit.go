package main

import (
	"flag"
	"fmt"
	"io"
	"strings"
	"time"
)

func init() {
	registerMe("group", "add-unit", meGroupAddUnitCmd)
}

// meGroupAddUnitCmd implements `dcs-sms me group add-unit --group <X> [...]`.
//
// Adds a unit to an existing group, mirroring the ME UI's "+" button. The
// new unit copies its skill / livery / heading / alt / payload from the
// group's last unit by default (so adding to a 4-ship F-16 flight gives
// you a 5th F-16 with the same load); any field can be overridden with
// the matching flag.
//
// For plane / helicopter groups the new unit's --type must equal
// g.units[1].type — DCS doesn't support heterogeneous air groups. The
// verb refuses on mismatch. For vehicle / ship / static groups, mixed
// types are allowed (Hawk SAM site = PCP + SR + TR + LN).
//
// Position: --offset-north and --offset-east are added to the group
// anchor (g.x / g.y). If neither is passed, Mission.insert_unit's
// default index-cumulative spread (40m south + 40m east per unit) takes
// over — same behaviour as the ME's + button.
//
// IMPORTANT for air groups: per-unit (x, y) is decorative for plane /
// helicopter groups — DCS overrides it at mission load and pins every
// unit to the group's formation_template. The offsets survive in the
// ME view and on disk, but at runtime the flight is laid out by the
// formation, not by what you set here. Vehicle / ship / static groups
// respect per-unit positions verbatim. (A future `me group set-formation`
// would be the right knob for air-group runtime layout.)
func meGroupAddUnitCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me group add-unit", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagGroup       = fs.String("group", "", "group name (mutually exclusive with --group-id)")
		flagGroupID     = fs.Int("group-id", 0, "group id (mutually exclusive with --group)")
		flagType        = fs.String("type", "", "unit type (defaults to last unit's type)")
		flagOffsetN     = fs.Float64("offset-north", 0, "meters north of group anchor (positive = north)")
		flagOffsetE     = fs.Float64("offset-east", 0, "meters east of group anchor (positive = east)")
		flagSkill       = fs.String("skill", "", "AI skill (defaults to last unit's)")
		flagLivery      = fs.String("livery", "", "livery id (defaults to last unit's)")
		flagHeading     = fs.Float64("heading", 0, "heading in degrees (defaults to last unit's)")
		flagAlt         = fs.Float64("alt", 0, "altitude in meters (air only; defaults to last unit's)")
		flagAltType     = fs.String("alt-type", "", "BARO | RADIO (air only; defaults to last unit's)")
		flagOnboardNum  = fs.String("onboard-num", "", "onboard number (insert_unit auto-allocates if empty)")
		flagCallsign    = fs.String("callsign", "", "radio callsign label (auto-allocates if empty)")
		flagFrequency   = fs.Float64("frequency", 0, "frequency MHz (ship only)")
		flagTimeout     = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty      = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames  = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	hasGroup := *flagGroup != ""
	hasGroupID := *flagGroupID != 0
	if hasGroup == hasGroupID {
		fmt.Fprintln(stderr, "dcs-sms me group add-unit: exactly one of --group or --group-id is required")
		return 2
	}

	// Selector clause for the group target.
	var groupClause string
	if hasGroup {
		groupClause = fmt.Sprintf("name = %q", *flagGroup)
	} else {
		groupClause = fmt.Sprintf("id = %d", *flagGroupID)
	}

	// Build the optional-args section. Lua-side handles nil-semantics; we
	// only emit fields the user actually passed (tracked via fs.Visit).
	var parts []string
	parts = append(parts, groupClause)
	visited := map[string]bool{}
	fs.Visit(func(f *flag.Flag) { visited[f.Name] = true })

	if *flagType != "" {
		parts = append(parts, fmt.Sprintf("type = %q", *flagType))
	}
	if visited["offset-north"] {
		parts = append(parts, fmt.Sprintf("offset_north = %g", *flagOffsetN))
	}
	if visited["offset-east"] {
		parts = append(parts, fmt.Sprintf("offset_east = %g", *flagOffsetE))
	}
	if *flagSkill != "" {
		parts = append(parts, fmt.Sprintf("skill = %q", *flagSkill))
	}
	if visited["livery"] {
		// Allow explicit empty string (= "default") via --livery="".
		parts = append(parts, fmt.Sprintf("livery = %q", *flagLivery))
	}
	if visited["heading"] {
		parts = append(parts, fmt.Sprintf("heading_deg = %g", *flagHeading))
	}
	if visited["alt"] {
		parts = append(parts, fmt.Sprintf("alt = %g", *flagAlt))
	}
	if *flagAltType != "" {
		altType := strings.ToUpper(*flagAltType)
		if altType != "BARO" && altType != "RADIO" {
			fmt.Fprintln(stderr, "dcs-sms me group add-unit: --alt-type must be BARO or RADIO")
			return 2
		}
		parts = append(parts, fmt.Sprintf("alt_type = %q", altType))
	}
	if *flagOnboardNum != "" {
		parts = append(parts, fmt.Sprintf("onboard_num = %q", *flagOnboardNum))
	}
	if *flagCallsign != "" {
		parts = append(parts, fmt.Sprintf("callsign = %q", *flagCallsign))
	}
	if visited["frequency"] {
		parts = append(parts, fmt.Sprintf("frequency = %g", *flagFrequency))
	}

	luaArgs := "{ " + strings.Join(parts, ", ") + " }"

	resp, exitCode := runMeVerb("group_add_unit", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
