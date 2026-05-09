package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("drawing", "set-angle", meDrawingSetAngleCmd)
}

// meDrawingSetAngleCmd implements
// `dcs-sms me drawing set-angle --name <X> --angle <degrees>`.
//
// Rotates a drawing around its anchor. Supported shapes: TextBox, Icon,
// and Polygon (oval / rect / arrow). Line, Polygon-circle (rotation
// symmetric), and Polygon-free (would need per-point transform) are
// refused with a clear error.
//
// Angle is in degrees (CW positive). Internally converted to radians
// via math.rad — saveToMission's `angle` field is radians, so this
// keeps the on-disk format consistent.
func meDrawingSetAngleCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing set-angle", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "drawing name")
		flagAngle      = fs.Float64("angle", 0, "rotation in degrees (CW positive)")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-angle: --name is required")
		return 2
	}
	angleSet := false
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "angle" {
			angleSet = true
		}
	})
	if !angleSet {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-angle: --angle is required (degrees)")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, angle_deg = %g }", *flagName, *flagAngle)

	resp, exitCode := runMeVerb("drawing_set_angle", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
