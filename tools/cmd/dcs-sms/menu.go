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
)

// menuActions holds the three subcommand handlers the menu invokes.
// Exposed as a struct so tests can stub them without touching real DCS
// install paths or network resources.
type menuActions struct {
	install   commandFunc
	uninstall commandFunc
	update    commandFunc
}

// menuDeps bundles every external dependency the menu needs.
type menuDeps struct {
	actions    menuActions
	configPath string // empty → resolved from dcspath.DefaultConfigPath()
}

func defaultMenuDeps() menuDeps {
	cfg, _ := dcspath.DefaultConfigPath()
	return menuDeps{
		actions: menuActions{
			install:   installMeModCmd,
			uninstall: uninstallMeModCmd,
			update:    updateCmd,
		},
		configPath: cfg,
	}
}

// runInteractiveMenu drives the no-args double-click menu. Reads choices
// from stdin, dispatches options 1/2/3 to install/uninstall/update,
// loops on option 4 (set DCS path), and exits on `q`. Three invalid
// inputs in a row return exit code 2 to guard against a closed stdin.
func runInteractiveMenu(stdin io.Reader, stdout, stderr io.Writer) int {
	return runInteractiveMenuWith(stdin, stdout, stderr, defaultMenuDeps())
}

func runInteractiveMenuWith(stdin io.Reader, stdout, stderr io.Writer, deps menuDeps) int {
	reader := bufio.NewReader(stdin)
	invalidStreak := 0
	const maxInvalid = 3

	for {
		printMenuBanner(stdout, deps)
		fmt.Fprint(stdout, "Choose [1/2/3/4/q]: ")
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
			return runActionAndPause(reader, stdout, stderr, deps.actions.install)
		case "2":
			return runActionAndPause(reader, stdout, stderr, deps.actions.uninstall)
		case "3":
			return runActionAndPause(reader, stdout, stderr, deps.actions.update)
		case "4":
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
	fmt.Fprintln(w, "  1. Install DCS-SMS Mission Editor mod")
	fmt.Fprintln(w, "  2. Uninstall DCS-SMS Mission Editor mod")
	fmt.Fprintln(w, "  3. Update dcs-sms.exe")
	fmt.Fprintln(w, "  4. Set DCS install path manually")
	fmt.Fprintln(w, "  q. Quit")
	fmt.Fprintln(w)
}

func dcsInstallLine(deps menuDeps) string {
	path, err := dcspath.DiscoverInstall("", deps.configPath)
	if err != nil || path == "" {
		return "DCS install: not detected — pick option 4 to set it"
	}
	return "DCS install: " + path
}

const maxPathAttempts = 2

// promptAndSaveDCSPath asks the user to paste their DCS install folder.
// On success it persists the (sanitized) path to deps.configPath via
// dcspath.SaveInstallConfig and prints "Saved.". On failure it reprompts
// once; after two failed attempts it returns to the main menu without
// saving.
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
