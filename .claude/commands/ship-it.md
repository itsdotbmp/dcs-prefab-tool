---
description: Ship a dcs-sms release end-to-end — derive next version, finalize CHANGELOG, bump version file, commit, tag, push, cleanup. Invoking /ship-it IS the explicit ship authorization; do not pause for further confirmation.
---

# /ship-it — autonomous dcs-sms release

The user has invoked `/ship-it` as explicit ship authorization. **Do everything the release needs autonomously and in one go**, including bumping the in-source version and finalizing the CHANGELOG `[Unreleased]` entry. You may push to remote. No "want me to..." questions.

Optional arg: a version string (e.g. `/ship-it 0.9.0` or `/ship-it me-mod 0.9.0`). If a version is provided, use it verbatim. If a track name is provided, ship only that track. If both arguments are omitted, auto-detect both.

Two parallel tracks (see `AGENTS.md` §11):
- **Framework** (`framework/`): tags `framework-vX.Y.Z`, in-source version at `framework/sms.lua` (`sms.version = "X.Y.Z"`).
- **ME-mod** (`tools/me-mod/`): tags `me-mod-vX.Y.Z`, in-source version at `tools/me-mod/lua/dcs_sms_me/version.lua`.

## Detect the track(s) in flight

Read `CHANGELOG.md`. Under each `## Framework` / `## ME-mod` section, look for a `### [Unreleased]` heading. Each Unreleased entry is a release in flight on that track.

- If exactly one track has an Unreleased entry → ship that one.
- If both tracks have Unreleased entries and no track argument was passed → ship them sequentially (ME-mod first, framework second), one full pass each.
- If neither has an Unreleased entry → stop and report "nothing to ship; no `[Unreleased]` in CHANGELOG."

## Compute the next version

For each track being shipped:

1. If the user passed an explicit version, use it.
2. Otherwise, read the in-source version (`return "X.Y.Z"` in `version.lua` or `sms.version = "X.Y.Z"` in `framework/sms.lua`). This is the previous version.
3. Inspect the Unreleased entry's section headers in CHANGELOG:
   - Contains a `**Breaking**` section → bump major (X+1.0.0)
   - Else contains `**Added**` → bump minor (X.Y+1.0)
   - Else (only `**Fixed**` / `**Changed**` / `**Internal**`) → bump patch (X.Y.Z+1)

Print the derived version and proceed without asking.

## Steps (per track being shipped)

1. **Pre-flight:**
   - `git status` clean (any uncommitted changes → stop and report)
   - Current branch is `main` OR a feature branch with work to merge
   - The selected track has an `[Unreleased]` CHANGELOG entry
   - If anything fails, stop and report exactly what's missing.

2. **Bump in-source version + finalize CHANGELOG entry:**
   - Edit `tools/me-mod/lua/dcs_sms_me/version.lua` (or `framework/sms.lua`) to the new version.
   - Edit `CHANGELOG.md`: rewrite the line `### [Unreleased]` (under the appropriate track section) to `### [<X.Y.Z>] — <YYYY-MM-DD>` using today's UTC date.

3. **Land on main:**
   - **If currently on a feature branch:** stage and commit the version-bump + CHANGELOG edit on the feature branch as a prep commit. Then squash-merge to `main` with title `release(<track>): v<X.Y.Z> — <summary>`. Summary = the most informative line from the CHANGELOG entry — typically the first `**Added**` bullet condensed, or the lead paragraph if no Added section. Keep the body 2-4 lines max referencing the CHANGELOG. Co-author trailer.
   - **If already on main:** stage the version-bump + CHANGELOG edit and commit directly on main as `release(<track>): v<X.Y.Z> — <summary>`.
   - Either way, the commit at `main` HEAD is the release commit.

4. **Annotated tag** the release commit on main:
   ```
   git tag -a <track>-v<X.Y.Z> -m "<track> v<X.Y.Z> — <summary>

   <full CHANGELOG entry body — Fixed/Added/Changed sections, verbatim>"
   ```
   Annotated only — never lightweight. Reference: `git show me-mod-v0.8.1`.

5. **Push** main and the new tag:
   ```
   git push origin main
   git push origin <track>-v<X.Y.Z>
   ```
   This triggers the CI release workflow that builds and publishes the artifact (`dcs-sms.exe` for ME-mod releases). Mention the workflow URL or `gh run watch` so the user can follow it.

6. **Cleanup:**
   - If a feature branch was squash-merged: delete it locally (`git branch -d`) and remotely (`git push origin --delete`).
   - If the work happened in a `.claude/worktrees/<dir>` or `.worktrees/<dir>`, run `git worktree remove` from the main repo root.

7. **Report:**
   - Tag name + commit SHA pushed.
   - Any pending CI run URL (`gh run list --limit 1 --json url --jq '.[0].url'` if `gh` available).
   - One-line summary suitable for paste into Discord / release notes (drawn from the CHANGELOG entry's lead Added/Changed bullet).

## Hard rules

- **Never** force-push `main`.
- **Never** `--no-verify` past a failing hook — investigate, surface, stop.
- **Never** use lightweight tags. Annotated only.
- **Never** tag a feature-branch tip — always tag a commit on `main`.
- **Never** rebase or amend a commit that's already been pushed.
- **Never** invent a version number that doesn't match the heuristic AND wasn't passed explicitly. If you're uncertain, surface the question once at the top and then proceed with the user's answer; do NOT silently pick a major bump for an "Added"-only changelog.

## Tone

Concise. One status line per step. No questions, no "want me to..."; the user said yes by invoking the command. If something fails, stop immediately and surface the exact error.
