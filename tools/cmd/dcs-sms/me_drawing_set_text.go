package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("drawing", "set-text", meDrawingSetTextCmd)
}

// meDrawingSetTextCmd implements
// `dcs-sms me drawing set-text --name <X> --text <S>`.
//
// TextBox-only setter — refuses on non-TextBox drawings (the rest
// have no text content). To change a textbox's font / fontSize /
// borderThickness / angle, remove + re-create with the new values.
func meDrawingSetTextCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me drawing set-text", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagName       = fs.String("name", "", "drawing name (TextBox only)")
		flagText       = fs.String("text", "", "new text content")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagName == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-text: --name is required")
		return 2
	}
	if *flagText == "" {
		fmt.Fprintln(stderr, "dcs-sms me drawing set-text: --text is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ name = %q, text = %q }", *flagName, *flagText)

	resp, exitCode := runMeVerb("drawing_set_text", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
