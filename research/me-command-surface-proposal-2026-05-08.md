# `dcs-sms me <verb>` command surface — v1 proposal

**Date:** 2026-05-08 (amended after reference miz expansion)
**Status:** Synthesis from reference-miz catalog + dcs-sms code surface inspection. Pre-spec input. Not yet probed against the live ME — that's the next phase.
**Method:** Reference miz at `D:\git\honu\claude_example.miz` was catalogued by parallel Explore agents in two passes:
- **Pass 1 (early afternoon):** air units, surface units, mission state, dcs-sms CLI/Lua surface. Ref miz had no triggers / drawings / FARPs / cargo / parking-start aircraft.
- **Pass 2 (evening):** user expanded the reference miz with **trigger zones, drawings, FARPs (4 variants), cargo statics, parked aircraft (both parking and runway start), full trigger system (rules + conditions + actions)**. This catalog reflects pass 2.

This document answers the question *"what should `dcs-sms me <verb>` look like in v1, given a canonical reference mission with every plausible task/command/option/trigger/drawing exercised?"* It is meant as input to the live probing session (`research/me-bridge-discovery-2026-05-08.md`) and the eventual command-surface spec under `docs/superpowers/specs/`.

---

## 1. Top-level shape

- **Namespace:** `dcs-sms me <noun> <verb> [flags]`. Nested rather than flat — the surface below has ~250 leaf commands. Existing `dcs-sms exec / status` stay flat; everything new lives under `me`.
- **Transport:** every `me` command routes via `--target gui` to the ME-mod bridge. v1 is ME-only.
- **Output:** JSON on stdout by default. `--human` for readable text. `--pretty` indents JSON.
- **Identity:** groups/units by `--name` (string label) or `--id` (groupId/unitId). Zones by `--name` or `--id` (zoneId). Drawings by `--name` and `--layer`. Trigger rules by index (`--rule N`).
- **Coordinates:** meters in DCS map space. **Axes: `x` = North–South (north positive), `y` = East–West (east positive). Altitude is `alt` (separate field) — there is no `z` at the mission-table level.** (Confirmed during F-16 CAP probing; corrected from an earlier incorrect assumption that y was north.)
- **Headings:** degrees at the CLI; radians internally (matches `heading`/`psi` in radians).
- **Frequency:** MHz at the CLI for radios (matches plane convention `frequency = 251`); converted to Hz internally for ships and beacons (matches `frequency = 127500000` and `frequency = 962000000`). FARPs use string MHz at the file level (`heliport_frequency = "127.5"`) — CLI accepts numeric MHz.
- **Color:** hex string `"0xRRGGBBAA"` at the CLI (matches drawings encoding). Auto-converted to RGBA float array `[r,g,b,a]` (0..1) for zones, since the file format differs there.

---

## 2. Command inventory

Each leaf is tagged: **command-worthy** (recurring, deserves native verb), **recipe** (rare; documented snippet), or **needs-more** (cataloged but unconfirmed shape; probing will tell).

### 2.1 Mission state — read

| Command | Returns | Tag |
|---|---|---|
| `me mission show` | theatre, date, start_time, weather, briefing keys, requiredModules, currentKey, version, sortie, maxDictId | command-worthy |
| `me mission describe` | human text version of show | command-worthy |
| `me theatre name` | "Syria" | command-worthy |
| `me view get` | centerX, centerY, zoom (ME camera) | command-worthy |

### 2.2 Mission state — write

| Command | Flags | Tag |
|---|---|---|
| `me weather set` | `--preset "Winter, clean sky"`, `--temp C`, `--qnh mmHg`, `--wind-ground sp,dir`, `--wind-2k sp,dir`, `--wind-8k sp,dir`, `--clouds-base m --clouds-thickness m --clouds-density 0..10 --clouds-preset Preset2 --clouds-precip 0..4`, `--fog-on --fog-vis m --fog-thick m`, `--dust-on --dust-density 0..3`, `--turbulence 0..10`, `--halo auto\|...`, `--name "..."` | command-worthy |
| `me time set` | `--hour H [--day D --month M --year Y]` (writes start_time + date) | command-worthy |
| `me briefing set` | `--side blue\|red\|neutrals\|description --text "..."` (writes via dictionary; auto-allocates dict key if needed, increments maxDictId) | command-worthy |
| `me bullseye set` | `--side blue\|red --x --y` | command-worthy |
| `me sortie set` | `--name "..."` | recipe |
| `me ground-control set` | `--side --role artillery_commander\|instructor\|observer\|forward_observer --slots N [--password "..."]` | recipe |
| `me modules require` | `--module "A-4E-C"` | recipe |
| `me modules clear` | — | recipe |
| `me forced-options set` | `--key X --value Y` (free-form) | needs-more |
| `me view set` | `--x --y --zoom` | recipe |
| `me view focus` | `--group X` or `--airbase X` (zoom-to-fit) | command-worthy |

### 2.3 Coalition / country

| Command | Flags | Tag |
|---|---|---|
| `me country list` | `[--side blue\|red\|neutrals]` → array of `{id, name, categories[]}` | command-worthy |
| `me country show` | `--side --id N` → full country block summary | recipe |
| `me country add` | `--side --id N` (rare) | needs-more |
| `me country remove` | `--side --id N` | needs-more |

### 2.4 Airbase / theatre

| Command | Flags | Tag |
|---|---|---|
| `me airbase list` | `[--coalition blue\|red\|neutral]` → name, id, x, y, coalition | command-worthy |
| `me airbase show` | `--name "Akrotiri"` → coalition, runway angle, freqs, fueldepots, warehouses, parking | command-worthy |
| `me airbase find` | `--near x,y [--radius m] [--coalition X]` | command-worthy |
| `me airbase set-coalition` | `--name X --coalition blue\|red` | command-worthy |
| `me parking list` | `--airbase X` → all spots: id, type (helo/jet/jet-large), occupied, terminal | command-worthy |
| `me warehouse get` | `--airbase X` → fuel/weapons/aircraft inventory | command-worthy |
| `me warehouse set` | `--airbase X --slot Y --qty N` | command-worthy |

### 2.5 Group — create

Every create accepts `--from-template ref:<id>` to pull a known-good shape from the reference miz. Templates: `ref:plane.cap-f16`, `ref:plane.parked-a10`, `ref:plane.runway-a10`, `ref:samsite.s-300`, `ref:carrier.stennis-full-beacons`, `ref:ground.armor-column`, `ref:ground.infantry-squad`, `ref:helicopter.cargo-uh1`, `ref:static.farp-full`, `ref:static.farp-invisible`, `ref:static.farp-single`, `ref:static.farp-pad-modular`, `ref:static.cargo-iso`, `ref:static.cargo-crate`. Built once from the reference miz catalog.

| Command | Flags | Tag |
|---|---|---|
| `me group create plane` | `--name --country N --task CAS\|CAP\|... --type "F-16C_50" --x --y --alt --skill --units N [--callsign "Enfield11" --flight 1 --num 1] [--frequency MHz --modulation AM\|FM] [--start air\|from-parking\|from-parking-hot\|from-runway\|from-ground\|from-ground-hot] [--airbase X] [--parking-id ID] [--from-template ref:...]` | command-worthy |
| `me group create heli` | same as plane (no task=AWACS/AFAC/Tanker) [+ `--rope-length m` for sling-load] | command-worthy |
| `me group create vehicle` | `--name --country --type "M-1 Abrams" --units "[type1,type2,...]" --formation column\|line\|... --x --y --heading deg [--cold-start] [--from-template ref:samsite.s-300]` | command-worthy |
| `me group create ship` | `--name --country --type "Stennis" --x --y --heading [--airboss-pwd hash --lso-pwd hash --allow-airboss --allow-lso] [--from-template ref:carrier.stennis-full-beacons]` | command-worthy |
| `me group create static` | see §2.13 | command-worthy |

**Start-type semantics** (confirmed from reference miz):
- `air` (default for current behavior) — group spawns in flight; first waypoint `type="Turning Point"`.
- `from-parking` (cold) — first waypoint `type="TakeOffParking"`, `action="From Parking Area"`, `airdromeId=N`. Each unit gets `parking="28"` (legacy slot) AND `parking_id="27"` (post-2024 normalized) — both written; the migration-on-load gap motivated this.
- `from-parking-hot` — same as above but engines-on at start.
- `from-runway` — first waypoint `type="TakeOff"`, `action="From Runway"`, `airdromeId=N`. Units have **no** `parking` or `parking_id` fields.
- `from-ground` / `from-ground-hot` — for vehicles/ships; just position + heading.

### 2.6 Group — list / show / find / edit / delete

| Command | Flags | Tag |
|---|---|---|
| `me group list` | `[--side X] [--country Y] [--category plane\|heli\|vehicle\|ship\|static] [--task X] [--name-glob "*"]` | command-worthy |
| `me group show` | `--name X` → full group structure as JSON | command-worthy |
| `me group ids` | `--name X` → groupId + unitIds | command-worthy |
| `me group near` | `--x --y --radius [--category]` | command-worthy |
| `me group rename` | `--name OLD --to NEW` | command-worthy |
| `me group move` | `--name X --x --y [--rotate-deg D] [--anchor first-unit\|center\|name]` | command-worthy |
| `me group set-task` | `--name X --task CAS\|CAP\|"Antiship Strike"\|AFAC\|AWACS\|Escort\|"Fighter Sweep"\|Refueling\|"Runway Attack"\|SEAD\|Transport\|"Ground Nothing"\|...` | command-worthy |
| `me group set-country` | `--name X --country N` (re-coalitions the group) | command-worthy |
| `me group set-late` | `--name X --on\|--off` (lateActivation) | command-worthy |
| `me group set-hidden` | `--name X --on\|--off` | command-worthy |
| `me group set-hidden-on-mfd` | `--name X --on\|--off` | command-worthy |
| `me group set-hidden-on-planner` | `--name X --on\|--off` | command-worthy |
| `me group set-uncontrolled` | `--name X --on\|--off` | command-worthy |
| `me group set-frequency` | `--name X --mhz N --modulation AM\|FM` | command-worthy |
| `me group set-start-time` | `--name X --seconds N` | command-worthy |
| `me group set-probability` | `--name X --p 0..1` | recipe |
| `me group delete` | `--name X` | command-worthy |
| `me group clone` | `--name X --to Y --offset x,y [--rotate D]` | command-worthy |

### 2.7 Unit — edit

| Command | Flags | Tag |
|---|---|---|
| `me unit show` | `--name X` | command-worthy |
| `me unit set-skill` | `--name X --skill Player\|Excellent\|High\|Average\|Random\|Client` | command-worthy |
| `me unit set-callsign` | `--name X --callsign-name "Enfield11" --flight 1 --num 1` | command-worthy |
| `me unit set-onboard` | `--name X --num "010"` | command-worthy |
| `me unit set-livery` | `--name X --livery "..."` | command-worthy |
| `me unit set-heading` | `--name X --deg D` | command-worthy |
| `me unit set-position` | `--name X --x --y [--alt]` | command-worthy |
| `me unit set-parking` | `--name X --airbase Y --parking-id ID [--legacy-parking N]` (writes both `parking_id` and `parking`; CLI handles the old/new ID conversion) | command-worthy |
| `me unit clear-parking` | `--name X` (removes `parking` and `parking_id` — used when converting parked aircraft to runway-start) | command-worthy |
| `me unit set-prop-aircraft` | `--name X --key SADL_TN\|VoiceCallsignLabel\|VoiceCallsignNumber\|HelmetMountedDevice\|STN_L16\|... --value "..."` | command-worthy |
| `me unit set-radio` | `--name X --radio 1\|2\|3 --frequency MHz --modulation AM\|FM` (multi-radio aircraft) | command-worthy |
| `me unit set-cold-start` | `--name X --on\|--off` (ground) | command-worthy |
| `me unit set-player-can-drive` | `--name X --on\|--off` (ground) | command-worthy |
| `me unit add` | `--group G --type X --x --y [--skill] [--name]` | command-worthy |
| `me unit remove` | `--name X` (refuses to leave group empty unless `--force-empty-group`) | command-worthy |
| `me unit set-rope-length` | `--name X --m N` (helo sling-load) | recipe |

### 2.8 Payload (planes / helis)

| Command | Flags | Tag |
|---|---|---|
| `me payload show` | `--unit X` → pylons, fuel, flare, chaff, gun, ammo_type | command-worthy |
| `me payload set-fuel` | `--unit X --kg N` | command-worthy |
| `me payload set-flare` | `--unit X --count N` | command-worthy |
| `me payload set-chaff` | `--unit X --count N` | command-worthy |
| `me payload set-gun` | `--unit X --pct N` | command-worthy |
| `me payload set-ammo-type` | `--unit X --type N` | command-worthy |
| `me payload pylon set` | `--unit X --pylon N --clsid "..." [--qty N]` | command-worthy |
| `me payload pylon clear` | `--unit X --pylon N` | command-worthy |
| `me payload from-template` | `ref:cap-f16-loadout --unit X` | command-worthy |

### 2.9 Route / waypoints

| Command | Flags | Tag |
|---|---|---|
| `me route show` | `--group X` → waypoint list with index, type, action, x, y, alt, speed, ETA | command-worthy |
| `me route add-waypoint` | `--group X --index N --type "Turning Point" --x --y --alt --speed [--alt-type BARO\|RADIO]` | command-worthy |
| `me route remove-waypoint` | `--group X --index N` | command-worthy |
| `me route move-waypoint` | `--group X --index N --x --y [--alt] [--speed]` | command-worthy |
| `me route set-waypoint-action` | `--group X --index N --action "Turning Point"\|"Fly Over Point"\|"Off Road"\|"On Road"\|"Land at"\|"From Parking Area"\|"From Parking Area Hot"\|"From Runway"\|"From Ground Area"\|"From Ground Area Hot"\|"Air Start"\|"Cone"\|"Custom"\|"Stop"` (drives `type` → "TakeOffParking"/"TakeOff"/"Turning Point" automatically) | command-worthy |
| `me route set-waypoint-airbase` | `--group X --index N --airbase Y [--runway-id R] [--helipad-id H]` (writes airdromeId on takeoff/landing waypoints) | command-worthy |
| `me route set-waypoint-speed` | `--group X --index N --speed N --locked\|--unlocked` | command-worthy |
| `me route set-waypoint-eta` | `--group X --index N --eta N --locked\|--unlocked` | command-worthy |
| `me route set-waypoint-alt-type` | `--group X --index N --alt-type BARO\|RADIO` | command-worthy |
| `me route set-waypoint-formation-template` | `--group X --index N --formation "..."` | command-worthy |
| `me route set-waypoint-properties` | `--group X --index N --vnav N --scale N --vangle deg --angle deg --steer N` | recipe |
| `me route set-relative-tot` | `--group X --on\|--off` | recipe |

### 2.10 Tasks at waypoint

A unified `me task <verb>` API.

| Task ID | Where | Params (CLI flags) | Tag |
|---|---|---|---|
| `EngageTargets` | air | `--targets "Air;Helicopters" --priority N [--max-dist m]` | command-worthy |
| `EngageGroup` | air | `--target-group X --weapon-type N --priority --visible` | command-worthy |
| `EngageUnit` | air | `--target-unit X --weapon-type --attack-qty --expend Auto\|All\|Half\|Quarter\|Two\|One --altitude --direction-deg --group-attack` | command-worthy |
| `EngageTargetsInZone` | air | `--x --y --radius --target-types --priority` | command-worthy |
| `AttackGroup` | air, naval | `--target-group --weapon-type --attack-qty --altitude --direction-deg --group-attack` | command-worthy |
| `AttackUnit` | air, ground | `--target-unit --weapon-type --attack-qty --altitude --direction-deg` | command-worthy |
| `AttackMapObject` | air | `--x --y --weapon-type --altitude` | command-worthy |
| `Bombing` | air | `--x --y --weapon-type --attack-qty --altitude --direction-deg` | command-worthy |
| `BombingRunway` | air | `--airbase X --weapon-type --attack-qty` | command-worthy |
| `Strafing` | air | `--x --y --length --direction-deg --weapon-type` | command-worthy |
| `CarpetBombing` | air | `--x --y --carpet-length --direction-deg --weapon-type --attack-qty` | command-worthy |
| `Orbit` | air | `--pattern Anchored\|Circle\|RaceTrack --speed --altitude [--clockwise --width --leg-length --hot-leg-dir]` | command-worthy |
| `Refueling` | air | (no params; aircraft seeks tanker) | command-worthy |
| `Tanker` | air, naval | (no params; this group acts as tanker) | command-worthy |
| `AWACS` | air | (no params) | command-worthy |
| `FAC` | air, ground | (no params) | command-worthy |
| `FAC_AttackGroup` | air, ground | `--target-group --weapon-type --datalink --frequency --modulation --callname --designation --number` | command-worthy |
| `Hold` | ground, ship | `[--duration s]` | command-worthy |
| `Land` | helo | `--x --y --direction --duration` | command-worthy |
| `GroundEscort` | air | `--target-group --engagement-dist-max --target-types --last-wpt-index` | command-worthy |
| `Escort` | air | `--target-group --engagement-dist-max --target-types --pos x,y,z` | command-worthy |
| `FollowBigFormation` | air | `--leader-group --pos x,y,z` | command-worthy |
| `FireAtPoint` | ground, ship | `--x --y --weapon-type --expend-qty --zone-radius --altitude --alt-type` | command-worthy |
| `Embarking` | ground | `--x --y --selected-transport --duration --on-start-mission --groups-for-embarking ...` | command-worthy |
| `Disembarking` | ground | `--x --y --groups-for-embarking ...` | command-worthy |
| `EmbarkToTransport` | ground | `--x --y --zone-radius` | command-worthy |
| `CargoTransportation` | helo | (no params) | command-worthy |
| `GoToWaypoint` | any | `--target-waypoint N --from-waypoint N` | command-worthy |
| `ShipHoldPoint` | naval | (no params) | command-worthy |
| `ControlledTask` | air | `--inner-task-id X --inner-params ... --condition-time s \| --condition-flag NAME --flag-state on\|off \| --condition-script "..." \| --condition-prob 0..1` | recipe |
| `Aerobatics` | air | `--maneuver "LOOP[order=1,value=...]" [--maneuver "TURN[..]"] ...` (CANDLE, EDGE_FLIGHT, WINGOVER_FLIGHT, LOOP, HORIZONTAL_EIGHT, HUMMERHEAD, SKEWED_LOOP, TURN, DIVE, MILITARY_TURN, STRAIGHT_FLIGHT, CLIMB, SPIRAL, SPLIT_S, AILERON_ROLL, FORCED_TURN, BARREL_ROLL) | recipe |

Plus:
- `me task list --group X --waypoint N`
- `me task remove --group X --waypoint N --index M`
- `me task move --group X --waypoint N --from M --to K`
- `me task enable --group X --waypoint N --index M --on|--off`
- `me task auto --group X --waypoint N --index M --on|--off`

### 2.11 Options at waypoint (`Option` WrappedAction)

The reference miz exercises options 1, 3, 4, 5, 6, 7, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 32, 35, 36, 37, 38.

| Name | Meaning | Values seen | Tag |
|---|---|---|---|
| `roe` (1) | Rules of Engagement | 0..4 | command-worthy |
| `reaction-on-threat` (3) | air evasion policy | 0..5 | command-worthy |
| `radar-using` (4) | radar usage | 0..3 | command-worthy |
| `flare-using` (5) | flare/chaff dispense | 0..3 + variantIndex/formationIndex (formation enum) | command-worthy |
| `formation` (5 alt) | Formation index | int (e.g., 131074, 4) | command-worthy |
| `rtb-on-bingo` (6) | RTB on fuel | bool | command-worthy |
| `silence` (7) | radio silence | bool | command-worthy |
| `disperse-on-attack` (8) | ground dispersal | bool | command-worthy |
| `alarm-state` (9) | ground alarm | 0=Auto, 1=Green, 2=Red | command-worthy |
| `rtb-on-out-of-ammo` (10) | RTB on ammo | bool | command-worthy |
| `ecm-using` (13) | ECM policy | 0..3 | command-worthy |
| `prohibit-aa` (14) | restrict A-A missile | bool | command-worthy |
| `prohibit-jett` (15) | restrict jettison | bool | command-worthy |
| `prohibit-ab` (16) | restrict afterburner | bool | command-worthy |
| `prohibit-ag` (17) | restrict A-G | bool | command-worthy |
| `missile-attack` (18) | missile attack policy | 0..3 | command-worthy |
| `prohibit-wp-pass-report` (19) | quiet WP pass | bool | command-worthy |
| `engage-air-weapons` (20) | naval AA enable | bool | command-worthy |
| `no-jett-targets` (21) | NO-attack target type list | "All;" / "Air;" / etc. | command-worthy |
| `engage-allowed-targets` (22) | restrict engagement to types | "All;" / type list | command-worthy |
| `jett-allowed-targets` (23) | restrict jettison to types | "All;" / type list | command-worthy |
| `option-24` (24) | (naval ROE %?) | int (100) | needs-more |
| `option-25` (25) | air formation/holding | bool | needs-more |
| `option-26` (26) | (formation-related) | bool | needs-more |
| `option-32` (32) | engage-air-weapons variant | bool | needs-more |
| `option-35` (35) | weapon/ammo selection | int | needs-more |
| `option-36` (36) | option setting | int | needs-more |
| `option-37` (37) | option setting | int | needs-more |
| `option-38` (38) | option setting | int | needs-more |

CLI:
- `me option set --group X --waypoint N --name <name> --value <v> [--variant <i> --formation <i>] [--target-types "..."]`
- `me option list --group X --waypoint N`
- `me option remove --group X --waypoint N --name X`
- Raw escape: `me option set --group X --waypoint N --raw-name 38 --raw-value 0`

### 2.12 Commands at waypoint (other `WrappedAction` IDs)

| Command | Flags | Tag |
|---|---|---|
| `me command activate-beacon` | `--group --waypoint --type 4\|... --system 3\|... --callsign "TKR" --frequency Hz --channel N --mode-channel X\|Y --aa --bearing --name "..."` (TACAN) | command-worthy |
| `me command deactivate-beacon` | `--group --waypoint` | command-worthy |
| `me command activate-icls` | `--group --waypoint --unit X --channel N --type 131584` | command-worthy |
| `me command deactivate-icls` | `--group --waypoint` | command-worthy |
| `me command activate-link4` | `--group --waypoint --unit X --frequency Hz` | command-worthy |
| `me command deactivate-link4` | `--group --waypoint` | command-worthy |
| `me command activate-acls` | `--group --waypoint --unit X` | command-worthy |
| `me command deactivate-acls` | `--group --waypoint` | command-worthy |
| `me command set-frequency` | `--group --waypoint --hz N --modulation AM\|FM --power W` | command-worthy |
| `me command set-frequency-for-unit` | `--group --waypoint --unit X --hz --modulation` | command-worthy |
| `me command set-callsign` | `--group --waypoint --name "Enfield11" --flight --num` | command-worthy |
| `me command switch-waypoint` | `--group --waypoint --target N` | command-worthy |
| `me command run-script` | `--group --waypoint --code "..."` (or `--file path`) | command-worthy |
| `me command run-script-file` | `--group --waypoint --file path` | command-worthy |
| `me command transmit-message` | `--group --waypoint --file path.ogg --duration s --loop --subtitle "..."` | command-worthy |
| `me command stop-transmission` | `--group --waypoint` | command-worthy |
| `me command smoke` | `--group --waypoint --color green\|red\|white\|orange\|blue [--off]` | command-worthy |
| `me command eplrs` | `--group --waypoint --on\|--off` | command-worthy |
| `me command set-unlimited-fuel` | `--group --waypoint --on\|--off` | command-worthy |
| `me command set-invisible` | `--group --waypoint --on\|--off` | command-worthy |
| `me command set-immortal` | `--group --waypoint --on\|--off` | command-worthy |
| `me command loading-ship` | `--group --waypoint --target-ship X --duration s` | command-worthy |
| `me command start` | `--group --waypoint` | command-worthy |
| `me command stop` | `--group --waypoint` | command-worthy |

Plus:
- `me command list --group X --waypoint N`
- `me command remove --group X --waypoint N --index M`

### 2.13 Statics — cargo, FARPs, regular

The reference miz now has: 1 ADEquipment static, 2 cargo statics (`iso_container`, `cds_crate`), 4 FARP variants (full FARP, single helipad, invisible FARP, modular FARP_SINGLE_01).

**Categories observed:** `Cargos`, `Heliports`, `ADEquipment`. (Other DCS categories: `Fortifications`, `Warehouses`, `MissilesAndBombs`, etc.)

| Command | Flags | Tag |
|---|---|---|
| `me static list` | `[--country X] [--category Cargos\|Heliports\|...]` | command-worthy |
| `me static create` | `--name --country --category Cargos\|Heliports\|... --type X --shape-name "..." --x --y --heading [--dead --rate N --livery "..."]` | command-worthy |
| `me static set-mass` | `--name X --kg N` | command-worthy |
| `me static set-cargo` | `--name X --on\|--off [--mass kg]` (toggles `canCargo`) | command-worthy |
| `me static set-shape` | `--name X --shape "outpost"` | command-worthy |
| `me static set-livery` | `--name X --livery "..."` | command-worthy |
| `me static set-heading` | `--name X --deg D` | command-worthy |
| `me static set-position` | `--name X --x --y` | command-worthy |
| `me static set-rate` | `--name X --rate N` | command-worthy |
| `me static delete` | `--name X` | command-worthy |

**Cargo specifics** (confirmed shapes from reference):
- `iso_container`: `category="Cargos"`, `type="iso_container"`, `shape_name="iso_container_cargo"`, `mass=4500`, `canCargo=true`, `rate=100`.
- `cds_crate`: `category="Cargos"`, `type="cds_crate"`, `shape_name="cds_crate"`, `mass=400`, `canCargo=true`, `rate=1200`.
- High-level wrapper: `me cargo create --name --country --type iso-container\|cds-crate\|... --x --y --mass-kg N` (auto-fills shape/category/canCargo).

**FARP specifics** (4 variants confirmed from reference):

| Variant | type | shape_name | category | rate | Notes |
|---|---|---|---|---|---|
| Full FARP | `FARP` | `FARPS` | `Heliports` | (none) | The big standard FARP |
| Single helipad | `SINGLE_HELIPAD` | `FARP` | `Heliports` | (none) | Small ED-style pad |
| Invisible FARP | `Invisible FARP` | `invisiblefarp` | `Heliports` | 100 | No visible model |
| Modular FARP | `FARP_SINGLE_01` | `FARP_SINGLE_01` | `Heliports` | 100 | Modular pad piece |

All four carry: `heliport_frequency` (string MHz like `"127.5"`), `heliport_modulation` (int, 0=AM), `heliport_callsign_id` (int).

| FARP command | Flags | Tag |
|---|---|---|
| `me farp create` | `--name --country --x --y --variant full\|single\|invisible\|modular --frequency MHz --modulation AM\|FM --callsign-id N` | command-worthy |
| `me farp set-frequency` | `--name X --mhz N` | command-worthy |
| `me farp set-modulation` | `--name X --modulation AM\|FM` | command-worthy |
| `me farp set-callsign` | `--name X --callsign-id N` | command-worthy |
| `me farp delete` | `--name X` (alias of `me static delete`) | command-worthy |

**Carrier wrapper**:
- `me carrier setup --name X --tacan-channel "1X" --tacan-callsign "TKR" --icls-channel N --link4-mhz N --acls-on --airboss-pwd "..." --lso-pwd "..."` — high-level wrapper over §2.12 beacon commands plus the carrier-specific group fields. command-worthy.

### 2.14 Trigger zones

**Confirmed from reference (circle zone):**
- Per-zone fields: `zoneId` (int), `name` (str), `x`, `y`, `radius` (m), `type` (0=circle, 2=quad), `heading` (deg), `hidden` (bool), `color` (RGBA float array `[r,g,b,a]` 0..1), `properties` (array of `{key,value}` custom metadata).
- Quad-shape variant inferred from DCS but not in reference — would use `vertices[]` instead of `radius`.

| Command | Flags | Tag |
|---|---|---|
| `me zone list` | — | command-worthy |
| `me zone show` | `--name X` | command-worthy |
| `me zone create` | `--name --shape circle\|quad --x --y [--radius m \| --quad p1x,p1y;p2x,p2y;p3x,p3y;p4x,p4y] [--color "0xRRGGBBAA"] [--hidden] [--heading deg]` | command-worthy |
| `me zone set-position` | `--name X --x --y` | command-worthy |
| `me zone set-radius` | `--name X --m N` (circle only) | command-worthy |
| `me zone set-color` | `--name X --color "0xRRGGBBAA"` | command-worthy |
| `me zone set-hidden` | `--name X --on\|--off` | command-worthy |
| `me zone set-heading` | `--name X --deg D` | command-worthy |
| `me zone property set` | `--name X --key K --value V` | command-worthy |
| `me zone property remove` | `--name X --key K` | command-worthy |
| `me zone delete` | `--name X` | command-worthy |

### 2.15 Drawings — the ME map drawings

`mission.drawings` has 5 layers (`Red`, `Blue`, `Neutral`, `Common`, `Author`) — each with `visible`, `name`, `objects[]`. The `Author` layer is the typical user drawings target. There's also `mission.drawings.options.hiddenOnF10Map.<role>.<coalition>` for per-role visibility on the F10 map.

**Drawing primitive types (confirmed from reference):**

| primitiveType | polygonMode | Distinctive fields |
|---|---|---|
| `Line` | — | `points[]`, `colorString`, `thickness`, `style`, `lineMode` ("segments"/"segment"), `closed` |
| `Polygon` | `free` | `points[]` (free-hand), `fillColorString`, `colorString`, `thickness`, `style` |
| `Polygon` | `circle` | `radius`, `fillColorString`, `colorString`, `thickness`, `style` |
| `Polygon` | `oval` | `r1`, `r2`, `angle`, `fillColorString`, `colorString` |
| `Polygon` | `rect` | `width`, `height`, `angle`, `fillColorString`, `colorString` |
| `Polygon` | `arrow` | `points[]` (8-point arrow geometry), `length`, `angle`, `fillColorString`, `colorString` |
| `TextBox` | — | `text`, `font` (e.g. `"DejaVuLGCSansCondensed.ttf"`), `fontSize`, `borderThickness`, `colorString`, `fillColorString`, `angle` |

Common fields on every primitive: `visible`, `mapX`, `mapY` (anchor in DCS world meters), `name`, `layerName`. Color encoding: hex string `"0xRRGGBBAA"`. Drawing-local points are relative to `mapX`/`mapY`.

| Command | Flags | Tag |
|---|---|---|
| `me drawing list` | `[--layer Red\|Blue\|Neutral\|Common\|Author]` | command-worthy |
| `me drawing show` | `--name X` | command-worthy |
| `me drawing create line` | `--name --layer --x --y --points "x1,y1;x2,y2;..." [--color "0xRRGGBBAA"] [--thickness N] [--style solid\|dashed\|dotted] [--line-mode segments\|segment] [--closed]` | command-worthy |
| `me drawing create polygon` | `--name --layer --x --y --points "x1,y1;..." [--color] [--fill "0xRRGGBBAA"] [--thickness] [--style]` | command-worthy |
| `me drawing create circle` | `--name --layer --x --y --radius m [--color] [--fill] [--thickness]` | command-worthy |
| `me drawing create oval` | `--name --layer --x --y --r1 --r2 --angle deg [--color] [--fill]` | command-worthy |
| `me drawing create rect` | `--name --layer --x --y --width --height --angle deg [--color] [--fill]` | command-worthy |
| `me drawing create arrow` | `--name --layer --x --y --length --angle deg [--color] [--fill]` | command-worthy |
| `me drawing create text` | `--name --layer --x --y --text "..." [--font "..."] [--font-size N] [--color] [--fill] [--border-thickness N] [--angle deg]` | command-worthy |
| `me drawing set-color` | `--name X --color "0xRRGGBBAA"` | command-worthy |
| `me drawing set-fill` | `--name X --fill "0xRRGGBBAA"` | command-worthy |
| `me drawing set-thickness` | `--name X --thickness N` | command-worthy |
| `me drawing set-text` | `--name X --text "..."` (TextBox only) | command-worthy |
| `me drawing set-position` | `--name X --x --y` | command-worthy |
| `me drawing set-visible` | `--name X --on\|--off` | command-worthy |
| `me drawing set-layer` | `--name X --layer Y` (move between layers) | command-worthy |
| `me drawing delete` | `--name X` | command-worthy |
| `me drawing layer set-visible` | `--layer X --on\|--off` | command-worthy |
| `me drawing layer hide-on-f10` | `--layer X --role pilot\|... --coalition red\|blue\|neutral --on\|--off` | recipe |

### 2.16 Trigger system — rules, conditions, actions

**Major area**, now fully cataloged from the reference. The structure: `mission.trigrules[N]` is a rule with `predicate` (rule type), `comment`, `eventlist`, `rules[]` (conditions), `actions[]`. The compiled trigger code lives separately as Lua strings in `mission.trig.{actions,conditions,func,flag,events,custom,customStartup,funcStartup}` — those are written by the ME on save and don't need to be hand-edited; they should be regenerated from `mission.trigrules` whenever rules change. The CLI should treat `mission.trigrules` as the source of truth.

**Rule predicates seen:** `triggerOnce`, `triggerContinious` (note: ED's typo, not ours).

**DCS rule predicate enum** (full from DCS docs): `triggerStart`, `triggerOnce`, `triggerContinious`, `triggerActiveContinious`, `triggerFront`, `triggerFrontOnce`. (Only first two seen in reference; others inferred.)

**Condition predicates seen** (50+):

`c_absolute_time_before`, `c_absolute_time_after`, `c_all_of_coalition_in_zone`, `c_all_of_coalition_out_zone`, `c_all_of_group_in_zone`, `c_bomb_in_zone`, `c_cargo_unhooked_in_zone`, `c_coalition_has_airdrome`, `c_coalition_has_helipad`, `c_flag_equals`, `c_flag_equals_flag`, `c_flag_is_false`, `c_flag_less`, `c_flag_less_flag`, `c_flag_more`, `c_flag_is_true`, `c_group_alive`, `c_group_life_less`, `c_group_dead`, `c_group_member_fuel_higher`, `c_group_member_fuel_less`, `c_predicate` (Lua predicate), `c_dead_zone`, `c_missile_in_zone`, `c_mission_score_higher`, `c_mission_score_lower`, `c_mlrs_in_zone`, `c_part_of_coalition_in_zone`, `c_part_of_coalition_out_zone`, `c_part_of_group_in_zone`, `c_part_of_group_out_zone`, `c_player_score_less`, `c_player_score_more`, `c_player_unit_argument_in_range`, `c_random_less`, `c_signal_flare_in_zone`, `c_time_before`, `c_time_after`, `c_time_since_flag`, `c_unit_alive`, `c_unit_damaged`, `c_unit_dead`, `c_unit_fuel_higher`, `c_unit_fuel_less`, `c_unit_hit`, `c_unit_in_zone_unit`, `c_unit_in_zone`, `c_unit_out_zone_unit`, `c_unit_out_zone`, `c_unit_altitude_higher_AGL`, `c_unit_altitude_lower_AGL`, `c_unit_altitude_higher`, `c_unit_altitude_lower`, `c_unit_argument_in_range`, `c_unit_bank`, `c_unit_heading`, `c_unit_life_less`, `c_unit_pitch`, `c_unit_speed_higher`, `c_unit_speed_lower`, `c_unit_vertical_speed`, `c_argument_in_range`, `c_cockpit_highlight_visible`, `c_indication_txt_equal_to`, `c_cockpit_param_equal_to`, `c_cockpit_param_in_range`, `c_cockpit_param_is_equal_to_another`.

**Action predicates seen** (30+):

`a_zone_increment_resize`, `a_cockpit_push_actor`, `a_aircraft_ctf_color_tag`, `a_do_script`, `a_do_script_file`, `a_effect_smoke`, `a_effect_smoke_stop`, `a_end_mission`, `a_explosion_unit`, `a_explosion`, `a_dec_flag`, `a_inc_flag`, `a_clear_flag`, `a_set_flag`, `a_set_flag_random`, `a_activate_group`, `a_group_off`, `a_group_on`, `a_group_controllable_on`, `a_group_controllable_off`, `a_deactivate_group`, `a_group_resume`, `a_group_stop`, `a_unit_highlight`, `a_illumination_bomb`, `a_load_mission`, `a_mark_to_all`, `a_mark_to_coalition`, `a_mark_to_group`, `a_out_text_delay`, `a_out_text_delay_s`, `a_out_text_delay_c`, `a_out_text_delay_u`, `a_out_text_delay_g`, `a_mission_pause`, `a_mission_restart`, `a_mission_resume`, `a_out_picture_stop`, `a_play_argument`, `a_qmg_end_mission`.

| Command | Flags | Tag |
|---|---|---|
| `me trigger list` | — → array of `{index, predicate, comment, condition_count, action_count}` | command-worthy |
| `me trigger show` | `--rule N` → full rule shape | command-worthy |
| `me trigger create` | `--predicate triggerOnce\|triggerContinious\|triggerStart\|... [--comment "..."]` → returns rule index | command-worthy |
| `me trigger set-comment` | `--rule N --comment "..."` | command-worthy |
| `me trigger set-predicate` | `--rule N --predicate triggerOnce\|...` | command-worthy |
| `me trigger delete` | `--rule N` | command-worthy |
| `me trigger condition add` | `--rule N --predicate <c_*> --params '{key:value,...}'` (JSON params; CLI validates against known shape per predicate) | command-worthy |
| `me trigger condition list` | `--rule N` | command-worthy |
| `me trigger condition remove` | `--rule N --index M` | command-worthy |
| `me trigger condition move` | `--rule N --from M --to K` | command-worthy |
| `me trigger action add` | `--rule N --predicate <a_*> --params '{key:value,...}'` | command-worthy |
| `me trigger action list` | `--rule N` | command-worthy |
| `me trigger action remove` | `--rule N --index M` | command-worthy |
| `me trigger action move` | `--rule N --from M --to K` | command-worthy |
| `me flag set` | `--name "MyFlag" --value true\|N` (writes via `a_set_flag` semantics; flag names are strings) | command-worthy |
| `me flag get` | `--name X` | command-worthy |
| `me flag list` | (all flags referenced in trigrules) | command-worthy |
| `me trigger compile` | (rebuilds `mission.trig.*` Lua strings from `mission.trigrules`; should be automatic on save but exposed for debugging) | recipe |

**Higher-level shorthand commands** (because writing `me trigger condition add` for every condition gets tedious):

| Command | Sugar for | Tag |
|---|---|---|
| `me trigger when-flag` | `--rule N --flag X --is true\|false\|equals N\|more N\|less N` (sugars `c_flag_is_true/is_false/equals/more/less`) | command-worthy |
| `me trigger when-group-in-zone` | `--rule N --group X --zone Y --kind all\|part [--out]` (sugars 4 c_*_zone variants) | command-worthy |
| `me trigger when-coalition-in-zone` | `--rule N --coalition red\|blue --zone Y --kind all\|part --unit-type ALL\|... [--out]` | command-worthy |
| `me trigger when-time` | `--rule N --kind absolute\|relative --before s\|--after s` (sugars c_(absolute_)?time_before/after) | command-worthy |
| `me trigger when-unit-life` | `--rule N --unit X --less-than-pct N` | command-worthy |
| `me trigger then-flag` | `--rule N --flag X --action set\|clear\|inc\|dec\|random --value N` | command-worthy |
| `me trigger then-message` | `--rule N --to all\|coalition\|country\|unit\|group --target X --text "..." --duration s [--start-delay s] [--clearview]` (sugars a_out_text_delay/_s/_c/_u/_g, auto-allocates DictKey) | command-worthy |
| `me trigger then-mark` | `--rule N --to all\|coalition\|group --target X --zone Y --text "..." --comment "..." [--readonly]` (sugars a_mark_to_*) | command-worthy |
| `me trigger then-group-control` | `--rule N --group X --action activate\|deactivate\|on\|off\|stop\|resume\|controllable-on\|controllable-off` | command-worthy |
| `me trigger then-explosion` | `--rule N --target zone\|unit --id X --volume N [--altitude N]` | command-worthy |
| `me trigger then-smoke` | `--rule N --zone X --preset N --density N [--name "..."]` (sugars a_effect_smoke; pair with `me trigger then-smoke-stop`) | command-worthy |
| `me trigger then-illumination` | `--rule N --zone X --altitude N` | command-worthy |
| `me trigger then-script` | `--rule N --code "..."` or `--file path` | command-worthy |
| `me trigger then-end-mission` | `--rule N --winner red\|blue\|"" [--text "..."] [--start-delay s]` | command-worthy |
| `me trigger then-mission-control` | `--rule N --action pause\|resume\|restart` | command-worthy |
| `me trigger then-zone-resize` | `--rule N --zone X --meters N` | command-worthy |

**Cargo trigger field** — `c_cargo_unhooked_in_zone` uses `cargo = "ANY_BLUE"` (string). Other values plausible: `"ANY_RED"`, `"ANY_NEUTRAL"`, `"ANY"`, or specific cargo unit-name. Probing should confirm.

**Dict-key auto-allocation** — Actions like `a_out_text_delay*` and `a_mark_to_*` reference text via `["text"] = "DictKey_ActionText_24"` pairs (with `["KeyDict_text"]` mirror). The CLI **must** auto-allocate new DictKeys when text is supplied inline. The `mission.maxDictId` field tracks the high-water mark; CLI bumps it.

### 2.17 Prefab — CLI for existing Lua surface

| Command | Flags | Tag |
|---|---|---|
| `me prefab list` | (uses `prefab_ops.scan_dir`) | command-worthy |
| `me prefab show` | `--name X` | command-worthy |
| `me prefab place` | `--name X --x --y [--rotate-deg D] [--country X] [--keep-position]` | command-worthy |
| `me prefab save` | `--name X --selection-only\|--all [--airbases]` | command-worthy |
| `me prefab apply-airbases` | `--name X [--override-coalition]` | command-worthy |
| `me prefab bbox` | `--name X` | recipe |
| `me prefab delete` | `--name X` | command-worthy |

### 2.18 File / mission lifecycle

| Command | Flags | Tag |
|---|---|---|
| `me file save` | `[--path X.miz]` | command-worthy |
| `me file save-as` | `--path X.miz` | command-worthy |
| `me file new` | (File > New) | command-worthy |
| `me file open` | `--path X.miz` | command-worthy |
| `me file path` | (current open .miz path) | command-worthy |
| `me file dirty` | (has unsaved changes?) | recipe |

### 2.19 Selection (ME marquee)

| Command | Flags | Tag |
|---|---|---|
| `me select list` | currently-selected groups/units/zones/drawings | command-worthy |
| `me select clear` | — | command-worthy |
| `me select group` | `--name X` (replace) | command-worthy |
| `me select add-group` | `--name X` (extend) | command-worthy |
| `me select zone` | `--name X` | command-worthy |
| `me select drawing` | `--name X` | command-worthy |

### 2.20 Failures

| Command | Flags | Tag |
|---|---|---|
| `me failure list` | (all modules: TACAN_FAILURE_RECEIVER, RADAR_ALTIMETR_RIGHT_ANT_FAILURE, sas_pitch_left, TGP_FAILURE_LEFT, CADC_FAILURE_TOTAL, ...) | recipe |
| `me failure set` | `--module X --prob 0..100 --enable --hh H --mm M [--mmint N]` | recipe |
| `me failure clear` | `--module X` | recipe |

---

## 3. Phasing

### v1 — must-haves (covers ≥90% of natural-language requests)

§2.1 (read), §2.2 weather/time/briefing/bullseye/view-focus, §2.4 airbase, §2.5 group create with **all 5 start types** and `--from-template`, §2.6 group ops, §2.7 unit ops including parking handling, §2.8 payload, §2.9 route including airbase-anchored takeoff/landing, §2.10 tasks for the **command-worthy** task IDs, §2.11 options for the named ones (raw escape covers the rest), §2.12 commands except rare variants, §2.13 statics+cargo+FARPs (4 variants), §2.14 zones, §2.15 drawings (all 7 primitive types), §2.16 trigger system with shorthand verbs, §2.17 prefab CLI, §2.18 file, §2.19 selection.

### v2 — nice-to-haves

§2.10 ControlledTask + Aerobatics, §2.11 unmapped option IDs (24, 25, 26, 32, 35–38) once probed, §2.13 carrier-setup wrapper (already command-worthy in §2.13 but lower-priority), §2.20 failures, §2.16 raw-mode `me trigger condition add --predicate <c_*>` + `me trigger action add --predicate <a_*>` (the shorthand sugars cover most cases), §2.2 ground-control set / modules / sortie / forced-options, `me view set/get`, `me select add-* / zone / drawing`.

### Out of scope for v1 (recipe via `dcs-sms exec --target gui --code "..."`)

- `mission.trig.{actions,conditions,func,flag}` direct edit (these are the compiled-string form; `mission.trigrules` is the source of truth).
- `mission.result` win conditions (use trigger `then-end-mission` instead).
- `mission.goals`.
- Layer-level `hiddenOnF10Map` overrides (recipe — exposed but rare).
- The `triggerStart`, `triggerActiveContinious`, `triggerFront`, `triggerFrontOnce` rule predicates not seen in reference (predicate flag accepts them, but no curated shorthand).
- Cockpit-bound condition predicates (`c_argument_in_range`, `c_cockpit_*`, `c_indication_txt_equal_to`) — these are esoteric; raw-mode covers them.

---

## 4. Probing priorities (next phase)

The cataloging is from disk. Bridge probing confirms round-trip. In order:

1. **Spawn an ME-perfect F-16 CAP from `ref:plane.cap-f16`.** Proves template extraction.
2. **Spawn a parked A-10 from `ref:plane.parked-a10`** (validates parking_id + parking dual-write + airdromeId + TakeOffParking waypoint).
3. **Spawn a runway-start A-10 from `ref:plane.runway-a10`** (validates TakeOff + From Runway + airdromeId without parking).
4. **Spawn a SAM site from `ref:samsite.s-300`.**
5. **Spawn a Stennis from `ref:carrier.stennis-full-beacons`** with full beacon stack.
6. **Place an iso_container cargo** via `me cargo create` and verify `canCargo=true` + `mass=4500` round-trip.
7. **Place a full FARP** via `me farp create --variant full` and verify `heliport_frequency`/`callsign_id` round-trip.
8. **Create a circle zone** via `me zone create --shape circle`.
9. **Create a polygon drawing** with fill color via `me drawing create polygon`.
10. **Create a `triggerOnce` rule** with `c_unit_in_zone` condition + `a_out_text_delay` action via `me trigger when-unit-in-zone` + `me trigger then-message`. Verify the rule fires after save+reload.
11. **Add a single waypoint task** to an existing group via `me task add`.
12. **Set option** at a waypoint via `me option set roe`.
13. **Set weather** via `me weather set`.
14. **Round-trip:** save the mission, close, reopen. Verify all changes survived in the .miz on disk.

---

## 5. Open questions for probing to answer

- **Country IDs across DCS versions** — stable? Reference uses 80=CJTF Blue, 81=CJTF Red. Probe `me country list` against current DCS.
- **Dictionary key allocation** — `me briefing set` and `me trigger then-message` both auto-allocate DictKeys. Does the ME accept arbitrary `DictKey_<prefix>_<N>` patterns, or only specific prefixes (`DictKey_ActionText_*`, `DictKey_ActionComment_*`, `DictKey_descriptionText_*`)? Probe with a freshly-allocated key.
- **`mission.failures` shape** — sparse fields per module; which are required vs optional?
- **Parking ID semantics** — `parking="28"` vs `parking_id="27"` — which one ED reads at mission-load? The CLI writes both (per the migration-on-load gap memory). Confirm by removing one and seeing what the ME does.
- **Cargo trigger value enum** — `cargo = "ANY_BLUE"`. What other values are valid? `"ANY_RED"`, `"ANY"`, specific unit-name? Probe.
- **Trigger flag type** — flags are strings (`flag = "1"`) but used numerically by some predicates. Document the cast.
- **`triggerContinious` typo** — ED's typo, not ours. Document it loudly.
- **`mission.trig.*` Lua-string regeneration** — when the ME saves, are these strings recompiled from `mission.trigrules`, or hand-maintained? If recompiled, the CLI should ignore them (treat trigrules as truth). If not, the CLI must update both. Probe by editing a rule and saving.
- **FARP repair/refuel/rearm** — the unit-level fields don't carry these; warehouse-level config likely. Probe via `mission.warehouses` (the separate `warehouses` file in the .miz).
- **Drawing layer naming** — are `Red/Blue/Neutral/Common/Author` the only valid layer names, or can users add more? Probe.
- **Option name 5 dual usage** (`flare-using` AND `formation`) — variantIndex/formationIndex disambiguation. Probe.
- **Zone color encoding** — file uses RGBA float array `[r,g,b,a]` (0..1). Drawings use `"0xRRGGBBAA"`. CLI normalizes to hex string in both places. Confirm the float→hex conversion is round-trip safe.
- **Helicopter sling-load** (`ropeLength`) — not in reference even after expansion. Probe by saving a sling-load helo manually.

---

## 6. Raw catalog (source for the proposal above)

### 6.A — Air units (planes + helis)

`coalition.<side>.country[N].plane.group[]` and `helicopter.group[]`. Group fields: `name`, `groupId`, `x`, `y`, `task`, `taskSelected`, `start_time`, `frequency`, `modulation`, `communication`, `radioSet`, `lateActivation`, `uncontrolled`, `uncontrollable`, `hidden`, `hiddenOnMFD`, `hiddenOnPlanner`, `dynSpawnTemplate`, `route`, `units`, `visible`, `tasks` (deprecated empty array).

**Group `task` enum seen:** CAS, Ground Nothing, AFAC, Antiship Strike, AWACS, CAP, Escort, Fighter Sweep, Refueling, Runway Attack, SEAD, Transport.

**Unit fields:** `type`, `name`, `unitId`, `x`, `y`, `alt`, `alt_type`, `heading`, `psi`, `speed`, `skill`, `livery_id`, `onboard_num`, `callsign`, `payload`, `Radio` (multi-radio; planes), `AddPropAircraft` (per-airframe), `datalinks`. **Parked aircraft additionally have `parking` (legacy slot string) and `parking_id` (post-2024 stringified slot ID).**

**Waypoint shape:**
- Common: `type`, `action`, `alt`, `alt_type`, `x`, `y`, `speed`, `speed_locked`, `ETA`, `ETA_locked`, `formation_template`, `task` (always ComboTask), `properties` (planes: vnav/scale/vangle/angle/steer).
- Takeoff variants: `type="TakeOffParking"`, `action="From Parking Area"` + `airdromeId=N` (parked); `type="TakeOff"`, `action="From Runway"` + `airdromeId=N` (runway).

**Per-waypoint task IDs seen:** EngageTargets, WrappedAction, AttackGroup, AttackUnit, Strafing, Orbit, Refueling, ControlledTask, Aerobatics, EngageTargetsInZone, EngageGroup, EngageUnit, Land, GroundEscort, FAC, FAC_AttackGroup, FireAtPoint, AWACS, EmbarkToTransport. (Inferred but not in reference: Bombing, BombingRunway, CarpetBombing, Tanker, AttackMapObject, Escort, FollowBigFormation, CargoTransportation.)

**Per-waypoint command IDs (in WrappedAction) seen:** Option, EPLRS, Script, ScriptFile, SetFrequency, SetFrequencyForUnit, SwitchWaypoint, ActivateBeacon, DeactivateBeacon, ActivateICLS, DeactivateICLS, ActivateLink4, DeactivateLink4, ActivateACLS, DeactivateACLS, TransmitMessage, StopTransmission, SMOKE_ON_OFF, SetUnlimitedFuel, SetInvisible.

**Aerobatics maneuvers:** CANDLE, EDGE_FLIGHT, WINGOVER_FLIGHT, LOOP, HORIZONTAL_EIGHT, HUMMERHEAD, SKEWED_LOOP, TURN, DIVE, MILITARY_TURN, STRAIGHT_FLIGHT, CLIMB, SPIRAL, SPLIT_S, AILERON_ROLL, FORCED_TURN, BARREL_ROLL.

**`Option` names exercised:** 1, 3, 4, 5, 6, 7, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 32, 35, 36, 37, 38.

### 6.B — Surface units (ground + naval + statics)

**Ground:** `action` waypoints `Off Road`, `On Road`. Waypoint tasks seen: `EmbarkToTransport`, `FAC_AttackGroup`, `FireAtPoint`, `AttackGroup`, `AttackUnit`, `Hold`, `Disembarking`, `GoToWaypoint`, `Embarking`, `WrappedAction[Option]`. SAM-site is single multi-unit group.

**Naval:** `frequency` in Hz (127500000 = 127.5 MHz). Stennis carries `passwordAirboss`/`passwordLso` (encrypted), `allowAirboss`/`allowLso`. Some ship groups have `probability` (0.95). Ship per-waypoint tasks: `FireAtPoint` (10 weapon-type variants), `AttackGroup`, `GoToWaypoint`, `ShipHoldPoint`, plus full `WrappedAction[ActivateBeacon/ICLS/Link4/ACLS]` stack.

**Beacon canonical TACAN params:** `frequency` (Hz), `type` (4), `system` (3), `callsign` ("TKR"), `channel` (1), `mode-channel` ("X"|"Y"), `AA` (bool), `bearing` (bool).

**Statics — categories seen:** `ADEquipment` (AS32-31A), `Cargos` (iso_container, cds_crate), `Heliports` (FARPS/FARP/invisiblefarp/FARP_SINGLE_01).

**Cargo unit fields:** `category="Cargos"`, `type`, `shape_name`, `mass` (kg), `canCargo=true`, `rate`, position fields. Two variants: `iso_container` (mass 4500, rate 100), `cds_crate` (mass 400, rate 1200).

**FARP unit fields:** `category="Heliports"`, `type`, `shape_name`, `heliport_frequency` (string MHz), `heliport_modulation` (int), `heliport_callsign_id` (int), position fields. Invisible FARP and FARP_SINGLE_01 also carry `rate=100`.

### 6.C — Mission state

**`mission.weather`:** `wind.{atGround,at2000,at8000}.{speed,dir}`, `season.temperature`, `qnh`, `clouds.{thickness,density,base,iprecptns,preset}`, `fog.{visibility,thickness}`, `enable_fog`, `visibility.distance`, `halo.preset`, `dust_density`, `enable_dust`, `groundTurbulence`, `atmosphere_type`, `type_weather`, `modifiedTime`, `name`, `cyclones`.

**`mission.date`:** `Day/Month/Year`. **`mission.theatre`** = "Syria". **`mission.start_time`** (top-level, seconds-from-midnight). **`mission.sortie`**, `version`, `currentKey` (= 2755 after expansion; was 1802), `maxDictId` (= 61 after expansion; was 12).

**`mission.coalitions`** (side roster): `bullseye {x,y}`, `nav_points`, `name`, `country[]` of `{id, name}` — 22 blue, 11 red, 59 neutrals.

**`mission.groundControl`:** `passwords.<role>`, `roles.<role>.<side>=N`, `isPilotControlVehicles`. Roles: artillery_commander, instructor, observer, forward_observer.

**`mission.requiredModules`:** `["A-4E-C"] = "A-4E-C"`.

**`mission.failures`:** modules with `id`, `prob`, `enable`, `hh`, `mm`, `mmint`. Sample: `TACAN_FAILURE_RECEIVER`, `RADAR_ALTIMETR_RIGHT_ANT_FAILURE`, `sas_pitch_left`, `TGP_FAILURE_LEFT`, `CADC_FAILURE_TOTAL`.

**`mission.forcedOptions`:** empty.

**`mission.map`:** `centerX`, `centerY`, `zoom`.

### 6.D — Drawings (`mission.drawings`)

**Top-level:** `options.hiddenOnF10Map.<role>.<coalition>` (bool overrides), `layers[1..5]`. Layer names: Red, Blue, Neutral, Common, Author. Layer fields: `visible`, `name`, `objects[]`.

**Primitive types and distinctive fields:**
- `Line` (`primitiveType="Line"`): `points[]`, `colorString`, `thickness`, `style`, `lineMode` ("segments"/"segment"), `closed`.
- `Polygon` mode `free`: `points[]` (free-hand), `fillColorString`.
- `Polygon` mode `circle`: `radius`.
- `Polygon` mode `oval`: `r1`, `r2`, `angle`.
- `Polygon` mode `rect`: `width`, `height`, `angle`.
- `Polygon` mode `arrow`: `points[]` (8-point arrow geometry), `length`, `angle`.
- `TextBox`: `text`, `font`, `fontSize`, `borderThickness`, `angle`.

**Common fields:** `visible`, `mapX`, `mapY`, `name`, `layerName`, `colorString`. Polygons additionally have `fillColorString`, `thickness`, `style`. Color encoding: `"0xRRGGBBAA"`.

### 6.E — Trigger zones (`mission.triggers.zones`)

Per-zone fields: `zoneId` (int), `name` (str), `x`, `y`, `radius` (m, circle only), `vertices[]` (quad only — inferred), `type` (0=circle, 2=quad), `heading` (deg), `hidden` (bool), `color` (RGBA float array `[r,g,b,a]`, 0..1), `properties` (`{key,value}` array, currently empty).

### 6.F — Trigger system (`mission.trig` + `mission.trigrules`)

**`mission.trig.{actions,conditions,func,flag}`** are populated as **compiled Lua strings** (one entry per rule) — these are the runtime form, written by the ME on save. `mission.trigrules` is the editable form.

**`mission.trigrules[N]` shape:**
- `predicate` (str): `triggerOnce`, `triggerContinious`, etc.
- `comment` (str): free-text label.
- `eventlist` (str): event hooks (typically empty).
- `rules[]`: array of `{predicate: c_*, ...params}`.
- `actions[]`: array of `{predicate: a_*, ...params}`.

**Rule predicates seen:** `triggerOnce`, `triggerContinious`. **Inferred from DCS:** `triggerStart`, `triggerActiveContinious`, `triggerFront`, `triggerFrontOnce`.

**Condition predicates** (50+, full list in §2.16).

**Action predicates** (30+, full list in §2.16).

**Cross-references:**
- Zone IDs, unit IDs, group IDs: numeric.
- Flag names: strings (`"1"`, `"MyFlag"`).
- Text refs: paired `["text"]="DictKey_..."` + `["KeyDict_text"]="DictKey_..."` (mirror).
- Coalition strings: `"red"`, `"blue"`.
- Cargo strings: `"ANY_BLUE"` (other values not yet probed).
- Bomb/missile/MLRS classification: 4-int array `[category, subcategory, type, subtype]`.

### 6.G — dcs-sms code surface

**CLI entry:** `tools/cmd/dcs-sms/dispatch.go` — flat command map. To add `me <verb>` namespace, register dispatcher: `register("me", meDispatch)` with its own subcommand map.

**Bridge:** `tools/me-mod/lua/dcs_sms_me/bridge.lua` — `loadstring(code)` then `xpcall`. Returns JSON-encoded via `jval()` (table heuristic for object/array, numbers 6 sig figs, strings escaped).

**Existing Lua surface to reuse:** `dcs_sms_me.prefab_ops`, `me_mission` (create_group/insert_unit/save_mission/group_by_name/mission/missionCountry), `Mission.AirdromeController` (getAirdromes), `Mission.TheatreOfWarData` (getName), `Mission.TriggerZoneController`, `lfs`.

**ME globals reachable inside snippets:** `me_mission`, `module_mission`, `Mission.*`, `dcs_sms_me.*`, `lfs`, `log`, `io`, `os`, `_G.DCS_SMS_GUI_BRIDGE_ENABLED`, plus `_G.mission` (the editable mission table).

---

*End of proposal. Probing session continues against this document.*
