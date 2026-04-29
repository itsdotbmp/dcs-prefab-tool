# Framework `sms.commands` + `sms.options` — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two new framework modules (`sms.commands`, `sms.options`) wrapping DCS's controller `setCommand` / `setOption` APIs. Carbon-copy of the `sms.task` v1 pattern: builders return DCS-native tables tagged with `_sms_*` markers; apply methods (`group:set_command`, `group:set_option`) live alongside `set_task` in `group.lua` and route the dispatch.

**Architecture:** Same shape as `sms.task`. Each builder file has a private `_stamp` helper, lowercase builder functions, and uppercase enum tables (e.g. `sms.options.ROE.WEAPON_HOLD = "weapon_hold"`). Apply methods extend `_validate_apply` in `group.lua` to support `_sms_naval_only` and `_sms_roe`. The ROE builder returns a tag-only table (`{_sms_verb="roe", _sms_roe=true, value="..."}`); `set_option` resolves the right `AI.Option.{Air,Ground,Naval}.id.ROE` and validates the value at apply time using helpers exposed by `options.lua`. `set_command` and `set_option` do **not** defer (unlike `set_task`); commands and options have no observed same-frame-spawn race.

**Tech Stack:** Lua 5.1 (DCS mission environment), Bash smoke harness, the bridge (`tools/dcs-sms.exe`).

**Constraint — DCS is closed during implementation.** Smoke entries are written into `framework/test/smoke_commands.sh` / `smoke_options.sh` but cannot be RUN per task. Per-task green signal is `luac -p` on the touched Lua files. Smoke runs are deferred to the user post-implementation.

**Spec:** [`docs/superpowers/specs/2026-04-29-framework-commands-options-design.md`](../specs/2026-04-29-framework-commands-options-design.md).

---

## File Structure

**New files:**
- `framework/commands.lua` — 19 command builders + enum tables.
- `framework/options.lua` — 20 option builders + enum tables + ROE-dispatch helpers.
- `framework/test/smoke_commands.sh` — synthetic + live-DCS smoke.
- `framework/test/smoke_options.sh` — synthetic + live-DCS smoke.
- `docs/api/commands.md` — per-builder reference page.
- `docs/api/options.md` — per-builder reference page.

**Modified files:**
- `framework/group.lua` — extend `_validate_apply` for `_sms_naval_only` + ROE-dispatch hook; add `set_command` and `set_option` methods.
- `framework/load_all.lua` — append `commands.lua`, `options.lua` to load order.
- `AGENTS.md` — new sub-sections under §7 (`sms.commands`, `sms.options`); brief mentions of `_sms_naval_only` and `_sms_roe` in §3.
- `docs/api/README.md` — index gains two rows.
- `docs/api/examples.md` — recipe 1 rewritten using `sms.options.roe(...)`; "Framework gap" callout removed.
- `README.md` — module list under "Repo layout" gains the two modules.

---

## Task 1: Extend `_validate_apply` in `group.lua` for naval-only + ROE-dispatch hook

**Files:**
- Modify: `framework/group.lua` (replace `_validate_apply` body, ~line 216)

- [ ] **Step 1: Replace `_validate_apply` to support `_sms_naval_only` and `_sms_roe`**

Locate the `_validate_apply` function in `framework/group.lua` (around line 216). Replace the entire function and the preceding `_air_categories` constant with this version (note the added `_ground_categories`, `_naval_categories`, the `_sms_naval_only` branch, and the new `_sms_roe` branch that delegates to `sms.options._validate_roe`):

```lua
-- Categories DCS will honor a flag-restricted command/option/task on.
local _air_categories    = { airplane = true, helicopter = true }
local _ground_categories = { ground = true }
local _naval_categories  = { ship = true }

-- Shared validation for set_task / push_task / set_command / set_option.
-- Returns the live DCS group object on success, or nil after logging.
local function _validate_apply(method, group_handle, payload)
  if not sms._is_handle_of(group_handle, sms.group) then
    log.warn(method .. ": first argument must be an sms.group handle")
    return nil
  end
  if not group_handle:is_alive() then
    log.warn(method .. ": group '" .. tostring(group_handle.name) .. "' is not alive")
    return nil
  end
  if type(payload) ~= "table" then
    log.warn(method .. ": payload must be a table")
    return nil
  end
  -- For tasks (set_task / push_task), require the DCS shape (id+params).
  -- For commands/options, the apply method has already done its own shape check.
  if method == "set_task" or method == "push_task" then
    if type(payload.id) ~= "string" or type(payload.params) ~= "table" then
      log.warn(method .. ": task must be a table with 'id' (string) and 'params' (table) fields")
      return nil
    end
  end
  if payload._sms_air_only then
    local cat = group_handle:get_category()
    if not _air_categories[cat] then
      local verb = payload._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is air-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  if payload._sms_ground_only then
    local cat = group_handle:get_category()
    if not _ground_categories[cat] then
      local verb = payload._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is ground-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  if payload._sms_naval_only then
    local cat = group_handle:get_category()
    if not _naval_categories[cat] then
      local verb = payload._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is naval-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  -- ROE option carries _sms_roe instead of a fixed category flag.
  -- Defer to sms.options._validate_roe (loaded by options.lua) which knows
  -- the per-category value tables. Resolved at call time so group.lua does
  -- not need options.lua to be loaded first.
  if payload._sms_roe then
    if not (sms.options and type(sms.options._validate_roe) == "function") then
      log.error(method .. ": _sms_roe payload but sms.options._validate_roe not loaded")
      return nil
    end
    local cat = group_handle:get_category()
    local ok, msg = sms.options._validate_roe(payload.value, cat)
    if not ok then
      log.warn(method .. ": " .. (msg or "roe validation failed") .. "; group '" .. tostring(group_handle.name) .. "' — not applied")
      return nil
    end
  end
  local raw = Group.getByName(group_handle.name)
  if not raw then
    log.warn(method .. ": group '" .. tostring(group_handle.name) .. "' disappeared between is_alive and apply")
    return nil
  end
  return raw
end
```

- [ ] **Step 2: Syntax-check group.lua**

Run: `luac -p framework/group.lua`
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add framework/group.lua
git commit -m "refactor(group): generalize _validate_apply for naval-only and ROE-dispatch"
```

---

## Task 2: `framework/commands.lua` — skeleton, enums, simple builders

**Files:**
- Create: `framework/commands.lua`

- [ ] **Step 1: Create the file with the module header, dependencies, `_stamp`, the enum tables, and the simple builders**

Create `framework/commands.lua` exactly:

```lua
-- dcs-sms framework: commands module (sms.commands).
--
-- Builders for DCS one-shot controller commands (Group:getController():setCommand).
-- Each builder returns a plain DCS command table {id, params, ...} with a
-- private _sms_verb tag (and optionally _sms_air_only) used by the apply
-- layer for log messages and category enforcement.
--
-- Application via sms.group:set_command(cmd) — installed in group.lua.
--
-- Loading order: ... -> task.lua -> commands.lua -> options.lua.
-- Depends on: sms.group (for the apply method install path), sms.utils.

assert(type(sms)         == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log)     == "table", "framework/log.lua must be loaded first")
assert(type(sms.group)   == "table", "framework/group.lua must be loaded first")
assert(type(sms.utils)   == "table", "framework/utils.lua must be loaded first")

sms.commands = sms.commands or {}

local log = sms.log.module("sms.commands")

-- Stamp a command table with the framework's private markers.
-- Returns the same table for fluent use.
local function _stamp(t, verb, air_only)
  t._sms_verb = verb
  if air_only then t._sms_air_only = true end
  return t
end

-- ============================================================
-- Enum tables
-- ============================================================

-- Radio modulation (used by set_frequency / set_frequency_for_unit).
sms.commands.MODULATION = {
  AM = 0,
  FM = 1,
}

-- Beacon constants used by activate_beacon. Numeric DCS-native ids; the
-- framework passes them through verbatim.
sms.commands.BEACON = {
  TYPE = {
    NULL                       = 0,
    VOR                        = 2,
    DME                        = 3,
    TACAN                      = 4,
    VORTAC                     = 5,
    HOMER                      = 8,
    AIRPORT_HOMER              = 9,
    AIRPORT_HOMER_WITH_MARKER  = 10,
    ILS_FAR_HOMER              = 16,
    ILS_NEAR_HOMER             = 17,
    ILS_LOCALIZER              = 18,
    ILS_GLIDESLOPE             = 19,
    NAUTICAL_HOMER             = 65,
  },
  SYSTEM = {
    PAR_10            = 1,
    RSBN_5            = 2,
    TACAN             = 3,
    TACAN_TANKER_X    = 4,
    TACAN_TANKER_Y    = 5,
    VOR               = 6,
    ILS_LOCALIZER     = 7,
    ILS_GLIDESLOPE    = 8,
    BROADCAST_STATION = 9,
    VORTAC            = 10,
    TACAN_AA_MODE_X   = 11,
    TACAN_AA_MODE_Y   = 12,
    ICLS              = 13,
    ICLS_LOCALIZER    = 14,
    ICLS_GLIDESLOPE   = 15,
  },
}

-- DCS callsign numeric enum is huge and per-aircraft. Most users will pass
-- raw integers from DCS docs; the most common air-side namesakes are exposed
-- here as a starting set. Builders accept any positive integer (passthrough).
sms.commands.CALLSIGN = {
  -- Common AWACS / tanker / FAC numeric callnames (Aircraft.id range).
  -- Add more here as users encounter them.
  ENFIELD  = 1,
  SPRINGFIELD = 2,
  UZI      = 3,
  COLT     = 4,
  DODGE    = 5,
  FORD     = 6,
  CHEVY    = 7,
  PONTIAC  = 8,
  TEXACO   = 1,
  ARCO     = 2,
  SHELL    = 3,
  OVERLORD = 1,
  MAGIC    = 2,
  WIZARD   = 3,
  FOCUS    = 4,
  DARKSTAR = 5,
}

-- ============================================================
-- Simple builders (no special arg shapes, all-categories unless noted)
-- ============================================================

-- No-op command. Useful for clearing a queued command.
sms.commands.no_action = function()
  return _stamp({ id = "NoAction", params = {} }, "no_action", false)
end

-- Toggle visibility to AI sensors.
sms.commands.set_invisible = function(value)
  if type(value) ~= "boolean" then
    log.warn("set_invisible: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({ id = "SetInvisible", params = { value = value } }, "set_invisible", false)
end

-- Toggle damage immunity.
sms.commands.set_immortal = function(value)
  if type(value) ~= "boolean" then
    log.warn("set_immortal: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({ id = "SetImmortal", params = { value = value } }, "set_immortal", false)
end

-- Halt or resume the group's route.
sms.commands.stop_route = function(value)
  if type(value) ~= "boolean" then
    log.warn("stop_route: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({ id = "StopRoute", params = { value = value } }, "stop_route", false)
end

-- Switch to a triggered action by index.
sms.commands.switch_action = function(action_index)
  if type(action_index) ~= "number" then
    log.warn("switch_action: action_index must be a number, got " .. type(action_index))
    return nil
  end
  return _stamp({
    id = "SwitchAction",
    params = { actionIndex = action_index },
  }, "switch_action", false)
end

-- Toggle unlimited fuel on aircraft.
sms.commands.set_unlimited_fuel = function(value)
  if type(value) ~= "boolean" then
    log.warn("set_unlimited_fuel: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({
    id = "SetUnlimitedFuel",
    params = { value = value },
  }, "set_unlimited_fuel", true)
end

-- Toggle EPLRS datalink. group_id is optional; when omitted, DCS uses the
-- group the command is applied to.
sms.commands.eplrs = function(value, group_id)
  if type(value) ~= "boolean" then
    log.warn("eplrs: value must be a boolean, got " .. type(value))
    return nil
  end
  if group_id ~= nil and type(group_id) ~= "number" then
    log.warn("eplrs: group_id must be a number when given, got " .. type(group_id))
    return nil
  end
  local params = { value = value }
  if group_id then params.groupId = group_id end
  return _stamp({ id = "EPLRS", params = params }, "eplrs", false)
end
```

- [ ] **Step 2: Syntax-check**

Run: `luac -p framework/commands.lua`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add framework/commands.lua
git commit -m "feat(commands): module skeleton, enums, and simple builders"
```

---

## Task 3: `framework/commands.lua` — frequency, waypoint, callsign, beacon, ACLS/ICLS/Link4

**Files:**
- Modify: `framework/commands.lua` (append after the simple-builders block)

- [ ] **Step 1: Append the remaining 12 builders**

Append the following code to the end of `framework/commands.lua` (after the `eplrs` builder):

```lua
-- ============================================================
-- Frequency builders
-- ============================================================

-- Set the group's radio frequency. modulation is sms.commands.MODULATION.AM
-- (default) or .FM. power is optional (W); DCS picks a reasonable default
-- when nil.
sms.commands.set_frequency = function(hz, modulation, power)
  if type(hz) ~= "number" then
    log.warn("set_frequency: hz must be a number, got " .. type(hz))
    return nil
  end
  if modulation == nil then modulation = sms.commands.MODULATION.AM end
  if type(modulation) ~= "number" then
    log.warn("set_frequency: modulation must be a number, got " .. type(modulation))
    return nil
  end
  if power ~= nil and type(power) ~= "number" then
    log.warn("set_frequency: power must be a number when given, got " .. type(power))
    return nil
  end
  local params = { frequency = hz, modulation = modulation }
  if power then params.power = power end
  return _stamp({ id = "SetFrequency", params = params }, "set_frequency", false)
end

-- Per-unit variant; unit_id is the integer DCS unit id.
sms.commands.set_frequency_for_unit = function(hz, modulation, power, unit_id)
  if type(hz) ~= "number" then
    log.warn("set_frequency_for_unit: hz must be a number, got " .. type(hz))
    return nil
  end
  if type(unit_id) ~= "number" then
    log.warn("set_frequency_for_unit: unit_id must be a number, got " .. type(unit_id))
    return nil
  end
  if modulation == nil then modulation = sms.commands.MODULATION.AM end
  if type(modulation) ~= "number" then
    log.warn("set_frequency_for_unit: modulation must be a number, got " .. type(modulation))
    return nil
  end
  if power ~= nil and type(power) ~= "number" then
    log.warn("set_frequency_for_unit: power must be a number when given, got " .. type(power))
    return nil
  end
  local params = { frequency = hz, modulation = modulation, unitId = unit_id }
  if power then params.power = power end
  return _stamp({ id = "SetFrequencyForUnit", params = params }, "set_frequency_for_unit", false)
end

-- ============================================================
-- Waypoint
-- ============================================================

-- Jump from waypoint index `from_idx` to `to_idx` (DCS uses 0-based).
sms.commands.switch_waypoint = function(from_idx, to_idx)
  if type(from_idx) ~= "number" or type(to_idx) ~= "number" then
    log.warn("switch_waypoint: both indices must be numbers")
    return nil
  end
  return _stamp({
    id = "SwitchWaypoint",
    params = { fromWaypointIndex = from_idx, goToWaypointIndex = to_idx },
  }, "switch_waypoint", false)
end

-- ============================================================
-- Callsign (air-only)
-- ============================================================

-- Set the AI radio callsign. callname is a numeric DCS callname enum
-- (sms.commands.CALLSIGN.* or any DCS Aircraft.id integer). number is the
-- flight number (default 1).
sms.commands.set_callsign = function(callname, number)
  if type(callname) ~= "number" then
    log.warn("set_callsign: callname must be a number, got " .. type(callname))
    return nil
  end
  if number == nil then number = 1 end
  if type(number) ~= "number" then
    log.warn("set_callsign: number must be a number when given, got " .. type(number))
    return nil
  end
  return _stamp({
    id = "SetCallsign",
    params = { callname = callname, number = number },
  }, "set_callsign", true)
end

-- ============================================================
-- Beacon (TACAN, ILS, VOR, etc.) — air-only
-- ============================================================

-- Activate a beacon on the group. opts table:
--   type      (number, required) — sms.commands.BEACON.TYPE.* (or DCS int)
--   system    (number, required) — sms.commands.BEACON.SYSTEM.* (or DCS int)
--   frequency (number, required) — Hz
--   callsign  (string, optional) — TACAN voice callsign, e.g. "TEX"
--   name      (string, optional) — beacon name (defaults to "")
--   unit_id   (number, optional) — host unit id
--   channel   (number, optional) — TACAN channel number
--   mode_channel (string, optional) — "X" or "Y"
--   aa        (boolean, optional) — air-to-air mode
--   bearing   (boolean, optional) — bearing info enable
sms.commands.activate_beacon = function(opts)
  if type(opts) ~= "table" then
    log.warn("activate_beacon: opts must be a table")
    return nil
  end
  if type(opts.type) ~= "number" then
    log.warn("activate_beacon: opts.type must be a number")
    return nil
  end
  if type(opts.system) ~= "number" then
    log.warn("activate_beacon: opts.system must be a number")
    return nil
  end
  if type(opts.frequency) ~= "number" then
    log.warn("activate_beacon: opts.frequency must be a number")
    return nil
  end
  local params = {
    type      = opts.type,
    system    = opts.system,
    frequency = opts.frequency,
    callsign  = opts.callsign or "",
    name      = opts.name     or "",
  }
  if opts.unit_id      then params.unitId      = opts.unit_id end
  if opts.channel      then params.channel     = opts.channel end
  if opts.mode_channel then params.modeChannel = opts.mode_channel end
  if opts.aa ~= nil    then params.AA          = opts.aa end
  if opts.bearing ~= nil then params.bearing   = opts.bearing end
  return _stamp({ id = "ActivateBeacon", params = params }, "activate_beacon", true)
end

-- Deactivate any active beacon.
sms.commands.deactivate_beacon = function()
  return _stamp({ id = "DeactivateBeacon", params = {} }, "deactivate_beacon", true)
end

-- ============================================================
-- ACLS / ICLS / Link4 (carrier ops, all air-only)
-- ============================================================

-- Aircraft Carrier Landing System.
sms.commands.activate_acls = function(unit_id, name)
  if unit_id ~= nil and type(unit_id) ~= "number" then
    log.warn("activate_acls: unit_id must be a number when given, got " .. type(unit_id))
    return nil
  end
  if name ~= nil and type(name) ~= "string" then
    log.warn("activate_acls: name must be a string when given, got " .. type(name))
    return nil
  end
  local params = {}
  if unit_id then params.UnitID = unit_id end
  if name    then params.Name   = name    end
  return _stamp({ id = "ActivateACLS", params = params }, "activate_acls", true)
end

sms.commands.deactivate_acls = function()
  return _stamp({ id = "DeactivateACLS", params = {} }, "deactivate_acls", true)
end

-- Instrument Carrier Landing System.
sms.commands.activate_icls = function(channel, unit_id, callsign)
  if type(channel) ~= "number" then
    log.warn("activate_icls: channel must be a number, got " .. type(channel))
    return nil
  end
  if unit_id  ~= nil and type(unit_id)  ~= "number" then
    log.warn("activate_icls: unit_id must be a number when given, got " .. type(unit_id))
    return nil
  end
  if callsign ~= nil and type(callsign) ~= "string" then
    log.warn("activate_icls: callsign must be a string when given, got " .. type(callsign))
    return nil
  end
  local params = { channel = channel }
  if unit_id  then params.unitId   = unit_id  end
  if callsign then params.callsign = callsign end
  return _stamp({ id = "ActivateICLS", params = params }, "activate_icls", true)
end

sms.commands.deactivate_icls = function()
  return _stamp({ id = "DeactivateICLS", params = {} }, "deactivate_icls", true)
end

-- Link 4 datalink.
sms.commands.activate_link4 = function(frequency, unit_id, callsign)
  if type(frequency) ~= "number" then
    log.warn("activate_link4: frequency must be a number, got " .. type(frequency))
    return nil
  end
  if unit_id  ~= nil and type(unit_id)  ~= "number" then
    log.warn("activate_link4: unit_id must be a number when given, got " .. type(unit_id))
    return nil
  end
  if callsign ~= nil and type(callsign) ~= "string" then
    log.warn("activate_link4: callsign must be a string when given, got " .. type(callsign))
    return nil
  end
  local params = { frequency = frequency }
  if unit_id  then params.unitId   = unit_id  end
  if callsign then params.callsign = callsign end
  return _stamp({ id = "ActivateLink4", params = params }, "activate_link4", true)
end

sms.commands.deactivate_link4 = function()
  return _stamp({ id = "DeactivateLink4", params = {} }, "deactivate_link4", true)
end
```

- [ ] **Step 2: Syntax-check**

Run: `luac -p framework/commands.lua`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add framework/commands.lua
git commit -m "feat(commands): frequency, waypoint, callsign, beacon, ACLS/ICLS/Link4 builders"
```

---

## Task 4: `group:set_command` apply method + `load_all.lua` update

**Files:**
- Modify: `framework/group.lua` (append after `push_task`, before the closing `_make_callable_handle` line)
- Modify: `framework/load_all.lua` (append `commands.lua`)

- [ ] **Step 1: Append `set_command` to `framework/group.lua`**

Find the line `sms._make_callable_handle(sms.group, Group.getByName, log)` near the bottom of `framework/group.lua`. Insert this block immediately ABOVE that line:

```lua
-- ============================================================
-- set_command (apply API for sms.commands builders)
-- ============================================================

-- Dispatch a command from sms.commands to the group's controller. Wraps
-- Group:getController():setCommand(cmd). Unlike set_task, no deferred
-- dispatch — commands have no observed same-frame race.
sms.group.set_command = function(g, cmd)
  if type(cmd) ~= "table" or type(cmd._sms_verb) ~= "string" then
    log.warn("set_command: command must be built via sms.commands.* (missing _sms_verb)")
    return false
  end
  local raw = _validate_apply("set_command", g, cmd)
  if not raw then return false end
  local ctrl = raw:getController()
  if not ctrl then
    log.warn("set_command: group '" .. tostring(g.name) .. "' has no controller")
    return false
  end
  local ok, err = pcall(ctrl.setCommand, ctrl, { id = cmd.id, params = cmd.params })
  if not ok then
    log.error("set_command: DCS rejected command for '" .. tostring(g.name) .. "': " .. tostring(err))
    return false
  end
  return true
end
```

- [ ] **Step 2: Append `commands.lua` to the load list in `framework/load_all.lua`**

Open `framework/load_all.lua`. Find the `modules` array. Add `"commands.lua"` after `"task.lua"`:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "targets.lua",
  "designations.lua",
  "group.lua",
  "unit.lua",
  "area.lua",
  "timer.lua",
  "group_spawn.lua",
  "static.lua",
  "events.lua",
  "weapon.lua",
  "task.lua",
  "commands.lua",
}
```

- [ ] **Step 3: Syntax-check both files**

Run: `luac -p framework/group.lua framework/load_all.lua`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add framework/group.lua framework/load_all.lua
git commit -m "feat(group): add set_command apply method; load commands.lua"
```

---

## Task 5: `framework/options.lua` — skeleton + enum tables

**Files:**
- Create: `framework/options.lua`

- [ ] **Step 1: Create the skeleton + all enum tables**

Create `framework/options.lua`:

```lua
-- dcs-sms framework: options module (sms.options).
--
-- Builders for DCS persistent controller options
-- (Group:getController():setOption). Each builder returns a table
-- {id (int|nil), params|value, _sms_verb, _sms_air_only|_sms_ground_only|_sms_naval_only|_sms_roe}.
-- Application via sms.group:set_option(opt) — installed in group.lua.
--
-- ROE is special: the builder returns an id-less table tagged with
-- _sms_roe = true; set_option resolves the right AI.Option.{Air,Ground,Naval}.id.ROE
-- and validates the value at apply time using the helpers below.
--
-- Loading order: ... -> task.lua -> commands.lua -> options.lua.
-- Depends on: sms.group, sms.utils.

assert(type(sms)         == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log)     == "table", "framework/log.lua must be loaded first")
assert(type(sms.group)   == "table", "framework/group.lua must be loaded first")
assert(type(sms.utils)   == "table", "framework/utils.lua must be loaded first")

sms.options = sms.options or {}

local log = sms.log.module("sms.options")

local function _stamp(t, verb, air_only, ground_only, naval_only)
  t._sms_verb = verb
  if air_only    then t._sms_air_only    = true end
  if ground_only then t._sms_ground_only = true end
  if naval_only  then t._sms_naval_only  = true end
  return t
end

-- ============================================================
-- Enum tables (lowercase strings; builders accept either constant or string)
-- ============================================================

sms.options.ROE = {
  WEAPON_FREE           = "weapon_free",
  OPEN_FIRE_WEAPON_FREE = "open_fire_weapon_free",
  OPEN_FIRE             = "open_fire",
  RETURN_FIRE           = "return_fire",
  WEAPON_HOLD           = "weapon_hold",
}

sms.options.REACTION_ON_THREAT = {
  NO_REACTION         = "no_reaction",
  PASSIVE_DEFENCE     = "passive_defence",
  EVADE_FIRE          = "evade_fire",
  BYPASS_AND_ESCAPE   = "bypass_and_escape",
  ALLOW_ABORT_MISSION = "allow_abort_mission",
}

sms.options.RADAR_USING = {
  NEVER                  = "never",
  FOR_ATTACK_ONLY        = "for_attack_only",
  FOR_SEARCH_IF_REQUIRED = "for_search_if_required",
  FOR_CONTINUOUS_SEARCH  = "for_continuous_search",
}

sms.options.FLARE_USING = {
  NEVER                    = "never",
  AGAINST_FIRED_MISSILE    = "against_fired_missile",
  WHEN_FLYING_IN_SAM_WEZ   = "when_flying_in_sam_wez",
  WHEN_FLYING_NEAR_ENEMIES = "when_flying_near_enemies",
}

sms.options.ALARM_STATE = { AUTO = "auto", GREEN = "green", RED = "red" }

-- Air formation presets — strings here; builder maps to DCS packed integers.
-- Builder also accepts a raw integer for unknown formations.
sms.options.FORMATION = {
  LINE_ABREAST  = "line_abreast",
  TRAIL         = "trail",
  WEDGE         = "wedge",
  ECHELON_RIGHT = "echelon_right",
  ECHELON_LEFT  = "echelon_left",
  FINGER_FOUR   = "finger_four",
  SPREAD        = "spread",
}

-- ============================================================
-- Internal lookup tables
-- ============================================================

-- DCS air formation -> packed integer (per AI.Formation enum).
-- Verified against MOOSE Wrapper/Controllable.lua and DCS docs.
local _formation_dcs = {
  line_abreast  = 65537,    -- LINE_ABREAST
  trail         = 131073,   -- TRAIL
  wedge         = 196609,   -- WEDGE
  echelon_right = 262145,   -- ECHELON_RIGHT
  echelon_left  = 327681,   -- ECHELON_LEFT
  finger_four   = 393217,   -- FINGER_FOUR
  spread        = 458753,   -- SPREAD
}

-- Air ROE: lowercase string -> AI.Option.Air.val.ROE numeric.
local _roe_air = {
  weapon_free           = 0,
  open_fire_weapon_free = 1,
  open_fire             = 2,
  return_fire           = 3,
  weapon_hold           = 4,
}

-- Ground ROE.
local _roe_ground = {
  open_fire   = 0,
  return_fire = 1,
  weapon_hold = 2,
}

-- Naval ROE (same shape as ground in DCS).
local _roe_naval = {
  open_fire   = 0,
  return_fire = 1,
  weapon_hold = 2,
}

local _reaction_on_threat = {
  no_reaction         = 0,
  passive_defence     = 1,
  evade_fire          = 2,
  bypass_and_escape   = 3,
  allow_abort_mission = 4,
}

local _radar_using = {
  never                  = 0,
  for_attack_only        = 1,
  for_search_if_required = 2,
  for_continuous_search  = 3,
}

local _flare_using = {
  never                    = 0,
  against_fired_missile    = 1,
  when_flying_in_sam_wez   = 2,
  when_flying_near_enemies = 3,
}

local _alarm_state = { auto = 0, green = 1, red = 2 }

-- ============================================================
-- ROE category dispatch helpers (used by group.lua's set_option)
-- ============================================================

-- Resolve which DCS option id and value table to use for a given group
-- category. Returns id, value_table, category_name (for log messages).
sms.options._roe_resolve_for_category = function(category)
  if category == "airplane" or category == "helicopter" then
    return AI.Option.Air.id.ROE, _roe_air, "air"
  elseif category == "ground" or category == "train" then
    return AI.Option.Ground.id.ROE, _roe_ground, "ground"
  elseif category == "ship" then
    return AI.Option.Naval.id.ROE, _roe_naval, "naval"
  end
  return nil, nil, tostring(category)
end

-- Validate an ROE value against a category. Returns true on success;
-- false + reason string otherwise. Called by group.lua's _validate_apply
-- when payload._sms_roe is set.
sms.options._validate_roe = function(value, category)
  if type(value) ~= "string" then
    return false, "roe value must be a string, got " .. type(value)
  end
  local _, value_table, cat_name = sms.options._roe_resolve_for_category(category)
  if not value_table then
    return false, "roe: unsupported category '" .. cat_name .. "'"
  end
  if value_table[value] == nil then
    return false, "roe: value '" .. value .. "' not allowed for " .. cat_name .. " groups"
  end
  return true
end

-- Look up the DCS-side numeric value for a validated (category, value) pair.
-- Caller must have already passed _validate_roe.
sms.options._roe_value_to_dcs = function(value, category)
  local _, value_table = sms.options._roe_resolve_for_category(category)
  return value_table and value_table[value] or nil
end
```

- [ ] **Step 2: Syntax-check**

Run: `luac -p framework/options.lua`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add framework/options.lua
git commit -m "feat(options): module skeleton, enum tables, and ROE dispatch helpers"
```

---

## Task 6: `framework/options.lua` — air-only enum and bool builders + ROE builder

**Files:**
- Modify: `framework/options.lua` (append after the helpers block)

- [ ] **Step 1: Append the air-only enum builders, bool builders, formation builders, radio builders, and the ROE builder**

Append to the end of `framework/options.lua`:

```lua
-- ============================================================
-- ROE builder (special: id resolved at apply time via _sms_roe marker)
-- ============================================================

sms.options.roe = function(value)
  if type(value) ~= "string" then
    log.warn("roe: value must be a string, got " .. type(value))
    return nil
  end
  -- Validate the string is at least known to one of the three category sets.
  -- Apply layer enforces category-specific allowed values; this is just a
  -- "did you mistype it entirely" guard.
  if not (_roe_air[value] or _roe_ground[value] or _roe_naval[value]) then
    log.warn("roe: unknown value '" .. value .. "'")
    return nil
  end
  local t = { _sms_roe = true, value = value }
  return _stamp(t, "roe", false)
end

-- ============================================================
-- Air-only enum builders
-- ============================================================

sms.options.reaction_on_threat = function(value)
  if type(value) ~= "string" or _reaction_on_threat[value] == nil then
    log.warn("reaction_on_threat: unknown or invalid value '" .. tostring(value) .. "'")
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.REACTION_ON_THREAT,
    params = _reaction_on_threat[value],
  }, "reaction_on_threat", true)
end

sms.options.radar_using = function(value)
  if type(value) ~= "string" or _radar_using[value] == nil then
    log.warn("radar_using: unknown or invalid value '" .. tostring(value) .. "'")
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.RADAR_USING,
    params = _radar_using[value],
  }, "radar_using", true)
end

sms.options.flare_using = function(value)
  if type(value) ~= "string" or _flare_using[value] == nil then
    log.warn("flare_using: unknown or invalid value '" .. tostring(value) .. "'")
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.FLARE_USING,
    params = _flare_using[value],
  }, "flare_using", true)
end

-- ============================================================
-- Formation builders (air-only)
-- ============================================================

-- formation accepts either a sms.options.FORMATION string preset or a raw
-- DCS packed integer (escape hatch for formations not in the preset list).
sms.options.formation = function(value)
  local packed
  if type(value) == "number" then
    packed = value
  elseif type(value) == "string" then
    packed = _formation_dcs[value]
    if packed == nil then
      log.warn("formation: unknown preset '" .. value .. "'")
      return nil
    end
  else
    log.warn("formation: value must be a string preset or DCS integer, got " .. type(value))
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.FORMATION,
    params = packed,
  }, "formation", true)
end

-- Spacing in meters between formation members.
sms.options.formation_interval = function(meters)
  if type(meters) ~= "number" or meters < 0 then
    log.warn("formation_interval: meters must be a non-negative number")
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.FORMATION_INTERVAL,
    params = meters,
  }, "formation_interval", true)
end

-- ============================================================
-- Air-only boolean builders
-- ============================================================

local function _make_bool_air_option(verb, dcs_id)
  return function(value)
    if type(value) ~= "boolean" then
      log.warn(verb .. ": value must be a boolean, got " .. type(value))
      return nil
    end
    return _stamp({ id = dcs_id, params = value }, verb, true)
  end
end

sms.options.rtb_on_bingo       = _make_bool_air_option("rtb_on_bingo",       AI.Option.Air.id.RTB_ON_BINGO)
sms.options.rtb_on_bingo_ammo  = _make_bool_air_option("rtb_on_bingo_ammo",  AI.Option.Air.id.RTB_ON_OUT_OF_AMMO)
sms.options.silence            = _make_bool_air_option("silence",            AI.Option.Air.id.SILENCE)
sms.options.jettison_empty_tanks = _make_bool_air_option("jettison_empty_tanks", AI.Option.Air.id.JETT_TANKS_IF_EMPTY)
sms.options.landing_straight_in     = _make_bool_air_option("landing_straight_in",     AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_STRAIGHT_IN)
sms.options.landing_force_pair      = _make_bool_air_option("landing_force_pair",      AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_FORCE_PAIR)
sms.options.landing_restrict_pair   = _make_bool_air_option("landing_restrict_pair",   AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_RESTRICT_PAIR)
sms.options.landing_overhead_break  = _make_bool_air_option("landing_overhead_break",  AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_OVERHEAD_BREAK)

-- waypoint_pass_report flips the user-facing semantics: DCS exposes this
-- as PROHIBIT_WP_PASS_REPORT (inverted). We expose `true = report` and
-- invert internally so users don't think backwards.
sms.options.waypoint_pass_report = function(value)
  if type(value) ~= "boolean" then
    log.warn("waypoint_pass_report: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.PROHIBIT_WP_PASS_REPORT,
    params = not value,                  -- inverted: false = "do report"
  }, "waypoint_pass_report", true)
end

-- ============================================================
-- Radio reporting (air-only). Accepts a list of DCS attribute strings.
-- Defaults to {"Air"} when nil/empty (matches MOOSE).
-- ============================================================

local function _make_radio_option(verb, dcs_id)
  return function(attrs)
    if attrs == nil then attrs = { "Air" } end
    if type(attrs) == "string" then attrs = { attrs } end
    if type(attrs) ~= "table" then
      log.warn(verb .. ": attrs must be a table or string, got " .. type(attrs))
      return nil
    end
    for i, a in ipairs(attrs) do
      if type(a) ~= "string" then
        log.warn(verb .. ": attrs[" .. i .. "] must be a string, got " .. type(a))
        return nil
      end
    end
    return _stamp({ id = dcs_id, params = attrs }, verb, true)
  end
end

sms.options.radio_contact = _make_radio_option("radio_contact", AI.Option.Air.id.OPTION_RADIO_USAGE_CONTACT)
sms.options.radio_engage  = _make_radio_option("radio_engage",  AI.Option.Air.id.OPTION_RADIO_USAGE_ENGAGE)
sms.options.radio_kill    = _make_radio_option("radio_kill",    AI.Option.Air.id.OPTION_RADIO_USAGE_KILL)

-- ============================================================
-- Ground-only builders
-- ============================================================

sms.options.alarm_state = function(value)
  if type(value) ~= "string" or _alarm_state[value] == nil then
    log.warn("alarm_state: unknown or invalid value '" .. tostring(value) .. "'")
    return nil
  end
  return _stamp({
    id     = AI.Option.Ground.id.ALARM_STATE,
    params = _alarm_state[value],
  }, "alarm_state", false, true)
end

-- DCS takes seconds (integer). 0 disables; positive value sets duration.
sms.options.disperse_on_attack = function(seconds)
  if type(seconds) ~= "number" or seconds < 0 then
    log.warn("disperse_on_attack: seconds must be a non-negative number")
    return nil
  end
  return _stamp({
    id     = AI.Option.Ground.id.DISPERSE_ON_ATTACK,
    params = seconds,
  }, "disperse_on_attack", false, true)
end
```

- [ ] **Step 2: Syntax-check**

Run: `luac -p framework/options.lua`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add framework/options.lua
git commit -m "feat(options): all 20 builders incl. ROE, formation, radio, ground-only"
```

---

## Task 7: `group:set_option` apply method + `load_all.lua` update

**Files:**
- Modify: `framework/group.lua` (insert above `_make_callable_handle` line, after `set_command`)
- Modify: `framework/load_all.lua` (append `options.lua`)

- [ ] **Step 1: Append `set_option` to `framework/group.lua`**

Insert this block immediately after the `set_command` block from Task 4 and before the `sms._make_callable_handle(...)` line:

```lua
-- ============================================================
-- set_option (apply API for sms.options builders)
-- ============================================================

-- Dispatch an option from sms.options to the group's controller. Wraps
-- Group:getController():setOption(id, value). Handles ROE category
-- dispatch (resolves AI.Option.{Air,Ground,Naval}.id.ROE + numeric value
-- via sms.options helpers).
sms.group.set_option = function(g, opt)
  if type(opt) ~= "table" or type(opt._sms_verb) ~= "string" then
    log.warn("set_option: option must be built via sms.options.* (missing _sms_verb)")
    return false
  end
  local raw = _validate_apply("set_option", g, opt)
  if not raw then return false end
  local ctrl = raw:getController()
  if not ctrl then
    log.warn("set_option: group '" .. tostring(g.name) .. "' has no controller")
    return false
  end
  local id, value
  if opt._sms_roe then
    local category = g:get_category()
    id    = sms.options._roe_resolve_for_category(category)
    value = sms.options._roe_value_to_dcs(opt.value, category)
    if not id or value == nil then
      log.error("set_option: roe id/value resolution failed for category '" .. tostring(category) .. "'")
      return false
    end
  else
    id    = opt.id
    value = opt.params
  end
  local ok, err = pcall(ctrl.setOption, ctrl, id, value)
  if not ok then
    log.error("set_option: DCS rejected option for '" .. tostring(g.name) .. "': " .. tostring(err))
    return false
  end
  return true
end
```

- [ ] **Step 2: Append `options.lua` to `framework/load_all.lua`**

The `modules` array becomes:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "targets.lua",
  "designations.lua",
  "group.lua",
  "unit.lua",
  "area.lua",
  "timer.lua",
  "group_spawn.lua",
  "static.lua",
  "events.lua",
  "weapon.lua",
  "task.lua",
  "commands.lua",
  "options.lua",
}
```

- [ ] **Step 3: Syntax-check both files**

Run: `luac -p framework/group.lua framework/load_all.lua`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add framework/group.lua framework/load_all.lua
git commit -m "feat(group): add set_option apply method with ROE category dispatch"
```

---

## Task 8: `framework/test/smoke_commands.sh`

**Files:**
- Create: `framework/test/smoke_commands.sh`

- [ ] **Step 1: Create the smoke script**

Create `framework/test/smoke_commands.sh` with executable bit:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.commands.
# Synthetic checks (no DCS dispatch) verify builder shape + air-only flag.
# Live DCS sections spawn small fixture groups and exercise apply.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

SMOKE_FIXTURES="_smoke_cmd_air _smoke_cmd_ground"

cleanup_smoke_fixtures() {
  [ -z "${SMOKE_FIXTURES}" ] && return 0
  local lua_list=""
  for n in ${SMOKE_FIXTURES}; do lua_list="${lua_list}'${n}',"; done
  "${DCSSMS}" exec --code "
    for _, n in ipairs({${lua_list%,}}) do
      local g = Group.getByName(n); if g then g:destroy() end
    end" >/dev/null 2>&1 || true
}
trap cleanup_smoke_fixtures EXIT

cd "${FRAMEWORK_DIR}"

expect_true() {
  local label="$1"; local code="$2"; local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_false() {
  local label="$1"; local code="$2"; local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":false' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_str() {
  local label="$1"; local code="$2"; local expected="$3"; local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected '${expected}'): ${result}"; exit 1; }
}

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework"
"${DCSSMS}" exec --file load_all.lua >/dev/null

# ----------------------------------------------------------------
# Synthetic builder shape checks
# ----------------------------------------------------------------

echo "==> [build] no_action shape"
expect_str "no_action verb"  'return sms.commands.no_action()._sms_verb' 'no_action'
expect_str "no_action id"    'return sms.commands.no_action().id' 'NoAction'

echo "==> [build] simple bool builders"
expect_true "set_invisible(true) verb"   'return sms.commands.set_invisible(true)._sms_verb == "set_invisible"'
expect_true "set_immortal(false) shape"  'return sms.commands.set_immortal(false).params.value == false'
expect_true "stop_route(true) shape"     'return sms.commands.stop_route(true).params.value == true'
expect_true "set_invisible bad arg nil"  'return sms.commands.set_invisible(nil) == nil'
expect_true "set_immortal bad arg nil"   'return sms.commands.set_immortal("yes") == nil'

echo "==> [build] frequency builders"
expect_true "set_frequency Hz/AM"      'local c = sms.commands.set_frequency(251000000); return c.params.frequency == 251000000 and c.params.modulation == 0'
expect_true "set_frequency FM"         'local c = sms.commands.set_frequency(40500000, sms.commands.MODULATION.FM); return c.params.modulation == 1'
expect_true "set_frequency bad hz"     'return sms.commands.set_frequency("foo") == nil'
expect_true "set_frequency_for_unit"   'local c = sms.commands.set_frequency_for_unit(251000000, sms.commands.MODULATION.AM, nil, 42); return c.params.unitId == 42'

echo "==> [build] switch_waypoint"
expect_true "switch_waypoint shape"    'local c = sms.commands.switch_waypoint(0, 1); return c.params.fromWaypointIndex == 0 and c.params.goToWaypointIndex == 1'
expect_true "switch_waypoint bad arg"  'return sms.commands.switch_waypoint(0, "x") == nil'

echo "==> [build] callsign (air-only)"
expect_true "set_callsign air-only flag" 'return sms.commands.set_callsign(sms.commands.CALLSIGN.ENFIELD, 1)._sms_air_only == true'
expect_true "set_callsign bad arg"       'return sms.commands.set_callsign("foo") == nil'

echo "==> [build] beacon"
expect_true "activate_beacon air-only" 'return sms.commands.activate_beacon({type=sms.commands.BEACON.TYPE.TACAN, system=sms.commands.BEACON.SYSTEM.TACAN_TANKER_X, frequency=1088000000})._sms_air_only == true'
expect_true "activate_beacon bad opts" 'return sms.commands.activate_beacon({type="x"}) == nil'
expect_true "deactivate_beacon shape"  'return sms.commands.deactivate_beacon()._sms_verb == "deactivate_beacon"'

echo "==> [build] ACLS / ICLS / Link4"
expect_true "activate_acls"   'return sms.commands.activate_acls()._sms_air_only == true'
expect_true "deactivate_acls" 'return sms.commands.deactivate_acls()._sms_verb == "deactivate_acls"'
expect_true "activate_icls"   'return sms.commands.activate_icls(11)._sms_air_only == true'
expect_true "activate_link4"  'return sms.commands.activate_link4(336000000)._sms_air_only == true'

echo "==> [build] eplrs"
expect_true "eplrs(true)"          'return sms.commands.eplrs(true).params.value == true'
expect_true "eplrs with group_id"  'return sms.commands.eplrs(true, 100).params.groupId == 100'
expect_true "eplrs bad value"      'return sms.commands.eplrs("x") == nil'

# ----------------------------------------------------------------
# Live-DCS apply checks
# ----------------------------------------------------------------

echo "==> [apply] spawn ground fixture"
expect_true "spawn ground" "
  return sms.group.create({
    name='_smoke_cmd_ground', position={x=0,y=0,z=0}, country='USA',
    units={{type='M-1 Abrams'}},
  }) ~= nil"

echo "==> [apply] spawn air fixture"
expect_true "spawn air" "
  return sms.group.create({
    name='_smoke_cmd_air', position={x=20000,y=0,z=20000}, country='USA',
    category='airplane',
    units={{type='F-16C_50', alt=6000}},
  }) ~= nil"

# Wait one sim tick for controllers to wire up.
"${DCSSMS}" exec --code 'sms.timer.after(0.5, function() end)' >/dev/null

echo "==> [apply] valid command on air"
expect_true "switch_waypoint on air" "
  return sms.group('_smoke_cmd_air'):set_command(sms.commands.switch_waypoint(0, 1))"

echo "==> [apply] air-only rejected on ground"
expect_false "set_callsign on ground" "
  return sms.group('_smoke_cmd_ground'):set_command(sms.commands.set_callsign(sms.commands.CALLSIGN.ENFIELD))"

echo "==> [apply] non-handle rejected"
expect_false "non-handle set_command" "return sms.group.set_command('not-a-handle', sms.commands.no_action())"

echo "==> [apply] manually-built table rejected (missing _sms_verb)"
expect_false "raw table rejected" "return sms.group('_smoke_cmd_air'):set_command({id='NoAction', params={}})"

echo "ALL SMOKE PASSED"
```

- [ ] **Step 2: Make executable + syntax-check**

Run:
```bash
chmod +x framework/test/smoke_commands.sh
bash -n framework/test/smoke_commands.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke_commands.sh
git commit -m "test(commands): add synthetic + live smoke coverage"
```

---

## Task 9: `framework/test/smoke_options.sh`

**Files:**
- Create: `framework/test/smoke_options.sh`

- [ ] **Step 1: Create the smoke script**

Create `framework/test/smoke_options.sh`:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.options.
# Synthetic checks (no DCS dispatch) verify builder shape + flags + ROE marker.
# Live DCS sections spawn small fixture groups and exercise apply.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

SMOKE_FIXTURES="_smoke_opt_air _smoke_opt_ground"

cleanup_smoke_fixtures() {
  [ -z "${SMOKE_FIXTURES}" ] && return 0
  local lua_list=""
  for n in ${SMOKE_FIXTURES}; do lua_list="${lua_list}'${n}',"; done
  "${DCSSMS}" exec --code "
    for _, n in ipairs({${lua_list%,}}) do
      local g = Group.getByName(n); if g then g:destroy() end
    end" >/dev/null 2>&1 || true
}
trap cleanup_smoke_fixtures EXIT

cd "${FRAMEWORK_DIR}"

expect_true() {
  local label="$1"; local code="$2"; local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}
expect_false() {
  local label="$1"; local code="$2"; local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":false' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}
expect_str() {
  local label="$1"; local code="$2"; local expected="$3"; local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected '${expected}'): ${result}"; exit 1; }
}

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework"
"${DCSSMS}" exec --file load_all.lua >/dev/null

# ----------------------------------------------------------------
# Synthetic builder shape checks
# ----------------------------------------------------------------

echo "==> [build] ROE marker + value"
expect_true "roe via constant"       'local o = sms.options.roe(sms.options.ROE.WEAPON_HOLD); return o._sms_roe == true and o.value == "weapon_hold"'
expect_true "roe via raw string"     'local o = sms.options.roe("weapon_free"); return o._sms_roe == true and o.value == "weapon_free"'
expect_true "roe verb"               'return sms.options.roe(sms.options.ROE.WEAPON_HOLD)._sms_verb == "roe"'
expect_true "roe unknown rejected"   'return sms.options.roe("kill_em_all") == nil'

echo "==> [build] enum builders (air-only)"
expect_true "reaction_on_threat"     'return sms.options.reaction_on_threat(sms.options.REACTION_ON_THREAT.EVADE_FIRE)._sms_air_only == true'
expect_true "radar_using"            'return sms.options.radar_using(sms.options.RADAR_USING.NEVER).params == 0'
expect_true "flare_using bad arg"    'return sms.options.flare_using("often") == nil'

echo "==> [build] formation"
expect_true "formation preset"       'return sms.options.formation(sms.options.FORMATION.LINE_ABREAST).params == 65537'
expect_true "formation raw int"      'return sms.options.formation(393217).params == 393217'
expect_true "formation bad arg"      'return sms.options.formation("invalid_preset") == nil'
expect_true "formation_interval"     'return sms.options.formation_interval(50).params == 50'

echo "==> [build] bool builders"
expect_true "rtb_on_bingo true"      'return sms.options.rtb_on_bingo(true).params == true'
expect_true "rtb_on_bingo bad arg"   'return sms.options.rtb_on_bingo("yes") == nil'
expect_true "silence(true) air-only" 'return sms.options.silence(true)._sms_air_only == true'
expect_true "jettison_empty_tanks"   'return sms.options.jettison_empty_tanks(true).params == true'
expect_true "landing_straight_in"    'return sms.options.landing_straight_in(true)._sms_air_only == true'

echo "==> [build] waypoint_pass_report (inverted)"
expect_true "wp report=true -> false" 'return sms.options.waypoint_pass_report(true).params == false'
expect_true "wp report=false -> true" 'return sms.options.waypoint_pass_report(false).params == true'

echo "==> [build] radio reporting (default + list)"
expect_true "radio_contact default"  'local o = sms.options.radio_contact(); return o.params[1] == "Air"'
expect_true "radio_engage list"      'local o = sms.options.radio_engage({"Ground Units","Air"}); return o.params[1] == "Ground Units"'
expect_true "radio_kill string -> table" 'local o = sms.options.radio_kill("Air"); return o.params[1] == "Air"'

echo "==> [build] ground-only builders"
expect_true "alarm_state"            'return sms.options.alarm_state(sms.options.ALARM_STATE.RED).params == 2'
expect_true "alarm_state ground-only" 'return sms.options.alarm_state(sms.options.ALARM_STATE.GREEN)._sms_ground_only == true'
expect_true "disperse_on_attack"     'return sms.options.disperse_on_attack(30).params == 30'
expect_true "disperse_on_attack neg" 'return sms.options.disperse_on_attack(-5) == nil'

# ----------------------------------------------------------------
# Live-DCS apply checks
# ----------------------------------------------------------------

echo "==> [apply] spawn fixtures"
expect_true "spawn air" "
  return sms.group.create({
    name='_smoke_opt_air', position={x=40000,y=0,z=40000}, country='USA',
    category='airplane',
    units={{type='F-16C_50', alt=6000}},
  }) ~= nil"

expect_true "spawn ground" "
  return sms.group.create({
    name='_smoke_opt_ground', position={x=10000,y=0,z=10000}, country='USA',
    units={{type='M-1 Abrams'}},
  }) ~= nil"

"${DCSSMS}" exec --code 'sms.timer.after(0.5, function() end)' >/dev/null

echo "==> [apply] ROE on each category"
expect_true "air ROE weapon_free"      "return sms.group('_smoke_opt_air'):set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))"
expect_true "air ROE weapon_hold"      "return sms.group('_smoke_opt_air'):set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))"
expect_true "ground ROE weapon_hold"   "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))"
expect_true "ground ROE return_fire"   "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.options.ROE.RETURN_FIRE))"

echo "==> [apply] ROE air-only value rejected on ground"
expect_false "ground ROE weapon_free" "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))"
expect_false "ground ROE open_fire_weapon_free" "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.options.ROE.OPEN_FIRE_WEAPON_FREE))"

echo "==> [apply] air-only option rejected on ground"
expect_false "rtb_on_bingo on ground" "return sms.group('_smoke_opt_ground'):set_option(sms.options.rtb_on_bingo(true))"

echo "==> [apply] ground-only option rejected on air"
expect_false "alarm_state on air" "return sms.group('_smoke_opt_air'):set_option(sms.options.alarm_state(sms.options.ALARM_STATE.RED))"

echo "==> [apply] valid air options"
expect_true "rtb_on_bingo on air"  "return sms.group('_smoke_opt_air'):set_option(sms.options.rtb_on_bingo(true))"
expect_true "radar_using on air"   "return sms.group('_smoke_opt_air'):set_option(sms.options.radar_using(sms.options.RADAR_USING.FOR_CONTINUOUS_SEARCH))"

echo "==> [apply] valid ground options"
expect_true "alarm_state on ground" "return sms.group('_smoke_opt_ground'):set_option(sms.options.alarm_state(sms.options.ALARM_STATE.RED))"
expect_true "disperse_on_attack ground" "return sms.group('_smoke_opt_ground'):set_option(sms.options.disperse_on_attack(15))"

echo "==> [apply] manually-built table rejected"
expect_false "raw option rejected" "return sms.group('_smoke_opt_air'):set_option({id=AI.Option.Air.id.ROE, params=4})"

echo "ALL SMOKE PASSED"
```

- [ ] **Step 2: Make executable + syntax-check**

Run:
```bash
chmod +x framework/test/smoke_options.sh
bash -n framework/test/smoke_options.sh
```
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke_options.sh
git commit -m "test(options): add synthetic + live smoke coverage including ROE dispatch"
```

---

## Task 10: Update `AGENTS.md`

**Files:**
- Modify: `AGENTS.md` (§3 mention naval-only and ROE flags; §6 load order; §7 add `sms.commands` and `sms.options` sub-sections)

- [ ] **Step 1: Update §3 (Failure model — Category enforcement)**

Find the `### Category enforcement: air-only and ground-only` heading. Rename it to:

```markdown
### Category enforcement: air-only / ground-only / naval-only / ROE
```

Replace the bullet list and the trailing paragraph with:

```markdown
Four private flags on a payload (task / command / option) mark category restrictions:

- `_sms_air_only = true` — only `airplane` / `helicopter` groups accept this payload.
- `_sms_ground_only = true` — only `ground` groups accept (ships and trains are excluded).
- `_sms_naval_only = true` — only `ship` groups accept. (No v1 builder sets this; reserved for forward-compat.)
- `_sms_roe = true` — special marker on ROE options. Apply layer reads the group's category and dispatches to `AI.Option.{Air,Ground,Naval}.id.ROE` with category-specific value validation. Rejects values not allowed for the resolved category (e.g. `"weapon_free"` against ground groups).

`set_task` / `push_task` / `set_command` / `set_option` reject mismatches at apply time with `log.warn + return false`. `combo` (sms.task only) aggregates: a combo containing any air-only or ground-only sub-task inherits the corresponding flag.
```

- [ ] **Step 2: Update §6 (Loading order)**

Find the `## 6. Loading order` heading. Replace the load-chain code block with:

```
sms.lua → log.lua → utils.lua → targets.lua → designations.lua → group.lua → unit.lua → area.lua → timer.lua → group_spawn.lua → static.lua → events.lua → weapon.lua → task.lua → commands.lua → options.lua
```

- [ ] **Step 3: Update §2 file map**

Find the `## 2. Repo layout at a glance` section's tree block. Add two lines under the framework block, after `task.lua`:

```
│   ├── commands.lua        sms.commands — DCS controller setCommand wrappers.
│   ├── options.lua         sms.options — DCS controller setOption wrappers + ROE dispatch.
```

- [ ] **Step 4: Add `sms.commands` and `sms.options` sub-sections under §7**

After the `### sms.designations — framework/designations.lua` block (the last sub-section under §7), append:

```markdown
### `sms.commands` — `framework/commands.lua`

One-shot controller commands. Each builder returns a DCS command table (`{id, params, _sms_verb, _sms_air_only?}`); apply via `group:set_command(cmd)`.

| Function | Args | Categories |
|---|---|---|
| `sms.commands.no_action()` | — | all |
| `sms.commands.set_invisible(value)` | bool | all |
| `sms.commands.set_immortal(value)` | bool | all |
| `sms.commands.stop_route(value)` | bool | all |
| `sms.commands.switch_action(idx)` | int | all |
| `sms.commands.set_unlimited_fuel(value)` | bool | air |
| `sms.commands.eplrs(value, group_id?)` | bool + optional int | all |
| `sms.commands.set_frequency(hz, modulation?, power?)` | Hz, `MODULATION.AM`/`.FM`, optional W | all |
| `sms.commands.set_frequency_for_unit(hz, modulation?, power?, unit_id)` | same plus unit id | all |
| `sms.commands.switch_waypoint(from, to)` | two ints | all |
| `sms.commands.set_callsign(callname, number?)` | numeric callname enum + flight num | air |
| `sms.commands.activate_beacon(opts)` | `{type, system, frequency, callsign?, name?, unit_id?, channel?, mode_channel?, aa?, bearing?}` | air |
| `sms.commands.deactivate_beacon()` | — | air |
| `sms.commands.activate_acls(unit_id?, name?)` | optional int + optional string | air |
| `sms.commands.deactivate_acls()` | — | air |
| `sms.commands.activate_icls(channel, unit_id?, callsign?)` | int + optional int + optional string | air |
| `sms.commands.deactivate_icls()` | — | air |
| `sms.commands.activate_link4(frequency, unit_id?, callsign?)` | Hz + optional int + optional string | air |
| `sms.commands.deactivate_link4()` | — | air |

**Enums** (uppercase tables; builders accept either constant or raw value): `sms.commands.MODULATION` (`AM`/`FM`), `sms.commands.BEACON.TYPE`, `sms.commands.BEACON.SYSTEM`, `sms.commands.CALLSIGN`.

**Apply API on sms.group:**

| Method | Returns |
|---|---|
| `group:set_command(cmd)` | `true` on dispatch; `false` + log on bad input or category mismatch. Wraps `Group:getController():setCommand`. Manually-built tables (no `_sms_verb`) are rejected — different from `set_task`. |

### `sms.options` — `framework/options.lua`

Persistent controller options. Each builder returns `{id (int|nil), params|value, _sms_verb, _sms_air_only?, _sms_ground_only?, _sms_roe?}`; apply via `group:set_option(opt)`.

| Function | Args | Categories |
|---|---|---|
| `sms.options.roe(value)` | `sms.options.ROE.*` (or string). Dispatched per category at apply time. | all (special) |
| `sms.options.reaction_on_threat(value)` | `sms.options.REACTION_ON_THREAT.*` | air |
| `sms.options.radar_using(value)` | `sms.options.RADAR_USING.*` | air |
| `sms.options.flare_using(value)` | `sms.options.FLARE_USING.*` | air |
| `sms.options.formation(value)` | `sms.options.FORMATION.*` preset OR raw DCS packed integer | air |
| `sms.options.formation_interval(meters)` | non-negative number | air |
| `sms.options.rtb_on_bingo(value)` | bool | air |
| `sms.options.rtb_on_bingo_ammo(value)` | bool | air |
| `sms.options.silence(value)` | bool | air |
| `sms.options.jettison_empty_tanks(value)` | bool | air |
| `sms.options.landing_straight_in(value)` | bool | air |
| `sms.options.landing_force_pair(value)` | bool | air |
| `sms.options.landing_restrict_pair(value)` | bool | air |
| `sms.options.landing_overhead_break(value)` | bool | air |
| `sms.options.waypoint_pass_report(value)` | bool. **Inverted internally** — `true` = report. | air |
| `sms.options.radio_contact(attrs?)` | list of DCS attribute strings (default `{"Air"}`) | air |
| `sms.options.radio_engage(attrs?)` | same | air |
| `sms.options.radio_kill(attrs?)` | same | air |
| `sms.options.alarm_state(value)` | `sms.options.ALARM_STATE.AUTO`/`GREEN`/`RED` | ground |
| `sms.options.disperse_on_attack(seconds)` | non-negative int seconds (0 disables) | ground |

**Enums:** `sms.options.ROE`, `sms.options.REACTION_ON_THREAT`, `sms.options.RADAR_USING`, `sms.options.FLARE_USING`, `sms.options.ALARM_STATE`, `sms.options.FORMATION`. Each is a small table of uppercase keys → lowercase string values.

**ROE dispatch.** `sms.options.roe(value)` returns a table with `_sms_roe = true` and no `id`. At apply time, `set_option` reads the group's category and resolves to:

- `airplane` / `helicopter` → `AI.Option.Air.id.ROE`; full 5 values allowed.
- `ground` / `train` → `AI.Option.Ground.id.ROE`; 3 values (`open_fire`, `return_fire`, `weapon_hold`).
- `ship` → `AI.Option.Naval.id.ROE`; 3 values (same as ground).

Air-only ROE strings (`weapon_free`, `open_fire_weapon_free`) are rejected for ground/naval with a logged `false`.

**Apply API on sms.group:**

| Method | Returns |
|---|---|
| `group:set_option(opt)` | `true` on dispatch; `false` + log on bad input, category mismatch, or ROE value not allowed for the resolved category. Wraps `Group:getController():setOption`. Manually-built tables (no `_sms_verb`) are rejected. |
```

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): document sms.commands and sms.options modules"
```

---

## Task 11: Write `docs/api/commands.md`

**Files:**
- Create: `docs/api/commands.md`

- [ ] **Step 1: Create the per-builder reference page**

Read [`docs/api/README.md`](../../docs/api/README.md) to confirm the page template. Then create `docs/api/commands.md` covering every builder with the standard layout (Synopsis / Arguments / Returns / Example). Required sections:

1. **Header + overview** — link to `AGENTS.md` §3 for the failure model and §7 for the dense map. State that `sms` is loaded globally.
2. **Loading note** — depends on `sms.group`, `sms.utils`. Loaded by `load_all.lua`.
3. **Conventions block** — modulation: `sms.commands.MODULATION.AM`/`.FM`. All `_sms_air_only` builders are flagged in the table.
4. **Apply API section first** — `group:set_command(cmd)`. Show that manually-built tables without `_sms_verb` are rejected.
5. **Builder sections** — one per command, in this order: simple-bool group (no_action / set_invisible / set_immortal / stop_route / switch_action / set_unlimited_fuel / eplrs), frequency group, switch_waypoint, set_callsign, beacon group, ACLS / ICLS / Link4 group.
6. **Enum reference tables** — three tables at the bottom: `MODULATION`, `BEACON.TYPE`, `BEACON.SYSTEM`, `CALLSIGN`.

Every example must reference only symbols verified in `framework/commands.lua`. Keep examples realistic — show the builder paired with `group:set_command(...)`.

Confirm the page passes a self-grep check: every options-table key shown must appear in `framework/commands.lua`.

- [ ] **Step 2: Commit**

```bash
git add docs/api/commands.md
git commit -m "docs(api): per-builder reference for sms.commands"
```

---

## Task 12: Write `docs/api/options.md`

**Files:**
- Create: `docs/api/options.md`

- [ ] **Step 1: Create the per-builder reference page**

Same format as `commands.md`. Required sections:

1. **Header + overview** — link to AGENTS.md §3 / §7. Highlight the ROE-dispatch quirk near the top.
2. **Loading note** — depends on `sms.group`, `sms.utils`. Loaded by `load_all.lua`.
3. **Conventions block** — string values are lowercase + underscores; constants are UPPERCASE; both forms accepted.
4. **Apply API section first** — `group:set_option(opt)`. ROE dispatch table (3 categories → DCS option id + allowed values).
5. **ROE first** as the most-commonly-reached-for option, with realistic CAP / SAM examples and an explicit demonstration of the air-only `weapon_free` being rejected on ground.
6. **Air-only enum builders** — `reaction_on_threat`, `radar_using`, `flare_using`, `formation`, `formation_interval`.
7. **Air-only bool builders** — `rtb_on_bingo`, `rtb_on_bingo_ammo`, `silence`, `jettison_empty_tanks`, `landing_*`, `waypoint_pass_report`. Spell out the `waypoint_pass_report` inversion clearly.
8. **Radio reporting builders** — `radio_contact`, `radio_engage`, `radio_kill`, with example DCS attribute strings.
9. **Ground-only builders** — `alarm_state`, `disperse_on_attack` (note integer-seconds, not bool).
10. **Enum reference tables** — `ROE`, `REACTION_ON_THREAT`, `RADAR_USING`, `FLARE_USING`, `ALARM_STATE`, `FORMATION` at the bottom.

Every value listed in any enum table must appear in `framework/options.lua`.

- [ ] **Step 2: Commit**

```bash
git add docs/api/options.md
git commit -m "docs(api): per-builder reference for sms.options"
```

---

## Task 13: Update `docs/api/README.md`, `docs/api/examples.md`, top-level `README.md`

**Files:**
- Modify: `docs/api/README.md` (index gets two rows)
- Modify: `docs/api/examples.md` (rewrite recipe 1; remove "Framework gap" callout)
- Modify: `README.md` (module list under "Repo layout")

- [ ] **Step 1: Add rows to the `docs/api/README.md` module index**

Find the `## Module index` table. Insert these two rows after the `task.md` row and before `group.md`:

```markdown
| [`commands.md`](commands.md) | `sms.commands` | One-shot controller commands (frequency, beacons, callsign, waypoint switch, etc.) and `group:set_command`. |
| [`options.md`](options.md) | `sms.options` | Persistent controller options (ROE, alarm state, RTB on bingo, formation, …) and `group:set_option`. ROE dispatched per category. |
```

- [ ] **Step 2: Rewrite recipe 1 in `docs/api/examples.md`**

Replace the entire **"## 1. ROE flip on proximity"** section with:

```markdown
## 1. ROE flip on proximity

**Scenario** — A blue CAP and a red CAP are airborne with rules of engagement set to *Weapons Hold*. As soon as the two flights close to within 20 nautical miles, blue is cleared to *Weapons Free*. Used a lot for training scenarios where you want a known engagement geometry.

**Modules used** — [`sms.group`](group.md), [`sms.task`](task.md), [`sms.options`](options.md), [`sms.timer`](timer.md), [`sms.utils`](utils.md).

```lua
-- Spawn the two CAPs.
local blue_cap = sms.group.create({
  name     = "blue-cap",
  position = {x = 0,      y = 0, z = 0},
  country  = "USA",
  category = "airplane",
  units    = { {type = "FA-18C_hornet", alt = 7500, heading = 90, speed = 220} },
})

local red_cap = sms.group.create({
  name     = "red-cap",
  position = {x = 80000, y = 0, z = 0},   -- ~43 nm east
  country  = "RUSSIA",
  category = "airplane",
  units    = { {type = "Su-27", alt = 7500, heading = 270, speed = 220} },
})

-- Send each side to orbit a point 30 km in front of itself.
blue_cap:set_task(sms.task.orbit({x = 30000, y = 0, z = 0}, {
  altitude = 7500, speed = 220, pattern = "Circle",
}))
red_cap:set_task(sms.task.orbit({x = 50000, y = 0, z = 0}, {
  altitude = 7500, speed = 220, pattern = "Circle",
}))

-- Both sides start with weapons hold.
blue_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))
red_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))

-- Poll once per second; convert 20 NM to meters once.
local TRIGGER_RANGE_M = sms.utils.feet_to_meters(20 * 6076)   -- 20 NM ≈ 37 040 m
local triggered       = false

sms.timer.every(1.0, function()
  if triggered then return false end                          -- self-cancel after flip
  if not (blue_cap:is_alive() and red_cap:is_alive()) then return false end

  local d = sms.utils.vec3_distance(blue_cap:get_position(), red_cap:get_position())
  if d and d <= TRIGGER_RANGE_M then
    blue_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))
    sms.log.info(string.format("blue cleared hot at %.0f m", d))
    triggered = true
  end
end)
```
```

(Note: the closing triple backtick is part of the literal block content. The "Framework gap" callout that was below the original snippet is removed entirely.)

- [ ] **Step 3: Update `README.md` framework module list**

Find the line in the top-level `README.md` "Repo layout" section that reads:

```
- `framework/` — in-DCS Lua framework. Modules: `sms`, `sms.log`, `sms.utils`, `sms.targets`, `sms.designations`, `sms.group` (+ `sms.spawn` factories), `sms.unit`, `sms.area`, `sms.timer`, `sms.static`, `sms.events`, `sms.weapon`, `sms.task`. See [`AGENTS.md`](AGENTS.md) for the surface and conventions, or [`docs/api/`](docs/api/) for per-function detail.
```

Replace it with the version that includes the new modules:

```
- `framework/` — in-DCS Lua framework. Modules: `sms`, `sms.log`, `sms.utils`, `sms.targets`, `sms.designations`, `sms.group` (+ `sms.spawn` factories), `sms.unit`, `sms.area`, `sms.timer`, `sms.static`, `sms.events`, `sms.weapon`, `sms.task`, `sms.commands`, `sms.options`. See [`AGENTS.md`](AGENTS.md) for the surface and conventions, or [`docs/api/`](docs/api/) for per-function detail.
```

- [ ] **Step 4: Commit**

```bash
git add docs/api/README.md docs/api/examples.md README.md
git commit -m "docs: add commands/options to api index, rewrite ROE recipe, update README"
```

---

## Self-Review

Plan checked against spec on 2026-04-29. Spec coverage:

- **Module skeleton + enums** — Tasks 2 (`commands.lua`), 5 (`options.lua`).
- **All 19 commands builders** — Task 2 (simple, 7) + Task 3 (complex, 12).
- **All 20 options builders** — Task 5 (helpers + ROE dispatch table) + Task 6 (everything).
- **`_validate_apply` extension** — Task 1.
- **`group:set_command` + `group:set_option`** — Tasks 4, 7.
- **`load_all.lua`** — split across Tasks 4 and 7 (one append each, on the file's modification points).
- **Smoke tests** — Tasks 8, 9.
- **AGENTS.md** — Task 10 (§3, §6, §2 file map, §7 sub-sections).
- **`docs/api/commands.md`, `docs/api/options.md`** — Tasks 11, 12.
- **`docs/api/README.md` index, `docs/api/examples.md` recipe 1, `README.md` module list** — Task 13.

No placeholders found. Type consistency verified: `_sms_verb` strings consistent across builder + smoke test entries; `AI.Option.*.id.*` constant names consistent across `options.lua` and `_validate_apply`'s ROE dispatch (resolved via `sms.options._roe_resolve_for_category` so the constants exist only inside `options.lua`). Apply-method log strings match `[sms.commands]` / `[sms.options]` tags from each module's `sms.log.module(...)` call.
