package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// helper: build a fake DCS install dir and return its path.
func newFakeInstall(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	me := filepath.Join(root, "MissionEditor")
	if err := os.MkdirAll(filepath.Join(me, "modules"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(me, "MissionEditor.lua"),
		[]byte("-- original ME bootstrap\nlocal x = 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestInstallMeMod_CopiesModuleFiles(t *testing.T) {
	install := newFakeInstall(t)
	var stdout, stderr bytes.Buffer
	code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, stderr: %s", code, stderr.String())
	}
	moduleDir := filepath.Join(install, "MissionEditor", "modules", "dcs_sms_me")
	for _, name := range []string{"init.lua", "window.lua", "selection.lua", "serializer.lua", "paths.lua"} {
		p := filepath.Join(moduleDir, name)
		if info, err := os.Stat(p); err != nil || info.Size() == 0 {
			t.Errorf("expected %s present and non-empty: %v", p, err)
		}
	}
}

func TestInstallMeMod_PatchesAndBacksUp(t *testing.T) {
	install := newFakeInstall(t)
	var stdout, stderr bytes.Buffer
	if code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr); code != 0 {
		t.Fatalf("exit %d, stderr: %s", code, stderr.String())
	}
	bak, err := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua.dcs-sms.bak"))
	if err != nil {
		t.Fatalf("backup not created: %v", err)
	}
	if !strings.Contains(string(bak), "original ME bootstrap") {
		t.Fatalf("backup does not contain original content: %q", bak)
	}
	patched, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))
	if !strings.Contains(string(patched), "-- dcs-sms-me-mod begin") ||
		!strings.Contains(string(patched), "require('dcs_sms_me')") ||
		!strings.Contains(string(patched), "-- dcs-sms-me-mod end") {
		t.Fatalf("patched MissionEditor.lua missing markers/require: %s", patched)
	}
	if !strings.Contains(string(patched), "original ME bootstrap") {
		t.Fatalf("original content lost from MissionEditor.lua: %s", patched)
	}
}

func TestInstallMeMod_RefusesIfBackupExists(t *testing.T) {
	install := newFakeInstall(t)
	// Simulate a stale backup from a previous incomplete uninstall.
	if err := os.WriteFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua.dcs-sms.bak"),
		[]byte("stale"), 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr)
	if code == 0 {
		t.Fatal("expected non-zero exit when backup already exists")
	}
	if !strings.Contains(stderr.String(), "backup") {
		t.Fatalf("stderr should mention backup, got: %s", stderr.String())
	}
}

func TestInstallMeMod_Idempotent_ReinstallPreservesPatch(t *testing.T) {
	install := newFakeInstall(t)
	var stdout, stderr bytes.Buffer
	if code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr); code != 0 {
		t.Fatalf("first install exit %d, stderr: %s", code, stderr.String())
	}
	firstPatched, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))

	// Second run: should NOT add a second require line, should NOT touch the
	// existing backup, should still re-copy module files.
	stdout.Reset()
	stderr.Reset()
	if code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr); code != 0 {
		t.Fatalf("re-install exit %d, stderr: %s", code, stderr.String())
	}
	secondPatched, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))
	if !bytes.Equal(firstPatched, secondPatched) {
		t.Fatalf("MissionEditor.lua changed on re-install:\n--- first:\n%s\n--- second:\n%s",
			firstPatched, secondPatched)
	}
	// Module files should still exist.
	if _, err := os.Stat(filepath.Join(install, "MissionEditor", "modules", "dcs_sms_me", "init.lua")); err != nil {
		t.Fatalf("module file missing after re-install: %v", err)
	}
}
