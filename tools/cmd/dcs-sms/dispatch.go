package main

import (
	"fmt"
	"io"
)

// commandFunc is the signature for every subcommand. It receives the args
// after the subcommand name (so for `dcs-sms exec --file foo.lua`,
// argsAfterCmd would be ["--file", "foo.lua"]). It returns an OS exit code.
type commandFunc func(argsAfterCmd []string, stdout, stderr io.Writer) int

// commands maps subcommand names to their handlers. Subcommands register
// themselves here in init() blocks across cmd/dcs-sms/*.go.
var commands = map[string]commandFunc{}

func register(name string, fn commandFunc) {
	if _, exists := commands[name]; exists {
		panic("duplicate command registration: " + name)
	}
	commands[name] = fn
}

// dispatch routes args[0] (subcommand name) to its handler. With no args,
// behavior depends on `interactive`: a real terminal gets the menu; a
// piped/scripted stdin gets today's "print usage + exit 2" behavior.
func dispatch(args []string, stdin io.Reader, stdout, stderr io.Writer, interactive bool) int {
	if len(args) == 0 {
		if interactive {
			return runInteractiveMenu(stdin, stdout, stderr)
		}
		printUsage(stderr)
		return 2
	}
	switch args[0] {
	case "--version", "-v", "version":
		fmt.Fprintln(stdout, version)
		return 0
	case "--help", "-h", "help":
		printUsage(stdout)
		return 0
	}
	cmd, ok := commands[args[0]]
	if !ok {
		fmt.Fprintf(stderr, "dcs-sms: unknown command %q\n", args[0])
		printUsage(stderr)
		return 2
	}
	return cmd(args[1:], stdout, stderr)
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, "dcs-sms — Digital Combat Simulator scripting bridge")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Usage: dcs-sms <command> [flags]")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Commands:")
	fmt.Fprintln(w, "  exec          execute a Lua snippet inside the running mission")
	fmt.Fprintln(w, "  status        report whether the hook is alive and a mission is loaded")
	fmt.Fprintln(w, "  tail-log      read recent lines from dcs.log")
	fmt.Fprintln(w, "  install-hook  install/update the Lua hook in Saved Games/DCS*/Scripts/Hooks/")
	fmt.Fprintln(w, "  install-me-mod   install/update the Mission Editor mod into <DCS install>/MissionEditor/")
	fmt.Fprintln(w, "  uninstall-me-mod remove the Mission Editor mod (revert MissionEditor.lua, delete modules)")
	fmt.Fprintln(w, "  install-ai-skill   write a 'dcs-sms' skill into ~/.claude / ~/.agents / ~/.gemini")
	fmt.Fprintln(w, "  uninstall-ai-skill remove the 'dcs-sms' skill from one or all AI agent config dirs")
	fmt.Fprintln(w, "  gen-units     regenerate framework/constants/{units,statics}.lua from dcs-lua-datamine")
	fmt.Fprintln(w, "  update        download the latest dcs-sms.exe from GitHub and replace this binary")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Run `dcs-sms <command> --help` for command-specific flags.")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Tip: double-click dcs-sms.exe (or run with no arguments from a real terminal)")
	fmt.Fprintln(w, "for an interactive install/uninstall/update menu.")
}
