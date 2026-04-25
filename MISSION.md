# dcs-sms — Mission Statement

**dcs-sms** (Digital Combat Simulator Simple Mission Scripting) is a from-scratch scripting and tooling framework for DCS missions. It exists because the alternatives (DCS's stock Mission Editor and the MOOSE library) each fall short in ways that this project tries to fix.

## Why this exists

The DCS Mission Editor is limited and clunky. The trigger system is barebones. You cannot spawn anything that wasn't pre-placed on the map. The recurring pain point: there is no good way to express "this is an area where red and blue are fighting — generate a believable battle here and have units behave somewhat realistically." Doing that with the ME alone is essentially impossible.

[MOOSE](https://flightcontrol-master.github.io/MOOSE_DOCS_DEVELOP/Documentation/index.html) is the de-facto answer. It has solid object-oriented foundations and a decade of work behind it. But it has grown too large to comfortably reason about. PRs land without rigorous review. The code style is hard to follow. The docs are incomplete. In practice, ~95% of MOOSE goes unused on any given mission, and reaching for it has become more of a chore than a help. The natural reaction — write your own thing — risks reinventing what's already there.

## What dcs-sms is

A small, focused, maintainable framework that:

- Takes the best ideas from MOOSE — but reworks them into smaller, clearly-bounded units that are easy to understand, easy to test, and easy to change.
- Keeps scope narrow. Features earn their place. Anything that isn't pulling its weight gets cut.
- Treats automation as a first-class concern: spawning, respawning, and orchestrating realistic engagements should be expressible in a few lines, not improvised per-mission.
- Stays approachable. Docs and examples are part of the deliverable, not an afterthought.

## Stretch goals

- Mod or extend the DCS Mission Editor itself so it can work directly with the framework, if that turns out to be feasible.
- Compiled extensions (C++ and possibly Rust/Go) are on the table when there's a clear performance or capability win for in-DCS Lua to call into.

## Constraints to remember

- DCS embeds **Lua 5.2**. All scripts that run inside the simulator must be Lua 5.2 compatible.
- The mission environment is sandboxed by `MissionScripting.lua` — `os`, `io`, `lfs` are nilled. The hook environment (`Scripts/Hooks`) is not sandboxed and has access to LuaSocket.
- The `dcs_code_injector` (D:\git\dcs_code_injector) is the user's existing Lua-injection tool. It works but is janky: it listens for a fresh TCP connection on every simulation frame and only acknowledges receipt — it does not return actual results. Replacing it with a cleaner execute-and-read-back mechanism is the first sub-project of dcs-sms.

## How agents should approach this

- Default to small, well-bounded units. If a file is getting large or doing several things, that is a signal to split it.
- Prefer cutting features over adding speculative ones. YAGNI applies hard here — sprawl is what dcs-sms exists to avoid.
- When in doubt about scope or design, ask. The author has strong opinions informed by years in this domain.
