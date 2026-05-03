package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
	hookpkg "github.com/nielsvaes/dcs-sms/tools/lua"
)

func init() {
	register("install-hook", installHookCmd)
}

func installHookCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("install-hook", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagSavedGames := fs.String("saved-games", "", "override Saved Games path")
	flagNoSave := fs.Bool("no-config-save", false, "do not persist --saved-games to config")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(*flagSavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-hook:", err)
		return 3
	}
	hooksDir := filepath.Join(root, "Scripts", "Hooks")
	if err := os.MkdirAll(hooksDir, 0o755); err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-hook: mkdir:", err)
		return 3
	}
	dst := filepath.Join(hooksDir, "dcs-sms-hook.lua")
	if err := os.WriteFile(dst, hookpkg.Source, 0o644); err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-hook: write:", err)
		return 3
	}
	fmt.Fprintf(stdout, "installed hook to %s (%d bytes)\n", dst, len(hookpkg.Source))

	if !*flagNoSave {
		if cfg, _ := dcspath.DefaultConfigPath(); cfg != "" {
			if err := dcspath.SaveConfig(cfg, root); err != nil {
				fmt.Fprintln(stderr, "dcs-sms install-hook: warning: could not save config:", err)
			} else {
				fmt.Fprintf(stdout, "saved saved_games = %q to %s\n", root, cfg)
			}
		}
	}

	fmt.Fprintln(stdout, "")
	fmt.Fprintln(stdout, "Next steps:")
	fmt.Fprintln(stdout, "  1. In your DCS install dir, edit Scripts/MissionScripting.lua and comment out")
	fmt.Fprintln(stdout, "     the sanitizeModule('os'), ('io'), and ('lfs') lines so the hook can talk to")
	fmt.Fprintln(stdout, "     the mission environment.")
	fmt.Fprintln(stdout, "  2. Start DCS and load any mission.")
	fmt.Fprintln(stdout, "  3. Run `dcs-sms status` to confirm the hook is alive.")
	return 0
}
