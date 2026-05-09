package main

import (
	"bufio"
	"fmt"
	"io"
	"strings"
)

// runInteractiveMenu drives the no-args double-click menu. Reads choices
// from stdin, dispatches options 1/2/3 to install/uninstall/update,
// loops on option 4 (set DCS path), and exits on `q`. Three invalid
// inputs in a row return exit code 2 to guard against a closed stdin.
func runInteractiveMenu(stdin io.Reader, stdout, stderr io.Writer) int {
	reader := bufio.NewReader(stdin)
	invalidStreak := 0
	const maxInvalid = 3

	for {
		printMenuBanner(stdout)
		fmt.Fprint(stdout, "Choose [1/2/3/4/q]: ")
		line, err := reader.ReadString('\n')
		if err != nil && line == "" {
			// EOF or read error with nothing buffered.
			fmt.Fprintln(stderr, "dcs-sms: no input received")
			return 2
		}
		choice := strings.ToLower(strings.TrimSpace(line))
		switch choice {
		case "q", "quit", "exit":
			return 0
		case "1", "2", "3", "4":
			// Action handling lands in Task 3 / Task 5.
			fmt.Fprintln(stdout, "(not yet implemented)")
			return 0
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
