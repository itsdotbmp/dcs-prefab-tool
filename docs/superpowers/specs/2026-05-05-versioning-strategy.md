## Versioning Strategy — Design

**Date:** 2026-05-05
**Status:** Brainstorm
**Scope:** Establish a deliberate version-numbering scheme for the dcs-sms project — what to version, where the canonical version string lives, how it gets surfaced to users, and the release process (commit + tag + changelog). Touches `framework/sms.lua` (an existing field's semantics), adds a new ME-mod version helper, and codifies the workflow in `AGENTS.md` §6 / `CLAUDE.md`.

## Goal

Move from "version numbers exist informally" to a tracked discipline. Today: `sms.version = "0.1.0"` in `framework/sms.lua` has been frozen since April 25 while nine `framework-v0.x.0` git tags have been created (the most recent being `framework-v0.9.0`, 2026-04-27); the ME-mod has no version at all; the prefab-data format version (`PREFAB_VERSION = "0.3.0"`) is the only thing currently bumped on schedule. End state: every release moves an in-source version string in the same commit as the git tag, and that version is visible from inside DCS so a user reporting a bug can say "I'm on framework 0.10.1, me-mod 0.2.0" without grepping a git checkout.

## Non-goals

- **Not migrating to 1.0.** The public `sms.*` surface is still being shaped (open issues #15 sms.mission, #23 sms.airdrome, #3 bridge auto-return). 1.0 commits to API stability across breaking changes, which the project isn't ready for. Stay in 0.x and bump minor for breaks until the surface stops moving.
- **Not unifying repo-wide into a single `vX.Y.Z`.** The framework and the ME-mod ship at different cadences for different audiences (mission scripts vs editor users). One version forces churn on the unmoving component every time the other ships. Keep them on separate tracks. The `PREFAB_VERSION` data-format string stays a third independent track.
- **Not introducing automated release tooling** (no semantic-release, no GitHub Releases automation, no changelog generators). Manual `git tag` + a hand-edited line in the version file remains the workflow. Cheap and unambiguous for a single-developer repo.
- **Not versioning anything below the public surface.** Internal helpers, test fixtures, and per-symbol `docs/api/*.md` pages don't get individual version stamps.

## Background — current state

| Surface | In-source string | Most recent tag | Notes |
| --- | --- | --- | --- |
| Framework (`sms.*`) | `sms.version = "0.1.0"` (`framework/sms.lua:23`) | `framework-v0.9.0` (c50ede4, 2026-04-27) | The string is stale by 9 minor bumps. Tagging stopped after `sms.weapon`. |
| ME-mod (`tools/me-mod/`) | none | none | Active development since May — Prefab Manager v1, airbase supplies, undo, native MsgWindow popups, severity-coloured status, etc. — all unversioned. |
| Prefab data format | `PREFAB_VERSION = "0.3.0"` (`prefab_distill.lua:25`) | n/a (data, not release) | Already moves on its own schedule — bumped to 0.3.0 with airbase supplies. Stays untouched by this spec. |

The nine `framework-v0.x.0` tags each correspond to a single-module milestone (logger → sms.group → sms.timer → sms.unit → sms.area → group.create/clone → sms.static → sms.events → sms.weapon), so 0.x bumps have been minor in semver terms — additive features with potential breaks. That cadence continues.

## Decisions

### 1. Two independent version tracks, both in semver 0.x.y

- **Framework:** continues `framework-v0.X.Y`. Next release is **`framework-v0.10.0`** — `sms.task` and any backlog cleanups since `0.9.0`. Reserve `framework-v1.0.0` for the moment we're confident the public `sms.*` API has stopped breaking.
- **ME-mod:** starts fresh at **`me-mod-v0.1.0`**. This snapshot is the first explicit ME-mod release: Prefab Manager with save / scan / load / place (origin + click) / undo / rename / delete, search + sort + country dropdown + rotation gizmo + airbase supplies + ship warehouses + native MsgWindow prompts + severity-coloured status. Future releases bump per the rule below.
- **Prefab data format:** unchanged, stays internal at `PREFAB_VERSION = "0.3.0"`. Explicitly NOT a third release-track tag.

### 2. Bump rules (semver-flavoured)

| Bump | When |
| --- | --- |
| **Patch** (`0.x.y` → `0.x.y+1`) | Pure bug fix — no new public symbols, no behaviour change for working callers. Example: today's catalog-validation refusal would be a patch since it changes a previously-broken case (silent corruption) into an explicit error. |
| **Minor** (`0.x.y` → `0.x+1.0`) | New public function / module / UI feature, OR a breaking change to an existing one (allowed under 0.x). Example: shipping `sms.airdrome` is a minor; renaming a callback shape is a minor. |
| **Major** (`0.x.y` → `1.0.0`) | One-time. Triggered when the user decides the public surface is stable enough to commit to deprecation cycles for breaking changes. Not on the table for v1. |

The asymmetry vs strict semver: under 0.x we treat minor as the "anything goes" tier rather than splitting break vs add into major vs minor. This matches what the framework's already been doing through 0.1 → 0.9.

### 3. Single source of truth per component, in source

- `framework/sms.lua` already has `sms.version = "..."`. Bump the string to `"0.10.0"` in the commit that creates the next framework tag.
- ME-mod gets a new module **`tools/me-mod/lua/dcs_sms_me/version.lua`** that returns a single string. `init.lua` requires it, sets `M.version`, and the bootstrap log line includes it. `M.version` is also exposed in the Prefab Manager's About / window-title overflow if there's room — but the log line is the contract.
- The git tag is the *announcement*; the in-source string is the *truth*. They land in the same commit.

### 4. Tag format and message

- Annotated tags only (`git tag -a`), never lightweight. The annotation message is the release summary — what changed, what to know.
- Tag prefix matches the component: `framework-v0.10.0`, `me-mod-v0.1.0`. No bare `v0.1.0` tags; the prefix is what disambiguates the two tracks on `git tag -l`.
- Tag points at the commit that bumped the in-source version, not a separate "release" commit.

### 5. Surfacing the version to users

- **Framework:** `sms.version` is already exposed; the bootstrap log line at `framework/load_all.lua:53` already prints it. No additional UI.
- **ME-mod:** the bootstrap log line in `init.lua` includes `version` (e.g. `"sms.me bootstrap ok (12 modules, version 0.1.0)"`). The log destination is `dcs.log`, the same place the framework already writes — easily greppable. No status-bar or title-bar exposure needed for v1.
- **Prefab Manager title bar:** stays plain (`"dcs-sms — Prefab Manager"`). The version is in the log, not the chrome.

### 6. CHANGELOG

- A single top-level **`CHANGELOG.md`**, sections per component (`## Framework` and `## ME-mod`), entries grouped by version. Manually maintained. Each released tag gets one section. Patch/minor decisions are obvious from the diff between tagged commits, so the changelog stays human-readable rather than mechanically derived.
- Format borrowed from Keep-a-Changelog — Added / Changed / Fixed / Removed buckets — but loose; not enforced.

## Non-decisions / open questions

- **Pre-release suffixes (`-rc.1`, `-alpha`):** unused. If we end up wanting to share a build before tagging, the answer is "share the commit hash, don't pre-release-tag." Revisit if real users start consuming releases.
- **Who can tag:** repo-owner-only. No other contributors yet.
- **Backporting fixes to old releases:** out of scope. Bug fixes land on `main` and the user picks them up by upgrading. No long-term-support branches.
- **The 0.1 → 0.9 → 0.10 jump for the framework.** Some projects skip "10" because they read it as "10 in decimal" and prefer 1.0. We do not — semver minor/patch are integers, not decimals. `0.10.0` follows `0.9.0` cleanly.

## Implementation plan

The spec is small enough that a separate plan doc is overkill — the steps are linear and obvious:

1. **Framework catch-up:**
   - Edit `framework/sms.lua:23` — `sms.version = "0.10.0"`.
   - Add `CHANGELOG.md` at repo root with the full `## Framework` history reconstructed from git log between the existing tags (one-time effort; a few lines per tag).
   - `git commit` with message `chore(framework): bump version to 0.10.0`.
   - `git tag -a framework-v0.10.0 -m "<summary>"` pointed at that commit.

2. **ME-mod first release:**
   - Create `tools/me-mod/lua/dcs_sms_me/version.lua` returning `"0.1.0"`.
   - Update `tools/me-mod/lua/dcs_sms_me/init.lua` to require it, set `M.version`, and include the version in the bootstrap log line.
   - Mirror to install path.
   - Add a `## ME-mod` section to `CHANGELOG.md` with the v0.1.0 highlights (Prefab Manager + airbase supplies + undo + native popups + severity status).
   - `git commit` with message `chore(me-mod): version 0.1.0`.
   - `git tag -a me-mod-v0.1.0 -m "<summary>"` pointed at that commit.

3. **Codify the rules:**
   - Add a §6 "Versioning and Releases" section to `AGENTS.md` that summarises decisions §1-§5 above, so the next contributor (or a future-me) can find the workflow without re-reading this spec.
   - Add a sentence to `CLAUDE.md` saying "every public-surface change includes the in-source version bump in the same commit; tags are annotated and prefixed by component."

4. **Push.** The user pushes, then can keep working.

After landing, the workflow per release becomes: bump the string → write the changelog entry → commit → annotated tag → push (with `--follow-tags` or a separate `git push origin <tag>`).

## Acceptance

- `git tag -l` shows `framework-v0.10.0` and `me-mod-v0.1.0`.
- Loading the framework in DCS prints `version 0.10.0` in dcs.log.
- Loading the ME-mod in DCS prints `version 0.1.0` in dcs.log.
- `CHANGELOG.md` has both component sections with at least the latest entry.
- `AGENTS.md` §6 documents the bump rules and tag format so the workflow is self-serve.
