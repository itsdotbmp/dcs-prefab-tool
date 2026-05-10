package aiskill

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestParseAgent(t *testing.T) {
	cases := []struct {
		in     string
		want   Agent
		wantOK bool
	}{
		{"claude", AgentClaude, true},
		{"codex", AgentCodex, true},
		{"gemini", AgentGemini, true},
		{"all", AgentAll, true},
		{"CLAUDE", AgentClaude, true}, // case-insensitive
		{"foo", "", false},
		{"", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			got, ok := ParseAgent(tc.in)
			if ok != tc.wantOK {
				t.Errorf("ParseAgent(%q) ok = %v, want %v", tc.in, ok, tc.wantOK)
			}
			if got != tc.want {
				t.Errorf("ParseAgent(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}

func TestPaths_Claude(t *testing.T) {
	home := filepath.Join(t.TempDir(), "user")
	got := Paths(AgentClaude, home)
	want := []string{filepath.Join(home, ".claude", "skills", "dcs-sms", "SKILL.md")}
	if !equalSlices(got, want) {
		t.Errorf("Paths(claude) = %v, want %v", got, want)
	}
}

func TestPaths_Codex(t *testing.T) {
	home := filepath.Join(t.TempDir(), "user")
	got := Paths(AgentCodex, home)
	want := []string{filepath.Join(home, ".agents", "skills", "dcs-sms", "SKILL.md")}
	if !equalSlices(got, want) {
		t.Errorf("Paths(codex) = %v, want %v", got, want)
	}
}

func TestPaths_Gemini(t *testing.T) {
	home := filepath.Join(t.TempDir(), "user")
	got := Paths(AgentGemini, home)
	want := []string{
		filepath.Join(home, ".gemini", "commands", "dcs-sms.toml"),
		filepath.Join(home, ".gemini", "skills", "dcs-sms", "SKILL.md"),
	}
	if !equalSlices(got, want) {
		t.Errorf("Paths(gemini) = %v, want %v", got, want)
	}
}

func TestPaths_All_IsUnion(t *testing.T) {
	home := filepath.Join(t.TempDir(), "user")
	got := Paths(AgentAll, home)
	if len(got) != 4 {
		t.Errorf("Paths(all) = %d files, want 4: %v", len(got), got)
	}
	// Spot-check that each per-agent path is present.
	for _, sub := range []string{".claude", ".agents", ".gemini"} {
		var found bool
		for _, p := range got {
			if strings.Contains(p, string(filepath.Separator)+sub+string(filepath.Separator)) {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("Paths(all) missing %s entry: %v", sub, got)
		}
	}
}

func TestPaths_Unknown_ReturnsNil(t *testing.T) {
	got := Paths(Agent("bogus"), "/home/x")
	if got != nil {
		t.Errorf("Paths(bogus) = %v, want nil", got)
	}
}

func equalSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
