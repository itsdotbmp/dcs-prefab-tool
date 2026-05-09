package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "create", meTriggerCreateCmd)
}

// meTriggerCreateCmd implements
// `dcs-sms me trigger create --type once|continuous|start|front [--name N]`.
//
// Inserts an empty trigger of the given type. Returns its name (auto-
// suffixed on collision). Bundled --condition / --action repeatable
// flags will be added in a later task; for now the trigger is empty
// and the caller composes via add-condition / add-action.
func meTriggerCreateCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger create", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagType       = fs.String("type", "", "trigger type: once|continuous|start|front")
		flagName       = fs.String("name", "", "trigger name (defaults to \"Trigger <epoch>\")")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagType == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger create: --type is required")
		return 2
	}
	luaArgs := fmt.Sprintf("{ [\"type\"] = %q, name = %q }", *flagType, *flagName)
	resp, exitCode := runMeVerb("trigger_create", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, *flagPretty, stdout)
}
