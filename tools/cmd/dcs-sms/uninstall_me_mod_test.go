package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// reuse newFakeInstall from install_me_mod_test.go (same package).

func installFirst(t *testing.T) string {
	t.Helper()
	install := newFakeInstall(t)
	var stdout, stderr bytes.Buffer
	if code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr); code != 0 {
		t.Fatalf("install setup failed: %s", stderr.String())
	}
	return install
}

func TestUninstallMeMod_RemovesMarkerBlockSurgically(t *testing.T) {
	install := installFirst(t)
	var stdout, stderr bytes.Buffer
	if code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr); code != 0 {
		t.Fatalf("uninstall exit %d, stderr: %s", code, stderr.String())
	}
	me, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))
	if strings.Contains(string(me), "dcs-sms-me-mod") || strings.Contains(string(me), "require('dcs_sms_me')") {
		t.Fatalf("patch markers still present after uninstall: %s", me)
	}
	if !strings.Contains(string(me), "original ME bootstrap") {
		t.Fatalf("original content lost: %s", me)
	}
}

func TestUninstallMeMod_RemovesModuleDir(t *testing.T) {
	install := installFirst(t)
	var stdout, stderr bytes.Buffer
	if code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr); code != 0 {
		t.Fatalf("uninstall exit %d, stderr: %s", code, stderr.String())
	}
	if _, err := os.Stat(filepath.Join(install, "MissionEditor", "modules", "dcs_sms_me")); !os.IsNotExist(err) {
		t.Fatalf("module dir still exists: %v", err)
	}
}

func TestUninstallMeMod_RemovesBackupFile(t *testing.T) {
	install := installFirst(t)
	var stdout, stderr bytes.Buffer
	if code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr); code != 0 {
		t.Fatalf("uninstall exit %d, stderr: %s", code, stderr.String())
	}
	if _, err := os.Stat(filepath.Join(install, "MissionEditor", "MissionEditor.lua.dcs-sms.bak")); !os.IsNotExist(err) {
		t.Fatalf("backup file still exists: %v", err)
	}
}

func TestUninstallMeMod_FallsBackToBackupWhenMarkersMissing(t *testing.T) {
	install := installFirst(t)
	// Simulate a user manually editing MissionEditor.lua and stripping markers
	// but leaving "require('dcs_sms_me')" mangled.
	meFile := filepath.Join(install, "MissionEditor", "MissionEditor.lua")
	if err := os.WriteFile(meFile, []byte("-- corrupted by user\nrequire('dcs_sms_me')\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	if code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr); code != 0 {
		t.Fatalf("uninstall exit %d, stderr: %s", code, stderr.String())
	}
	me, _ := os.ReadFile(meFile)
	if !strings.Contains(string(me), "original ME bootstrap") {
		t.Fatalf("backup-restore failed: %s", me)
	}
	if strings.Contains(string(me), "corrupted by user") {
		t.Fatalf("backup-restore did not overwrite corrupted file: %s", me)
	}
}

func TestUninstallMeMod_NoOpWhenNothingInstalled(t *testing.T) {
	install := newFakeInstall(t)
	var stdout, stderr bytes.Buffer
	code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("uninstall on clean install should succeed, exit %d, stderr: %s", code, stderr.String())
	}
	// Original file untouched.
	me, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))
	if !strings.Contains(string(me), "original ME bootstrap") {
		t.Fatalf("original content lost: %s", me)
	}
}
