package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInstallHookWritesFile(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := installHookCmd([]string{"--no-config-save"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, want 0; stderr=%s", code, stderr.String())
	}
	hookPath := filepath.Join(root, "Scripts", "Hooks", "dcs-sms-hook.lua")
	data, err := os.ReadFile(hookPath)
	if err != nil {
		t.Fatalf("expected hook file at %s: %v", hookPath, err)
	}
	if !strings.Contains(string(data), "DCS_SMS") {
		t.Errorf("hook file does not look like the embedded source")
	}
}

func TestInstallHookOverwritesExisting(t *testing.T) {
	root := t.TempDir()
	hookDir := filepath.Join(root, "Scripts", "Hooks")
	_ = os.MkdirAll(hookDir, 0o755)
	hookPath := filepath.Join(hookDir, "dcs-sms-hook.lua")
	if err := os.WriteFile(hookPath, []byte("OLD"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := installHookCmd([]string{"--no-config-save"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	data, _ := os.ReadFile(hookPath)
	if string(data) == "OLD" {
		t.Error("expected hook file to be overwritten")
	}
}

func TestInstallHook_PatchesMissionScriptingWhenDCSPathPassed(t *testing.T) {
	savedGames := t.TempDir()
	t.Setenv("DCS_SMS_SAVED_GAMES", savedGames)

	dcsInstall := t.TempDir()
	scriptsDir := filepath.Join(dcsInstall, "Scripts")
	if err := os.MkdirAll(scriptsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	msPath := filepath.Join(scriptsDir, "MissionScripting.lua")
	original := "do\n\tsanitizeModule('os')\n\tsanitizeModule('io')\n\tsanitizeModule('lfs')\nend\n"
	if err := os.WriteFile(msPath, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}

	var stdout, stderr bytes.Buffer
	code := installHookCmd([]string{"--no-config-save", "--dcs-path", dcsInstall}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, stderr=%s", code, stderr.String())
	}
	got, _ := os.ReadFile(msPath)
	for _, mod := range []string{"os", "io", "lfs"} {
		want := "-- sanitizeModule('" + mod + "')  -- dcs-sms"
		if !strings.Contains(string(got), want) {
			t.Errorf("expected %q in patched file, got: %s", want, got)
		}
	}
	if !strings.Contains(stdout.String(), "commented out sanitizeModule") {
		t.Errorf("expected patch message in stdout, got: %s", stdout.String())
	}
	// Backup created on first patch.
	if _, err := os.Stat(msPath + missionScriptingBackupSuffix); err != nil {
		t.Errorf("backup not created: %v", err)
	}
}

func TestInstallHook_NoDCSPathPrintsSkipNote(t *testing.T) {
	savedGames := t.TempDir()
	t.Setenv("DCS_SMS_SAVED_GAMES", savedGames)

	var stdout, stderr bytes.Buffer
	code := installHookCmd([]string{"--no-config-save"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, stderr=%s", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "Skipping MissionScripting.lua patch") {
		t.Errorf("expected a 'Skipping MissionScripting.lua patch' notice in stdout, got: %s", stdout.String())
	}
	if !strings.Contains(stdout.String(), "--dcs-path not set") {
		t.Errorf("expected the skip note to explain why (--dcs-path not set), got: %s", stdout.String())
	}
}
