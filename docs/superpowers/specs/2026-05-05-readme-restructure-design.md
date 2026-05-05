# README restructure — landing page + per-component pages

**Date:** 2026-05-05
**Status:** Drafted, pending implementation plan
**Driver:** The repo now ships three independent components (framework, ME-mod, CLI). The existing top-level `README.md` was written when only the framework + bridge existed; it has zero mention of the ME-mod, references pre-`sms.K` module names, and tries to be both pitch and quick-start. Several other READMEs are out of date or dead.

---

## User value

A new visitor lands on the repo and within 30 seconds can answer: "what does this project ship, and which page is for me?" Today the answer is "the framework, apparently? and a bridge tool? and there's a Mission Editor mod nobody mentioned." Three component READMEs each tailored to their audience replace one top-level README that has drifted out of sync with the code.

For existing users the change is also concretely useful: the ME-mod gets a discoverable, current install/uninstall page; the CLI gets a complete subcommand index instead of two half-pages in different folders; and the framework's first-taste snippet is updated to match the actual module names (`sms.K.country.USA`, not the long-removed `sms.countries.USA`).

## Decisions

These were settled during the brainstorming conversation; recording them so the implementer doesn't re-litigate:

- **CLI is its own component**, not folded into framework or ME-mod. It earns a top-level slot on the landing page and its own README at `tools/cmd/dcs-sms/README.md`.
- **Component READMEs live next to their code**, not centralised under `docs/`. GitHub-native auto-render at folder browsing.
- **No project pitch on the landing page.** `MISSION.md` is deleted (content survives in git history). The root README is purely a router.
- **Smoke checklists are release-gate procedure**, not user docs. They move to `docs/release-gate/` and link from `AGENTS.md`, not from the user-facing component READMEs.
- **The OVGME install path is officially dead.** The entire `tools/me-mod/ovgme/` skeleton tree is deleted, not just its README.
- **The standalone `tools/lua/README.md` is dead.** Its bridge content folds into the new CLI README; same audience, single home.
- **`docs/api/` stays as-is.** One outbound cross-link inside it gets updated. No content rewrite.

## Goal

Reshape the user-facing documentation so that:

1. The repo's **front door** (`README.md`) is a clean router — name, one-line tagline, three component links, a short pointer block. Nothing else.
2. Each component owns a **self-contained** README living next to its code, written for that component's audience.
3. Stale content is deleted (not migrated): the OVGME skeleton, the standalone bridge README, the `MISSION.md` essay all retire to git history.
4. Release-gate procedures (smoke checklists) move out of user-facing pages into a dedicated `docs/release-gate/` directory so casual readers don't see them, but we keep them around for releases.

The exercise is structural, not editorial. The goal is *where things live*, not a full content rewrite — though every page touched gets a correctness pass against the current state of the code.

## Non-goals

- Rewriting `docs/api/`. The per-module API reference is current and stays as-is (one cross-link inside it gets updated; otherwise untouched).
- Changing `AGENTS.md`, `CHANGELOG.md`, or anything under `docs/superpowers/`.
- Adding new content (badges, screenshots, demo gifs, install one-liners that span components). README polish is out of scope; this spec is purely about decomposition.
- Touching `.worktrees/` — gitignored, parallel worktrees are out of scope.

## Final structure

### Root `README.md` — router only

```
# dcs-sms

<one-sentence tagline — exact wording decided at implementation time; something like "DCS scripting framework, Mission Editor extension, and host-side tooling.">

## Components

- **Framework** — in-DCS Lua scripting framework (`sms.*`). → [`framework/README.md`](framework/README.md)
- **ME-mod** — DCS Mission Editor extension (Prefab Manager, etc.). → [`tools/me-mod/README.md`](tools/me-mod/README.md)
- **CLI / bridge** — host-side `dcs-sms.exe` for installing the above and live-poking a running mission. → [`tools/cmd/dcs-sms/README.md`](tools/cmd/dcs-sms/README.md)

## More

- [`docs/api/`](docs/api/) — framework API reference.
- [`CHANGELOG.md`](CHANGELOG.md) — release history (two parallel tracks).
- [`AGENTS.md`](AGENTS.md) — contributor rules and conventions.
```

That's the entire file. ~25 lines.

### `framework/README.md` — NEW

Audience: mission scripters who write Lua that runs inside DCS.

Contents:
- What it is + audience.
- Install (the `dofile("…/load_all.lua")` pattern, plus the bridge alternative).
- One short "first taste" snippet (lifted from the old root README and updated to use current symbol names — `sms.K.country.USA` instead of `sms.countries.USA`, etc.).
- A sentence pointing at `docs/api/` for the full reference.
- A sentence pointing at the **Framework** section of `CHANGELOG.md`.

Length: ~40 lines max.

### `tools/me-mod/README.md` — REWRITE

Audience: mission designers using the Mission Editor. May not write any Lua.

Contents:
- What it is + audience (zero Lua required).
- Install (`dcs-sms.exe install-me-mod`, `--dcs-path` flag, config caching).
- Feature overview — Prefab Manager (save / place / undo), airbase supplies, country override, etc. Short bullets, no UI deep-dives.
- Uninstall (`dcs-sms.exe uninstall-me-mod`).
- A sentence pointing at the **ME-mod** section of `CHANGELOG.md`.

Removed from current README: the OVGME DIY section, the long "manual smoke checklist", and the file-tree layout (the latter is contributor-facing and now lives in `AGENTS.md` / specs).

Length: ~60 lines max.

### `tools/cmd/dcs-sms/README.md` — NEW

Audience: anyone using either component — they all need the .exe.

Contents:
- What it is (Go-built host-side multi-tool, `dcs-sms.exe`).
- Install (download from a Release page, or `cd tools && go build ./cmd/dcs-sms` from source).
- Subcommand index, grouped by purpose:
  - **Bridge** — `install-hook`, `status`, `exec`, `tail-log`. Including the `MissionScripting.lua` sandbox-removal step (currently in `tools/lua/README.md`) — that is required, not optional, so it stays prominent.
  - **ME-mod** — `install-me-mod`, `uninstall-me-mod`. One-line each, pointer to `tools/me-mod/README.md` for context.
  - **Framework data** — `gen-units`. One-line; primarily a contributor concern.
- Each command: 1-2 lines of "what + when" + a single example invocation.

Length: ~80 lines.

## Files deleted

| Path | Reason |
|---|---|
| `MISSION.md` | Pitch/vision retires to git history per user decision; not part of the user-facing surface any more. |
| `tools/lua/README.md` | Bridge install + smoke content folds into the new `tools/cmd/dcs-sms/README.md` (smoke moves to release-gate). Same audience as the rest of the CLI. |
| `tools/me-mod/ovgme/dcs-sms-me-mod/README.md` | OVGME skeleton path was officially dropped when the .exe became the canonical install. |
| `tools/me-mod/ovgme/` (entire subtree) | Same — the skeleton is dead code; deleting the README without deleting the surrounding tree leaves a confusing orphan. |

## Files moved (release-gate split)

The two existing smoke checklists are release-gate procedure, not user docs. They move out of the user-facing READMEs and live in their own directory:

| New path | Source |
|---|---|
| `docs/release-gate/bridge-smoke.md` | The "Manual smoke checklist" section currently in `tools/lua/README.md`. |
| `docs/release-gate/me-mod-smoke.md` | The "Manual smoke checklist (Sub-project 3 — Prefab Manager)" section currently in `tools/me-mod/README.md`. |

These pages are linked from `AGENTS.md` (contributor surface), not from the user-facing component READMEs.

## Files unchanged (or near-unchanged)

| Path | Status |
|---|---|
| `AGENTS.md` | Add a one-line pointer to `docs/release-gate/` in the appropriate section. Otherwise unchanged. |
| `CHANGELOG.md` | Unchanged. The component READMEs link into its named sections (`#framework`, `#me-mod`). |
| `docs/api/README.md` | One cross-link update: line 15 currently says "See the top-level [`README.md`](../../README.md) for bridge setup." After the restructure, that pointer becomes `tools/cmd/dcs-sms/README.md`. Otherwise unchanged. |
| Per-module pages under `docs/api/` | Unchanged. |

## Open questions / risks

- **The `MissionScripting.lua` sandbox edit is still manual.** It must be visibly required in the CLI README; users who skip it will silently break the bridge. The new CLI README needs a "Required setup" callout for this.
- **`gen-units` is contributor-only.** It's listed for completeness in the CLI README, but the description should make it clear it's for developers regenerating the catalog, not for end users.
- **Deletion of `MISSION.md` is destructive but safe.** Content is preserved in git history; anyone who wants the pitch can read it via `git log -p` or by browsing an older tag. No external links to it are known to exist (it's a recent file, not yet linked from any release notes).

## Out-of-scope follow-ups

These are noted because they came up during brainstorming but are explicitly **not** part of this restructure:

- A landing-page rewrite that adds badges, screenshots, an animated demo, etc.
- Per-component CHANGELOG splits (currently a single `CHANGELOG.md` with two tracks — fine).
- Auto-generation of subcommand docs from `dcs-sms --help` output. Manual is fine for now.

## Implementation order (rough)

The plan skill will turn this into ordered tasks; sketching the natural sequence here:

1. Create `tools/cmd/dcs-sms/README.md` (new), folding in bridge content from `tools/lua/README.md`.
2. Create `framework/README.md` (new), with the first-taste snippet updated to `sms.K`.
3. Create `docs/release-gate/{bridge,me-mod}-smoke.md` from the existing smoke sections.
4. Rewrite `tools/me-mod/README.md` (drop OVGME, drop smoke, drop layout, link out).
5. Rewrite root `README.md` as the router.
6. Update `docs/api/README.md` cross-link (line 15).
7. Update `AGENTS.md` to reference `docs/release-gate/`.
8. Delete: `MISSION.md`, `tools/lua/README.md`, `tools/me-mod/ovgme/`.
9. Final pass: every README scanned for stale references to deleted files.

Each of those is a small, independently-reviewable change. The plan will batch them into commits sensibly.
