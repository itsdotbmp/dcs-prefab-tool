package main

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
	"github.com/nielsvaes/dcs-sms/tools/internal/elevate"
)

// menuActions holds the subcommand handlers the menu invokes. Exposed
// as a struct so tests can stub them without touching real DCS install
// paths or AI-agent config dirs.
type menuActions struct {
	setup            commandFunc
	teardown         commandFunc
	installAISkill   commandFunc
	uninstallAISkill commandFunc
}

// menuDeps bundles every external dependency the menu needs.
type menuDeps struct {
	actions    menuActions
	configPath string                    // empty → resolved from dcspath.DefaultConfigPath()
	reExec     func(args []string) error // nil → real elevate.ReExecElevated
}

func defaultMenuDeps() menuDeps {
	cfg, _ := dcspath.DefaultConfigPath()
	return menuDeps{
		actions: menuActions{
			setup:            setupCmd,
			teardown:         teardownCmd,
			installAISkill:   installAISkillCmd,
			uninstallAISkill: uninstallAISkillCmd,
		},
		configPath: cfg,
		reExec:     elevate.ReExecElevated,
	}
}

// runInteractiveMenu drives the no-args double-click menu. Reads choices
// from stdin, dispatches options 1-5, and exits on `q`. Three invalid
// inputs in a row return exit code 2 to guard against a closed stdin.
func runInteractiveMenu(stdin io.Reader, stdout, stderr io.Writer) int {
	return runInteractiveMenuWith(stdin, stdout, stderr, defaultMenuDeps())
}

func runInteractiveMenuWith(stdin io.Reader, stdout, stderr io.Writer, deps menuDeps) int {
	if deps.reExec == nil {
		deps.reExec = elevate.ReExecElevated
	}
	reader := bufio.NewReader(stdin)
	invalidStreak := 0
	const maxInvalid = 3

	for {
		printMenuBanner(stdout, deps)
		fmt.Fprint(stdout, "Choose [1/2/3/4/5/q]: ")
		line, err := reader.ReadString('\n')
		if err != nil && line == "" {
			fmt.Fprintln(stderr, "dcs-sms: no input received")
			return 2
		}
		choice := strings.ToLower(strings.TrimSpace(line))
		switch choice {
		case "q", "quit", "exit":
			return 0
		case "1":
			return runActionWithElevation(reader, stdout, stderr, deps, deps.actions.setup,
				[]string{"setup", "--skip-update"})
		case "2":
			return runActionWithElevation(reader, stdout, stderr, deps, deps.actions.teardown,
				[]string{"teardown"})
		case "3":
			return runActionAndPause(reader, stdout, stderr, func(_ []string, so, se io.Writer) int {
				return deps.actions.installAISkill([]string{"--agent", "all"}, so, se)
			})
		case "4":
			return runActionAndPause(reader, stdout, stderr, func(_ []string, so, se io.Writer) int {
				return deps.actions.uninstallAISkill([]string{"--agent", "all"}, so, se)
			})
		case "5":
			promptAndSaveDCSPath(reader, stdout, stderr, deps.configPath)
			invalidStreak = 0
			continue
		default:
			invalidStreak++
			if invalidStreak >= maxInvalid {
				fmt.Fprintln(stderr, "dcs-sms: too many invalid inputs")
				return 2
			}
			fmt.Fprintf(stdout, "Unknown choice %q.\n", choice)
		}
	}
}

// runActionWithElevation calls action and pauses for Enter. If action
// returns elevate.ExitCodeNeedsElevation, the menu prompts the user
// y/N to re-launch as admin via deps.reExec; on yes, it spawns the
// elevated child with reExecArgs and exits.
//
// Caveat: env vars like DCS_SMS_SAVED_GAMES / DCS_SMS_DCS_INSTALL are
// NOT inherited by the elevated child (Windows UAC spawns a fresh
// cmd.exe process with no env inheritance from this process). The
// child relies on its own config-file lookup. Users who need a path
// other than what's in `%AppData%\dcs-sms\config.toml` should set it
// via the menu's "Set DCS install path" option (which writes config)
// before triggering the elevation prompt — or run `dcs-sms setup`
// directly from an already-elevated terminal.
func runActionWithElevation(reader *bufio.Reader, stdout, stderr io.Writer, deps menuDeps, action commandFunc, reExecArgs []string) int {
	code := action(nil, stdout, stderr)
	if code == elevate.ExitCodeNeedsElevation {
		if promptElevationYesNo(reader, stdout) {
			if err := deps.reExec(reExecArgs); err != nil {
				fmt.Fprintf(stderr, "dcs-sms: could not re-launch as admin: %v\n", err)
				fmt.Fprintln(stdout)
				fmt.Fprint(stdout, "Press Enter to exit...")
				_, _ = reader.ReadString('\n')
				return 3
			}
			fmt.Fprintln(stdout)
			fmt.Fprintln(stdout, "Elevated install started in a new window. This window will close.")
			return 0
		}
		fmt.Fprintln(stdout)
		fmt.Fprintln(stdout, "Skipped. Re-run dcs-sms.exe from an admin terminal if you want to install.")
	}
	// Pause unconditionally so the user can read the action's output (or
	// the "Skipped" message above) before the console window closes.
	fmt.Fprintln(stdout)
	fmt.Fprint(stdout, "Press Enter to exit...")
	_, _ = reader.ReadString('\n')
	return code
}

func promptElevationYesNo(reader *bufio.Reader, stdout io.Writer) bool {
	fmt.Fprintln(stdout)
	fmt.Fprintln(stdout, "This operation needs admin permission (DCS install dir is not writable).")
	fmt.Fprint(stdout, "Re-launch with admin permission? [y/N]: ")
	line, _ := reader.ReadString('\n')
	ans := strings.ToLower(strings.TrimSpace(line))
	return ans == "y" || ans == "yes"
}

func runActionAndPause(reader *bufio.Reader, stdout, stderr io.Writer, action commandFunc) int {
	code := action(nil, stdout, stderr)
	fmt.Fprintln(stdout)
	fmt.Fprint(stdout, "Press Enter to exit...")
	_, _ = reader.ReadString('\n')
	return code
}

func printMenuBanner(w io.Writer, deps menuDeps) {
	fmt.Fprintln(w)
	fmt.Fprintf(w, "DCS-SMS  v%s\n", version)
	fmt.Fprintln(w)
	fmt.Fprintln(w, "  "+dcsInstallLine(deps))
	fmt.Fprintln(w)
	fmt.Fprintln(w, "  1. Install or update DCS-SMS (mod + hook + .exe)")
	fmt.Fprintln(w, "     └─ Not sure what to pick? Pick this. It makes sure you have the latest of everything.")
	fmt.Fprintln(w, "  2. Uninstall DCS-SMS (mod + hook)")
	fmt.Fprintln(w, "  3. Install AI agent skill (Claude + Codex + Gemini)")
	fmt.Fprintln(w, "  4. Uninstall AI agent skill (Claude + Codex + Gemini)")
	fmt.Fprintln(w, "  5. Set DCS install path manually")
	fmt.Fprintln(w, "  q. Quit")
	fmt.Fprintln(w)
}

func dcsInstallLine(deps menuDeps) string {
	path, err := dcspath.DiscoverInstall("", deps.configPath)
	if err != nil || path == "" {
		return "DCS install: not detected — pick option 5 to set it"
	}
	return "DCS install: " + path
}

const maxPathAttempts = 2

// promptAndSaveDCSPath asks the user to paste their DCS install folder.
func promptAndSaveDCSPath(reader *bufio.Reader, stdout, stderr io.Writer, configPath string) {
	for attempt := 0; attempt < maxPathAttempts; attempt++ {
		fmt.Fprintln(stdout)
		fmt.Fprintln(stdout, `Paste your DCS install folder (the one containing MissionEditor\MissionEditor.lua).`)
		fmt.Fprintln(stdout, `Quotes are fine, they'll be stripped.`)
		fmt.Fprint(stdout, "> ")
		line, err := reader.ReadString('\n')
		if err != nil && line == "" {
			fmt.Fprintln(stderr, "dcs-sms: no path entered")
			return
		}
		path := dcspath.SanitizeUserPath(line)
		if path == "" {
			fmt.Fprintln(stdout, "Empty path — try again.")
			continue
		}
		if err := validateDCSInstallRoot(path); err != nil {
			fmt.Fprintf(stdout, "%v\n", err)
			continue
		}
		if configPath == "" {
			fmt.Fprintln(stderr, "dcs-sms: cannot determine config file location; not saving")
			return
		}
		if err := dcspath.SaveInstallConfig(configPath, filepath.ToSlash(path)); err != nil {
			fmt.Fprintf(stderr, "dcs-sms: failed to save config: %v\n", err)
			return
		}
		fmt.Fprintln(stdout, "Saved.")
		return
	}
	fmt.Fprintln(stdout, "Returning to menu without saving.")
}

func validateDCSInstallRoot(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("path does not exist: %s", path)
		}
		return fmt.Errorf("could not stat %s: %v", path, err)
	}
	if !info.IsDir() {
		return fmt.Errorf("not a directory: %s", path)
	}
	meFile := filepath.Join(path, "MissionEditor", "MissionEditor.lua")
	if _, err := os.Stat(meFile); err != nil {
		return fmt.Errorf("MissionEditor.lua not found at %s — is this really the DCS install root?", meFile)
	}
	return nil
}
