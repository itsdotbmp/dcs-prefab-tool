# `sms.commands` — one-shot controller commands

`sms.commands` is the builder layer for DCS *controller commands* — one-shot directives like "switch to waypoint 3", "set radio to 251.0 AM", "activate the TACAN beacon", "go invisible to AI sensors". Where [`sms.task`](task.md) builds long-lived behaviors and [`sms.options`](options.md) flips persistent flags, commands are fire-and-forget pokes at the group's controller (`Group:getController():setCommand`).

Each builder returns a plain DCS-shaped command table `{id = ..., params = ...}` with a private `_sms_verb` tag (and optionally `_sms_air_only`) that the apply layer uses for log messages and category enforcement. The apply step is [`group:set_command(cmd)`](#applying-a-command).

All builders follow the framework's [failure model](../../framework/AGENTS.md#3-failure-model-log--nil-never-throw) — log + return `nil` on bad input; never throw.

## Loading

`sms.commands` lives in `framework/commands.lua` and depends on [`sms.group`](group.md) (for the apply method install path) and [`sms.utils`](utils.md). All three load via `framework/load_all.lua`; nothing extra is required.

## Conventions

- **Modulation** — pass `sms.commands.MODULATION.AM` (`0`) or `sms.commands.MODULATION.FM` (`1`) to the frequency builders. Raw integers also work.
- **Frequencies** — Hz. `251000000` is 251.0 MHz.
- **Air-only builders** — DCS rejects (or silently ignores) some commands on non-aircraft groups. The framework stamps these with `_sms_air_only`; applying them to a ground or naval group logs a warning and returns `false`. Air-only builders are flagged in the tables below.
- **Booleans are booleans.** `set_invisible(true)`, not `set_invisible(1)`. Bad types log + return `nil`.
- **DCS callsign / beacon enums** — the framework re-exports the most common values as [`sms.commands.CALLSIGN`](#callsign), [`sms.commands.BEACON.TYPE`](#beacontype) and [`sms.commands.BEACON.SYSTEM`](#beaconsystem). Any positive integer from the DCS docs is accepted (passthrough).

## Applying a command

### `group:set_command(cmd) → bool`

**Synopsis** — apply a `sms.commands.*` command table to a group's controller.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `cmd` | command table | Result of any `sms.commands.*` builder. Manually-built tables (no `_sms_verb` tag) are rejected. |

**Returns** — `true` on success; `false` + log on bad handle, dead group, missing controller, air-only mismatch, or a DCS-side rejection. Per the [failure model](../../framework/AGENTS.md#3-failure-model-log--nil-never-throw), the mission script keeps running.

**Example**

```lua
local strike = sms.group("red-strike-1")
local cmd    = sms.commands.set_invisible(true)
strike:set_command(cmd)              -- true; group is now invisible to AI sensors
```

**Notes**

- Manually-built tables are rejected on purpose: `group:set_command({id = "NoAction", params = {}})` logs a warning and returns `false`. Always go through a builder so the framework can tag the command.
- Commands have no observed same-frame race, so `set_command` dispatches synchronously (unlike [`set_task`](group.md#gset_tasktask--bool), which defers).

---

## Builders

### Simple boolean / no-arg commands

These builders take a single boolean (or no argument). They produce all-categories commands except where flagged.

#### `sms.commands.no_action() → cmd`

**Synopsis** — a no-op command. Useful for clearing a queued command on the controller.

**Returns** — command table; never fails.

**Example**

```lua
sms.group("convoy-1"):set_command(sms.commands.no_action())
```

#### `sms.commands.set_invisible(value) → cmd`

**Synopsis** — toggle the group's invisibility to AI sensors. While invisible, the AI cannot detect or target the group.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` to hide from AI, `false` to restore. |

**Returns** — command table, or `nil` + log if `value` is not a boolean.

**Example**

```lua
local recon = sms.group("recon-1")
recon:set_command(sms.commands.set_invisible(true))    -- hide
sms.timer.after(60, function()
  recon:set_command(sms.commands.set_invisible(false)) -- reveal a minute later
end)
```

#### `sms.commands.set_immortal(value) → cmd`

**Synopsis** — toggle damage immunity. While immortal, weapons hit but cause no damage.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` for immortal, `false` to restore. |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
sms.group("vip-convoy"):set_command(sms.commands.set_immortal(true))
```

#### `sms.commands.stop_route(value) → cmd`

**Synopsis** — halt or resume the group's route. `true` halts at the current position; `false` resumes the route from where it stopped.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` halts, `false` resumes. |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
local armor = sms.group("red-armor-1")
armor:set_command(sms.commands.stop_route(true))   -- hold position
sms.timer.after(120, function()
  armor:set_command(sms.commands.stop_route(false)) -- resume after 2 min
end)
```

#### `sms.commands.switch_action(action_index) → cmd`

**Synopsis** — switch to a triggered action by index, as defined in the mission editor's group "triggered actions" panel. Passed verbatim as `params.actionIndex` to DCS.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `action_index` | `number` | Triggered-action index from the group definition. |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
sms.group("sam-site-1"):set_command(sms.commands.switch_action(2))
```

#### `sms.commands.set_unlimited_fuel(value) → cmd` *(air-only)*

**Synopsis** — toggle unlimited fuel on aircraft. Convenient for long-running CAS / CAP groups.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` enables, `false` restores normal fuel burn. |

**Returns** — command table, or `nil` + log on bad input. Applying to a ground / naval group logs and returns `false`.

**Example**

```lua
sms.group("blue-cap-1"):set_command(sms.commands.set_unlimited_fuel(true))
```

#### `sms.commands.eplrs(value, group_id) → cmd`

**Synopsis** — toggle EPLRS / Link-16 datalink on the group.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` enables datalink, `false` disables. |
| `group_id` | `number` | (optional) DCS integer group id. When omitted, DCS uses the group the command is applied to. |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
sms.group("blue-strike-1"):set_command(sms.commands.eplrs(true))
```

---

### Frequency

#### `sms.commands.set_frequency(hz, modulation, power) → cmd`

**Synopsis** — set the group's radio frequency.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `hz` | `number` | Frequency in Hz. `251000000` is 251.0 MHz. |
| `modulation` | `number` | (optional) `sms.commands.MODULATION.AM` (default) or `.FM`. |
| `power` | `number` | (optional) Transmit power in watts. DCS picks a default when omitted. |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_command(sms.commands.set_frequency(251000000, sms.commands.MODULATION.AM, 100))
```

#### `sms.commands.set_frequency_for_unit(hz, modulation, power, unit_id) → cmd`

**Synopsis** — per-unit variant of `set_frequency`. Sets the radio on a single unit inside the group.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `hz` | `number` | Frequency in Hz. |
| `modulation` | `number` | (optional) `sms.commands.MODULATION.AM` (default) or `.FM`. |
| `power` | `number` | (optional) Transmit power in watts. |
| `unit_id` | `number` | DCS integer unit id. **Required.** |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
-- unit_id here is the integer DCS unit id (Unit:getID()).
local unit_id = Unit.getByName("blue-cap-1-1"):getID()
sms.group("blue-cap-1"):set_command(
  sms.commands.set_frequency_for_unit(305000000, sms.commands.MODULATION.AM, nil, unit_id)
)
```

**Notes** — `power` is optional but positional; pass `nil` to skip it. The unit id is the DCS integer (`Unit:getID()`); the framework does not currently expose a helper for it.

---

### Waypoint

#### `sms.commands.switch_waypoint(from_idx, to_idx) → cmd`

**Synopsis** — jump from waypoint `from_idx` to `to_idx`. DCS uses 0-based waypoint indices.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `from_idx` | `number` | Source waypoint index (0-based). |
| `to_idx` | `number` | Destination waypoint index (0-based). |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
-- Skip ahead from waypoint 0 to waypoint 3.
sms.group("blue-strike-1"):set_command(sms.commands.switch_waypoint(0, 3))
```

---

### Callsign

#### `sms.commands.set_callsign(callname, number) → cmd` *(air-only)*

**Synopsis** — set the AI radio callsign and flight number.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `callname` | `number` | Numeric DCS callname enum. Use [`sms.commands.CALLSIGN.*`](#callsign) or any DCS `Aircraft.id` integer. |
| `number` | `number` | (optional) Flight number; defaults to `1`. |

**Returns** — command table, or `nil` + log on bad input. Applying to a non-aircraft group logs and returns `false`.

**Example**

```lua
sms.group("blue-cap-1"):set_command(
  sms.commands.set_callsign(sms.commands.CALLSIGN.ENFIELD, 2)  -- "Enfield 2"
)
```

**Notes** — the callname namespace is per-aircraft-role in DCS (fighters, AWACS, tankers all share integer ids). The framework treats the callname as a passthrough integer; pick the right value from the DCS docs for your aircraft.

---

### Beacon

#### `sms.commands.activate_beacon(opts) → cmd` *(air-only)*

**Synopsis** — activate a beacon (TACAN, ILS, VOR, …) on an air group. The host group must support the chosen beacon type (e.g. only tankers can run an air-to-air TACAN).

**Arguments**

| Key | Type | Default | Description |
|---|---|---|---|
| `type` | `number` | (required) | `sms.commands.BEACON.TYPE.*` (or DCS int). |
| `system` | `number` | (required) | `sms.commands.BEACON.SYSTEM.*` (or DCS int). |
| `frequency` | `number` (Hz) | (required) | Beacon frequency. |
| `callsign` | `string` | `""` | TACAN voice callsign, e.g. `"TEX"`. |
| `name` | `string` | `""` | Beacon name (mostly cosmetic in DCS logs). |
| `unit_id` | `number` | nil | Host unit id. When omitted DCS picks a unit from the group. |
| `channel` | `number` | nil | TACAN channel number. |
| `mode_channel` | `string` | nil | `"X"` or `"Y"` mode. |
| `aa` | `boolean` | nil | Air-to-air mode (tanker TACAN). |
| `bearing` | `boolean` | nil | Whether the beacon transmits bearing. |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
local tex = sms.group("texaco-1")
local cmd = sms.commands.activate_beacon({
  type         = sms.commands.BEACON.TYPE.TACAN,
  system       = sms.commands.BEACON.SYSTEM.TACAN_TANKER_Y,
  frequency    = 1088000000,    -- TACAN ch 25Y
  channel      = 25,
  mode_channel = "Y",
  callsign     = "TEX",
  aa           = true,
  bearing      = true,
})
tex:set_command(cmd)
```

#### `sms.commands.deactivate_beacon() → cmd` *(air-only)*

**Synopsis** — deactivate any active beacon on the group.

**Returns** — command table; never fails.

**Example**

```lua
sms.group("texaco-1"):set_command(sms.commands.deactivate_beacon())
```

---

### ACLS / ICLS / Link 4 — carrier ops

All carrier-ops builders are *air-only*. They drive the receivers on aircraft, not the carrier itself.

#### `sms.commands.activate_acls(unit_id, name) → cmd` *(air-only)*

**Synopsis** — activate Aircraft Carrier Landing System on the group's aircraft.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `unit_id` | `number` | (optional) Receiver unit id. When omitted DCS picks a unit from the group. |
| `name` | `string` | (optional) ACLS instance name (passthrough). |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
sms.group("hornet-1"):set_command(sms.commands.activate_acls())
```

#### `sms.commands.deactivate_acls() → cmd` *(air-only)*

**Synopsis** — deactivate ACLS on the group.

**Example**

```lua
sms.group("hornet-1"):set_command(sms.commands.deactivate_acls())
```

#### `sms.commands.activate_icls(channel, unit_id, callsign) → cmd` *(air-only)*

**Synopsis** — activate Instrument Carrier Landing System.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `channel` | `number` | ICLS channel (1–20). |
| `unit_id` | `number` | (optional) Receiver unit id. |
| `callsign` | `string` | (optional) ICLS callsign. |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
sms.group("hornet-1"):set_command(sms.commands.activate_icls(11, nil, "STN"))
```

#### `sms.commands.deactivate_icls() → cmd` *(air-only)*

**Synopsis** — deactivate ICLS on the group.

**Example**

```lua
sms.group("hornet-1"):set_command(sms.commands.deactivate_icls())
```

#### `sms.commands.activate_link4(frequency, unit_id, callsign) → cmd` *(air-only)*

**Synopsis** — activate the Link 4 datalink (CVN ↔ aircraft).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `frequency` | `number` (Hz) | Link 4 frequency. |
| `unit_id` | `number` | (optional) Receiver unit id. |
| `callsign` | `string` | (optional) Link 4 callsign. |

**Returns** — command table, or `nil` + log on bad input.

**Example**

```lua
sms.group("tomcat-1"):set_command(
  sms.commands.activate_link4(336000000, nil, "STN")
)
```

#### `sms.commands.deactivate_link4() → cmd` *(air-only)*

**Synopsis** — deactivate the Link 4 datalink on the group.

**Example**

```lua
sms.group("tomcat-1"):set_command(sms.commands.deactivate_link4())
```

---

## Enum reference

### `MODULATION`

Used by [`set_frequency`](#smscommandsset_frequencyhz-modulation-power--cmd) and [`set_frequency_for_unit`](#smscommandsset_frequency_for_unithz-modulation-power-unit_id--cmd).

| Key | Value |
|---|---|
| `AM` | `0` |
| `FM` | `1` |

### `BEACON.TYPE`

Used by [`activate_beacon`](#smscommandsactivate_beaconopts--cmd) (`opts.type`). Values are DCS-native integers and pass through verbatim — additional DCS values can be supplied as raw numbers.

| Key | Value |
|---|---|
| `NULL` | `0` |
| `VOR` | `2` |
| `DME` | `3` |
| `TACAN` | `4` |
| `VORTAC` | `5` |
| `HOMER` | `8` |
| `AIRPORT_HOMER` | `9` |
| `AIRPORT_HOMER_WITH_MARKER` | `10` |
| `ILS_FAR_HOMER` | `16` |
| `ILS_NEAR_HOMER` | `17` |
| `ILS_LOCALIZER` | `18` |
| `ILS_GLIDESLOPE` | `19` |
| `NAUTICAL_HOMER` | `65` |

### `BEACON.SYSTEM`

Used by [`activate_beacon`](#smscommandsactivate_beaconopts--cmd) (`opts.system`).

| Key | Value |
|---|---|
| `PAR_10` | `1` |
| `RSBN_5` | `2` |
| `TACAN` | `3` |
| `TACAN_TANKER_X` | `4` |
| `TACAN_TANKER_Y` | `5` |
| `VOR` | `6` |
| `ILS_LOCALIZER` | `7` |
| `ILS_GLIDESLOPE` | `8` |
| `BROADCAST_STATION` | `9` |
| `VORTAC` | `10` |
| `TACAN_AA_MODE_X` | `11` |
| `TACAN_AA_MODE_Y` | `12` |
| `ICLS` | `13` |
| `ICLS_LOCALIZER` | `14` |
| `ICLS_GLIDESLOPE` | `15` |

### `CALLSIGN`

Used by [`set_callsign`](#smscommandsset_callsigncallname-number--cmd). Starting set of common air callnames; the field is a passthrough integer, so any value from the DCS docs (per-aircraft `Aircraft.id` enum) is accepted.

| Key | Value |
|---|---|
| `ENFIELD` | `1` |
| `SPRINGFIELD` | `2` |
| `UZI` | `3` |
| `COLT` | `4` |
| `DODGE` | `5` |
| `FORD` | `6` |
| `CHEVY` | `7` |
| `PONTIAC` | `8` |
| `TEXACO` | `1` |
| `ARCO` | `2` |
| `SHELL` | `3` |
| `OVERLORD` | `1` |
| `MAGIC` | `2` |
| `WIZARD` | `3` |
| `FOCUS` | `4` |
| `DARKSTAR` | `5` |

**Notes** — DCS reuses the same integer namespace across roles (fighters, tankers, AWACS), so e.g. `TEXACO` and `ENFIELD` both map to `1`. Pick the constant that matches your aircraft's role; the apply layer just forwards the integer to DCS.

## See also

- [`sms.task`](task.md) — long-lived AI behaviors (move, attack, orbit, …).
- [`sms.options`](options.md) — persistent controller flags (ROE, alarm state, …).
- [`sms.group`](group.md) — the group handle and the `set_command` apply method.
