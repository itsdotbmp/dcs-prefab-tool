# Changelog

This project ships two parallel components on independent semver tracks:

- **Framework** (`framework/`) — the runtime `sms.*` API loaded into mission scripts. Tags: `framework-v0.X.Y`. Canonical version: `sms.version` in `framework/sms.lua`.
- **ME-mod** (`tools/me-mod/`) — the Mission Editor extension. Tags: `me-mod-v0.X.Y`. Canonical version: `tools/me-mod/lua/dcs_sms_me/version.lua`.

Format loosely follows [Keep a Changelog](https://keepachangelog.com). Both tracks live in 0.x — minor bumps may include breaking changes; major bump (1.0) is reserved for the moment the public surface stabilises.

---

## Framework

### [0.10.0] — 2026-05-05

This is the first tag after a long quiet period — `sms.version` had been frozen at `"0.1.0"` while nine `framework-v0.x.0` tags shipped through April 27. 0.10.0 catches the in-source string up to reality and folds in everything added since `framework-v0.9.0`.

**Added**
- `sms.task` — task spec builders covering move-to, attack, orbit, escort, refueling, and more, with per-category adaptation.
- `sms.options` — group options (ROE, alarm state, formation, …) wired through `sms.K` enums.
- `sms.commands` — runtime commands: start/stop firing, set frequency, set callsign.
- `sms.rule` — declarative AI rule API.
- `sms.K` — central enum namespace. Subsumes the previous standalone `sms.countries` / `sms.skill` / `sms.alt_type` / `sms.waypoint` / `sms.targets` / `sms.designations` modules and adds `sms.K.coalition`, `sms.K.category`, `sms.K.roe`, `sms.K.alarm_state`, `sms.K.formation`.
- `sms.K.units` and `sms.K.statics` — generated catalogs of every DCS unit and static type, written by `tools/dcs-sms.exe gen-units`.
- `sms.utils.serialize` — byte-stable Lua-data serializer; shared with the ME-mod's prefab format.
- `sms.prefab` — load and spawn prefabs from a mission script (rotation, country override, injection record).

**Changed**
- Country resolution now reads `boss.id` from the real ME selection shape (replaces an earlier heuristic).
- Drawing serialization preserves vertex deltas instead of absolute coords; place applies drawing rotation.

**Internal**
- Smoke test suite ported from bash to PowerShell.
- ACE skill level added to `sms.K.skill`.

### [0.9.0] — 2026-04-27
**Added**
- `sms.weapon` — wrapper with snapshot, polled tracker, impact extrapolation, `on_impact` and `WEAPON_IMPACT` bus delivery, destroy semantics.

### [0.8.0] — 2026-04-27
**Added**
- `sms.events` — pub/sub bus with entity-handle sugar, destroy emit, group-fully-dead semantic.

### [0.7.0] — 2026-04-27
**Added**
- `sms.static` — entity wrapper, `create`, `clone`.
- `sms.area:is_static_in`.

### [0.6.0] — 2026-04-26
**Added**
- `sms.group.create`, `sms.group.clone`.
- `sms.utils` conversions.

### [0.5.0] — 2026-04-26
**Added**
- `sms.area`.
- `_make_callable_handle` factory (internal).

### [0.4.0] — 2026-04-26
**Added**
- `sms.unit`.
- `sms.group:get_units()`.

### [0.3.0] — 2026-04-26
**Added**
- `sms.timer`.

### [0.2.0] — 2026-04-26
**Added**
- `sms.group`.

### [0.1.0] — 2026-04-25
**Added**
- `sms.log` (logger module).
- `sms.utils`.

---

## ME-mod

(No releases yet — first tag landing as `me-mod-v0.1.0`.)
