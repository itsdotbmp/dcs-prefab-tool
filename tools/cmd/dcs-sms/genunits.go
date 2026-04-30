package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/nielsvaes/dcs-sms/tools/internal/genunits"
)

func init() {
	register("gen-units", genUnitsCmd)
}

// genUnitsCmd runs the units/statics catalog generator. Exit codes:
//
//	0 — success; framework/units.lua + framework/statics.lua written.
//	1 — generator error (parse, emit, or validation failed).
//	2 — flag parse error or required path missing.
func genUnitsCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("gen-units", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagDatamine := fs.String("datamine", "", "path to dcs-lua-datamine repo (default: $DCS_LUA_DATAMINE_PATH or D:/git/dcs-lua-datamine)")
	flagOutDir := fs.String("out-dir", "", "where to write units.lua/statics.lua (default: ./framework relative to cwd)")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	datamine := *flagDatamine
	if datamine == "" {
		datamine = os.Getenv("DCS_LUA_DATAMINE_PATH")
	}
	if datamine == "" {
		datamine = "D:/git/dcs-lua-datamine"
	}

	outDir := *flagOutDir
	if outDir == "" {
		// Default: ./framework relative to cwd
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintln(stderr, "dcs-sms gen-units: cannot determine cwd:", err)
			return 2
		}
		outDir = filepath.Join(cwd, "framework")
	}

	if _, err := os.Stat(datamine); err != nil {
		fmt.Fprintln(stderr, "dcs-sms gen-units: datamine path not found:", datamine)
		return 2
	}
	if _, err := os.Stat(outDir); err != nil {
		fmt.Fprintln(stderr, "dcs-sms gen-units: out-dir not found:", outDir)
		return 2
	}

	u, s, err := genunits.Run(genunits.Options{
		DatamineRoot: datamine,
		OutDir:       outDir,
	})
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms gen-units:", err)
		return 1
	}
	fmt.Fprintf(stdout, "wrote %s/units.lua (%d entries) and %s/statics.lua (%d entries)\n", outDir, u, outDir, s)
	return 0
}
