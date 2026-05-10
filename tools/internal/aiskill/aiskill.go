package aiskill

import (
	"fmt"
	"os"
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

// Result describes what one Install / Uninstall call did for a single
// agent, suitable for printing one line per file.
type Result struct {
	Agent  Agent
	Paths  []string // files written (Install) or removed/missing (Uninstall)
	Errors []error  // empty on full success
}

// Install writes the skill / command files for one agent (or all three)
// under home. home must be absolute. Idempotent: re-running overwrites.
// For AgentAll, all three are attempted; failures on one do not abort
// the others. Returns one Result per agent attempted.
func Install(agent Agent, home string) []Result {
	agents := concreteAgents(agent)
	out := make([]Result, 0, len(agents))
	for _, a := range agents {
		out = append(out, installOne(a, home))
	}
	return out
}

func installOne(agent Agent, home string) Result {
	r := Result{Agent: agent}
	for _, target := range Paths(agent, home) {
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			r.Errors = append(r.Errors, fmt.Errorf("%s: mkdir parent: %w", target, err))
			continue
		}
		body := bodyFor(target)
		if err := os.WriteFile(target, body, 0o644); err != nil {
			r.Errors = append(r.Errors, fmt.Errorf("%s: write: %w", target, err))
			continue
		}
		r.Paths = append(r.Paths, target)
	}
	return r
}

// bodyFor returns the file body to write at target. The Gemini TOML lives
// at the .toml suffix; everything else is the SKILL.md markdown body.
func bodyFor(target string) []byte {
	if strings.HasSuffix(target, ".toml") {
		return geminiTOML
	}
	return skillMarkdown
}

// Uninstall removes the files Install wrote for one agent (or all three)
// under home. Missing files are not errors — the call still reports them
// in Result.Paths so the CLI can print "not present: <path>".
//
// After removing each target file, the immediate parent directory
// (~/.<agent>/skills/dcs-sms/) is removed if it is now empty. The
// grandparent (~/.<agent>/skills/) is never removed even if empty,
// because other skills may live there.
func Uninstall(agent Agent, home string) []Result {
	agents := concreteAgents(agent)
	out := make([]Result, 0, len(agents))
	for _, a := range agents {
		out = append(out, uninstallOne(a, home))
	}
	return out
}

func uninstallOne(agent Agent, home string) Result {
	r := Result{Agent: agent}
	for _, target := range Paths(agent, home) {
		r.Paths = append(r.Paths, target)
		err := os.Remove(target)
		if err != nil && !os.IsNotExist(err) {
			r.Errors = append(r.Errors, fmt.Errorf("%s: remove: %w", target, err))
			continue
		}
		// Try to remove the dcs-sms/ dir if empty. Skip when the file is the
		// Gemini TOML, whose immediate parent is commands/ (shared with other
		// commands) — not a dcs-sms/ subdir we own. The grandparent (skills/
		// or commands/) is never removed.
		parent := filepath.Dir(target)
		if filepath.Base(parent) == "dcs-sms" {
			_ = os.Remove(parent) // best-effort; ignored if not empty
		}
	}
	return r
}
