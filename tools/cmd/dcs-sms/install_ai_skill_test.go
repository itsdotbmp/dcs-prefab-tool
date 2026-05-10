package main

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func setFakeHome(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	if runtime.GOOS == "windows" {
		t.Setenv("USERPROFILE", home)
	} else {
		t.Setenv("HOME", home)
	}
	return home
}

func TestInstallAISkill_NoAgentFlag(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := installAISkillCmd(nil, &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
	if !strings.Contains(stderr.String()+stdout.String(), "agent") {
		t.Errorf("expected 'agent' in usage output, got stdout=%q stderr=%q", stdout.String(), stderr.String())
	}
}

func TestInstallAISkill_InvalidAgent(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := installAISkillCmd([]string{"--agent", "foo"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
	if !strings.Contains(stderr.String(), "invalid --agent") {
		t.Errorf("expected error about invalid agent in stderr, got %q", stderr.String())
	}
}

func TestInstallAISkill_Claude_WritesAndReports(t *testing.T) {
	home := setFakeHome(t)
	var stdout, stderr bytes.Buffer
	code := installAISkillCmd([]string{"--agent", "claude"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0; stderr=%q", code, stderr.String())
	}
	want := filepath.Join(home, ".claude", "skills", "dcs-sms", "SKILL.md")
	if _, err := os.Stat(want); err != nil {
		t.Errorf("expected file at %s, got err: %v", want, err)
	}
	if !strings.Contains(stdout.String(), "wrote: ") {
		t.Errorf("expected 'wrote:' in stdout, got %q", stdout.String())
	}
}

func TestInstallAISkill_All_ReportsFourPaths(t *testing.T) {
	_ = setFakeHome(t)
	var stdout, stderr bytes.Buffer
	code := installAISkillCmd([]string{"--agent", "all"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0; stderr=%q", code, stderr.String())
	}
	if c := strings.Count(stdout.String(), "wrote: "); c != 4 {
		t.Errorf("expected 4 'wrote:' lines, got %d in %q", c, stdout.String())
	}
}
