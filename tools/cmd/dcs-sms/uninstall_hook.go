package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
)

type uninstallHookOpts struct {
	SavedGames string
	DCSPath    string
}

func uninstallHookFlags() (*flag.FlagSet, *uninstallHookOpts) {
	opts := &uninstallHookOpts{}
	fs := flag.NewFlagSet("uninstall-hook", flag.ContinueOnError)
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	fs.StringVar(&opts.DCSPath, "dcs-path", "", "DCS install path (used to revert the MissionScripting.lua patch)")
	return fs, opts
}

func init() {
	registerInfo("uninstall-hook", cmdInfo{
		Run:      uninstallHookCmd,
		Flags:    flagsOnly(uninstallHookFlags),
		Synopsis: "remove the Lua hook + revert the MissionScripting.lua patch",
	})
}

func uninstallHookCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := uninstallHookFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(opts.SavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms uninstall-hook:", err)
		return 3
	}
	dst := filepath.Join(root, "Scripts", "Hooks", "dcs-sms-hook.lua")
	err = os.Remove(dst)
	switch {
	case err == nil:
		fmt.Fprintf(stdout, "removed %s\n", dst)
	case errors.Is(err, os.ErrNotExist):
		fmt.Fprintf(stdout, "not present: %s\n", dst)
	default:
		fmt.Fprintln(stderr, "dcs-sms uninstall-hook: remove:", err)
		return 3
	}

	tryUnpatchMissionScripting(opts.DCSPath, stdout, stderr)
	return 0
}

// tryUnpatchMissionScripting reverts any dcs-sms-tagged comments in the
// DCS install's MissionScripting.lua. Best-effort: silently skips if the
// DCS install path can't be resolved or the file doesn't exist (uninstall
// is best-effort, and the user might not have ever installed against
// this DCS path).
func tryUnpatchMissionScripting(dcsPathOverride string, stdout, stderr io.Writer) {
	cfgPath, _ := dcspath.DefaultConfigPath()
	install, err := dcspath.DiscoverInstall(dcsPathOverride, cfgPath)
	if err != nil || install == "" {
		return
	}
	msPath := filepath.Join(install, "Scripts", "MissionScripting.lua")
	if _, err := os.Stat(msPath); err != nil {
		return
	}
	result, err := unpatchMissionScripting(msPath)
	if err != nil {
		fmt.Fprintf(stderr, "dcs-sms uninstall-hook: revert %s: %v\n", msPath, err)
		return
	}
	if len(result.Changed) > 0 {
		fmt.Fprintf(stdout, "reverted MissionScripting.lua: re-enabled sanitizeModule(%s)\n",
			strings.Join(result.Changed, ", "))
	}
}
