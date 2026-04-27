# `sms.weapon` v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap DCS weapon objects from SHOT events into `sms.weapon` handles with snapshotted release-time state and an opt-in polling-based tracker that detects impact and reports a best-estimate impact position. Closes intent of #10 by upgrading `evt.weapon_type` (string) with `evt.weapon` (handle) on weapon-bearing DCS events.

**Architecture:** Lightweight handle pattern (no inheritance), method dispatch via `__index = sms.weapon`. `sms.weapon.wrap(raw_dcs_obj)` is the only constructor (weapons are not name-addressable in DCS). Tracking uses `sms.timer.every(1/rate, ...)`; on each tick `pcall(weapon:getPosition)` — failure means the DCS object is gone, transitioning the handle to "impacted" and computing extrapolated impact via `land.getIP`. Per-handle callbacks (`on_impact`, `on_tick`) for local use; one fabricated bus event `sms.events.WEAPON_IMPACT` for cross-cutting subscribers. No `WEAPON_TICK` on the bus by design.

**Tech Stack:** Lua 5.1 (DCS scripting environment), DCS World API (`world.event`, `Weapon`, `Unit`, `land.getIP`, `coalition.addGroup`), `sms.timer` (existing polling primitive), `sms.events` (existing pub/sub bus). Smoke testing via bash + `tools/dcs-sms.exe exec` against a live DCS mission.

**Spec:** `docs/superpowers/specs/2026-04-27-framework-weapon-design.md`

---

## File Structure

| File | Status | Purpose |
|---|---|---|
| `framework/unit.lua` | Modify | Add `get_heading` / `get_pitch` / `get_altitude` getters on `sms.unit` (used by weapon's release-time snapshot, useful broadly) |
| `framework/events.lua` | Modify | Extend `_normalize_event` to populate `evt.weapon` (sms.weapon handle) when `sms.weapon` module is loaded — closes #10 |
| `framework/weapon.lua` | Create | The new module: handle wrapper + state machine + snapshot + tracking loop + callbacks + impact extrapolation + `WEAPON_IMPACT` constant |
| `framework/test/smoke_unit.sh` | Modify | Add tests for the three new `sms.unit` getters |
| `framework/test/smoke_weapon.sh` | Create | New smoke test: synthetic checks + live DCS round-trip via AI artillery firing a shell |

---

## Task 1: Add `sms.unit` heading/pitch/altitude getters

**Files:**
- Modify: `framework/unit.lua` (append three new methods before the `_make_callable_handle` call at the bottom)
- Modify: `framework/test/smoke_unit.sh` (add new test sections after the existing get_type test)

**Background:** `framework/unit.lua` follows the entity-wrapper template:
- `_name_of(u)` accepts handle or string
- Methods that touch DCS check `is_alive` first, log + return nil otherwise
- `Unit.getByName(name):getPosition()` returns a Position3 struct: `{p = origin_vec3, x = forward_unit_vec, y = up_unit_vec, z = right_unit_vec}`. The forward axis (`x`) gives heading/pitch directly.
- `Unit.getByName(name):getPoint()` returns a vec3 origin (same as `getPosition().p`).
- `land.getHeight({x=..., y=...})` (DCS-2D — y here corresponds to vec3.z) returns terrain altitude in meters.

- [ ] **Step 1.1: Add `sms.unit.get_heading`**

In `framework/unit.lua`, before the `sms._make_callable_handle(sms.unit, Unit.getByName, log)` line at the end of the file, add:

```lua
-- Heading in degrees (0 = north, 90 = east). Computed from the forward
-- axis of the unit's pose, projected to the horizontal plane and
-- converted from radians. Returns nil + log if the unit is not alive.
sms.unit.get_heading = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_heading: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local pos = Unit.getByName(name):getPosition()
  -- DCS world coords: x = east, y = altitude, z = north. Forward is pos.x.
  -- atan2(east, north) = heading from north, clockwise (DCS convention).
  local heading_rad = math.atan2(pos.x.x, pos.x.z)
  local heading_deg = heading_rad * 180 / math.pi
  if heading_deg < 0 then heading_deg = heading_deg + 360 end
  return heading_deg
end
```

- [ ] **Step 1.2: Add `sms.unit.get_pitch`**

After `get_heading`, add:

```lua
-- Pitch in degrees, positive = nose up. Computed from the y-component
-- (vertical) of the forward axis: asin(forward.y). Returns nil + log
-- if the unit is not alive.
sms.unit.get_pitch = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_pitch: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local pos = Unit.getByName(name):getPosition()
  local pitch_rad = math.asin(pos.x.y)
  return pitch_rad * 180 / math.pi
end
```

- [ ] **Step 1.3: Add `sms.unit.get_altitude`**

After `get_pitch`, add:

```lua
-- Altitude in meters. ASL (above sea level) by default; pass true for
-- AGL (above ground level). Returns nil + log if the unit is not alive.
sms.unit.get_altitude = function(u, agl)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_altitude: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local p = Unit.getByName(name):getPoint()
  -- DCS world coords: y = altitude.
  if not agl then
    return p.y
  end
  -- AGL: subtract terrain height at the unit's horizontal position.
  -- land.getHeight uses DCS-2D coords: input.y corresponds to vec3.z.
  local terrain = land.getHeight({x = p.x, y = p.z})
  return p.y - terrain
end
```

- [ ] **Step 1.4: Add smoke tests for the three new methods**

In `framework/test/smoke_unit.sh`, after the existing `get_type` block (search for `get_type should be Soldier M4`), add the following block. The fixture `_sms_test_unit` is a stationary ground unit at heading=0, pitch=0, altitude≈ground.

```bash
echo "==> get_heading should be a number in [0, 360)"
result=$("${DCSSMS}" exec --code '
  local h = sms.unit("_sms_test_unit"):get_heading()
  return type(h) == "number" and h >= 0 and h < 360
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_heading: ${result}"; exit 1; }

echo "==> get_pitch should be a number near 0 for a ground unit"
result=$("${DCSSMS}" exec --code '
  local p = sms.unit("_sms_test_unit"):get_pitch()
  return type(p) == "number" and math.abs(p) < 5
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_pitch: ${result}"; exit 1; }

echo "==> get_altitude (ASL) should be a number"
result=$("${DCSSMS}" exec --code '
  local a = sms.unit("_sms_test_unit"):get_altitude()
  return type(a) == "number"
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_altitude ASL: ${result}"; exit 1; }

echo "==> get_altitude (AGL) should be near 0 for a ground unit"
result=$("${DCSSMS}" exec --code '
  local a = sms.unit("_sms_test_unit"):get_altitude(true)
  return type(a) == "number" and math.abs(a) < 5
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_altitude AGL: ${result}"; exit 1; }
```

- [ ] **Step 1.5: Run the smoke test**

Run:
```bash
framework/test/smoke_unit.sh
```

Expected: ends with `smoke ok`. If it fails on `get_heading` / `get_pitch` / `get_altitude`, inspect the new code paths.

If the test fails because DCS isn't running / mission isn't loaded, surface the error to the user — do not "fix" by skipping the test.

- [ ] **Step 1.6: Commit**

```bash
git add framework/unit.lua framework/test/smoke_unit.sh
git commit -m "$(cat <<'EOF'
feat(unit): add get_heading / get_pitch / get_altitude

Three new sms.unit getters needed by sms.weapon's release-time snapshot.
Heading in degrees (0=N), pitch in degrees (positive=nose-up), altitude
in meters (ASL default, AGL via opts).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `sms.weapon` skeleton — `wrap()` + always-available methods + `WEAPON_IMPACT` constant

**Files:**
- Create: `framework/weapon.lua`
- Create: `framework/test/smoke_weapon.sh` (synthetic-only stage; live DCS round-trip is added in Tasks 3–6)

**Background:** This task creates the module file with everything that doesn't depend on tracking. Tracking-related methods (`start_tracking`, `stop_tracking`, `is_tracking`, `is_alive`, `get_position`, `get_velocity`, `get_speed`, `get_target`, `on_tick`, `on_impact`, the `_tick` function, `get_impact_position`, `get_last_known_position`, `get_impact_distance_from`, `destroy`) are added in later tasks.

DCS reference for the snapshot:
- `weapon:getName()` — usually a numeric string like "1234567"
- `weapon:getTypeName()` — e.g. `"FAB_500"`, `"AIM-120C"`
- `weapon:getDesc()` — returns descriptor table; `.category` is one of `Weapon.Category.{SHELL=0, MISSILE=1, ROCKET=2, BOMB=3, TORPEDO=4}`
- `weapon:getCoalition()` — int (0=neutral, 1=red, 2=blue)
- `weapon:getCountry()` — int (matches a value in `country.id`)
- `weapon:getLauncher()` — DCS Unit object (or nil for some triggered weapons)

- [ ] **Step 2.1: Create `framework/weapon.lua`**

Create the file with this exact content:

```lua
-- dcs-sms framework: weapon module (sms.weapon).
--
-- Wraps DCS weapon objects from SHOT events with snapshotted release-time
-- state and an opt-in polling-based tracker. Unlike unit/group/static,
-- weapons are NOT name-addressable in DCS — Weapon.getByName does not
-- exist. The only public constructor is sms.weapon.wrap(raw_dcs_weapon),
-- which is what sms.events uses internally to populate evt.weapon on
-- SHOT/HIT events.
--
-- Tracking uses sms.timer.every to poll weapon:getPosition at a configurable
-- rate (default 60 Hz). When the DCS object stops existing, the handle
-- transitions to "impacted" and the impact position is computed via
-- land.getIP extrapolation from the last known position+forward axis,
-- falling back to the last known position when no terrain intersection
-- is found. Per-handle callbacks (on_impact, on_tick) are the primary API;
-- a fabricated WEAPON_IMPACT signal is also emitted on the sms.events bus
-- for cross-cutting subscribers.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> group.lua -> unit.lua
--                -> area.lua -> timer.lua -> spawn.lua -> static.lua
--                -> events.lua -> weapon.lua.
--
-- See docs/superpowers/specs/2026-04-27-framework-weapon-design.md.

assert(type(sms) == "table",         "framework/sms.lua must be loaded first")
assert(type(sms.unit) == "table",    "framework/unit.lua must be loaded first")
assert(type(sms.timer) == "table",   "framework/timer.lua must be loaded first")
assert(type(sms.events) == "table",  "framework/events.lua must be loaded first")
local log = sms.log.module("sms.weapon")
sms.weapon = sms.weapon or {}

-- Fabricated bus event constant. Auto-derivation only handles
-- world.event.S_EVENT_*; weapon impact is fabricated by this module's
-- polling loop, so the constant is added explicitly at load time.
sms.events.WEAPON_IMPACT = "weapon_impact"

-- Handle metatable. Identity-checked in module functions so callers
-- can't slip arbitrary tables in.
local _handle_mt = {__index = sms.weapon}

local function _is_handle(h)
  return type(h) == "table" and getmetatable(h) == _handle_mt
end

-- DCS Weapon.Category int -> normalized lowercase string.
local _category_str = {
  [0] = "shell",
  [1] = "missile",
  [2] = "rocket",
  [3] = "bomb",
  [4] = "torpedo",
}

-- DCS coalition int -> normalized lowercase string.
local _coalition_str = {[0] = "neutral", [1] = "red", [2] = "blue"}

-- int country id -> string country name. Built lazily.
local _country_reverse = nil
local function _build_country_reverse()
  if _country_reverse then return end
  _country_reverse = {}
  for k, v in pairs(country.id) do
    _country_reverse[v] = k:lower()
  end
end

-- ============================================================
-- Constructor
-- ============================================================

-- Snapshot all release-time state at construction. The handle stays
-- usable after the DCS weapon object is destroyed because nothing here
-- relies on the raw object after wrap returns.
sms.weapon.wrap = function(raw)
  if type(raw) ~= "userdata" and type(raw) ~= "table" then
    log.error("wrap: argument must be a DCS weapon object, got " .. type(raw))
    return nil
  end

  -- Snapshot fields. Each call is pcall-wrapped because half-deconstructed
  -- weapon objects can throw during late-frame access.
  local ok_name, name = pcall(raw.getName, raw)
  if not ok_name or not name then
    log.error("wrap: failed to read weapon name (object may be invalid)")
    return nil
  end

  local handle = setmetatable({
    name             = name,
    state            = "created",
    _raw             = raw,                 -- cleared on impacted / destroyed
  }, _handle_mt)

  local ok_type, t = pcall(raw.getTypeName, raw)
  if ok_type and t then handle.type = t end

  local ok_desc, desc = pcall(raw.getDesc, raw)
  if ok_desc and desc and type(desc.category) == "number" then
    handle.category = _category_str[desc.category]
    if not handle.category then
      log.error("wrap: '" .. name .. "' returned unknown category " .. tostring(desc.category))
    end
  end

  local ok_coa, coa = pcall(raw.getCoalition, raw)
  if ok_coa and coa then handle.coalition = _coalition_str[coa] end

  local ok_country, country_int = pcall(raw.getCountry, raw)
  if ok_country and country_int then
    _build_country_reverse()
    handle.country = _country_reverse[country_int]
  end

  -- Launcher snapshot. Some weapons (triggered explosions, etc.) have no
  -- launcher; in that case launcher and all release_* fields stay nil.
  local ok_launcher, launcher_obj = pcall(raw.getLauncher, raw)
  if ok_launcher and launcher_obj then
    local ok_lname, lname = pcall(launcher_obj.getName, launcher_obj)
    if ok_lname and lname then
      handle.launcher = sms._make_handle(sms.unit, lname)
      -- Capture release-time state from the launcher. Use sms.unit
      -- getters so we stay inside the framework's idiom. If the launcher
      -- is somehow already gone (rare, racy), the getters will log + nil
      -- and the corresponding handle fields stay nil.
      handle.release_position     = sms.unit.get_position(handle.launcher)
      handle.release_heading      = sms.unit.get_heading(handle.launcher)
      handle.release_pitch        = sms.unit.get_pitch(handle.launcher)
      handle.release_altitude_asl = sms.unit.get_altitude(handle.launcher)
      handle.release_altitude_agl = sms.unit.get_altitude(handle.launcher, true)
    end
  end

  return handle
end

-- ============================================================
-- Always-available getters (snapshotted, work in any state)
-- ============================================================

sms.weapon.get_name = function(w)
  if not _is_handle(w) then
    log.error("get_name: argument must be an sms.weapon handle")
    return nil
  end
  return w.name
end

sms.weapon.get_type = function(w)
  if not _is_handle(w) then
    log.error("get_type: argument must be an sms.weapon handle")
    return nil
  end
  return w.type
end

sms.weapon.get_category = function(w)
  if not _is_handle(w) then
    log.error("get_category: argument must be an sms.weapon handle")
    return nil
  end
  return w.category
end

sms.weapon.get_coalition = function(w)
  if not _is_handle(w) then
    log.error("get_coalition: argument must be an sms.weapon handle")
    return nil
  end
  return w.coalition
end

sms.weapon.get_country = function(w)
  if not _is_handle(w) then
    log.error("get_country: argument must be an sms.weapon handle")
    return nil
  end
  return w.country
end

sms.weapon.get_launcher = function(w)
  if not _is_handle(w) then
    log.error("get_launcher: argument must be an sms.weapon handle")
    return nil
  end
  return w.launcher
end

sms.weapon.get_state = function(w)
  if not _is_handle(w) then
    log.error("get_state: argument must be an sms.weapon handle")
    return nil
  end
  return w.state
end

-- Release-time getters. Snapshotted at wrap; nil if launcher was absent.

sms.weapon.get_release_position = function(w)
  if not _is_handle(w) then
    log.error("get_release_position: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_position
end

sms.weapon.get_release_heading = function(w)
  if not _is_handle(w) then
    log.error("get_release_heading: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_heading
end

sms.weapon.get_release_pitch = function(w)
  if not _is_handle(w) then
    log.error("get_release_pitch: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_pitch
end

sms.weapon.get_release_altitude_asl = function(w)
  if not _is_handle(w) then
    log.error("get_release_altitude_asl: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_altitude_asl
end

sms.weapon.get_release_altitude_agl = function(w)
  if not _is_handle(w) then
    log.error("get_release_altitude_agl: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_altitude_agl
end

-- Category sugar. False if category lookup failed at wrap time.

sms.weapon.is_bomb    = function(w) return _is_handle(w) and w.category == "bomb"    or false end
sms.weapon.is_missile = function(w) return _is_handle(w) and w.category == "missile" or false end
sms.weapon.is_rocket  = function(w) return _is_handle(w) and w.category == "rocket"  or false end
sms.weapon.is_shell   = function(w) return _is_handle(w) and w.category == "shell"   or false end
sms.weapon.is_torpedo = function(w) return _is_handle(w) and w.category == "torpedo" or false end
```

- [ ] **Step 2.2: Create `framework/test/smoke_weapon.sh`**

Create the file with this exact content (synthetic-only at this stage — Tasks 3–6 extend it with live DCS sections):

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.weapon v1.
# Synthetic checks first (load + constants + bad-arg paths). Live DCS
# round-trip lives in later sections (added incrementally as tracking
# capabilities land per task).
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

expect_true() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_str() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected '${expected}'): ${result}"; exit 1; }
}

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file utils.lua >/dev/null
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null
"${DCSSMS}" exec --file area.lua >/dev/null
"${DCSSMS}" exec --file timer.lua >/dev/null
"${DCSSMS}" exec --file spawn.lua >/dev/null
"${DCSSMS}" exec --file static.lua >/dev/null
"${DCSSMS}" exec --file events.lua >/dev/null
"${DCSSMS}" exec --file weapon.lua >/dev/null

echo "==> WEAPON_IMPACT constant exists"
expect_str "WEAPON_IMPACT" 'return sms.events.WEAPON_IMPACT' 'weapon_impact'

echo "==> wrap with bad input returns nil"
expect_true "wrap nil"     'return sms.weapon.wrap(nil) == nil'
expect_true "wrap number"  'return sms.weapon.wrap(42) == nil'
expect_true "wrap string"  'return sms.weapon.wrap("hi") == nil'

echo "==> module getters reject non-handles"
expect_true "get_name on string"    'return sms.weapon.get_name("nope") == nil'
expect_true "get_type on nil"       'return sms.weapon.get_type(nil) == nil'
expect_true "get_state on number"   'return sms.weapon.get_state(7) == nil'
expect_true "is_bomb on string"     'return sms.weapon.is_bomb("nope") == false'

echo "==> verify [sms.weapon] log lines for bad args"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.weapon\]' -n 100)
echo "${log_window}" | grep -q "wrap: argument must be a DCS weapon object" \
  || { echo "FAIL: missing log line for bad wrap arg"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "get_name: argument must be an sms.weapon handle" \
  || { echo "FAIL: missing log line for bad get_name arg"; echo "${log_window}"; exit 1; }

echo "smoke ok"
```

Make the script executable:

```bash
chmod +x framework/test/smoke_weapon.sh
```

- [ ] **Step 2.3: Run the smoke test**

Run:
```bash
framework/test/smoke_weapon.sh
```

Expected: ends with `smoke ok`. If `weapon.lua` fails to load, check assertion order and that `events.lua` is loaded before `weapon.lua`.

- [ ] **Step 2.4: Commit**

```bash
git add framework/weapon.lua framework/test/smoke_weapon.sh
git commit -m "$(cat <<'EOF'
feat(weapon): sms.weapon module skeleton with wrap() and snapshot getters

New framework/weapon.lua:
- sms.weapon.wrap(raw_dcs_obj) snapshots name/type/category/coalition/
  country/launcher and release-time state (position/heading/pitch/
  altitude_asl/altitude_agl from launcher).
- Always-available getters work in any state.
- is_bomb / is_missile / is_rocket / is_shell / is_torpedo sugar.
- Adds sms.events.WEAPON_IMPACT = "weapon_impact" (fabricated bus event).
- No tracking yet; that comes in subsequent tasks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Wire `evt.weapon` into `sms.events`

**Files:**
- Modify: `framework/events.lua` (extend `_normalize_event`)
- Modify: `framework/test/smoke_weapon.sh` (add live-DCS section that fires a shot and asserts evt.weapon shape)

**Background:** Currently `framework/events.lua`'s `_normalize_event` only extracts `evt.weapon_type` (string) from `raw.weapon`. We add `evt.weapon` (sms.weapon handle) when the `sms.weapon` module is loaded. The `evt.weapon_type` field stays for back-compat. This closes the intent of issue #10.

The live DCS test pattern is to spawn an artillery unit and use `Controller:pushTask({id="FireAtPoint", ...})` to fire a single shell. Shells are DCS weapon objects and trigger `S_EVENT_SHOT`. Shell flight time is short (~3-10 seconds) — fast enough for a smoke test.

- [ ] **Step 3.1: Modify `_normalize_event` in `framework/events.lua`**

Open `framework/events.lua`. Find the existing `raw.weapon` block inside `_normalize_event` (around line 110–115). It currently looks like:

```lua
  if raw.weapon then
    local ok, t = pcall(raw.weapon.getTypeName, raw.weapon)
    if ok and t then evt.weapon_type = t end
  end
```

Replace it with:

```lua
  if raw.weapon then
    local ok, t = pcall(raw.weapon.getTypeName, raw.weapon)
    if ok and t then evt.weapon_type = t end
    -- Lazy upgrade: if sms.weapon is loaded, also expose the wrapped
    -- handle as evt.weapon. If sms.weapon isn't loaded, evt.weapon stays
    -- nil (current behavior). Closes #10.
    if sms.weapon and sms.weapon.wrap then
      local w = sms.weapon.wrap(raw.weapon)
      if w then evt.weapon = w end
    end
  end
```

- [ ] **Step 3.2: Add live-DCS SHOT round-trip section to `smoke_weapon.sh`**

In `framework/test/smoke_weapon.sh`, before the final `echo "smoke ok"` line, add the following section:

```bash
echo "==> live DCS SHOT round-trip — spawn artillery and fire a shell"
"${DCSSMS}" status | grep -q "fresh: *true" \
  || { echo "FAIL: live DCS section requires fresh heartbeat (mission unpaused)"; exit 1; }

# Spawn an M109 self-propelled howitzer far from origin to avoid colliding
# with concurrent agents. Capture the resolved name (sms.spawn auto-suffixes).
"${DCSSMS}" exec --code '
  _G._sms_weapon_smoke = {
    arty_group  = nil,
    arty_unit   = nil,
    target_pos  = {x = -49500, y = 0, z = -50000},  -- ~500m east of arty
    shot_evt    = nil,   -- captured SHOT event
    shot_count  = 0,     -- only track first shot
  }
  local g = sms.group.create({
    name = "smoke_weapon_arty",
    position = {x = -50000, y = 0, z = -50000},
    country = "USA",
    category = "ground",
    units = {{ type = "M-109", offset = {x = 0, y = 0, z = 0}, heading = 90 }},
  })
  if g then
    _G._sms_weapon_smoke.arty_group = g:get_name()
    _G._sms_weapon_smoke.arty_unit  = g:get_units()[1]:get_name()
  end
' >/dev/null
expect_true "artillery spawned" \
  'return type(_G._sms_weapon_smoke.arty_unit) == "string" and _G._sms_weapon_smoke.arty_unit ~= ""'

# Subscribe to SHOT and capture the first shell whose launcher is our arty.
"${DCSSMS}" exec --code '
  sms.events.connect(sms.events.SHOT, function(evt)
    if _G._sms_weapon_smoke.shot_count > 0 then return end
    if not evt.weapon then return end
    local launcher = evt.weapon:get_launcher()
    if not launcher or launcher.name ~= _G._sms_weapon_smoke.arty_unit then return end
    _G._sms_weapon_smoke.shot_count = _G._sms_weapon_smoke.shot_count + 1
    _G._sms_weapon_smoke.shot_evt = evt
  end)
' >/dev/null

# Push a FireAtPoint task to the artillery. expendCnt=1 limits to one shell.
"${DCSSMS}" exec --code '
  local u = Unit.getByName(_G._sms_weapon_smoke.arty_unit)
  if u then
    local controller = u:getController()
    controller:pushTask({
      id = "FireAtPoint",
      params = {
        point     = { x = _G._sms_weapon_smoke.target_pos.x, y = _G._sms_weapon_smoke.target_pos.z },
        radius    = 5,
        expendQty = 1,
        expendQtyEnabled = true,
      },
    })
  end
' >/dev/null

# Wait for the shell to fire. M109 has a short prep time.
sleep 12

expect_true "SHOT event was captured" \
  'return _G._sms_weapon_smoke.shot_evt ~= nil'
expect_true "evt.weapon is an sms.weapon handle" \
  'local e = _G._sms_weapon_smoke.shot_evt; return e and type(e.weapon) == "table" and type(e.weapon.get_name) == "function"'
expect_str "evt.weapon:get_category() is shell" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:get_category()' 'shell'
expect_true "evt.weapon:is_shell() is true" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_shell()'
expect_true "evt.weapon:is_bomb() is false" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_bomb() == false'
expect_true "evt.weapon:get_launcher() returns a unit handle" \
  'local l = _G._sms_weapon_smoke.shot_evt.weapon:get_launcher(); return type(l) == "table" and l.name == _G._sms_weapon_smoke.arty_unit'
expect_true "evt.weapon:get_state() is created" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:get_state() == "created"'
expect_true "evt.weapon:get_release_position() returns a vec3" \
  'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_release_position(); return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
expect_true "evt.weapon_type back-compat string still present" \
  'return type(_G._sms_weapon_smoke.shot_evt.weapon_type) == "string"'

# Cleanup. Best-effort.
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_weapon_smoke.arty_group)
  if g then pcall(g.destroy, g) end
' >/dev/null
```

- [ ] **Step 3.3: Run the smoke test**

Run:
```bash
framework/test/smoke_weapon.sh
```

Expected: all sections pass through to `smoke ok`. If the SHOT event doesn't fire, the artillery may need more prep time — try increasing the sleep from 12 to 20 seconds. If `evt.weapon` is nil, verify the events.lua change went into the right block (inside `if raw.weapon then`).

- [ ] **Step 3.4: Commit**

```bash
git add framework/events.lua framework/test/smoke_weapon.sh
git commit -m "$(cat <<'EOF'
feat(events): expose evt.weapon as sms.weapon handle

Extends _normalize_event so SHOT/HIT events get evt.weapon (handle)
alongside the existing evt.weapon_type (string). Lazy: only populated
when sms.weapon module is loaded; back-compat field kept. Closes #10.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Tracking infrastructure — start/stop, on_tick, live getters

**Files:**
- Modify: `framework/weapon.lua` (append tracking methods + live getters)
- Modify: `framework/test/smoke_weapon.sh` (extend live section: track the shell, assert on_tick fires, in-flight getters work)

**Background:** Tracking creates a `sms.timer.every(1/rate, _tick, ...)` loop. Each tick: `pcall(weapon:getPosition)` — if it succeeds AND `weapon:isExist()` returns true, update `_last_pos3` (the full Position3 struct: `{p, x, y, z}`) and `_last_velocity` (vec3 from `weapon:getVelocity()`); fire `on_tick` callback. If the pcall fails or `isExist` returns false, the tick path delegates to the impact path (added in Task 5). For Task 4, the impact path is a stub that just stops the timer cleanly.

`sms.timer.every` semantics: fn returning `false` self-cancels the timer.

- [ ] **Step 4.1: Append tracking infrastructure to `framework/weapon.lua`**

After the `is_torpedo` line at the end of `framework/weapon.lua`, append the following block. This adds `is_tracking`, `start_tracking`, `stop_tracking`, the live getters (`is_alive`, `get_position`, `get_velocity`, `get_speed`, `get_target`), `on_tick` / `on_impact` slot setters, and the internal `_tick` function with a placeholder impact path (Task 5 fleshes out the impact path).

```lua
-- ============================================================
-- Tracking
-- ============================================================

-- Internal: handle a single poll. Stops the timer (returns false) when
-- the DCS weapon object is gone. Updates _last_pos3 and _last_velocity
-- otherwise. Triggers on_tick callback (pcall-wrapped) if set.
local function _tick(w)
  if w.state ~= "tracking" then
    return false  -- safety: timer somehow outlived the state machine
  end
  local raw = w._raw
  if not raw then
    -- Defensive: should not happen while tracking, but bail cleanly.
    return false
  end
  local ok_pos, pos3 = pcall(raw.getPosition, raw)
  local ok_exist, exists = pcall(raw.isExist, raw)
  if not ok_pos or not pos3 or not ok_exist or not exists then
    -- Weapon is gone: enter the impact path. (Task 5 fleshes this out;
    -- for now, just transition state and stop the timer cleanly.)
    sms.weapon._on_impact_detected(w)
    return false
  end
  w._last_pos3 = pos3
  local ok_vel, vel = pcall(raw.getVelocity, raw)
  if ok_vel and vel then w._last_velocity = vel end
  if w._on_tick_fn then
    local ok_cb, err = pcall(w._on_tick_fn, w)
    if not ok_cb then
      log.error("on_tick: user fn raised: " .. tostring(err))
    end
  end
  return nil  -- nil = continue at next interval (sms.timer contract)
end

-- Placeholder impact-detection hook. Task 5 replaces this with the real
-- extrapolation-and-emit path. Defined as sms.weapon._on_impact_detected
-- so the tick loop can reference it through the module table (allowing
-- Task 5's append to override).
sms.weapon._on_impact_detected = function(w)
  -- Stub for Task 4: just transition to impacted, clear raw.
  w.state = "impacted"
  w._raw = nil
  if w._timer_handle then
    sms.timer.stop(w._timer_handle)
    w._timer_handle = nil
  end
end

sms.weapon.is_tracking = function(w)
  if not _is_handle(w) then return false end
  return w.state == "tracking"
end

sms.weapon.start_tracking = function(w, opts)
  if not _is_handle(w) then
    log.error("start_tracking: argument must be an sms.weapon handle")
    return false
  end
  if w.state ~= "created" then
    log.error("start_tracking: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', cannot start")
    return false
  end
  opts = opts or {}
  local rate = opts.rate or 60
  if type(rate) ~= "number" or rate <= 0 then
    log.error("start_tracking: rate must be a positive number, got " .. tostring(rate))
    return false
  end
  local ip_distance = opts.ip_distance or 50
  if type(ip_distance) ~= "number" or ip_distance < 0 then
    log.error("start_tracking: ip_distance must be a non-negative number, got " .. tostring(ip_distance))
    return false
  end
  w._ip_distance = ip_distance
  w.state = "tracking"
  w._timer_handle = sms.timer.every(1 / rate, function() return _tick(w) end)
  if not w._timer_handle then
    -- sms.timer.every already logged; revert state.
    w.state = "created"
    return false
  end
  return true
end

sms.weapon.stop_tracking = function(w)
  if not _is_handle(w) then
    log.error("stop_tracking: argument must be an sms.weapon handle")
    return false
  end
  if w.state ~= "tracking" then
    return false
  end
  if w._timer_handle then
    sms.timer.stop(w._timer_handle)
    w._timer_handle = nil
  end
  w.state = "created"
  return true
end

-- ============================================================
-- Callback slots (single-slot, last-write-wins)
-- ============================================================

sms.weapon.on_tick = function(w, fn)
  if not _is_handle(w) then
    log.error("on_tick: argument must be an sms.weapon handle")
    return
  end
  if type(fn) ~= "function" then
    log.error("on_tick: fn must be a function, got " .. type(fn))
    return
  end
  w._on_tick_fn = fn
end

sms.weapon.on_impact = function(w, fn)
  if not _is_handle(w) then
    log.error("on_impact: argument must be an sms.weapon handle")
    return
  end
  if type(fn) ~= "function" then
    log.error("on_impact: fn must be a function, got " .. type(fn))
    return
  end
  w._on_impact_fn = fn
end

-- ============================================================
-- Live getters (require state == "tracking")
-- ============================================================

sms.weapon.is_alive = function(w)
  if not _is_handle(w) then return false end
  if w.state ~= "tracking" then return false end
  if not w._raw then return false end
  local ok, exists = pcall(w._raw.isExist, w._raw)
  return ok and exists == true
end

sms.weapon.get_position = function(w)
  if not _is_handle(w) then
    log.error("get_position: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "tracking" then
    log.error("get_position: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', no live position")
    return nil
  end
  if not w._last_pos3 then return nil end
  local p = w._last_pos3.p
  return {x = p.x, y = p.y, z = p.z}
end

sms.weapon.get_velocity = function(w)
  if not _is_handle(w) then
    log.error("get_velocity: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "tracking" then
    log.error("get_velocity: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', no live velocity")
    return nil
  end
  if not w._last_velocity then return nil end
  local v = w._last_velocity
  return {x = v.x, y = v.y, z = v.z}
end

sms.weapon.get_speed = function(w)
  local v = sms.weapon.get_velocity(w)
  if not v then return nil end
  return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

sms.weapon.get_target = function(w)
  if not _is_handle(w) then
    log.error("get_target: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "tracking" or not w._raw then return nil end
  local ok_t, target_obj = pcall(w._raw.getTarget, w._raw)
  if not ok_t or not target_obj then return nil end
  local ok_n, target_name = pcall(target_obj.getName, target_obj)
  if not ok_n or not target_name then return nil end
  -- Try unit first; fall back to static.
  if Unit.getByName(target_name) then
    return sms.unit(target_name)
  end
  if StaticObject.getByName(target_name) then
    return sms.static and sms.static(target_name) or nil
  end
  return nil
end
```

- [ ] **Step 4.2: Extend `smoke_weapon.sh` with tracking section**

In `framework/test/smoke_weapon.sh`, before the cleanup line (`local g = Group.getByName(_G._sms_weapon_smoke.arty_group)` block) and AFTER the existing `evt.weapon_type back-compat` assertion, insert the following section:

```bash
echo "==> tracking — start tracking, observe in-flight ticks"
"${DCSSMS}" exec --code '
  _G._sms_weapon_smoke.tick_count = 0
  _G._sms_weapon_smoke.last_pos = nil
  local w = _G._sms_weapon_smoke.shot_evt.weapon
  w:on_tick(function(weapon)
    _G._sms_weapon_smoke.tick_count = _G._sms_weapon_smoke.tick_count + 1
    _G._sms_weapon_smoke.last_pos = weapon:get_position()
  end)
  -- Use a slower poll rate (30 Hz) for the smoke test — fewer logs.
  local ok = w:start_tracking({rate = 30})
  _G._sms_weapon_smoke.start_ok = ok
  _G._sms_weapon_smoke.state_after_start = w:get_state()
' >/dev/null
expect_true "start_tracking returned true" \
  'return _G._sms_weapon_smoke.start_ok == true'
expect_str "state is tracking" \
  'return _G._sms_weapon_smoke.state_after_start' 'tracking'
expect_true "is_tracking returns true" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_tracking()'
expect_true "double start_tracking returns false" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:start_tracking() == false'

# Wait briefly to let several ticks fire while the shell is in flight.
# At 30 Hz, 0.5s ≈ 15 ticks.
sleep 1

expect_true "on_tick fired multiple times during flight" \
  'return _G._sms_weapon_smoke.tick_count >= 5'
expect_true "last_pos is a valid vec3" \
  'local p = _G._sms_weapon_smoke.last_pos; return p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
```

- [ ] **Step 4.3: Run the smoke test**

Run:
```bash
framework/test/smoke_weapon.sh
```

Expected: all sections pass through to `smoke ok`. The shell may impact during the 1-second sleep — that's OK for Task 4 (the stub impact path just transitions state and stops the timer cleanly without firing callbacks). Task 5 will exercise the full impact path. If `tick_count` is 0, ticks aren't firing — verify `_tick` references and `sms.timer.every` is being called.

- [ ] **Step 4.4: Commit**

```bash
git add framework/weapon.lua framework/test/smoke_weapon.sh
git commit -m "$(cat <<'EOF'
feat(weapon): tracking lifecycle and live getters

Adds start_tracking / stop_tracking / is_tracking, on_tick / on_impact
callback slots, and live getters (is_alive / get_position / get_velocity
/ get_speed / get_target). Polling timer runs through sms.timer.every
at configurable rate (default 60 Hz). Impact detection is stubbed in
this commit; Task 5 fleshes out the extrapolation + bus emit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Impact detection + extrapolation + bus emit + impact methods

**Files:**
- Modify: `framework/weapon.lua` (replace stub `_on_impact_detected`; add impact getters)
- Modify: `framework/test/smoke_weapon.sh` (extend live section: assert on_impact + WEAPON_IMPACT bus event + impact_position is reasonable)

**Background:** When the polling tick detects the DCS weapon object is gone, we transition to "impacted" and compute an extrapolated impact position via `land.getIP(origin, direction, distance)`:

- `origin` = `_last_pos3.p` (last polled vec3 origin)
- `direction` = `_last_pos3.x` (last polled forward unit-vector — for in-flight weapons, this equals the velocity direction)
- `distance` = `_ip_distance` (default 50m) — cap on ray length

Returns vec3 of ground intersection or nil. We fall back to `_last_pos3.p` when nil.

Then: clear `_raw`, fire `on_impact` callback, emit `sms.events.WEAPON_IMPACT` on the bus with `{weapon, impact_position, time}`.

- [ ] **Step 5.1: Replace the stub impact handler in `framework/weapon.lua`**

Find the existing `sms.weapon._on_impact_detected` block (the Task 4 stub) in `framework/weapon.lua` and REPLACE it with:

```lua
-- Impact-detection hook. Called by the polling _tick when the DCS
-- weapon object stops existing. Transitions state, computes extrapolated
-- impact position (with last-known fallback), fires the on_impact
-- callback, and emits sms.events.WEAPON_IMPACT for cross-cutting subscribers.
sms.weapon._on_impact_detected = function(w)
  if w.state ~= "tracking" then return end  -- defensive
  -- Extrapolate impact via land.getIP. Falls back to last-known position
  -- if no terrain intersection within ip_distance (off-map, mid-air
  -- detonation, or weapon disappeared without a ground-bound trajectory).
  local impact = nil
  if w._last_pos3 and w._last_pos3.p and w._last_pos3.x then
    local ok_ip, ip = pcall(land.getIP, w._last_pos3.p, w._last_pos3.x, w._ip_distance or 50)
    if ok_ip and ip then impact = ip end
  end
  if not impact and w._last_pos3 and w._last_pos3.p then
    impact = {x = w._last_pos3.p.x, y = w._last_pos3.p.y, z = w._last_pos3.p.z}
  end
  w._impact_position = impact
  w._impact_time = sms.timer.now()
  w.state = "impacted"
  w._raw = nil
  if w._timer_handle then
    sms.timer.stop(w._timer_handle)
    w._timer_handle = nil
  end
  -- Per-handle callback first (locally scoped, expected to dominate use cases).
  if w._on_impact_fn then
    local ok_cb, err = pcall(w._on_impact_fn, w)
    if not ok_cb then
      log.error("on_impact: user fn raised: " .. tostring(err))
    end
  end
  -- Then bus emit for cross-cutting subscribers.
  sms.events.emit(sms.events.WEAPON_IMPACT, {
    weapon          = w,
    impact_position = impact,
    time            = w._impact_time,
  })
end
```

- [ ] **Step 5.2: Append impact getters to `framework/weapon.lua`**

At the end of `framework/weapon.lua`, append:

```lua
-- ============================================================
-- Impact getters (require state == "impacted")
-- ============================================================

sms.weapon.get_impact_position = function(w)
  if not _is_handle(w) then
    log.error("get_impact_position: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "impacted" then
    log.error("get_impact_position: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', no impact yet")
    return nil
  end
  if not w._impact_position then return nil end
  local p = w._impact_position
  return {x = p.x, y = p.y, z = p.z}
end

sms.weapon.get_last_known_position = function(w)
  if not _is_handle(w) then
    log.error("get_last_known_position: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "impacted" then
    log.error("get_last_known_position: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', no impact yet")
    return nil
  end
  if not w._last_pos3 or not w._last_pos3.p then return nil end
  local p = w._last_pos3.p
  return {x = p.x, y = p.y, z = p.z}
end

-- Distance from impact to a vec3 OR to any handle that exposes :get_position().
-- Duck-typed: works for sms.unit, sms.static, sms.weapon, or any future
-- positionable handle.
sms.weapon.get_impact_distance_from = function(w, target)
  if not _is_handle(w) then
    log.error("get_impact_distance_from: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "impacted" or not w._impact_position then
    log.error("get_impact_distance_from: weapon '" .. tostring(w.name) .. "' has no impact yet")
    return nil
  end
  local target_pos
  if type(target) == "table" and type(target.x) == "number"
     and type(target.y) == "number" and type(target.z) == "number" then
    target_pos = target
  elseif type(target) == "table" and type(target.get_position) == "function" then
    target_pos = target:get_position()
  end
  if not target_pos then
    log.error("get_impact_distance_from: target must be a vec3 or a handle with :get_position()")
    return nil
  end
  local ip = w._impact_position
  local dx = ip.x - target_pos.x
  local dy = ip.y - target_pos.y
  local dz = ip.z - target_pos.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end
```

- [ ] **Step 5.3: Extend `smoke_weapon.sh` with impact assertions**

In `framework/test/smoke_weapon.sh`, REPLACE the existing tracking section's `sleep 1` (added in Task 4) with the following, and add new assertions for the impact path. The full replacement section (which goes between `expect_true "double start_tracking returns false"` and the cleanup block) is:

```bash
# Wire on_impact and a bus subscriber BEFORE waiting; the shell may impact
# at any moment within the next ~10 seconds.
"${DCSSMS}" exec --code '
  _G._sms_weapon_smoke.impact_callback_fired = 0
  _G._sms_weapon_smoke.bus_event_fired      = 0
  _G._sms_weapon_smoke.bus_event_payload    = nil

  local w = _G._sms_weapon_smoke.shot_evt.weapon
  w:on_impact(function(weapon)
    _G._sms_weapon_smoke.impact_callback_fired = _G._sms_weapon_smoke.impact_callback_fired + 1
  end)

  sms.events.connect(sms.events.WEAPON_IMPACT, function(evt)
    -- Filter to OUR weapon (defensive vs concurrent agents firing weapons).
    if evt.weapon and evt.weapon:get_name() == w:get_name() then
      _G._sms_weapon_smoke.bus_event_fired   = _G._sms_weapon_smoke.bus_event_fired + 1
      _G._sms_weapon_smoke.bus_event_payload = evt
    end
  end)
' >/dev/null

# Wait for shell to fly + impact. M-109 shells take ~5–8 seconds.
sleep 12

expect_true "on_tick fired many times during flight" \
  'return _G._sms_weapon_smoke.tick_count >= 30'
expect_eq() {
  local label="$1"; local code="$2"; local expected="$3"
  local result; result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":${expected}," \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
}
expect_eq "on_impact callback fired exactly once" \
  'return _G._sms_weapon_smoke.impact_callback_fired' 1
expect_eq "WEAPON_IMPACT bus event fired exactly once" \
  'return _G._sms_weapon_smoke.bus_event_fired' 1
expect_str "weapon state is impacted" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:get_state()' 'impacted'
expect_true "is_tracking returns false after impact" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_tracking() == false'
expect_true "is_alive returns false after impact" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_alive() == false'
expect_true "get_impact_position returns a vec3" \
  'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_position(); return p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
expect_true "get_last_known_position returns a vec3" \
  'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_last_known_position(); return p and type(p.x) == "number"'
expect_true "get_impact_distance_from(vec3) returns a positive number" \
  'local d = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_distance_from(_G._sms_weapon_smoke.target_pos); return type(d) == "number" and d >= 0'
expect_true "bus event payload has weapon, impact_position, time" \
  'local e = _G._sms_weapon_smoke.bus_event_payload; return e and e.weapon and e.impact_position and type(e.time) == "number"'
expect_true "impact landed within reasonable distance of target (within 200m)" \
  'local d = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_distance_from(_G._sms_weapon_smoke.target_pos); return d < 200'
```

Note: the existing `expect_eq` helper from earlier in the same script also works — defining it inline is for clarity in this section. If the script already has `expect_eq` defined (it does — events.lua's smoke uses it), drop the inline `expect_eq() { ... }` block above.

Final pass: review `smoke_weapon.sh` and ensure `expect_eq` is defined exactly once (at the top with the other helpers). If it's missing, add it next to `expect_true` and `expect_str`:

```bash
expect_eq() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":${expected}," \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
}
```

- [ ] **Step 5.4: Run the smoke test**

Run:
```bash
framework/test/smoke_weapon.sh
```

Expected: all sections pass through to `smoke ok`. If the impact assertion `< 200m` fails, check whether the `target_pos` matches the FireAtPoint task position (both at `{-49500, 0, -50000}`). M-109 is reasonably accurate at 500m range.

If `bus_event_fired` is 0 but `impact_callback_fired` is 1, the bus emit logic is wrong — verify `sms.events.emit(sms.events.WEAPON_IMPACT, ...)` is called.

- [ ] **Step 5.5: Commit**

```bash
git add framework/weapon.lua framework/test/smoke_weapon.sh
git commit -m "$(cat <<'EOF'
feat(weapon): impact detection, extrapolation, bus emit, impact getters

Replaces the Task 4 stub _on_impact_detected with the full path:
- land.getIP extrapolation from last-known position+forward axis
- last-known position fallback (off-map, mid-air detonation)
- on_impact callback (per-handle)
- sms.events.WEAPON_IMPACT bus emit with {weapon, impact_position, time}
- impact getters: get_impact_position / get_last_known_position /
  get_impact_distance_from (duck-typed for vec3 or :get_position handle)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `destroy()` — silent abort

**Files:**
- Modify: `framework/weapon.lua` (append `destroy`)
- Modify: `framework/test/smoke_weapon.sh` (add small section spawning a fresh shell, calling destroy, asserting no impact event fires)

**Background:** `w:destroy()` is an explicit programmatic abort. It stops tracking (no impact event), calls raw `weapon:destroy()`, transitions state to `"destroyed"`. Mirrors `sms.unit.destroy()`'s default-silent semantics.

- [ ] **Step 6.1: Append `destroy` to `framework/weapon.lua`**

At the end of `framework/weapon.lua`, append:

```lua
-- ============================================================
-- destroy
-- ============================================================

-- Stops tracking (silently, no impact event), removes the weapon from
-- the DCS world, transitions state to "destroyed". Idempotent: returns
-- true once, false thereafter. To get an impact-style event from a
-- programmatic abort, read get_position() before calling destroy().
sms.weapon.destroy = function(w)
  if not _is_handle(w) then
    log.error("destroy: argument must be an sms.weapon handle")
    return false
  end
  if w.state == "destroyed" then return false end
  if w.state == "tracking" and w._timer_handle then
    sms.timer.stop(w._timer_handle)
    w._timer_handle = nil
  end
  if w._raw then
    pcall(w._raw.destroy, w._raw)
    w._raw = nil
  end
  w.state = "destroyed"
  return true
end
```

- [ ] **Step 6.2: Add `destroy()` smoke section**

In `framework/test/smoke_weapon.sh`, AFTER the existing impact assertions and BEFORE the cleanup block, add the following section. It spawns a SECOND artillery (different name) and fires another shell, then calls `destroy()` mid-flight to verify no impact event fires.

```bash
echo "==> destroy() — silent abort (no impact event)"
"${DCSSMS}" exec --code '
  _G._sms_weapon_smoke.destroy_test = {
    arty_group     = nil,
    arty_unit      = nil,
    target_pos     = {x = -39500, y = 0, z = -40000},  -- different region
    weapon         = nil,
    callback_fired = 0,
    bus_fired      = 0,
  }
  local g = sms.group.create({
    name = "smoke_weapon_arty_destroy",
    position = {x = -40000, y = 0, z = -40000},
    country = "USA",
    category = "ground",
    units = {{ type = "M-109", offset = {x = 0, y = 0, z = 0}, heading = 90 }},
  })
  if g then
    _G._sms_weapon_smoke.destroy_test.arty_group = g:get_name()
    _G._sms_weapon_smoke.destroy_test.arty_unit  = g:get_units()[1]:get_name()
  end

  sms.events.connect(sms.events.SHOT, function(evt)
    if _G._sms_weapon_smoke.destroy_test.weapon then return end
    if not evt.weapon then return end
    local launcher = evt.weapon:get_launcher()
    if not launcher or launcher.name ~= _G._sms_weapon_smoke.destroy_test.arty_unit then return end
    _G._sms_weapon_smoke.destroy_test.weapon = evt.weapon
    evt.weapon:on_impact(function(_)
      _G._sms_weapon_smoke.destroy_test.callback_fired = _G._sms_weapon_smoke.destroy_test.callback_fired + 1
    end)
    evt.weapon:start_tracking({rate = 30})
  end)

  sms.events.connect(sms.events.WEAPON_IMPACT, function(evt)
    if evt.weapon and _G._sms_weapon_smoke.destroy_test.weapon
       and evt.weapon:get_name() == _G._sms_weapon_smoke.destroy_test.weapon:get_name() then
      _G._sms_weapon_smoke.destroy_test.bus_fired = _G._sms_weapon_smoke.destroy_test.bus_fired + 1
    end
  end)

  local u = Unit.getByName(_G._sms_weapon_smoke.destroy_test.arty_unit)
  if u then
    u:getController():pushTask({
      id = "FireAtPoint",
      params = {
        point     = { x = _G._sms_weapon_smoke.destroy_test.target_pos.x,
                      y = _G._sms_weapon_smoke.destroy_test.target_pos.z },
        radius    = 5,
        expendQty = 1,
        expendQtyEnabled = true,
      },
    })
  end
' >/dev/null

# Wait for the shell to fire and start tracking.
sleep 8

expect_true "second weapon was wrapped and tracking" \
  'return _G._sms_weapon_smoke.destroy_test.weapon ~= nil and _G._sms_weapon_smoke.destroy_test.weapon:is_tracking()'

# Destroy mid-flight. Should silently abort — no impact callback, no bus event.
"${DCSSMS}" exec --code '
  local w = _G._sms_weapon_smoke.destroy_test.weapon
  _G._sms_weapon_smoke.destroy_test.destroy_first = w:destroy()
  _G._sms_weapon_smoke.destroy_test.destroy_second = w:destroy()  -- idempotent
  _G._sms_weapon_smoke.destroy_test.state_after = w:get_state()
' >/dev/null

# Wait an additional moment to confirm no late impact callbacks slip in.
sleep 3

expect_true "destroy() returned true on first call" \
  'return _G._sms_weapon_smoke.destroy_test.destroy_first == true'
expect_true "destroy() returned false on second call (idempotent)" \
  'return _G._sms_weapon_smoke.destroy_test.destroy_second == false'
expect_str "state is destroyed" \
  'return _G._sms_weapon_smoke.destroy_test.state_after' 'destroyed'
expect_eq "on_impact did NOT fire after destroy()" \
  'return _G._sms_weapon_smoke.destroy_test.callback_fired' 0
expect_eq "WEAPON_IMPACT bus event did NOT fire after destroy()" \
  'return _G._sms_weapon_smoke.destroy_test.bus_fired' 0

# Cleanup destroy-test artillery group.
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_weapon_smoke.destroy_test.arty_group)
  if g then pcall(g.destroy, g) end
' >/dev/null
```

- [ ] **Step 6.3: Run the full smoke test**

Run:
```bash
framework/test/smoke_weapon.sh
```

Expected: all sections pass through to `smoke ok`. The full test now takes roughly 25–30 seconds (two artillery firings × ~10s each + sleeps). Make sure the heartbeat stays fresh throughout.

- [ ] **Step 6.4: Commit**

```bash
git add framework/weapon.lua framework/test/smoke_weapon.sh
git commit -m "$(cat <<'EOF'
feat(weapon): destroy() silent abort

Stops tracking and removes the weapon from the DCS world without firing
on_impact or WEAPON_IMPACT bus event. Idempotent. Mirrors sms.unit.destroy
default-silent semantics; opt-in {emit_event=true} pattern can be added
later if needed (deferred per spec Decisions section).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

The plan covers every section of the spec:

| Spec section | Where covered |
|---|---|
| Constructor `wrap()` + snapshot fields | Task 2 (Step 2.1) |
| State machine ("created"/"tracking"/"impacted"/"destroyed") | Tasks 2, 4, 5, 6 (state set at each transition) |
| `start_tracking` / `stop_tracking` / `is_tracking` | Task 4 (Step 4.1) |
| `_tick` poll loop with pcall + isExist guard | Task 4 (Step 4.1, `_tick` function) |
| `on_tick` / `on_impact` callbacks | Tasks 4 + 5 |
| Impact extrapolation via `land.getIP` | Task 5 (Step 5.1) |
| `WEAPON_IMPACT` bus event + constant | Task 2 (constant), Task 5 (emit) |
| Live getters (`is_alive`/`get_position`/`get_velocity`/`get_speed`/`get_target`) | Task 4 (Step 4.1) |
| Always-available getters + category sugar + release-time getters | Task 2 (Step 2.1) |
| Impact getters (`get_impact_position`/`get_last_known_position`/`get_impact_distance_from`) | Task 5 (Step 5.2) |
| `destroy()` silent abort | Task 6 |
| `events.lua` upgrade for `evt.weapon` (closes #10) | Task 3 (Step 3.1) |
| `sms.unit` heading/pitch/altitude bundled additions | Task 1 |
| Smoke test (synthetic + live DCS round-trip) | Tasks 2 (synthetic), 3+4+5+6 (live, incremental) |

**Placeholder scan:** No "TODO", "TBD", "implement later". Each step contains complete code or exact commands.

**Type consistency:** Field names verified across tasks: `_raw` / `_last_pos3` / `_last_velocity` / `_timer_handle` / `_on_tick_fn` / `_on_impact_fn` / `_ip_distance` / `_impact_position` / `_impact_time` / `state` / `name` / `type` / `category` / `coalition` / `country` / `launcher` / `release_position` / `release_heading` / `release_pitch` / `release_altitude_asl` / `release_altitude_agl`. All consistent across Task 2, 4, 5, 6.

**Method signatures:** `sms.weapon.<method>(w, ...)` consistently — no module/handle confusion. Bus event payload `{weapon, impact_position, time}` matches across emit (Task 5) and assertions (Task 5 smoke).

**External API references:** `sms.timer.every(seconds, fn)` (verified vs `framework/timer.lua:72`), `sms.timer.now()` (verified vs `framework/timer.lua:161`), `sms.events.connect/emit/WEAPON_IMPACT` (verified vs `framework/events.lua`), `sms._make_handle` (verified vs `framework/sms.lua:15`).

**Smoke test pattern:** matches existing `smoke_events.sh` style — `expect_true` / `expect_eq` / `expect_str` helpers, `_G._sms_weapon_smoke` global state for cross-call persistence, defensive filtering by our weapon name vs concurrent agents, best-effort cleanup on completion.

Plan is complete and self-consistent. Ready for implementation.
