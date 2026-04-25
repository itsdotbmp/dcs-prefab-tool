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
	code := installHookCmd(nil, &stdout, &stderr)
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
	code := installHookCmd(nil, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	data, _ := os.ReadFile(hookPath)
	if string(data) == "OLD" {
		t.Error("expected hook file to be overwritten")
	}
}
