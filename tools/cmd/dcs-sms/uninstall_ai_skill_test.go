package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUninstallAISkill_NoAgentFlag(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := uninstallAISkillCmd(nil, &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
}

func TestUninstallAISkill_InvalidAgent(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := uninstallAISkillCmd([]string{"--agent", "foo"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
}

func TestUninstallAISkill_AfterInstall_RemovesAndReports(t *testing.T) {
	home := setFakeHome(t)
	var stdout, stderr bytes.Buffer
	if code := installAISkillCmd([]string{"--agent", "claude"}, &stdout, &stderr); code != 0 {
		t.Fatalf("setup install failed: %d %q", code, stderr.String())
	}
	stdout.Reset()
	stderr.Reset()
	code := uninstallAISkillCmd([]string{"--agent", "claude"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0; stderr=%q", code, stderr.String())
	}
	target := filepath.Join(home, ".claude", "skills", "dcs-sms", "SKILL.md")
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Errorf("expected file removed, got err: %v", err)
	}
	if !strings.Contains(stdout.String(), "removed: ") {
		t.Errorf("expected 'removed:' in stdout, got %q", stdout.String())
	}
}

func TestUninstallAISkill_MissingFiles_ReportsNotPresent(t *testing.T) {
	_ = setFakeHome(t)
	var stdout, stderr bytes.Buffer
	code := uninstallAISkillCmd([]string{"--agent", "claude"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d on clean home, want 0; stderr=%q", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "not present: ") {
		t.Errorf("expected 'not present:' in stdout, got %q", stdout.String())
	}
}
