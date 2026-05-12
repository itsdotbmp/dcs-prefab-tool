# dcs-sms — instructions for AI agents

## Read this first

This repo's contributor reference is in [`AGENTS.md`](AGENTS.md) plus three sub-project files:

- [`AGENTS.md`](AGENTS.md) — repo orientation + cross-cutting rules (commits, versioning, doc sync, worktrees).
- [`framework/AGENTS.md`](framework/AGENTS.md) — in-DCS Lua framework (`sms.*`).
- [`tools/cmd/dcs-sms/AGENTS.md`](tools/cmd/dcs-sms/AGENTS.md) — host-side `dcs-sms.exe` CLI internals.
- [`tools/me-mod/AGENTS.md`](tools/me-mod/AGENTS.md) — Mission Editor mod + `me <noun> <verb>` verbs (both *using* them and *contributing* them).

**Read the AGENTS.md for the area you're touching before writing code.** Root-level cross-cutting rules in [`AGENTS.md`](AGENTS.md) apply to all three sub-projects — don't duplicate them.

## Don't suggest commits silently

The user's global preference: after substantial work, proactively suggest a commit but never run `git commit` (or push) without confirmation. Never push to remote without an explicit ask.
