# dcs-sms — instructions for AI agents

## Read this first

[`AGENTS.md`](AGENTS.md) is the dense framework reference. Read it before writing any code that touches `framework/`. It documents every public symbol, the failure model (log + nil + never throw), conventions (degrees, meters, lowercase coalition strings), and the workflow for flagging gaps where vanilla DCS API still has to be used.

## Keeping AGENTS.md in sync

`AGENTS.md` is load-bearing. Agents and humans both rely on it as the canonical surface map. **It must not drift from the code.**

- **When you write a spec** under `docs/superpowers/specs/` that adds, removes, or changes any public `sms.*` symbol, the spec must explicitly list "Update `AGENTS.md`" as part of its scope.
- **When you write a plan** under `docs/superpowers/plans/`, the plan must include a concrete task for the AGENTS.md update. It is part of the deliverable, not a follow-up.
- **When you implement**, the AGENTS.md update lands in the same PR / commit-set as the code change. A PR that adds new public surface without updating AGENTS.md is incomplete.
- **When you review code**, treat a missing AGENTS.md update as a review blocker for any change touching public surface.

## Keeping `docs/api/` in sync

Per-function reference pages with worked examples live at `docs/api/<module>.md` and are linked from the top-level `README.md`. They are load-bearing for users learning the framework — humans and agents both read them before writing mission code. **Any change that adds, removes, or renames a public `sms.*` symbol must update the relevant `docs/api/` page in the same change-set.** The full rule (specs / plans / implementation / review) is documented in [`AGENTS.md` §12](AGENTS.md#12-when-you-write-new-framework-code).

## Worktree directory

Use `.worktrees/` for new feature branches. It is gitignored. See the using-git-worktrees skill for the standard procedure.

## Commit and PR style

See top-level repo conventions (recent `git log` is the source of truth):
- Conventional-commit prefixes: `feat(<scope>)`, `fix(<scope>)`, `refactor(<scope>)`, `docs(<scope>)`.
- Scopes follow the directory: `framework`, `unit`, `events`, `bridge`, `spec`, `plan`, etc.
- Keep messages short; one-line subject + optional body. Detail belongs in the linked spec, not in the commit message.

## Don't suggest commits silently

The user's global preference: after substantial work, proactively suggest a commit but never run `git commit` (or push) without confirmation. Never push to remote without an explicit ask.
