## dcs-sms.exe Interactive Menu — Design

**Date:** 2026-05-09
**Status:** Approved (brainstorm phase)
**Scope:** Add a no-args interactive menu to `dcs-sms.exe` so non-CLI users can install / uninstall / update the Mission Editor mod by double-clicking the binary. All existing CLI invocations are unchanged.

## Goal

Today, double-clicking `dcs-sms.exe` opens a console that prints usage and immediately closes. Users who are not comfortable with a command line have reported difficulty installing the ME mod. This change makes the binary dual-mode:

- **CLI mode (unchanged):** `dcs-sms.exe install-me-mod`, `dcs-sms.exe update`, etc. continue to work exactly as today.
- **Interactive mode (new):** Double-clicking — or running with no args from a real terminal — opens a numbered menu. The user picks an action, the action runs in the same console window, and the program waits for `Enter` before exiting so any output (including errors) is readable.

The menu surfaces only the three operations a non-CLI user actually needs (install, uninstall, update), plus a fourth helper to set a custom DCS install path when auto-discovery fails.

## Non-goals

- A graphical installer (no GUI window — this is still a console app).
- Loop-back-to-menu mode for actions 1/2/3. After install/uninstall/update, the program exits. Setting a path (option 4) is the only loop-back case, because it is preparatory.
- Localization. English only.
- Saved Games path management from the menu. The three menu actions only need the DCS install path; the Saved Games discovery used by `exec` / `status` / `tail-log` remains a CLI-only concern.
- Prompting for `--dcs-path` during the install action itself. If discovery fails when the user picks option 1, the existing error message is printed verbatim and the user can pick option 4 next time.
- Replacing the existing `--dcs-path` flag, env var, or config-file mechanism. The menu is a *frontend* over those; option 4 just writes to the same config file `install-me-mod --dcs-path X` writes to.

## Context

`dcs-sms.exe` is a Go CLI built from `tools/cmd/dcs-sms/`. The current entry point in `main.go` calls `dispatch(os.Args[1:], os.Stdout, os.Stderr)`, which routes the first arg to a registered subcommand handler. With no args, `dispatch` prints usage and returns exit code 2 — fine for a power user, useless for a double-click.

DCS install path discovery lives in `tools/internal/dcspath/dcspath.go`. `DiscoverInstall` checks `override → DCS_SMS_DCS_INSTALL env → dcs_install` key in the config file at `%AppData%\dcs-sms\config.toml`. There is no automatic discovery of the install path (DCS install locations vary too much), so a fresh user has nothing in config and `DiscoverInstall` returns `"could not discover DCS install path"` until they pass `--dcs-path` once.

This is the friction the menu is built to remove.

## Architecture

One new file, `tools/cmd/dcs-sms/menu.go`. One new function in `tools/internal/dcspath/dcspath.go`. Small edits to `main.go` and `dispatch.go`. No churn anywhere else.

```
main.go
  └─ interactive := len(os.Args) <= 1 && term.IsTerminal(int(os.Stdin.Fd()))
  └─ dispatch(os.Args[1:], os.Stdin, os.Stdout, os.Stderr, interactive)

dispatch.go
  func dispatch(args, stdin, stdout, stderr, interactive) int
  └─ if len(args) == 0 && interactive   → runInteractiveMenu(stdin, stdout, stderr)
  └─ if len(args) == 0 && !interactive  → printUsage(stderr); return 2  (today's behavior)
  └─ otherwise                          → existing subcommand routing (unchanged)

menu.go
  func runInteractiveMenu(stdin io.Reader, stdout, stderr io.Writer) int
  loop:
    1. detect DCS install path via dcspath.DiscoverInstall("", cfg)
    2. print banner: version, "DCS install: <path>" or "DCS install: not detected …"
    3. print 4 numbered options + "q. Quit"
    4. read one line from stdin
    5. on "1" → installMeModCmd([]string{}, stdout, stderr); pause; return code
       on "2" → uninstallMeModCmd([]string{}, stdout, stderr); pause; return code
       on "3" → updateCmd([]string{}, stdout, stderr); pause; return code
       on "4" → promptAndSaveDCSPath(stdin, stdout, stderr); continue loop
       on "q" → return 0
       otherwise → reprompt; after 3 invalid attempts return 2

dcspath.go
  func SanitizeUserPath(s string) string
    1. trim whitespace
    2. strip a matching surrounding pair of quotes ("…", '…',
       smart double "…" U+201C/U+201D, smart single '…' U+2018/U+2019)
    3. strip a single stray leading or trailing quote of any of those four kinds
    4. trim whitespace again
    5. return filepath.Clean(s)
```

The menu reuses the existing subcommand handlers verbatim — no duplication of install/uninstall/update logic. TTY detection happens only in `main.go`, behind one `term.IsTerminal` call, so unit tests never need a real terminal.

Dependency added: `golang.org/x/term` (standard Go sub-repo). Used for one function call.

## Components

### `runInteractiveMenu` (new, `tools/cmd/dcs-sms/menu.go`)

Signature: `func runInteractiveMenu(stdin io.Reader, stdout, stderr io.Writer) int`. Pure-function design preserved — driven in tests with `strings.NewReader` and `bytes.Buffer`.

Banner format:

```
DCS-SMS  v0.5.0

  DCS install: D:\Eagle Dynamics\DCS World

  1. Install DCS-SMS Mission Editor mod
  2. Uninstall DCS-SMS Mission Editor mod
  3. Update dcs-sms.exe
  4. Set DCS install path manually
  q. Quit

Choose [1/2/3/4/q]: _
```

When discovery fails the install line reads `DCS install: not detected — pick option 4 to set it`.

Reads input with `bufio.NewReader(stdin).ReadString('\n')`. Whitespace and case are trimmed. Invalid input reprints the `Choose [1/2/3/4/q]:` prompt; after three invalid attempts, returns exit code 2 (defensive — prevents an infinite loop if stdin is closed or misbehaving in tests).

### `promptAndSaveDCSPath` (new, in `menu.go`)

Prompt format:

```
Paste your DCS install folder (the one containing MissionEditor\MissionEditor.lua).
Quotes are fine, they'll be stripped.
> _
```

Flow:

1. Read line from stdin.
2. Apply `dcspath.SanitizeUserPath`.
3. Validate: `os.Stat(path)` is a directory **and** `os.Stat(path/MissionEditor/MissionEditor.lua)` exists.
4. On success: call `dcspath.SaveInstallConfig(cfg, path)` (the same persistence the CLI uses), print `Saved.`, return to the menu loop. The redrawn menu shows the new path.
5. On failure: print a specific error (`not a directory: <path>` or `MissionEditor.lua not found at <path>\MissionEditor — is this really the DCS install root?`) and reprompt **once**. After two failed attempts, fall back to the main menu without saving.

### `SanitizeUserPath` (new, `tools/internal/dcspath/dcspath.go`)

Signature: `func SanitizeUserPath(s string) string`. Idempotent. Lives next to the rest of the path logic so other CLI code can reuse it later if needed.

Order of operations:

1. `strings.TrimSpace`.
2. If first and last rune are a matched pair from `{ "" "" '' "…" '…' }`, strip both. (Match means same-pair: a leading `"` only strips with a trailing `"`; a leading `"` U+201C only strips with a trailing `"` U+201D.)
3. If after step 2 the first rune is still any single quote-like character (`"`, `'`, `"`, `"`, `'`, `'`) without a matching partner at the end, strip only that one. Same on the trailing side.
4. `strings.TrimSpace` again.
5. Return `filepath.Clean(s)`.

Nested quotes inside the path (rare, e.g. an unusual folder name) are preserved — only the outermost matched pair is stripped.

## Data flow

Pure-function, dependency-injected throughout:

- `main.go` is the only place that reads `os.Args`, `os.Stdin`, calls `term.IsTerminal`, or invokes `os.Exit`. Two lines of new code there.
- `dispatch` becomes `func dispatch(args []string, stdin io.Reader, stdout, stderr io.Writer, interactive bool) int`. Existing tests in `dispatch_test.go` get a mechanical update at each call site to pass `nil` for stdin and `false` for `interactive` — preserving today's behavior.
- `runInteractiveMenu` and `promptAndSaveDCSPath` take `io.Reader`/`io.Writer` and never touch `os.*` directly.

## Error handling

The three action handlers (`installMeModCmd`, `uninstallMeModCmd`, `updateCmd`) already write their own errors to `stderr` and return non-zero exit codes. The menu propagates that exit code as its own. If an action fails, the user sees the existing error message in the same console window before the `Press Enter to exit...` prompt — so they have time to read it. (Today, double-click users see the error flash and disappear; this is a UX win on the failure path too.)

The post-action pause uses `bufio.NewReader(stdin).ReadString('\n')`. Cross-platform, accepts an extra newline if the user mashes the keyboard.

One non-obvious case worth noting: `update` swaps the running binary on Windows. After a successful self-update, the renamed-old binary is still running and can still print "Press Enter to exit" — Windows is fine with this. No special-casing needed.

## Testing

### `menu_test.go` (new)

- Each option (1, 2, 3) routes to the correct handler. Drive with `strings.NewReader("1\n\n")`. Use a stub registry: register fake handlers in a test helper instead of running real install/uninstall/update.
- `q` exits cleanly with code 0.
- Invalid input → reprompt → valid input → action.
- Three invalid attempts → exit code 2.
- Pause is honored (the trailing `\n` is consumed; menu does not return early).
- Banner shows the discovered DCS install path when config has one.
- Banner shows `not detected` when config is empty.

### `menu_test.go` — option 4 cases

- Happy path: paste valid path, validation passes, `SaveInstallConfig` is called against a tmp config file, menu redraws with the new path.
- Quoted path (`"D:\Program Files\…"`) is sanitized before validation and saved without quotes.
- Invalid path: error printed, reprompt once, then second invalid → fall back to main menu without saving.
- Path is a directory but lacks `MissionEditor\MissionEditor.lua` → specific error mentioning that file.

### `dcspath_test.go` — `TestSanitizeUserPath`

Table-driven cases:

| Input                                                | Expected                                          |
| ---------------------------------------------------- | ------------------------------------------------- |
| `D:\Eagle Dynamics\DCS World`                        | `D:\Eagle Dynamics\DCS World`                     |
| `"D:\Program Files\Eagle Dynamics\DCS World"`        | `D:\Program Files\Eagle Dynamics\DCS World`       |
| `'D:\Program Files\…\DCS World'`                     | `D:\Program Files\…\DCS World`                    |
| `"D:\…\DCS World"` (smart quotes U+201C / U+201D)    | `D:\…\DCS World`                                  |
| `'D:\…\DCS World'` (smart single quotes)             | `D:\…\DCS World`                                  |
| `"D:\…\DCS World` (lazy paste — only opening quote)  | `D:\…\DCS World`                                  |
| `D:\…\DCS World"` (only trailing quote)              | `D:\…\DCS World`                                  |
| `   "D:\…\DCS World"   ` (whitespace + quotes)       | `D:\…\DCS World`                                  |
| `D:\…\DCS World\\` (trailing separators)             | `D:\…\DCS World`                                  |
| `` (empty)                                           | `` (empty)                                        |

### `dispatch_test.go`

One new case: `len(args)==0, interactive=true` calls the menu (verified by output content); `len(args)==0, interactive=false` keeps printing usage + exit 2.

`main.go` itself has no tests today and stays that way — the TTY detection is one line and best verified by manual double-click + `dcs-sms.exe` from `cmd`.

## Decisions

Choices resolved during brainstorming. Recorded here so the implementer doesn't relitigate them.

- **Trigger:** No args **and** `term.IsTerminal(int(os.Stdin.Fd()))` returns true. Anything else (no args + piped stdin, or any subcommand) follows existing behavior. Considered: always-menu-on-no-args (rejected: would hang on `echo | dcs-sms.exe`), `GetConsoleProcessList` double-click detection (rejected: more code for marginal benefit).
- **After-action behavior:** Run one action, prompt `Press Enter to exit...`, exit. No loop-back to the menu for actions 1/2/3. Option 4 (set path) is the only loop-back case because it is preparatory.
- **Pause prompt:** "Press Enter to exit", read one line. Not "press any key" — that would require Windows-specific raw-mode (`golang.org/x/term.MakeRaw`) and adds complexity for no real gain.
- **Option 4 sanitization:** Strip surrounding matched quote pairs first (ASCII `"`, `'`, smart `"…"`, smart `'…'`), then strip a single stray leading or trailing quote of any of those kinds (lazy paste), then `filepath.Clean`. Nested mid-string quotes are preserved.
- **Option 4 validation:** Path must be a directory **and** contain `MissionEditor\MissionEditor.lua`. After two failed validation attempts in a row, fall back to the main menu without saving.
- **Option 4 persistence:** On success, write to the existing config file via `dcspath.SaveInstallConfig` — same persistence the CLI uses. Manually-set paths survive across launches.
- **Invalid menu input:** Reprompt up to three times, then exit code 2. Defensive — guards against an infinite loop on a closed/misbehaving stdin in tests.
- **Banner version:** Shows `version` from `main.go` (e.g. `0.1.0-dev` for local builds, the release tag for shipped binaries). No separate menu-mode version string.
- **Saved Games path:** Not surfaced in the menu. The three menu actions (install/uninstall/update) only need the DCS install path; Saved Games discovery used by `exec`/`status`/`tail-log` remains a CLI-only concern.

## Open questions

None. Anything not pinned above is delegated to the implementer's judgement (file layout within `tools/cmd/dcs-sms/`, exact wording of error messages, test naming, helper-function granularity).

## Versioning

Public surface change to `dcs-sms.exe` (new menu mode + new `dcspath.SanitizeUserPath` export). Per `AGENTS.md` §11, bumps the framework version. Update `CHANGELOG.md` in the same commit. Tag is announced separately.

## Out-of-band documentation

- `README.md` should mention "double-click `dcs-sms.exe` for an interactive menu" alongside the existing CLI quickstart. One line, in the same commit.
- `AGENTS.md` §7 module index needs no update (no new public `sms.*` module).
- No `docs/api/` page — this is a CLI surface, not a framework module.
