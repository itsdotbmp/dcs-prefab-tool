---
description: Ship a dcs-sms release end-to-end — detect track, squash-merge to main, annotated tag, push, cleanup. Invoking /ship-it IS the explicit ship authorization; do not pause for further confirmation.
---

# /ship-it — autonomous dcs-sms release

The user has already verified everything works and is invoking `/ship-it` as the explicit ship authorization. **Do all the plumbing autonomously, in one go, without pausing for per-step confirmation.** You may push to remote — the user's CLAUDE.md "never push without explicit ask" is satisfied by them typing `/ship-it`.

Two parallel tracks (see `AGENTS.md` §11):
- **Framework** (`framework/`): tags `framework-vX.Y.Z`, in-source version at `framework/sms.lua` (`sms.version = "X.Y.Z"`).
- **ME-mod** (`tools/me-mod/`): tags `me-mod-vX.Y.Z`, in-source version at `tools/me-mod/lua/dcs_sms_me/version.lua`.

Detect the track in flight by comparing the in-source version to the latest matching tag — whichever is higher than its tag is the release. Both tracks can be ahead simultaneously; ship them as separate releases (one full pass each).

## What to do

1. **Pre-flight (fast-fail, don't auto-fix):**
   - `git status` clean
   - In-source version > latest tag for at least one track
   - `CHANGELOG.md` has a `### [X.Y.Z] — YYYY-MM-DD` entry under the right `## Framework` / `## ME-mod` section
   - If anything fails, stop and report exactly what's missing. The user fixes it manually then re-runs `/ship-it`.

2. **Land on main:**
   - If on a feature branch, squash-merge to `main` with a `release(<track>): v<X.Y.Z> — <summary>` commit. Use the CHANGELOG entry's first line as the summary; keep the body short (2-4 lines max) referencing the CHANGELOG for detail. Co-author trailer.
   - If already on `main` and the release commit is there, skip.
   - Mirror existing release-commit style (`git show 1febc59` for ME-mod v0.3.2).

3. **Annotated tag** the release commit on `main`:
   ```
   git tag -a <track>-v<X.Y.Z> -m "<track> v<X.Y.Z> — <summary>

   <full CHANGELOG entry body — Fixed/Added/Changed sections, verbatim>"
   ```
   Annotated only — never lightweight. Reference: `git show me-mod-v0.3.2`.

4. **Push** main and the new tag:
   ```
   git push origin main
   git push origin <track>-v<X.Y.Z>
   ```
   This triggers the CI release workflow that builds and publishes the artifact (`dcs-sms.exe` for ME-mod releases). Mention the workflow URL or `gh run watch` as a follow-up so the user can keep an eye on it.

5. **Cleanup:**
   - Delete the local feature branch.
   - Delete the remote feature branch.
   - If the work happened in `.worktrees/<dir>`, run `git worktree remove`.

6. **Report** at the end:
   - Tag name + sha pushed.
   - Any pending CI run URL (`gh run list --limit 1` if available).
   - One-line summary suitable for paste into Discord / release notes (pulled from the CHANGELOG entry's lead paragraph).

## Hard rules

- **Never** force-push `main`.
- **Never** `--no-verify` past a failing hook — investigate, surface, stop.
- **Never** use lightweight tags. Annotated only.
- **Never** tag a feature-branch tip — always tag a commit on `main`.
- **Never** rebase or amend a commit that's already been pushed.
- **Never** bump versions or write CHANGELOG entries inside `/ship-it` — those rode in with the substantive change. If the version isn't already bumped at /ship-it time, the precondition failed; stop and tell the user.

## Tone

Concise. One status line per step. No questions, no "want me to..."; the user has already said yes by invoking the command. If something fails, stop immediately and surface the exact error.
