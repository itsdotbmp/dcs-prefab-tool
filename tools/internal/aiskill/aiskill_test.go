package aiskill

import (
	"os"
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

func TestInstall_Claude_WritesSkill(t *testing.T) {
	home := t.TempDir()
	results := Install(AgentClaude, home)
	if len(results) != 1 {
		t.Fatalf("len(results) = %d, want 1", len(results))
	}
	r := results[0]
	if r.Agent != AgentClaude {
		t.Errorf("Agent = %q, want claude", r.Agent)
	}
	if len(r.Errors) != 0 {
		t.Fatalf("unexpected errors: %v", r.Errors)
	}
	want := filepath.Join(home, ".claude", "skills", "dcs-sms", "SKILL.md")
	if !equalSlices(r.Paths, []string{want}) {
		t.Errorf("Paths = %v, want [%s]", r.Paths, want)
	}
	data, err := os.ReadFile(want)
	if err != nil {
		t.Fatalf("could not read written file: %v", err)
	}
	if !strings.HasPrefix(string(data), "---\nname: dcs-sms\n") {
		t.Errorf("written file should start with YAML frontmatter")
	}
}

func TestInstall_Codex_WritesSkill(t *testing.T) {
	home := t.TempDir()
	results := Install(AgentCodex, home)
	if len(results[0].Errors) != 0 {
		t.Fatalf("unexpected errors: %v", results[0].Errors)
	}
	want := filepath.Join(home, ".agents", "skills", "dcs-sms", "SKILL.md")
	if _, err := os.Stat(want); err != nil {
		t.Fatalf("expected file at %s, got err: %v", want, err)
	}
}

func TestInstall_Gemini_WritesBothFiles(t *testing.T) {
	home := t.TempDir()
	results := Install(AgentGemini, home)
	if len(results[0].Errors) != 0 {
		t.Fatalf("unexpected errors: %v", results[0].Errors)
	}
	wantTOML := filepath.Join(home, ".gemini", "commands", "dcs-sms.toml")
	wantSkill := filepath.Join(home, ".gemini", "skills", "dcs-sms", "SKILL.md")

	tomlData, err := os.ReadFile(wantTOML)
	if err != nil {
		t.Fatalf("expected TOML at %s, got err: %v", wantTOML, err)
	}
	if !strings.HasPrefix(string(tomlData), "description = ") {
		t.Errorf("TOML should start with `description = `")
	}
	if _, err := os.Stat(wantSkill); err != nil {
		t.Errorf("expected skill at %s, got err: %v", wantSkill, err)
	}
}

func TestInstall_All_WritesAllAgents(t *testing.T) {
	home := t.TempDir()
	results := Install(AgentAll, home)
	if len(results) != 3 {
		t.Fatalf("len(results) = %d, want 3 (claude/codex/gemini)", len(results))
	}
	for _, r := range results {
		if len(r.Errors) != 0 {
			t.Errorf("agent %q had errors: %v", r.Agent, r.Errors)
		}
	}
	// Total of 4 files written (claude=1, codex=1, gemini=2).
	total := 0
	for _, r := range results {
		total += len(r.Paths)
	}
	if total != 4 {
		t.Errorf("total written files = %d, want 4", total)
	}
}

func TestInstall_Idempotent_OverwritesQuietly(t *testing.T) {
	home := t.TempDir()
	first := Install(AgentClaude, home)
	if len(first[0].Errors) != 0 {
		t.Fatalf("first install errors: %v", first[0].Errors)
	}
	// Mutate the file so we can detect the overwrite.
	target := first[0].Paths[0]
	if err := os.WriteFile(target, []byte("STALE\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	second := Install(AgentClaude, home)
	if len(second[0].Errors) != 0 {
		t.Fatalf("second install errors: %v", second[0].Errors)
	}
	data, _ := os.ReadFile(target)
	if string(data) == "STALE\n" {
		t.Errorf("re-install did not overwrite stale content")
	}
}

func TestInstall_All_PartialFailureContinues(t *testing.T) {
	home := t.TempDir()
	// Sabotage Codex by creating a regular file where the .agents directory
	// must be created — MkdirAll will fail for that agent.
	if err := os.WriteFile(filepath.Join(home, ".agents"), []byte("blocker"), 0o644); err != nil {
		t.Fatal(err)
	}
	results := Install(AgentAll, home)
	if len(results) != 3 {
		t.Fatalf("len(results) = %d, want 3", len(results))
	}
	var codexFailed, claudeOK, geminiOK bool
	for _, r := range results {
		switch r.Agent {
		case AgentCodex:
			if len(r.Errors) == 0 {
				t.Errorf("expected Codex install to fail with .agents blocked")
			}
			codexFailed = true
		case AgentClaude:
			if len(r.Errors) == 0 {
				claudeOK = true
			}
		case AgentGemini:
			if len(r.Errors) == 0 {
				geminiOK = true
			}
		}
	}
	if !codexFailed || !claudeOK || !geminiOK {
		t.Errorf("expected Codex to fail and the other two to succeed; got codexFailed=%v claudeOK=%v geminiOK=%v", codexFailed, claudeOK, geminiOK)
	}
}
