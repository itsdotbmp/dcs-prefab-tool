package main

import (
	"flag"
	"fmt"
	"io"
)

type teardownOpts struct {
	DCSPath    string
	SavedGames string
}

func teardownFlags() (*flag.FlagSet, *teardownOpts) {
	opts := &teardownOpts{}
	fs := flag.NewFlagSet("teardown", flag.ContinueOnError)
	fs.StringVar(&opts.DCSPath, "dcs-path", "", "override DCS install path")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	return fs, opts
}

func init() {
	registerInfo("teardown", cmdInfo{
		Run:      teardownCmd,
		Flags:    flagsOnly(teardownFlags),
		Synopsis: "remove the ME mod and the hook in one shot",
	})
}

type teardownHooks interface {
	uninstallMeMod(args []string, stdout, stderr io.Writer) int
	uninstallHook(args []string, stdout, stderr io.Writer) int
}

type realTeardownHooks struct{}

func (realTeardownHooks) uninstallMeMod(args []string, stdout, stderr io.Writer) int {
	return uninstallMeModCmd(args, stdout, stderr)
}
func (realTeardownHooks) uninstallHook(args []string, stdout, stderr io.Writer) int {
	return uninstallHookCmd(args, stdout, stderr)
}

func teardownCmd(args []string, stdout, stderr io.Writer) int {
	return teardownCmdWith(args, stdout, stderr, realTeardownHooks{})
}

func teardownCmdWith(args []string, stdout, stderr io.Writer, hooks teardownHooks) int {
	fs, opts := teardownFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	// Step 1: uninstall ME mod. uninstall-me-mod only knows --dcs-path.
	var meArgs []string
	if opts.DCSPath != "" {
		meArgs = append(meArgs, "--dcs-path", opts.DCSPath)
	}
	if code := hooks.uninstallMeMod(meArgs, stdout, stderr); code != 0 {
		return code
	}

	// Step 2: uninstall hook (also reverts the MissionScripting.lua patch
	// when --dcs-path is set or discoverable).
	var hookArgs []string
	if opts.SavedGames != "" {
		hookArgs = append(hookArgs, "--saved-games", opts.SavedGames)
	}
	if opts.DCSPath != "" {
		hookArgs = append(hookArgs, "--dcs-path", opts.DCSPath)
	}
	if code := hooks.uninstallHook(hookArgs, stdout, stderr); code != 0 {
		return code
	}

	fmt.Fprintln(stdout, "")
	fmt.Fprintln(stdout, "Teardown complete.")
	return 0
}
