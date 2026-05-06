package main

import "os"

// version is overridden at release-build time via
// `-ldflags="-X main.version=$VERSION"` (see release-me-mod.yml).
// Local `go build` keeps the -dev suffix as a "running an
// unreleased build" signal.
var version = "0.1.0-dev"

func main() {
	os.Exit(dispatch(os.Args[1:], os.Stdout, os.Stderr))
}
