# CLI "update everything" flow + UAC elevation handling

## Goal

Collapse the multi-step "update the .exe, then uninstall the mod, then reinstall the mod, then maybe update the hook" workflow into a single menu choice that does it all. Detect when the operation needs Windows admin privileges and offer to re-launch elevated, instead of failing with a permission error users don't know how to fix.

## User value

- A user with a fresh `dcs-sms.exe` release notification clicks **one** menu option and ends up with the latest .exe on disk, the latest ME mod files in `<DCS>\MissionEditor\modules\dcs_sms_me\`, and the latest hook in `<Saved Games>\DCS*\Scripts\Hooks\`. No more "open, update, close, open, uninstall, open, reinstall."
- A user whose DCS install lives under `Program Files\Eagle Dynamics\DCS World` (the default Steam path, plus many standalone installs) is no longer stopped by a cryptic write error. The menu offers to re-launch with admin, the user clicks `y`, UAC pops, and the install completes in a separate console window.
- A user who wants to install the AI-agent skill no longer has to make two pointless choices ("which agent? then: install or uninstall?"). The menu has four direct entries: install everything / uninstall everything / install AI skill / uninstall AI skill.

## Scope

### In scope

- New `dcs-sms setup` subcommand: orchestrates `update` (binary swap if newer) → `install-me-mod` → `install-hook`.
- New `dcs-sms teardown` subcommand: orchestrates `uninstall-me-mod` → `uninstall-hook`.
- New `dcs-sms uninstall-hook` subcommand (peer to `install-hook`).
- New `tools/internal/elevate/` package with `IsElevated`, `CanWrite`, and `ReExecElevated` helpers.
- Pre-flight write probe in `install-me-mod` and `uninstall-me-mod`. Failure → exit code `5` ("needs elevation").
- New main-menu shape (5 flat entries): install/update, uninstall, install AI skill, uninstall AI skill, set DCS path.
- AI skill menu entries always invoke `install-ai-skill` / `uninstall-ai-skill` with `--agent all`. The 2-step picker (agent → action) is deleted.
- Menu catches exit code `5` from `setup` / `teardown` and shows a y/N "re-launch with admin?" prompt. On `y`, the menu re-execs itself elevated and exits.
- Elevated child runs in its own console window. It pauses on "Press Enter to close..." so the user can read the output before the window vanishes.
- Tests for all new files in the existing `_test.go` style (pure-function shape, no real DCS/network/UAC).
- `dcs-sms doc` regenerated.
- `CHANGELOG.md` entry and `me-mod-v*` version bump.

### Out of scope

- Auto-elevating without asking. Not a knob; always prompt.
- Auto-elevating in non-interactive CLI use. `dcs-sms setup` from a script returns exit code `5` and prints how to recover; it does not pop UAC.
- Bundling AI skill install into `setup`. Per user direction, AI skill stays a separate menu entry.
- Linux/macOS elevation. The package compiles cross-platform but `ReExecElevated` returns an error off Windows; the menu is Windows-first anyway.
- Removing the existing top-level `install-me-mod`, `uninstall-me-mod`, `install-hook`, `update`, `install-ai-skill`, `uninstall-ai-skill` subcommands. They stay as CLI knobs; only the menu's *exposure* of them is collapsed.
- Detecting hook-dir or AI-skill-dir permission errors. `<Saved Games>` and `~/.<agent>` are always user-writable; no probe needed.
- Streaming the elevated child's stdout back to the original menu console. Windows UAC severs stdio; the new console window is the standard pattern.

## Constraints

- **Repo conventions** (see [`tools/cmd/dcs-sms/AGENTS.md`](../../../tools/cmd/dcs-sms/AGENTS.md) and root [`AGENTS.md`](../../../AGENTS.md)):
  - Each subcommand registers in an `init()` via `registerInfo` / `flagsOnly`.
  - Handlers are pure: `func(args []string, stdout, stderr io.Writer) int`. No `os.Exit`. No `os.Stdin` outside `main.go`.
  - Exit codes: 0 success, 1 operation failed, 2 bad usage, 3 environment/setup, 4 bridge unavailable. We are adding **5 = needs elevation** — document it.
  - `cmdInfo.Synopsis` + `Flags` gate doc autogen. Run `dcs-sms doc` and commit `docs/cli/`.
  - User-visible behavior change → bump the `me-mod-v*` track and update `CHANGELOG.md` in the same commit.
- **Idempotency.** All install paths (`install-me-mod`, `install-hook`, AI skill) are already idempotent. `setup` and `teardown` must remain idempotent — running them twice in a row is a no-op on the second run (modulo the binary swap).
- **No interactive prompts inside subcommand handlers.** `setup` and `teardown` are pure functions; the y/N prompt lives in `menu.go`, not in the subcommands. CLI users see exit code `5` and a printed instruction; they don't get a TTY prompt from a subcommand.
- **Re-exec must not loop.** `setup` accepts `--skip-update`. The parent always passes it on re-exec. `--skip-update` is also useful for `go build` users who don't want self-update.
- **Test discipline.** No test may hit GitHub, write to a real DCS install, pop UAC, or call `os.Executable()` in a way that resolves to the real test binary's install location. Stub via dependency injection — the existing menu tests already do this with `menuActions`.

## Decisions

These were made during brainstorming and recorded here so the implementer doesn't need to re-derive them.

1. **Three new subcommands, not menu-internal helpers.** `setup` / `teardown` / `uninstall-hook` are top-level subcommands. Rationale: testable as pure functions, documented by `dcs-sms doc`, scriptable, and the re-exec after binary swap has a stable command name to invoke in the new binary.
2. **Bundled scope = .exe + ME mod + hook.** No AI skill in the bundle. Rationale: user chose this in brainstorming; AI skill is a separate menu entry with its own install/uninstall actions.
3. **Menu shape = flat 5-item.** No "Advanced" submenu, no per-piece options exposed in the menu. Granular control stays in the CLI. Rationale: user chose this in brainstorming.
4. **AI skill picker is removed entirely.** Menu entries 3 and 4 always invoke `--agent all`. Rationale: user said "install for all three" should be the default; people who want one-at-a-time can use the CLI.
5. **Exit code 5 = needs elevation.** New code in the table in [`tools/cmd/dcs-sms/AGENTS.md`](../../../tools/cmd/dcs-sms/AGENTS.md) §4. Rationale: distinct from `3` (environment/setup error) so the menu can disambiguate "user pasted a bad path" from "we need admin."
6. **Pre-flight write probe, not catch-and-retry.** `CanWrite` runs *before* any state change. Rationale: a half-failed install is harder to recover from than a clean-error-then-elevate cycle.
7. **Probe location.** Inside `install-me-mod` and `uninstall-me-mod` — not inside `setup` / `teardown`. Rationale: any CLI user invoking `install-me-mod` directly gets the same exit-code-5 signal. `setup` and `teardown` propagate the exit code unchanged.
8. **Elevated child runs in a new console window with "Press Enter to close."** Rationale: Windows UAC severs stdio; trying to inherit it across the boundary is fragile. Pause matches the existing menu's pause-after-action pattern so the user can read output.
9. **Ask before elevating.** The y/N prompt fires even when we're confident elevation is needed. Rationale: user chose this in brainstorming; surprise-UAC from a double-click is jarring.
10. **`setup` continues past `update` failures.** If the binary swap fails (network down, GitHub 503), `setup` still attempts `install-me-mod` and `install-hook` from the *currently installed* embedded content, then exits with code 0 if those succeed. Rationale: the user wanted "give me the new versions of everything"; in degraded-network mode that becomes "give me the versions I already have, applied."
11. **Re-exec on binary swap uses `--skip-update`.** Parent calls `updateCmd`; if it returns 0 *and* a swap happened, parent spawns `dcs-sms.exe setup --skip-update <forwarded flags>` as a child, inherits stdio, exits with child's code. Rationale: avoids a re-exec loop; the new binary's embedded Lua is what reaches DCS.
12. **Re-exec detection.** `updateCmd` today prints `"Up to date (vN.N.N)"` when no swap occurred and `"Updated. Run `dcs-sms.exe install-me-mod` to apply."` when it did. `setup` won't parse stdout; instead, refactor `updateCmd` to expose a typed result via a small helper called from both `setup` and the existing `update` subcommand. The helper returns `(swapped bool, err error)`.
13. **`teardown` does not need elevation if `install-me-mod` was never run.** But `CanWrite` is cheap — the probe runs unconditionally before any delete. Rationale: simpler control flow, and the user would hit elevation issues on the very first uninstall attempt of a Program-Files install anyway.
14. **`golang.org/x/sys/windows` dep.** Add to `tools/go.mod` if not present. Used for `windows.GetCurrentProcessToken().IsElevated()` and `windows.ShellExecute` for the runas verb.
15. **Cross-compile stubs.** `elevate_other.go` (build tag `!windows`) provides no-op `IsElevated` (returns false), real `CanWrite` (works everywhere), and `ReExecElevated` that returns `errors.New("elevation is only supported on Windows")`. Lets `go test ./...` pass on any host.
16. **The hidden submenu's deletion is a real deletion.** `runAISkillSubMenu` and its tests are removed in this change, not just unwired. Rationale: dead-code removal per repo CLAUDE.md ("Don't add backwards-compatibility hacks ... If you are certain that something is unused, you can delete it completely").
17. **CHANGELOG entry under "Unreleased."** Per repo versioning rules (see [`AGENTS.md` §4](../../../AGENTS.md)). The actual `me-mod-v*` bump happens at `/ship-it` time, not in this branch.
18. **No new external dependencies beyond `golang.org/x/sys/windows`.** All other functionality uses stdlib (`os/exec`, `os.Executable`, `os.Stat`, `errors.Is`).

## Open questions

None. All design decisions were settled during brainstorming or are codified in the Decisions section above.

## Acceptance criteria

A reviewer reading this spec should be able to verify the implementation by checking:

1. `dcs-sms --help` lists `setup`, `teardown`, `uninstall-hook` alongside the existing subcommands.
2. `dcs-sms doc` produces `docs/cli/setup.md`, `docs/cli/teardown.md`, `docs/cli/uninstall-hook.md`.
3. Running `dcs-sms.exe` with no args shows the new 5-item flat menu (not the old 5-item menu with the AI skill submenu).
4. With a known-readonly fake DCS path passed via `--dcs-path`, `install-me-mod` returns exit code 5 and prints a clear message.
5. With the same fake path, the interactive menu's option 1 catches exit code 5 and shows the y/N prompt.
6. On non-Windows, `dcs-sms setup` works (without the `update` step succeeding — `update` already refuses non-Windows). `dcs-sms teardown` works. The elevation prompt path is exercised by tests that stub `ReExecElevated`.
7. All Go tests pass: `cd tools && go test ./...`.
8. `me-mod-v*` track CHANGELOG.md has an Unreleased entry for the change.

## Related work and references

- `tools/cmd/dcs-sms/menu.go` — current interactive menu, will be re-shaped.
- `tools/cmd/dcs-sms/install_me_mod.go` — gains pre-flight probe.
- `tools/cmd/dcs-sms/uninstall_me_mod.go` — gains pre-flight probe.
- `tools/cmd/dcs-sms/installhook.go` — peer; `uninstall_hook.go` mirrors its shape.
- `tools/cmd/dcs-sms/update.go` — gets a small refactor so `setup` can call it and learn whether a swap occurred.
- `tools/cmd/dcs-sms/install_ai_skill.go` — unchanged; the menu just stops asking for an agent picker.
- `tools/cmd/dcs-sms/AGENTS.md` — exit code table in §4 grows by one row.
- `tools/internal/aiskill/aiskill.go` — `AgentAll` already exists; we rely on it.
- Recent design spec [`2026-05-06-dcs-sms-update.md`](2026-05-06-dcs-sms-update.md) — context for the self-update mechanism this builds on.
- Recent design spec [`2026-05-09-dcs-sms-interactive-menu-design.md`](2026-05-09-dcs-sms-interactive-menu-design.md) — context for the current menu shape this replaces.
- Recent design spec [`2026-05-10-ai-agent-skill-installer-design.md`](2026-05-10-ai-agent-skill-installer-design.md) — context for the AI skill installer this simplifies.
