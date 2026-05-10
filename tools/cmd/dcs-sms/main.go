package main

import (
	"os"

	"golang.org/x/term"
)

// version is overridden at release-build time via
// `-ldflags="-X main.version=$VERSION"` (see release-me-mod.yml).
// Local `go build` keeps the -dev suffix as a "running an
// unreleased build" signal.
var version = "0.1.1-dev"

func main() {
	args := os.Args[1:]
	interactive := len(args) == 0 && term.IsTerminal(int(os.Stdin.Fd()))
	os.Exit(dispatch(args, os.Stdin, os.Stdout, os.Stderr, interactive))
}
