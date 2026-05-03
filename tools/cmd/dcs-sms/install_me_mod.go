package main

import (
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
	memod "github.com/nielsvaes/dcs-sms/tools/me-mod/lua"
)

func init() {
	register("install-me-mod", installMeModCmd)
}

const meModBackupSuffix = ".dcs-sms.bak"

func installMeModCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("install-me-mod", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagDCSPath := fs.String("dcs-path", "", "override DCS install path")
	flagNoSave := fs.Bool("no-config-save", false, "do not persist --dcs-path to config")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	cfg, _ := dcspath.DefaultConfigPath()
	install, err := dcspath.DiscoverInstall(*flagDCSPath, cfg)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-me-mod:", err)
		return 3
	}

	// Sanity check: <install>/MissionEditor/MissionEditor.lua must exist.
	meDir := filepath.Join(install, "MissionEditor")
	meFile := filepath.Join(meDir, "MissionEditor.lua")
	if _, err := os.Stat(meFile); err != nil {
		fmt.Fprintf(stderr, "dcs-sms install-me-mod: %s not found (is --dcs-path correct?)\n", meFile)
		return 3
	}

	// Step 1: copy module files.
	moduleDst := filepath.Join(meDir, "modules", memod.ModuleDirName)
	if err := os.MkdirAll(moduleDst, 0o755); err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-me-mod: mkdir modules:", err)
		return 3
	}
	if err := copyEmbedDir(memod.FS, memod.ModuleDirName, moduleDst); err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-me-mod: copy modules:", err)
		return 3
	}
	fmt.Fprintf(stdout, "copied %s/* → %s\n", memod.ModuleDirName, moduleDst)

	// Step 2: patch MissionEditor.lua (idempotent).
	meSrc, err := os.ReadFile(meFile)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-me-mod: read ME file:", err)
		return 3
	}
	if bytes.Contains(meSrc, []byte(memod.RequireBeginMarker)) {
		fmt.Fprintf(stdout, "patch already present in %s, skipping\n", meFile)
	} else {
		backup := meFile + meModBackupSuffix
		if _, err := os.Stat(backup); err == nil {
			fmt.Fprintf(stderr,
				"dcs-sms install-me-mod: refusing to overwrite existing backup %s\n"+
					"  (run `dcs-sms uninstall-me-mod` first, or remove the .bak manually)\n",
				backup)
			return 3
		} else if !errors.Is(err, os.ErrNotExist) {
			fmt.Fprintln(stderr, "dcs-sms install-me-mod: stat backup:", err)
			return 3
		}
		if err := os.WriteFile(backup, meSrc, 0o644); err != nil {
			fmt.Fprintln(stderr, "dcs-sms install-me-mod: write backup:", err)
			return 3
		}
		patched := append(meSrc, []byte(memod.PatchBlock)...)
		if err := os.WriteFile(meFile, patched, 0o644); err != nil {
			fmt.Fprintln(stderr, "dcs-sms install-me-mod: write ME file:", err)
			return 3
		}
		fmt.Fprintf(stdout, "patched %s (backup: %s)\n", meFile, backup)
	}

	// Step 3: cache --dcs-path to config (unless --no-config-save).
	if *flagDCSPath != "" && !*flagNoSave {
		if cfg != "" {
			if err := dcspath.SaveInstallConfig(cfg, *flagDCSPath); err != nil {
				fmt.Fprintln(stderr, "dcs-sms install-me-mod: warning: could not save config:", err)
			} else {
				fmt.Fprintf(stdout, "saved dcs_install = %q to %s\n", *flagDCSPath, cfg)
			}
		}
	}

	fmt.Fprintln(stdout, "")
	fmt.Fprintln(stdout, "Install complete. Open the Mission Editor; the dcs-sms ME window should appear in the upper right.")
	return 0
}

// copyEmbedDir walks an embed.FS subtree and writes every file to dstDir,
// preserving the relative directory structure under srcSubdir.
func copyEmbedDir(efs fs.FS, srcSubdir, dstDir string) error {
	return fs.WalkDir(efs, srcSubdir, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel := strings.TrimPrefix(path, srcSubdir)
		rel = strings.TrimPrefix(rel, "/")
		target := filepath.Join(dstDir, filepath.FromSlash(rel))
		if d.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		data, err := fs.ReadFile(efs, path)
		if err != nil {
			return fmt.Errorf("read %s: %w", path, err)
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		return os.WriteFile(target, data, 0o644)
	})
}
