package main

import (
	"bufio"
	"fmt"
	"io"
	"strings"
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
// Future fields (e.g. a config-path override for option 4) live here.
type menuDeps struct {
	actions menuActions
}

func defaultMenuDeps() menuDeps {
	return menuDeps{
		actions: menuActions{
			install:   installMeModCmd,
			uninstall: uninstallMeModCmd,
			update:    updateCmd,
		},
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
		printMenuBanner(stdout)
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
			// Option 4 lands in Task 5.
			fmt.Fprintln(stdout, "(option 4 not yet implemented)")
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

func printMenuBanner(w io.Writer) {
	fmt.Fprintln(w)
	fmt.Fprintf(w, "DCS-SMS  v%s\n", version)
	fmt.Fprintln(w)
	fmt.Fprintln(w, "  1. Install DCS-SMS Mission Editor mod")
	fmt.Fprintln(w, "  2. Uninstall DCS-SMS Mission Editor mod")
	fmt.Fprintln(w, "  3. Update dcs-sms.exe")
	fmt.Fprintln(w, "  4. Set DCS install path manually")
	fmt.Fprintln(w, "  q. Quit")
	fmt.Fprintln(w)
}
