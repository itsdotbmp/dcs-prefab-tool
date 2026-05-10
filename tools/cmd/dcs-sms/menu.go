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

// menuActions holds the subcommand handlers the menu invokes. Exposed as
// a struct so tests can stub them without touching real DCS install paths
// or AI-agent config dirs.
type menuActions struct {
	install          commandFunc
	uninstall        commandFunc
	update           commandFunc
	installAISkill   commandFunc
	uninstallAISkill commandFunc
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
			install:          installMeModCmd,
			uninstall:        uninstallMeModCmd,
			update:           updateCmd,
			installAISkill:   installAISkillCmd,
			uninstallAISkill: uninstallAISkillCmd,
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
			return runActionAndPause(reader, stdout, stderr, deps.actions.install)
		case "2":
			return runActionAndPause(reader, stdout, stderr, deps.actions.uninstall)
		case "3":
			return runActionAndPause(reader, stdout, stderr, deps.actions.update)
		case "4":
			promptAndSaveDCSPath(reader, stdout, stderr, deps.configPath)
			invalidStreak = 0
			continue
		case "5":
			if code, didAct := runAISkillSubMenu(reader, stdout, stderr, deps); didAct {
				return code
			}
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
	fmt.Fprintln(w, "  5. Install AI agent skill (Claude / Codex / Gemini)")
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

// runAISkillSubMenu drives option 5: pick an agent, then pick install or
// uninstall. Returns (exitCode, true) if an action was invoked (caller
// should propagate the exit code and exit the binary, matching the
// post-action behavior of options 1/2/3). Returns (0, false) if the user
// cancelled at any sub-prompt or hit three invalid inputs in a row —
// caller should redraw the main menu.
func runAISkillSubMenu(reader *bufio.Reader, stdout, stderr io.Writer, deps menuDeps) (int, bool) {
	const maxInvalid = 3

	// 1. Agent picker.
	var agentSlug string
	invalidStreak := 0
	for {
		fmt.Fprintln(stdout)
		fmt.Fprintln(stdout, "Which agent?")
		fmt.Fprintln(stdout, "  a. Claude Code  (~/.claude/skills/dcs-sms/)")
		fmt.Fprintln(stdout, "  b. Codex CLI    (~/.agents/skills/dcs-sms/)")
		fmt.Fprintln(stdout, "  c. Gemini CLI   (~/.gemini/commands/dcs-sms.toml + ~/.gemini/skills/dcs-sms/)")
		fmt.Fprintln(stdout, "  d. All three")
		fmt.Fprintln(stdout, "  q. Cancel")
		fmt.Fprintln(stdout)
		fmt.Fprint(stdout, "Choose [a/b/c/d/q]: ")
		line, err := reader.ReadString('\n')
		if err != nil && line == "" {
			return 0, false
		}
		choice := strings.ToLower(strings.TrimSpace(line))
		switch choice {
		case "q", "quit", "cancel":
			return 0, false
		case "a":
			agentSlug = "claude"
		case "b":
			agentSlug = "codex"
		case "c":
			agentSlug = "gemini"
		case "d":
			agentSlug = "all"
		default:
			invalidStreak++
			if invalidStreak >= maxInvalid {
				fmt.Fprintln(stdout, "Returning to main menu.")
				return 0, false
			}
			fmt.Fprintf(stdout, "Unknown choice %q.\n", choice)
			continue
		}
		break
	}

	// 2. Install-or-uninstall picker.
	var action commandFunc
	invalidStreak = 0
	for {
		fmt.Fprintln(stdout)
		fmt.Fprintln(stdout, "Install or Uninstall?")
		fmt.Fprintln(stdout, "  i. Install (overwrite if present)")
		fmt.Fprintln(stdout, "  u. Uninstall")
		fmt.Fprintln(stdout, "  q. Cancel")
		fmt.Fprintln(stdout)
		fmt.Fprint(stdout, "Choose [i/u/q]: ")
		line, err := reader.ReadString('\n')
		if err != nil && line == "" {
			return 0, false
		}
		choice := strings.ToLower(strings.TrimSpace(line))
		switch choice {
		case "q", "quit", "cancel":
			return 0, false
		case "i":
			action = deps.actions.installAISkill
		case "u":
			action = deps.actions.uninstallAISkill
		default:
			invalidStreak++
			if invalidStreak >= maxInvalid {
				fmt.Fprintln(stdout, "Returning to main menu.")
				return 0, false
			}
			fmt.Fprintf(stdout, "Unknown choice %q.\n", choice)
			continue
		}
		break
	}

	// 3. Run the chosen action with --agent <slug> and pause for Enter.
	code := runActionAndPause(reader, stdout, stderr, func(_ []string, stdout, stderr io.Writer) int {
		return action([]string{"--agent", agentSlug}, stdout, stderr)
	})
	return code, true
}
