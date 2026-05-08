# ME discovery session — framework

**Date:** 2026-05-08
**Status:** Approved (brainstorming phase)
**Scope:** Frame a live, demo-driven session that maps the DCS Mission Editor's Lua API surface (via the v0.5.0 bridge) and produces a findings log used as input to a future spec for native `dcs-sms me <verb>` commands.

## Problem

The bridge ships in v0.5.0. Agents can now run arbitrary Lua against the ME via `dcs-sms exec --target gui`. But every interesting operation (find an airbase, spawn a group, read mission state) currently requires the agent to reverse-engineer ED's internal modules at runtime — slow, expensive, error-prone (witness the broken-F-16 group from our first test).

The fix is a curated set of high-level commands (`dcs-sms me list-airbases`, `dcs-sms me spawn-prefab ...`, etc.). But before we design those commands, we need to know which operations are recurring and command-worthy versus one-off and recipe-worthy.

## Out of scope (for this session)

- Designing the actual command surface (`dcs-sms me <verb> [flags]`). That's a follow-up spec session.
- Implementing any commands.
- In-mission scripting (`target=mission`). ME-first per the user's brief.
- Building tooling around the reference-mission strategy (see below). Manual extraction is fine for v1.

## Approach

**Live demo-driven discovery.** The user feeds natural-language requests ("spawn a CAP at Akrotiri", "rename every SAM in the blue coalition", "set the time of day to dawn", "place the carrier strike group X miles south of Cyprus"). For each, the agent probes the ME live via the bridge and tries to make it work. Successful patterns get logged.

**Reference-mission strategy for complex shapes.** The user prepares a reference `.miz` containing canonically-correct examples: a CAP flight, a SAM site, a CAS pair, a sea group, a static container with cargo flags, etc. — full groups with proper waypoints, tasks, commands, options. When discovery hits a "this group structure is too rich to synthesize" wall (which we know happens — the F-16 spawn proved it), the agent reads templates from the reference mission rather than building from scratch. How exactly the reference mission gets stored and addressed (file path? extracted into prefabs? something else?) emerges from the probing — we don't decide up front.

**Findings log as the artifact.** A markdown file at `research/me-bridge-discovery-2026-05-08.md` accumulates entries during the session. Each entry follows a fixed shape so a later spec session can ingest them mechanically:

```markdown
## <natural-language request>
**Tag:** command-worthy | recipe | needs-more
**Touches:** <ME modules / globals — comma-separated>
**Snippet:**
``lua
-- working code
``
**Notes:** <quirks, gotchas, edge cases>
```

**Tag definitions:**
- `command-worthy` — Recurring pattern. Deserves a native `dcs-sms me <verb>`. Multiple agent sessions will hit this.
- `recipe` — Useful but specialized. Lives in the findings log as a documented snippet for future agents to copy. Doesn't need a native command.
- `needs-more` — Hit something interesting but didn't fully crack it. Revisit.

## Session flow

1. User saves a reference mission with example groups (optional — can be added during the session).
2. User feeds requests one at a time.
3. Agent probes via `dcs-sms exec --target gui`. When it works, append a findings entry. When it doesn't, either iterate or tag `needs-more`.
4. Session ends when the user is out of asks or we hit a natural stopping point.
5. Findings log is committed.

## What comes after this session

A separate spec session reads the findings log and designs the actual `dcs-sms me <verb>` command surface — naming, flag shapes, output formats, error modes. That spec goes through the normal /write-it flow (spec → plan → subagent-driven implementation).

## Decisions

- **Discovery is live, not source-read.** Reading `me_mission.lua` offline is a fallback for things the live probe can't reach.
- **Findings doc lives in `research/`**, not `docs/`. It's working notes, not durable reference. The follow-up spec is what graduates to `docs/`.
- **No tagging is permanent.** A `recipe` entry can be promoted to `command-worthy` later if multiple sessions hit it. A `command-worthy` entry can be downgraded if the spec session decides it's not worth a native verb.
- **Subcommand namespace = `dcs-sms me <verb>`** is the working assumption for the future command shape, not a commitment. Revisit at spec time.

## Stop conditions

- Out of natural-language requests.
- Hit a wall (DCS crashed, the bridge is broken, etc.) — fix and resume, or end session.
- User signals fatigue.

That's the whole design. Probing starts immediately after this is committed.
