---
description: Walk through a dcs-sms release (framework or ME-mod) — pre-flight, land on main, tag, push — with explicit confirmation at every destructive step.
---

# /ship-it — guided dcs-sms release flow

You're shipping a dcs-sms release. Two parallel tracks, both semver `0.x.y`:

- **Framework** (`framework/`): tags `framework-vX.Y.Z`, in-source version at `framework/sms.lua` (`sms.version`).
- **ME-mod** (`tools/me-mod/`): tags `me-mod-vX.Y.Z`, in-source version at `tools/me-mod/lua/dcs_sms_me/version.lua`.

See `AGENTS.md` §11 for the canonical rules.

**Hard rule:** never run a destructive or remote-affecting git operation (commit, merge, tag, push) without explicit user confirmation in the same turn. Surface the exact command and wait for "yes" / "ship" / "go". Default to NO. The user's CLAUDE.md global says "never push to remote without an explicit ask".

Walk the user through these steps **one at a time**. Don't batch.

## 1. Pre-flight

Run, then report findings:

- `git status` — must be clean (no uncommitted changes).
- `git branch --show-current` and `git log --oneline -5` — orient on branch and recent commits.
- Detect track by comparing in-source versions to the latest tag:
  - `cat framework/sms.lua | grep -i "sms.version"` vs `git tag -l "framework-v*" --sort=-v:refname | head -1`
  - `cat tools/me-mod/lua/dcs_sms_me/version.lua` vs `git tag -l "me-mod-v*" --sort=-v:refname | head -1`
  - Whichever in-source version is **higher** than its latest tag is the track being released. Both can be ahead in a single session — handle as separate releases (one full /ship-it cycle each).
- Verify `CHANGELOG.md` has a `### [X.Y.Z] — YYYY-MM-DD` entry under the right section (`## Framework` or `## ME-mod`).

If anything is wrong (uncommitted work, version not bumped, no CHANGELOG entry) — STOP, report the issue, ask the user how to proceed. Don't auto-fix.

## 2. Land on main

If the user is on a feature branch:

- Show `git log main..HEAD --oneline` so the user sees what's about to land.
- Recommend squash-merge to match the existing release-commit style (look at `1febc59` for ME-mod v0.3.2 and `35f7119` for v0.3.0 — both are single release commits on `main`). Suggest:

  ```
  git checkout main
  git pull --ff-only origin main
  git merge --squash <branch>
  git commit -m "release(<track>): v<X.Y.Z> — <one-line summary>

  <optional 2-3 line body>

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

  The summary should match the CHANGELOG entry's tone. Co-author trailer if the AI was substantively involved (the user can drop it if not).

- Wait for explicit confirmation before running.

If the user is already on `main` and the release commit is already there (e.g. from a direct commit), skip to step 3.

## 3. Annotated tag

Format: `<track>-v<X.Y.Z>` (`framework-v0.10.0`, `me-mod-v0.3.3`, etc.). **Annotated only** — never lightweight.

Pull the message body verbatim from the corresponding `### [X.Y.Z]` block in `CHANGELOG.md`, preserving the **Fixed** / **Added** / **Changed** subheadings. Format:

```
git tag -a <track>-v<X.Y.Z> -m "<track> v<X.Y.Z> — <summary line>

<full CHANGELOG entry body — Fixed/Added/Changed sections>"
```

Look at `git show me-mod-v0.3.2` for a reference of the annotation style.

Wait for explicit confirmation before tagging.

## 4. Push

```
git push origin main
git push origin <track>-v<X.Y.Z>
```

These hit the remote. **Wait for explicit "push" / "ship" / "yes" / "go"** before running. Default to NO.

## 5. Cleanup

After successful push:

- Delete local feature branch: `git branch -d <branch>`
- Delete remote feature branch: `git push origin --delete <branch>` (or `git push origin :<branch>`)
- If the work happened in a `.worktrees/` directory: `git worktree remove .worktrees/<dir>`

Suggest each one, wait for confirmation. Each is reversible-ish but all touch state — don't batch.

## 6. Done

Report:
- Tag created and pushed: `<track>-vX.Y.Z`
- Main is at `<sha>` on origin.
- Cleanup status (branch deleted, worktree removed).
- Suggest the user verify the tag landed correctly (`gh release view <track>-vX.Y.Z` if they use gh, or just check the GitHub UI).

If the project has a release-gate checklist for the track (`docs/release-gate/me-mod-smoke.md`, `docs/release-gate/bridge-smoke.md`), mention it as a post-release verification step. Don't auto-run.

## Don'ts

- Don't bump versions inside `/ship-it`. The version bump rides in the same commit as the substantive change (per AGENTS.md §11), not at ship time.
- Don't write CHANGELOG entries inside `/ship-it`. Same reason.
- Don't use lightweight tags. Annotated only.
- Don't `--no-verify` past a failing hook. Investigate and fix.
- Don't force-push `main`. Ever.
- Don't tag a feature-branch tip — always tag a commit on `main`.
- Don't rebase or amend commits that have already been pushed (per CLAUDE.md global).

## Output tone

Brief, one suggestion at a time. After each suggestion, wait for the user. A status line per step, not a wall of text.
