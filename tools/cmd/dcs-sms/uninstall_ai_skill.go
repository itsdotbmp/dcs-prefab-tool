package main

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/nielsvaes/dcs-sms/tools/internal/aiskill"
)

func init() {
	register("uninstall-ai-skill", uninstallAISkillCmd)
}

func uninstallAISkillCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("uninstall-ai-skill", flag.ContinueOnError)
	fs.SetOutput(stderr)
	fs.Usage = func() {
		fmt.Fprintln(stderr, "Usage of uninstall-ai-skill:")
		fmt.Fprintln(stderr, "  --agent string   claude | codex | gemini | all (required)")
	}
	flagAgent := fs.String("agent", "", "claude | codex | gemini | all (required)")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagAgent == "" {
		fs.Usage()
		return 2
	}
	agent, ok := aiskill.ParseAgent(*flagAgent)
	if !ok {
		fmt.Fprintf(stderr, "dcs-sms uninstall-ai-skill: invalid --agent %q (want claude|codex|gemini|all)\n", *flagAgent)
		return 2
	}

	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms uninstall-ai-skill: could not resolve home directory:", err)
		return 3
	}

	// Snapshot which paths existed before removal, so we can distinguish
	// "removed" (was there, now gone) from "not present" (already absent).
	// aiskill.Uninstall does not surface that distinction in its Result.
	existedBefore := map[string]bool{}
	for _, p := range aiskill.Paths(agent, home) {
		if _, statErr := os.Stat(p); statErr == nil {
			existedBefore[p] = true
		}
	}

	results := aiskill.Uninstall(agent, home)
	return printUninstallResults(stdout, stderr, results, existedBefore)
}

// printUninstallResults prints one line per reported path:
//   - "removed: <path>"     when the file existed before uninstall
//   - "not present: <path>" when the file was already absent
//   - "error: <err>"        on a real filesystem error
//
// Returns 0 unless an actual filesystem error occurred (then 3).
func printUninstallResults(stdout, stderr io.Writer, results []aiskill.Result, existedBefore map[string]bool) int {
	hadError := false
	for _, r := range results {
		errPaths := map[string]bool{}
		for _, e := range r.Errors {
			fmt.Fprintln(stderr, "error:", e)
			hadError = true
			errPaths[errorPath(e)] = true
		}
		for _, p := range r.Paths {
			if errPaths[p] {
				continue
			}
			if existedBefore[p] {
				fmt.Fprintf(stdout, "removed: %s\n", p)
			} else {
				fmt.Fprintf(stdout, "not present: %s\n", p)
			}
		}
	}
	if hadError {
		return 3
	}
	return 0
}
