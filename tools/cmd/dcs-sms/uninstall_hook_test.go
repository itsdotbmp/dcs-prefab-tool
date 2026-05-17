package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// makeFakeSavedGames returns a tmp dir with Scripts/Hooks/dcs-sms-hook.lua
// pre-populated, mimicking a previously-installed hook.
func makeFakeSavedGames(t *testing.T, withHook bool) string {
	t.Helper()
	root := t.TempDir()
	hooks := filepath.Join(root, "Scripts", "Hooks")
	if err := os.MkdirAll(hooks, 0o755); err != nil {
		t.Fatal(err)
	}
	if withHook {
		if err := os.WriteFile(filepath.Join(hooks, "dcs-sms-hook.lua"),
			[]byte("-- stub hook\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestUninstallHook_RemovesFile(t *testing.T) {
	root := makeFakeSavedGames(t, true)
	var stdout, stderr bytes.Buffer
	code := uninstallHookCmd([]string{"--saved-games", root}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, stderr: %s", code, stderr.String())
	}
	hook := filepath.Join(root, "Scripts", "Hooks", "dcs-sms-hook.lua")
	if _, err := os.Stat(hook); !os.IsNotExist(err) {
		t.Errorf("expected hook removed, stat err = %v", err)
	}
	if !strings.Contains(stdout.String(), "removed") {
		t.Errorf("expected 'removed' in stdout, got %q", stdout.String())
	}
}

func TestUninstallHook_NoOpWhenMissing(t *testing.T) {
	root := makeFakeSavedGames(t, false)
	var stdout, stderr bytes.Buffer
	code := uninstallHookCmd([]string{"--saved-games", root}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, stderr: %s", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "not present") {
		t.Errorf("expected 'not present' in stdout, got %q", stdout.String())
	}
}

func TestUninstallHook_RejectsBadFlag(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := uninstallHookCmd([]string{"--bogus"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
}
