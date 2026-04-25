package main

import (
	"fmt"
	"os"
)

const version = "0.1.0-dev"

func main() {
	if len(os.Args) >= 2 && (os.Args[1] == "--version" || os.Args[1] == "version") {
		fmt.Println(version)
		return
	}
	fmt.Fprintln(os.Stderr, "dcs-sms — Digital Combat Simulator scripting bridge")
	fmt.Fprintln(os.Stderr, "Usage: dcs-sms <command> [flags]")
	fmt.Fprintln(os.Stderr, "Commands: exec, status, tail-log, install-hook (coming in later tasks)")
	os.Exit(2)
}
