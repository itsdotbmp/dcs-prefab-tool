package main

import (
	"flag"
	"fmt"
	"io"
	"time"
)

type meUnitGetOpts struct {
	Name       string
	ID         int
	Timeout    time.Duration
	Pretty     bool
	SavedGames string
}

func meUnitGetFlags() (*flag.FlagSet, *meUnitGetOpts) {
	opts := &meUnitGetOpts{}
	fs := flag.NewFlagSet("me unit get", flag.ContinueOnError)
	fs.StringVar(&opts.Name, "name", "", "unit name (exact match)")
	fs.IntVar(&opts.ID, "id", 0, "unitId (numeric)")
	fs.DurationVar(&opts.Timeout, "timeout", 30*time.Second, "wall-clock timeout")
	fs.BoolVar(&opts.Pretty, "pretty", false, "indent JSON output")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	return fs, opts
}

func init() {
	registerMeInfo("unit", "get", cmdInfo{
		Run:      meUnitGetCmd,
		Flags:    flagsOnly(meUnitGetFlags),
		Synopsis: "return full data for a unit by name or id",
	})
}

// meUnitGetCmd implements `dcs-sms me unit get --name <n> | --id <n>`.
func meUnitGetCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := meUnitGetFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	hasName := opts.Name != ""
	hasID := opts.ID != 0
	if hasName == hasID {
		fmt.Fprintln(stderr, "dcs-sms me unit get: pass exactly one of --name or --id")
		return 2
	}
	var luaArgs string
	if hasName {
		luaArgs = fmt.Sprintf("{ name = %q }", opts.Name)
	} else {
		luaArgs = fmt.Sprintf("{ id = %d }", opts.ID)
	}
	resp, exitCode := runMeVerb("unit_get", luaArgs, opts.Timeout, opts.SavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	return emitMeResponse(resp, opts.Pretty, stdout)
}
