package aiskill

import (
	"strings"
	"testing"
)

func TestSkillMarkdownEmbeddedAndShaped(t *testing.T) {
	s := string(skillMarkdown)
	if !strings.HasPrefix(s, "---\nname: dcs-sms\n") {
		t.Errorf("SKILL.md should start with YAML frontmatter naming the skill; got first 60 bytes: %q", s[:min(60, len(s))])
	}
	if !strings.Contains(s, "Allow External Execution") {
		t.Errorf("SKILL.md should mention the ME External Execution switch")
	}
	if !strings.Contains(s, "dcs-sms.exe") {
		t.Errorf("SKILL.md should mention dcs-sms.exe by name")
	}
}

func TestGeminiTOMLEmbeddedAndShaped(t *testing.T) {
	s := string(geminiTOML)
	if !strings.HasPrefix(s, "description = ") {
		t.Errorf("dcs-sms.toml should start with `description = `; got first 60 bytes: %q", s[:min(60, len(s))])
	}
	if !strings.Contains(s, "prompt = ") {
		t.Errorf("dcs-sms.toml should declare a `prompt = ` field")
	}
	if !strings.Contains(s, "{{args}}") {
		t.Errorf("dcs-sms.toml should forward user args via {{args}}")
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
