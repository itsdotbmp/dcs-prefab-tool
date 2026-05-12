package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
	memod "github.com/nielsvaes/dcs-sms/tools/me-mod/lua"
)

type uninstallMeModOpts struct {
	DCSPath string
}

func uninstallMeModFlags() (*flag.FlagSet, *uninstallMeModOpts) {
	opts := &uninstallMeModOpts{}
	fs := flag.NewFlagSet("uninstall-me-mod", flag.ContinueOnError)
	fs.StringVar(&opts.DCSPath, "dcs-path", "", "override DCS install path")
	return fs, opts
}

func init() {
	registerInfo("uninstall-me-mod", cmdInfo{
		Run:      uninstallMeModCmd,
		Flags:    flagsOnly(uninstallMeModFlags),
		Synopsis: "remove the Mission Editor mod (revert MissionEditor.lua, delete modules)",
	})
}

func uninstallMeModCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := uninstallMeModFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	cfg, _ := dcspath.DefaultConfigPath()
	install, err := dcspath.DiscoverInstall(opts.DCSPath, cfg)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod:", err)
		return 3
	}

	meDir := filepath.Join(install, "MissionEditor")
	meFile := filepath.Join(meDir, "MissionEditor.lua")
	if _, err := os.Stat(meFile); err != nil {
		fmt.Fprintf(stderr, "dcs-sms uninstall-me-mod: %s not found (is --dcs-path correct?)\n", meFile)
		return 3
	}

	// Step 1: revert MissionEditor.lua. Prefer marker-based surgical removal;
	// fall back to backup-file restore if markers are absent.
	src, err := os.ReadFile(meFile)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: read ME file:", err)
		return 3
	}
	backup := meFile + meModBackupSuffix
	cleaned, removedByMarker := removeMarkerBlock(src, memod.RequireBeginMarker, memod.RequireEndMarker)
	if removedByMarker {
		if err := os.WriteFile(meFile, cleaned, 0o644); err != nil {
			fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: write ME file:", err)
			return 3
		}
		fmt.Fprintf(stdout, "removed patch markers from %s\n", meFile)
	} else if _, err := os.Stat(backup); err == nil {
		bakData, err := os.ReadFile(backup)
		if err != nil {
			fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: read backup:", err)
			return 3
		}
		if err := os.WriteFile(meFile, bakData, 0o644); err != nil {
			fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: restore from backup:", err)
			return 3
		}
		fmt.Fprintf(stdout, "no markers found; restored %s from %s\n", meFile, backup)
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: stat backup:", err)
		return 3
	} else {
		fmt.Fprintf(stdout, "no patch markers and no backup found; %s left untouched\n", meFile)
	}

	// Step 2: delete the modules dir.
	moduleDir := filepath.Join(meDir, "modules", memod.ModuleDirName)
	if err := os.RemoveAll(moduleDir); err != nil {
		fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: remove module dir:", err)
		return 3
	}
	fmt.Fprintf(stdout, "removed %s\n", moduleDir)

	// Step 3: delete the backup file (if present).
	if err := os.Remove(backup); err != nil && !errors.Is(err, os.ErrNotExist) {
		fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: remove backup:", err)
		return 3
	}

	fmt.Fprintln(stdout, "uninstall complete.")
	return 0
}

// removeMarkerBlock returns src with everything from beginMarker through
// endMarker (inclusive, including any leading newline before beginMarker
// and trailing newline after endMarker) removed. The bool indicates whether
// any removal happened.
func removeMarkerBlock(src []byte, beginMarker, endMarker string) ([]byte, bool) {
	beginIdx := bytes.Index(src, []byte(beginMarker))
	if beginIdx < 0 {
		return src, false
	}
	endIdx := bytes.Index(src[beginIdx:], []byte(endMarker))
	if endIdx < 0 {
		return src, false
	}
	endIdx += beginIdx + len(endMarker)
	// Eat one trailing newline if present.
	if endIdx < len(src) && src[endIdx] == '\n' {
		endIdx++
	}
	// Eat one leading newline before the marker if present.
	if beginIdx > 0 && src[beginIdx-1] == '\n' {
		beginIdx--
	}
	out := make([]byte, 0, len(src)-(endIdx-beginIdx))
	out = append(out, src[:beginIdx]...)
	out = append(out, src[endIdx:]...)
	return out, true
}
