# `dcs-sms update` — host-side self-updater

**Date:** 2026-05-06
**Status:** Drafted, pending implementation plan
**Driver:** The release flow currently asks users to redownload `dcs-sms.exe` from GitHub when a new ME-mod version ships. The filename has no version in it, so users can't tell from disk what version they have, and running `install-me-mod` from an older `dcs-sms.exe` regresses the installed mod silently. A `dcs-sms update` subcommand that fetches the latest release in place removes the manual-download step and the silent-regress footgun.

---

## Goal

Add a new `update` subcommand to the host-side CLI. When run, it queries the GitHub Releases API for the most recent release that ships a `dcs-sms.exe` asset, compares the asset's tag version against the binary's own embedded version, and (if newer) downloads and replaces the running binary in place. A `--check` flag short-circuits the actual swap and just reports what would happen.

A minor cross-cutting fix lands as part of this work: the build currently embeds `version = "0.1.0-dev"` regardless of which tag the binary was cut from. The release workflow gets a `-ldflags="-X main.version=$VERSION"` so each released binary correctly identifies itself.

## User value

A non-technical mission designer who installed `dcs-sms.exe` last month wants the latest ME-mod features. They run `dcs-sms.exe update`. The .exe is replaced in place. They re-run `install-me-mod`, restart DCS, and they have the new version. Two commands, no browser, no "where did I save it last time", no risk of running an older `install-me-mod` over a newer install.

For someone curious: `dcs-sms.exe update --check` answers "is there an update?" without committing to anything.

## Scope

### In scope

- New `update` subcommand registered in the existing `init() { register(...) }` pattern.
- `--check` flag for "report only, don't download or swap".
- Windows file-replacement using the rename-then-write pattern (`os.Rename` works on a running .exe on Windows; on Unix it works because of how inode references survive rename).
- GitHub Releases API integration via stdlib `net/http`, no external libraries.
- Tag-version comparison via a small inline semver helper (`update_semver.go`) — handles `0.x.y` plus an optional `-dev` style prerelease suffix.
- Release workflow change: pass the tag-derived version into the build via `-ldflags`.
- Documentation updates: subcommand reference in `tools/cmd/dcs-sms/README.md`, a sentence in `tools/me-mod/README.md`'s Update section pointing users at `dcs-sms.exe update` as the primary update path.
- Unit tests using `httptest.NewServer` for the API path and a tempdir for the swap path.

### Out of scope

- **Cross-platform updates.** Linux/macOS users get a clear "self-update is Windows-only; rebuild from source" message. The release workflow is not extended to ship Linux/macOS assets.
- **Checksum / signature verification.** The release workflow doesn't currently produce checksums; adding that is a separate concern. Update verifies the download is non-empty and roughly the size of the previous binary, but no cryptographic verification.
- **Downgrade.** If the local version is newer than latest (e.g., a release got yanked, or you're running a `-dev` build), `update` reports "Up to date" and exits. No `--force-downgrade` flag — YAGNI.
- **`update`-then-`install-me-mod` chaining.** `update` is a discrete command; the user runs `install-me-mod` themselves afterwards.
- **Auto-update on launch / scheduled checks.** No background polling, no nag messages from `install-me-mod`. This spec is purely the explicit `update` command.
- **Cleanup of `dcs-sms.exe.old`.** The rename dance leaves an `.old` artefact. We don't proactively delete it; stale `.old` files are not load-bearing and the user can clean them up manually.

## Constraints

- **Stdlib only.** No new Go module dependencies (`go.mod` currently has only `github.com/google/uuid`; that stays the only direct dep). The semver comparator is written inline.
- **No external services beyond GitHub.** API calls hit `https://api.github.com/repos/nielsvaes/dcs-sms/releases` only.
- **30-second timeout on the API call**, **5-minute timeout on the asset download**. Both via `http.Client.Timeout`.
- **Idempotent on a race.** If two `update` invocations run simultaneously, the worst outcome is one of them wins the rename and the other fails cleanly. No partial writes to disk visible to other processes.
- **Quiet by default.** Single-line status updates; no progress bars (stdlib doesn't have one and the binary is ~6 MB so download takes seconds).
- **Failure recovery.** If anything fails *before* the rename, the existing `dcs-sms.exe` is unchanged. If the download succeeds but the rename fails, the user sees a clear message and the partial download is cleaned up.

## Decisions

These are choices made during brainstorming and during spec authoring. Recorded so the implementer doesn't re-litigate.

- **Discrete one-shot command, no follow-up `install-me-mod`.** `update` does the swap and stops. Compositional, smaller failure surface.
- **Windows only.** Confirmed in conversation: DCS is Windows-only and Linux/macOS users of the bridge subcommands are by definition developers who can `go build`. Non-Windows invocation prints a clear message and exits non-zero.
- **No interactive prompts.** Running `update` is itself the consent. Idiot-proof for non-technical users; scriptable for automated update sweeps. `--check` is the read-only escape hatch for "I want to look first".
- **Stdlib-only implementation.** Adds zero deps to `go.mod`. The cost is ~20 lines of semver-comparison code + tests. Worth it for the dependency posture.
- **Inline semver helper, not `golang.org/x/mod/semver`.** The version format is constrained (`MAJOR.MINOR.PATCH` with optional `-prerelease` suffix). A 20-line comparator covers the cases we need and stays in stdlib-only territory. (If a future change needs richer comparison — build metadata, complex prerelease ordering — pulling in `golang.org/x/mod/semver` is a one-commit upgrade.)
- **Release detection by asset name, not by tag pattern.** The latest release with a `dcs-sms.exe` asset wins. Robust to future release-track changes (e.g., if `framework-v*` ever starts producing GitHub releases, the asset filter still does the right thing — only releases that ship the .exe are considered).
- **Rename to `dcs-sms.exe.old`, write new bytes, exit.** The user is told to `dcs-sms install-me-mod` next. We do NOT auto-delete `.old` — the file is harmless; cleaning it up adds a foot-cannon if the rename succeeds but the user expected the previous version still around.
- **Embed version via `-ldflags` at build time.** The release workflow gains `-X main.version=${{ steps.ver.outputs.version }}` so released binaries identify as `0.X.Y` instead of `0.1.0-dev`. Local `go build` (no ldflags) keeps the `-dev` suffix as a "you're running an unreleased build" signal.
- **`-dev` suffix means "always update available".** The semver comparator treats `0.1.0-dev` < `0.1.0`. Running `update` from a dev build always offers to install the corresponding (or newer) release.
- **GitHub API anonymous, unauthenticated.** No token. The unauthenticated rate limit (60 req/hour per IP) is plenty for "ran update once" — and avoiding tokens means no setup story for users.
- **File layout:** four new files under `tools/cmd/dcs-sms/` — `update.go` (command), `update_release.go` (GitHub API call), `update_swap.go` (rename dance), `update_semver.go` (inline comparator). Plus `update_test.go`, `update_release_test.go`, `update_swap_test.go`, `update_semver_test.go`. Each unit small enough to hold in one screen.

## Open questions

None. The conversation settled the user-facing behaviour; the implementation choices above are well-bounded.

## Cross-cutting changes

Beyond the new files in `tools/cmd/dcs-sms/`:

- **`tools/cmd/dcs-sms/main.go`** — leave the `version = "0.1.0-dev"` const but ensure ldflags can override it. (`const` won't accept ldflags overrides; needs to be `var version = "0.1.0-dev"`. One-line change.)
- **`tools/cmd/dcs-sms/dispatch.go`** — `printUsage` gets a new line for `update`.
- **`.github/workflows/release-me-mod.yml`** — the build step's `go build` invocation gains `-ldflags="-s -w -X main.version=${{ steps.ver.outputs.version }}"` (extending the existing `-s -w`).
- **`tools/cmd/dcs-sms/README.md`** — new subsection under "Subcommands" documenting `update` and `update --check`.
- **`tools/me-mod/README.md`** — the existing **Update** section's first sentence updates to lead with `dcs-sms.exe update` as the primary path. The "download the new .exe manually" form stays as a fallback paragraph for users who prefer it.
