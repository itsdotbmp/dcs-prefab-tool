## dcs-sms AI Agent Skill Installer — Design

**Date:** 2026-05-10
**Status:** Approved (brainstorm phase)
**Scope:** Add a menu option (and parallel CLI verbs) to `dcs-sms.exe` that drops a small "skill" file into the user's AI-agent config directory so that Claude Code, OpenAI Codex CLI, and Google Gemini CLI all learn that `dcs-sms.exe` exists and how to discover its commands. No framework changes; no ME-mod changes; no behavior change for existing CLI verbs.

## Goal

When a DCS mission maker uses an AI coding assistant — Claude Code, Codex, or Gemini — to help with a mission, today the agent has no idea `dcs-sms.exe` is installed or how to drive DCS programmatically. This change closes that gap by installing a short, agent-native "skill" or "command" file that:

- Tells the agent `dcs-sms.exe` is on PATH and what it does (drive a live mission **or** the Mission Editor).
- Names the one critical user gesture for ME work (enable *Options → Misc → Allow External Execution*).
- Points the agent at `--help` self-discovery and `dcs-sms doc` reference rather than embedding a full reference.
- Triggers automatically when the user asks the agent to do something in DCS (via the skill's `description` field on Claude / Codex / Gemini-skill, and via the `/dcs-sms` slash command on Claude / Gemini).

The installer is exposed two ways: a new menu option (option `5`) for double-click users, and two top-level CLI verbs (`install-ai-skill` / `uninstall-ai-skill`) for power users and the menu's internal use.

## Non-goals

- A full reference embedded in the skill. The skill stays ≤ 30 lines so it doesn't drift when CLI verbs change. Agents discover the rest via `--help` and `docs/cli/`.
- Per-project skill installation (e.g. into `<repo>/.claude/skills/`). User-scope only. Project-scope is the user's call.
- Auto-detection of which agent the user uses. The user picks (or picks "all three") at install time.
- Editing user-level `GEMINI.md` / `~/.codex/AGENTS.md`. Both are global-context files that fire for every project; that's the wrong semantics for "tell me about dcs-sms when I ask." Skill / slash-command files are opt-in per session.
- Dependency on any of the three agents being installed. The installer just writes files at well-known paths; it does not invoke or test the agents themselves. If the user has never installed Codex CLI, writing `~/.agents/skills/dcs-sms/SKILL.md` is a no-op until they do.
- Any GUI window. Console-only, like the rest of `dcs-sms.exe`.

## Context

`dcs-sms.exe` already has a clean pattern for "install a small file at a well-known path" — `install-me-mod` copies `tools/me-mod/lua/dcs_sms_me/*` (embedded via `//go:embed`) into `<DCS install>/MissionEditor/modules/`. The existing interactive menu (`tools/cmd/dcs-sms/menu.go`) drives `installMeModCmd` / `uninstallMeModCmd` / `updateCmd` for double-click users. This spec extends both surfaces with a new install target.

Three agent conventions, confirmed against current docs and source (May 2026):

| Agent | Skill / command file | User-level path on Windows | Triggers `/dcs-sms`? | Auto-activates? |
|---|---|---|---|---|
| Claude Code | `SKILL.md` (markdown + YAML frontmatter) | `%USERPROFILE%\.claude\skills\dcs-sms\SKILL.md` | Yes (skill name = slash command) | Yes (via `description`) |
| Codex CLI | `SKILL.md` (same shape) | `%USERPROFILE%\.agents\skills\dcs-sms\SKILL.md` (canonical); `%USERPROFILE%\.codex\skills\dcs-sms\SKILL.md` is the deprecated fallback | No (use `/skills` picker or `$dcs-sms`) | Yes (via `description`) |
| Gemini CLI | TWO files: `dcs-sms.toml` (slash command) + `SKILL.md` (auto-activating skill) | `%USERPROFILE%\.gemini\commands\dcs-sms.toml` AND `%USERPROFILE%\.gemini\skills\dcs-sms\SKILL.md` | Yes (TOML slash command) | Yes (skill, separately) |

`%USERPROFILE%` resolves via `os.UserHomeDir()` on Go, which is portable: `$HOME` on Unix, `%USERPROFILE%` on Windows. The Codex deprecated fallback is **not** written by this installer — only the canonical `~/.agents/skills/dcs-sms/`.

## Architecture

Two new files in `tools/cmd/dcs-sms/` (one per CLI verb), one new internal package, and a small edit to `menu.go` for the new option. Everything else (dispatch, main, existing menu options) stays exactly as it is.

```
tools/cmd/dcs-sms/
  install_ai_skill.go        ← new (CLI verb wrapper)
  install_ai_skill_test.go   ← new (flag parsing tests)
  uninstall_ai_skill.go      ← new (CLI verb wrapper)
  uninstall_ai_skill_test.go ← new (flag parsing tests)
  menu.go                    ← modified (option 5 + sub-prompts)
  menu_test.go               ← modified (option 5 routing tests)
  dispatch.go                ← modified (one usage line)

tools/internal/aiskill/
  aiskill.go            ← new — Install / Uninstall / agent path resolution
  aiskill_test.go       ← new — table-driven, fake home dir
  embed.go              ← new — //go:embed for SKILL.md and dcs-sms.toml
  source/
    SKILL.md            ← new — the shared skill body
    dcs-sms.toml        ← new — the Gemini slash command file
```

The package layout mirrors `tools/me-mod/lua/` (embed sibling + an embedded subtree). Pure-function design: `aiskill.Install` takes a `home` string and writes to `<home>/.claude/skills/dcs-sms/SKILL.md` etc., so tests use `t.TempDir()` as the fake home and never touch the real config dirs.

## Components

### `aiskill` package (`tools/internal/aiskill/`)

```go
package aiskill

// Agent identifies which AI agent's config to target.
type Agent string

const (
    AgentClaude Agent = "claude"
    AgentCodex  Agent = "codex"
    AgentGemini Agent = "gemini"
    AgentAll    Agent = "all"
)

// Result describes what one Install / Uninstall call did, suitable for
// printing one line per write to the user.
type Result struct {
    Agent  Agent    // claude | codex | gemini
    Paths  []string // files written (Install) or removed (Uninstall)
    Errors []error  // empty on full success
}

// Install writes the skill / command files for one agent (or all three)
// under home. home must be absolute. Idempotent: re-running overwrites.
// For AgentAll, all three are attempted; failures on one do not abort
// the others. Returns one Result per agent attempted.
func Install(agent Agent, home string) []Result

// Uninstall removes the files Install wrote. Missing files are not an
// error — the call reports them in Result.Paths anyway with a "(not
// present)" suffix elsewhere in the user-facing output. Empty parent
// directories are removed too (e.g. ~/.claude/skills/dcs-sms/ goes away
// after the SKILL.md is removed); but the agent root (~/.claude/) is
// never removed.
func Uninstall(agent Agent, home string) []Result

// Paths reports the files that Install would write for an agent under
// home, without writing anything. Used by the menu to print the target
// paths next to each option.
func Paths(agent Agent, home string) []string
```

Path resolution table, applied to a given `home`:

| Agent | Files |
|---|---|
| `claude` | `<home>/.claude/skills/dcs-sms/SKILL.md` |
| `codex`  | `<home>/.agents/skills/dcs-sms/SKILL.md` |
| `gemini` | `<home>/.gemini/commands/dcs-sms.toml` and `<home>/.gemini/skills/dcs-sms/SKILL.md` |
| `all`    | union of the three above |

Source content is embedded at build time:

```go
// tools/internal/aiskill/embed.go
package aiskill

import _ "embed"

//go:embed source/SKILL.md
var skillMarkdown []byte

//go:embed source/dcs-sms.toml
var geminiTOML []byte
```

### `installAISkillCmd` (`tools/cmd/dcs-sms/install_ai_skill.go`)

```go
func init() { register("install-ai-skill", installAISkillCmd) }

func installAISkillCmd(args []string, stdout, stderr io.Writer) int {
    fs := flag.NewFlagSet("install-ai-skill", flag.ContinueOnError)
    fs.SetOutput(stderr)
    flagAgent := fs.String("agent", "", "claude | codex | gemini | all")
    if err := fs.Parse(args); err != nil { return 2 }
    if *flagAgent == "" { fs.Usage(); return 2 }

    agent, ok := parseAgent(*flagAgent)
    if !ok {
        fmt.Fprintf(stderr, "dcs-sms install-ai-skill: invalid --agent %q (want claude|codex|gemini|all)\n", *flagAgent)
        return 2
    }

    home, err := os.UserHomeDir()
    if err != nil {
        fmt.Fprintln(stderr, "dcs-sms install-ai-skill: could not resolve home directory:", err)
        return 3
    }

    results := aiskill.Install(agent, home)
    return printResultsAndExit(stdout, stderr, "install", results)
}
```

`parseAgent` is a tiny helper shared with the uninstall verb (lives in `install_ai_skill.go` since it's first registered there). `printResultsAndExit` prints one `wrote: <path>` line per success, one `error: <path>: <err>` line per failure, and returns 0 if every result is fully successful, 3 otherwise.

### `uninstallAISkillCmd` (`tools/cmd/dcs-sms/uninstall_ai_skill.go`)

Mirror of install. Flag set is the same. Reads `aiskill.Uninstall(agent, home)`, prints one `removed: <path>` per success and `not present: <path>` for missing files (not an error), returns exit code 0 unless an actual filesystem error occurred.

### `menu.go` changes

Three additions to the existing struct and one new branch in the loop:

```go
type menuActions struct {
    install        commandFunc
    uninstall      commandFunc
    update         commandFunc
    installAISkill   commandFunc // new
    uninstallAISkill commandFunc // new
}
```

`defaultMenuDeps` populates the two new fields with `installAISkillCmd` / `uninstallAISkillCmd`.

Banner gets one new line:

```
  5. Install AI agent skill (Claude / Codex / Gemini)
```

Prompt becomes `Choose [1/2/3/4/5/q]:`. Option `5` invokes a new helper:

```go
func runAISkillSubMenu(reader *bufio.Reader, stdout, stderr io.Writer, deps menuDeps) int
```

Sub-flow:

1. Print agent picker:
   ```
   Which agent?
     a. Claude Code  (~/.claude/skills/dcs-sms/)
     b. Codex CLI    (~/.agents/skills/dcs-sms/)
     c. Gemini CLI   (~/.gemini/commands/dcs-sms.toml + ~/.gemini/skills/dcs-sms/)
     d. All three
     q. Cancel

   Choose [a/b/c/d/q]:
   ```
2. Read one line. `q` → return to main menu (no action). Three invalid attempts → return to main menu without action (do **not** exit the binary; this is a sub-menu).
3. Print install-or-uninstall picker:
   ```
   Install or Uninstall?
     i. Install (overwrite if present)
     u. Uninstall
     q. Cancel

   Choose [i/u/q]:
   ```
4. On `i` → call `deps.actions.installAISkill([]string{"--agent", agentSlug}, stdout, stderr)`; pause; exit binary with the action's exit code.
5. On `u` → same with `uninstallAISkill`.
6. On `q` → return to main menu.

This mirrors options 1 / 2 / 3 in that a chosen action terminates the program after `Press Enter to exit...`. Only option 4 (set DCS path) loops back to the main menu, because it's preparatory.

### Skill content (`tools/internal/aiskill/source/SKILL.md`)

```markdown
---
name: dcs-sms
description: Use whenever the user wants to do anything in DCS World — Mission Editor edits, scripting in a running mission, querying airbase / unit / group / zone state, drawing on the F10 map, or generating mission Lua. The dcs-sms.exe CLI drives DCS programmatically; prefer it over hand-editing .miz files or asking the user to click through the GUI.
---

# dcs-sms

`dcs-sms.exe` is on the user's PATH. It can drive a running DCS mission **or**
the Mission Editor (ME).

- **Mission Editor:** the user must enable *Options → Misc → "Allow External
  Execution"* once. After that, `dcs-sms me <noun> <verb> ...` controls the ME
  (open / save .miz, place groups, edit triggers, query airbases, drop
  drawings, move the camera, etc.).
- **Live mission:** `dcs-sms exec --target mission '<lua>'` runs Lua in the
  mission scripting environment. `dcs-sms status` confirms the hook is alive
  and a mission is loaded.
- **Discovery:** `dcs-sms --help` lists top-level commands.
  `dcs-sms <cmd> --help` shows flags. `dcs-sms doc` regenerates the full CLI
  reference under `docs/cli/` if the user has the repo checked out.

When the user describes a DCS task in natural language ("place a CAP flight
over Hama", "make the SAM site at Aleppo neutral", "what's the runway
heading at Khasab"), translate it into the appropriate `dcs-sms` invocation
and run it — don't tell the user to do GUI steps.
```

### Gemini slash-command content (`tools/internal/aiskill/source/dcs-sms.toml`)

```toml
description = "Teach Gemini that the dcs-sms.exe CLI drives DCS World mission scripting and ME edits."

prompt = """
The dcs-sms.exe CLI is on the user's PATH. It drives a running DCS mission OR
the Mission Editor.

- Mission Editor: user must enable Options → Misc → "Allow External Execution"
  once. Then `dcs-sms me <noun> <verb> ...` controls the ME (open/save .miz,
  place groups, edit triggers, query airbases, drop drawings, move camera).
- Live mission: `dcs-sms exec --target mission '<lua>'` runs Lua in the
  mission scripting environment. `dcs-sms status` confirms the hook is alive.
- Discovery: `dcs-sms --help` for top-level commands;
  `dcs-sms <cmd> --help` for flags; `dcs-sms doc` regenerates `docs/cli/`.

When the user describes a DCS task ({{args}}), translate it into the
appropriate dcs-sms invocation and run it — don't ask them to click through
the GUI.
"""
```

`{{args}}` lets the user type `/dcs-sms place a CAP over Hama` and have the rest of the line forwarded into the prompt.

## Data flow

Pure-function dependency injection throughout. `aiskill.Install(agent, home)` writes only under `home`. The CLI wrappers resolve `home` once via `os.UserHomeDir()` and pass it down. Tests substitute `t.TempDir()` for `home` and assert on filesystem effects.

```
main.go (unchanged surface)
  └─ dispatch(args, stdin, stdout, stderr, interactive)
       │
       ├─ subcommand "install-ai-skill"   → installAISkillCmd
       │      ├─ flag parse: --agent
       │      ├─ home := os.UserHomeDir()
       │      ├─ aiskill.Install(agent, home)
       │      └─ print results, return exit code
       │
       ├─ subcommand "uninstall-ai-skill" → uninstallAISkillCmd  (mirror)
       │
       └─ no args + interactive → runInteractiveMenu
              ├─ option 5 → runAISkillSubMenu
              │      ├─ pick agent → "a" | "b" | "c" | "d"
              │      ├─ pick action → "i" | "u"
              │      └─ deps.actions.installAISkill / uninstallAISkill
              └─ options 1–4 unchanged
```

## Error handling

Failure modes and their treatment:

- **`os.UserHomeDir()` returns error.** Print `dcs-sms install-ai-skill: could not resolve home directory: <err>` to stderr, exit 3. Catastrophic; nothing else to do.
- **Per-agent write failure (`MkdirAll` or `WriteFile`).** Append the error to that agent's `Result.Errors`. Continue with the remaining agents in `--agent=all`. Final exit code: 0 if every result is fully clean, 3 if any agent failed.
- **Re-install over existing files.** Overwrite (idempotent — per design Q6). Print `wrote: <path>` either way; do not print "overwriting" or any warning.
- **Uninstall when files don't exist.** Not an error. Print `not present: <path>` and continue. Final exit 0.
- **Empty directory cleanup on uninstall.** After removing the SKILL.md or .toml file, `RemoveAll` the immediate parent dir if it's empty (e.g. `~/.claude/skills/dcs-sms/`). The grandparent (`~/.claude/skills/`) is **not** touched even if it's empty after — the user may have other skills.
- **`--agent` invalid or missing.** Print usage error to stderr, exit 2.
- **Unrecognized sub-menu input.** After three invalid attempts in `runAISkillSubMenu`, return to the main menu (don't exit the binary). The main menu's invalid-counter is independent.

`Install` writes the SKILL.md (or .toml) atomically? — **No.** `os.WriteFile` is one syscall on the target file; on Windows that's already crash-safe at the small file sizes involved (a few KB). No tempfile-rename dance is warranted.

## Testing

### `aiskill_test.go` (new)

Table-driven, fake home via `t.TempDir()`:

- `TestInstallClaude_WritesSkillMarkdown` — writes to `<home>/.claude/skills/dcs-sms/SKILL.md`. File contents start with `---\nname: dcs-sms`.
- `TestInstallCodex_WritesSkillMarkdown` — writes to `<home>/.agents/skills/dcs-sms/SKILL.md`. Same content as Claude (shared embed).
- `TestInstallGemini_WritesBothFiles` — writes both `<home>/.gemini/commands/dcs-sms.toml` and `<home>/.gemini/skills/dcs-sms/SKILL.md`. TOML starts with `description = `.
- `TestInstallAll_WritesAllAgents` — writes 4 files (Claude SKILL.md, Codex SKILL.md, Gemini TOML, Gemini SKILL.md).
- `TestInstallIdempotent` — second install over existing file overwrites; no error; result has no errors.
- `TestUninstallClaude_RemovesFiles` — after install + uninstall, the file is gone and the parent `dcs-sms/` directory is gone, but `<home>/.claude/skills/` still exists.
- `TestUninstallMissing_NotError` — uninstall on a clean home: no error, results report `(not present)`.
- `TestUninstallAll_RemovesEverything` — install all, uninstall all, all four files gone.
- `TestPaths_ReportsExpectedPaths` — table-driven: each agent returns the expected slice of paths.
- `TestInstallAll_PartialFailure` — induce a write failure on one agent (e.g. by `os.MkdirAll`-ing a regular file in the way) and assert the other agents still succeed and the failing agent's `Result.Errors` is non-empty.

### `install_ai_skill_test.go` (new)

- `TestInstallAISkill_NoAgentFlag` — `--agent` absent → exit 2, usage on stderr.
- `TestInstallAISkill_InvalidAgent` — `--agent=foo` → exit 2, error on stderr mentioning valid choices.
- `TestInstallAISkill_ValidAgentSucceeds` — patch `os.UserHomeDir` (or set `$HOME` / `%USERPROFILE%` for the test) to `t.TempDir()`, run with `--agent=claude`, assert exit 0 and `wrote:` line on stdout. (Use `t.Setenv` for `HOME` / `USERPROFILE`; `os.UserHomeDir` honors them.)

### `uninstall_ai_skill_test.go` (new)

Mirror — covers no-flag, invalid-agent, and successful uninstall after a prior install.

### `menu_test.go` (extended)

- `TestMenuOption5_AgentClaudeInstall` — input `5\na\ni\n\n`, stub installAISkill, assert it was called with `args == []string{"--agent", "claude"}` and exit code propagates.
- `TestMenuOption5_AgentAllUninstall` — input `5\nd\nu\n\n`, stub uninstallAISkill, assert called with `--agent all`.
- `TestMenuOption5_CancelAtAgent` — input `5\nq\nq\n` (cancel agent picker, then quit main menu), no handler called, exit 0.
- `TestMenuOption5_CancelAtAction` — input `5\na\nq\nq\n` (pick agent, cancel action picker, then quit), no handler called.
- `TestMenuOption5_ThreeInvalidAgentsFallsBackToMenu` — input `5\nx\ny\nz\nq\n`, no handler called, main menu redrawn, exit 0.

### Cross-cutting

- All tests use `t.TempDir()` and `t.Setenv` — no real filesystem writes outside the test sandbox.
- The shared `parseAgent` helper has a small unit test for round-trip of all four valid values + one invalid.
- No new test deps. Stays on stdlib + the existing project deps.

## Decisions

Choices resolved during brainstorming, recorded so the implementer doesn't relitigate them. (The Q numbers reference the brainstorming exchange in the originating session.)

- **Skill content scope (Q1):** Discovery launcher only — short body that says dcs-sms exists, mentions the External Execution switch for ME work, and points the agent at `--help`. ≤ 30 lines. Reasoning: longer content drifts the moment a flag changes; keeping it short means the file rarely needs an update.
- **Menu shape (Q3):** One new option `5`. Picking it opens an agent sub-menu (a/b/c/d/q), then an install-or-uninstall sub-menu (i/u/q). Considered: three top-level options (rejected — top-level menu balloons); install-everywhere unconditionally (rejected — clutters config dirs the user may not use).
- **Gemini both vs one (Q4):** Install **both** the slash command (`commands/dcs-sms.toml`) and the skill (`skills/dcs-sms/SKILL.md`). Rationale: command gives literal `/dcs-sms` invocation; skill gives auto-activation when the user mentions DCS without typing the slash command. Same UX coverage Claude gets from a single file.
- **Source location (Q5):** Embedded via `//go:embed` in `tools/internal/aiskill/source/`. Mirrors the `tools/me-mod/lua/` pattern. Reading from disk at runtime would break for users with only the standalone .exe.
- **CLI subcommand (Q5):** Yes — `install-ai-skill --agent=...` and `uninstall-ai-skill --agent=...`. The menu calls these via `commandFunc` for single-source-of-truth.
- **Lifecycle (Q6):** Idempotent install (overwrites without warning); explicit uninstall verb. Symmetric with `install-me-mod` / `uninstall-me-mod`.
- **Codex deprecated path:** Write canonical `~/.agents/skills/dcs-sms/SKILL.md` only. Do **not** also write the deprecated `~/.codex/skills/`. Codex CLI reads both, so writing one is sufficient and avoids future stale-file confusion when the deprecated path is dropped.
- **Codex `prompts/` for `/dcs-sms` form:** Skip. The deprecated `~/.codex/prompts/dcs-sms.md` would give `/prompts:dcs-sms` (not `/dcs-sms`) and is being phased out. Auto-activation from the skill `description` covers the discovery use case.
- **GEMINI.md / `~/.codex/AGENTS.md`:** Do not modify. Both are global-context files that fire for every project; appending to them would add noise to unrelated work. Slash commands and skills are the right opt-in primitives.
- **Agent slug syntax:** `claude`, `codex`, `gemini`, `all` (lowercase, no aliases). One word, easy to type, easy to grep.
- **Exit codes:** 0 = success or "nothing to remove"; 2 = usage error; 3 = filesystem error. Matches existing dcs-sms verbs.
- **Per-agent failure isolation in `--agent=all`:** Continue on failure (best-effort), exit 3 if any agent failed. Considered: abort on first failure (rejected — the user picked "all" because they want the others done).
- **Empty parent dir cleanup on uninstall:** Remove `<home>/.<agent>/skills/dcs-sms/` if empty after the SKILL.md is gone. Do **not** remove the `skills/` or `commands/` parent (other skills / commands may live there).
- **Cross-platform:** Same code path works on macOS/Linux (where `~/.claude/skills/...` is the actual path). The CLI prints with forward slashes regardless; the underlying writes use the OS's native separator via `filepath.Join`.
- **Sub-menu invalid-input limit:** Three attempts at each sub-prompt, then return to main menu without action (not exit the binary). Distinct from the main menu's three-strike exit — a user who fat-fingers in the sub-prompt should land back at the main menu, not be kicked out.
- **No prompt for confirmation before overwrite:** Idempotency is the contract. Adding a Y/N prompt makes the menu modal in an inconsistent way (options 1/2/3 don't ask either).

## Open questions

None. All design choices are pinned above.

## Versioning

Public surface change to `dcs-sms.exe` (two new top-level subcommands and a new menu option). Per `AGENTS.md` §11, this bumps the framework `version` constant in `tools/cmd/dcs-sms/main.go` (currently `"0.1.0-dev"` — release tagging happens via the existing `me-mod-v*` tag flow, since the .exe ships with the ME-mod release). Update `CHANGELOG.md` in the same commit.

`AGENTS.md` §7 module index: not affected (no new public `sms.*` Lua module).
`docs/api/`: not affected (CLI surface, not framework).
`docs/cli/`: regenerate via `dcs-sms doc` to pick up the two new verbs.

## Out-of-band documentation

- `tools/cmd/dcs-sms/README.md`: add a section "Install an AI agent skill" describing the menu option and the two CLI verbs. One paragraph, in the same commit.
- Top-level `README.md`: add one line under the install/uninstall flow mentioning the AI-agent skill option.
- `docs/cli/`: regenerated by `dcs-sms doc` (auto, not handwritten).
