package aiskill

import (
	"path/filepath"
	"strings"
)

// Agent identifies which AI-agent config directory to target.
type Agent string

const (
	AgentClaude Agent = "claude"
	AgentCodex  Agent = "codex"
	AgentGemini Agent = "gemini"
	AgentAll    Agent = "all"
)

// ParseAgent normalizes user input into a known Agent. Case-insensitive.
func ParseAgent(s string) (Agent, bool) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "claude":
		return AgentClaude, true
	case "codex":
		return AgentCodex, true
	case "gemini":
		return AgentGemini, true
	case "all":
		return AgentAll, true
	}
	return "", false
}

// Paths returns the absolute file paths Install would write for one agent
// under home. Order is stable: Gemini's TOML comes before Gemini's SKILL.md;
// AgentAll returns claude → codex → gemini-toml → gemini-skill.
//
// Returns nil for unknown agents.
func Paths(agent Agent, home string) []string {
	switch agent {
	case AgentClaude:
		return []string{filepath.Join(home, ".claude", "skills", "dcs-sms", "SKILL.md")}
	case AgentCodex:
		return []string{filepath.Join(home, ".agents", "skills", "dcs-sms", "SKILL.md")}
	case AgentGemini:
		return []string{
			filepath.Join(home, ".gemini", "commands", "dcs-sms.toml"),
			filepath.Join(home, ".gemini", "skills", "dcs-sms", "SKILL.md"),
		}
	case AgentAll:
		var out []string
		out = append(out, Paths(AgentClaude, home)...)
		out = append(out, Paths(AgentCodex, home)...)
		out = append(out, Paths(AgentGemini, home)...)
		return out
	}
	return nil
}

// concreteAgents returns the per-agent slugs that AgentAll expands to,
// in install / uninstall iteration order.
func concreteAgents(agent Agent) []Agent {
	if agent == AgentAll {
		return []Agent{AgentClaude, AgentCodex, AgentGemini}
	}
	return []Agent{agent}
}
