# dcs-sms — instructions for AI agents

## Read this first

[`AGENTS.md`](AGENTS.md) is the framework rules-and-conventions reference. Read it before writing any code that touches `framework/`. It covers the failure model (log + nil + never throw), conventions (degrees, meters, lowercase coalition strings), the universal handle pattern, the loading order, and the workflow for flagging gaps where vanilla DCS API still has to be used. For per-symbol API details (signatures, options tables, runnable examples), the canonical reference is [`docs/api/<module>.md`](docs/api/) — `AGENTS.md` only carries a one-line module index.

## Keeping AGENTS.md in sync

`AGENTS.md` is load-bearing. Agents and humans both rely on it as the orientation document. **It must not drift from the code.** Per-symbol API details live in `docs/api/`; what `AGENTS.md` carries is the §7 module index (one line per `sms.*` module) plus cross-cutting rules.

- **When you write a spec** under `docs/superpowers/specs/` that adds, removes, or renames a public `sms.*` module, the spec must explicitly list "Update `AGENTS.md` §7 module index" as part of its scope. Specs that only add or change symbols *within* an existing module update `docs/api/<module>.md` instead.
- **When you write a plan** under `docs/superpowers/plans/`, the plan must include a concrete task for the AGENTS.md / docs/api update. It is part of the deliverable, not a follow-up.
- **When you implement**, those doc updates land in the same PR / commit-set as the code change. A PR that adds new public surface without the corresponding doc update is incomplete.
- **When you review code**, treat a missing doc update as a review blocker for any change touching public surface.

## Keeping `docs/api/` in sync

Per-function reference pages with worked examples live at `docs/api/<module>.md` and are linked from the top-level `README.md`. They are load-bearing for users learning the framework — humans and agents both read them before writing mission code. **Any change that adds, removes, or renames a public `sms.*` symbol must update the relevant `docs/api/` page in the same change-set.** The full rule (specs / plans / implementation / review) is documented in [`AGENTS.md` §9](AGENTS.md#9-when-you-write-new-framework-code).

## Worktree directory

Use `.worktrees/` for new feature branches. It is gitignored. See the using-git-worktrees skill for the standard procedure.

## Commit and PR style

See top-level repo conventions (recent `git log` is the source of truth):
- Conventional-commit prefixes: `feat(<scope>)`, `fix(<scope>)`, `refactor(<scope>)`, `docs(<scope>)`.
- Scopes follow the directory: `framework`, `unit`, `events`, `bridge`, `spec`, `plan`, etc.
- Keep messages short; one-line subject + optional body. Detail belongs in the linked spec, not in the commit message.

## Don't suggest commits silently

The user's global preference: after substantial work, proactively suggest a commit but never run `git commit` (or push) without confirmation. Never push to remote without an explicit ask.
