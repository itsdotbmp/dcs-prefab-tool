// Package aiskill installs and removes "skill" / slash-command files in the
// user's AI agent config directories (Claude Code, OpenAI Codex CLI, Google
// Gemini CLI). The skill teaches the agent that dcs-sms.exe is on PATH and
// how to discover its commands; it does not embed a full reference.
//
// All filesystem operations are scoped under a caller-supplied home
// directory so tests can drive the package against t.TempDir() instead of
// the real user profile.
package aiskill

import _ "embed"

// skillMarkdown is the body of SKILL.md, used verbatim for Claude Code,
// Codex CLI, and the Gemini-skill slot.
//
//go:embed source/SKILL.md
var skillMarkdown []byte

// geminiTOML is the body of the Gemini slash-command file written to
// ~/.gemini/commands/dcs-sms.toml.
//
//go:embed source/dcs-sms.toml
var geminiTOML []byte
