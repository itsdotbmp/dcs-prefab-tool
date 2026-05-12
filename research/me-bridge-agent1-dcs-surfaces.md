# DCS Lua surfaces outside of mission runtime

Research aimed at "what can be scripted in DCS while no mission is running" — i.e. main menu, server browser, Mission Editor (ME), briefing screen. Sources cited inline. Verified against ED's own files in `D:\Program Files\Eagle Dynamics\DCS World\` (DCS install) and live hook scripts in `C:\Users\Gebruiker\Saved Games\DCS\Scripts\Hooks\`.

The two non-mission Lua environments that matter:
- **GUI/hook env** — the long-lived process Lua VM that hosts the launcher, server browser, briefing UI, and (via `dofile`) the ME. Loaded by `<DCS>/Scripts/UserHooks.lua` then `<DCS>/MissionEditor/GameGUI.lua`. Receives the user's `Saved Games/DCS/Scripts/Hooks/*.lua` files.
- **ME env** — same VM as the GUI/hook env (one process), but with `MissionEditor.lua` and the entire `MissionEditor/modules/` tree loaded on top. There is no environment boundary. ME modules and hook callbacks share globals.

There is one extra Lua VM mentioned for completeness: the **mission scripting env** (sandboxed, what `MissionScripting.lua` configures). It is not in scope here, but the GUI/hook env reaches into it via `net.dostring_in('mission', code)` plus `a_do_script(...)` — see `dcs_code_injector` and `dcs-sms-hook.lua` for the full pattern.

---

## 1. GUI hook env — `DCS.setUserCallbacks(handler)`

### Canonical callback list

The authoritative source is `D:\Program Files\Eagle Dynamics\DCS World\MissionEditor\GameGUI.lua` lines 57-93 (a comment block ED ships). Every callback there is a method on the `handler` table you pass to `DCS.setUserCallbacks`. Reproduced verbatim:

```
onMissionLoadBegin()
onMissionLoadProgress(progress_0_1, message)
onMissionLoadEnd()
onTriggerMessage(message, duration)
onRadioMessage(message, duration)
onRadioCommand(command_message)
onSimulationStart()
onSimulationFrame()
onSimulationStop()
onSimulationPause()
onSimulationResume()
onShowMainInterface()
onShowIntermission()
onShowGameMenu()
onShowBriefing()
onShowChatAll() / onShowChatTeam()
onShowScores() / onShowResources()
onShowGameInfo(text, duration)
onShowMessage(text, type)
onShowChatPanel() / onHideChatPanel()
onGameEvent(eventName, args...)
onPlayerDisconnect(id) / onPlayerStart(id) / onPlayerConnect(id, name)
onNetMissionChanged(mizName)
onServerRegistrationFail(code)
onShowRadioMenu(size)
```

Additional callbacks observed live in `GameGUI.lua` body and in ED's stock hook files in `<DCS>/Scripts/Hooks/`:
- `onMissionLoadFail(mission, reason, do_not_emit_modal_warnings)` — `GameGUI.lua:281`.
- `onSimulationEsc()` — `GameGUI.lua:452`.
- `onChatShowHide()`, `onBdaShowF10(bool)`, `onBdaShowHide()`, `onBdaSetModeWrite()`, `onBdaSetModeRead()` — `GameGUI.lua:251-275`.
- `onUserRequestMissionRestart(new_mission_path)` — `GameGUI.lua:604`.
- `onNetConnect(your_player_id)` / `onNetDisconnect(reason, code)` — `GameGUI.lua:666-731`.
- `onShowVoicechat(mode, value)`, `updateVoicechat(...)` — `GameGUI.lua:508-547`.
- `onPlayerStop(id)`, `onPlayerTryChangeSlot(id, side, unit)`, `onPlayerChangeSlot(id)`, `onPlayerChangeCoalition(id, coalition)`, `onPlayerChangeCoalitionDenied(reason, value)` — `GameGUI.lua:856-903`.
- `onPlayerTrySendChat(playerID, msg, all)`, `onChatMessage(msg, from, to)` — `GameGUI.lua:811, 817`.
- `onDebriefingEvent(e)`, `onUpdateScore()` — `GameGUI.lua:822, 905`.
- `onShowTraining(text)`, `onTriggerPicture(filename, duration, clearView, ...)` — `GameGUI.lua:995, 999`.
- `onShowPool()`, `onShowBda()` — `GameGUI.lua:439, 422`.
- `onMessageBox(message, title)` — `GameGUI.lua:504`.
- `onExportToMiz(a_pathDebrief, a_pathNewMiz)` — `GameGUI.lua:1040`.
- `onReloadEvent(enmEvent)`, `onRefuelEvent(enmEvent)` — `GameGUI.lua:1009, 1015`.
- `onNetMissionEnd` — `<DCS>/Scripts/Hooks/common.lua:25`.
- `onActivatePlane`, `onATCTerminalAcquireChanged` — `<DCS>/Scripts/Hooks/common.lua:26-27`.
- `onCreateAircraftDataNotification` — `<DCS>/Scripts/Hooks/multislot.lua:221`.
- `onInitCoalitionBlockerParams`, `onPlayerTryChangeCoalition` — `<DCS>/Scripts/Hooks/multiplayerCoalitionBlocker.lua:133-134`.
- `onWebServerRequest` — `<DCS>/Scripts/Hooks/webGUI.lua:587` (this fires for the embedded web GUI).
- `onDebriefingEvent(e)` — `GameGUI.lua:822`.

### Which callbacks fire while no mission is running?

Verified by grepping `GameGUI.lua` and the dcs-sms-hook behaviour we already ship:

- **Always-on, including main menu / browser / ME**: `onShowMainInterface` (fires when the splash returns to the main menu — `GameGUI.lua:746-748`), `onPlayerConnect/Disconnect` (multiplayer pre-mission lobby), `onChatMessage` and `onPlayerTrySendChat` (lobby chat), `onNetMissionChanged` (server changed mission while you're connected), `onNetConnect/onNetDisconnect`, `onMissionLoadBegin`/`Progress`/`End` (these straddle the boundary — they fire while loading screens are up, before sim starts).
- **Sim-only**: `onSimulationStart`, `onSimulationFrame`, `onSimulationStop`, `onSimulationPause`, `onSimulationResume`, `onSimulationEsc`, `onTriggerMessage`, `onRadioMessage/Command`, `onShowGameMenu`, `onShowBriefing`, `onShowGameInfo`, `onPlayerStart/Stop`, `onPlayerChangeSlot`, `onShowRadioMenu`, `onTriggerPicture`, `onShowTraining`. None of these fire in the menu or ME.
- **Editor-time**: there are NO `setUserCallbacks` events the ME fires for the user. The ME tick is its own thing (see §2 below).

### Idle / timer in the GUI hook env when no mission is running?

**No** — `onSimulationFrame` requires a sim. There is no documented `onMenuFrame`, `onIdle`, or `onMainInterfaceFrame`. Empirically: open DCS, sit on the main menu, no `setUserCallbacks` callbacks fire except `onShowMainInterface` (once, on first paint).

The only viable polling primitive in the menu/ME state is **`UpdateManager`** (an ED-published tick scheduler):
- Loaded eagerly by `Scripts/UserHooks.lua:18-19`: `Gui.AddUpdateCallback(UpdateManager.update)`. Every GUI frame, `UpdateManager.update()` runs every queued function.
- API: `UpdateManager.add(func)` and `UpdateManager.delete(func)`. `func` returning `true` removes itself. `<DCS>/Scripts/UpdateManager.lua` is ~50 lines.
- Stock ME use: `MissionEditor/dialogs/...`, `Scripts/Input/AddComboDialog.lua:486`, `FoldableView.lua:1604`, `View.lua:1237`. ME mods can use it as the equivalent of `onSimulationFrame` while in the editor.

### `DCS.*` API callable from this env, broken down

From `GameGUI.lua` lines 12-55 (ED-published comment) plus body usage:

Always callable (menu and ME):
- `DCS.setPause(bool)`, `DCS.getPause()`, `DCS.setViewPause(bool)`
- `DCS.exitProcess()`, `DCS.stopMission()`
- `DCS.isMultiplayer()`, `DCS.isServer()`, `DCS.isTrackPlaying()`, `DCS.takeTrackControl()`
- `DCS.getRealTime()` — wall-clock seconds, available in menu (used by `dcs-lua-datamine` to time exports; that hook runs at start before any mission)
- `DCS.getModelTime()` — only meaningful while sim is running, returns 0 otherwise
- `DCS.setMouseCapture(bool)`, `DCS.setKeyboardCapture(bool)`
- `DCS.getManualPath()`, `DCS.getUserOptions()`
- `DCS.HAVE_SUPERCARRIER` (constant, `MissionEditor.lua:37`)

Mission-context only — return nil/empty/garbage when no mission loaded:
- `DCS.getMissionOptions()`, `DCS.getMissionDescription()`, `DCS.getMissionTheatre()` (`GameGUI.lua:197`), `DCS.getMissionName()` (used by `dcs-sms-hook.lua:319`), `DCS.getMissionFilename()`
- `DCS.getPlayerCoalition()`, `DCS.getPlayerUnitType()`, `DCS.getPlayerUnit()`, `DCS.getPlayerBriefing()`
- `DCS.spawnPlayer()`, `DCS.setPlayerCoalition(id)`, `DCS.setPlayerUnit(misId)`
- `DCS.getAvailableCoalitions()`, `DCS.getAvailableSlots()`, `DCS.hasMultipleSlots()`
- `DCS.unitInfo(unitId)` (used by various community projects to query running units)

Other library tables visible in hook env: `net.*` (TCP/UDP, `net.dostring_in`, `net.json2lua`/`net.lua2json`, `net.get_my_player_id`, `net.get_player_info`, `net.get_server_settings`, `net.get_server_host`, `net.send_chat`, `net.log`, …), `log.*`, `lfs.*`, `os.*` (full unsanitized!), `io.*` (full!), `package.*`, `require`, `loadstring`/`load`. Verified from `dcs_code_injector` and `dcs-sms-hook.lua`.

---

## 2. Mission Editor env

### Same VM, with extra modules

`<DCS>/MissionEditor/GameGUI.lua:4`: `dofile('./MissionEditor/MissionEditor.lua')`. ME is not a separate Lua state — it is a `dofile` into the same VM that runs your `Saved Games/DCS/Scripts/Hooks/*.lua`. After `MissionEditor.lua` runs, the ME has `require`-loaded ~180 modules under `MissionEditor/modules/`.

The full module list lives at `D:\Program Files\Eagle Dynamics\DCS World\MissionEditor\modules\`. 184 files. Highlights — what `dcs-sms` actually uses (see `D:\git\dcs-sms\tools\me-mod\lua\dcs_sms_me\`):

| `require()` path | What it gives you |
| --- | --- |
| `me_mission` | Module-public; `me_mission.mission` is the live mission table (groups, statics, zones, `AirportsEquipment.airports/warehouses`, etc.). Same shape as the on-disk `mission` file inside a `.miz`. |
| `me_menubar` | `me_menubar.menuBar` (note: set without `local`) is the live MenuBar widget. `:insertItem(MenuBarItem)` adds a top-level menu. dcs-sms patches `me_menubar.show` and `me_menubar.hideME` to install the DCS-SMS top entry and auto-hide on ME exit. |
| `me_toolbar` | `me_toolbar.loadMission(filename)` is the File>Open path; dcs-sms wraps it (`new_mission_hook.lua`). |
| `me_map_window` | Map widget — pan/zoom, world↔screen coord conversion, marquee selection. dcs-sms uses it to capture clicks for prefab placement. |
| `me_multiSelection` | Live selection state. dcs-sms patches it to capture marquee rectangles. |
| `Mission.AirdromeController` | `getAirdromes()` returns the table of airbases in the current theatre. |
| `Mission.CoalitionController` | Coalition lookup, player-side queries. |
| `Mission.TheatreOfWarData` | `getName()` returns current theatre id; same call ME uses internally when serializing `.miz`. |
| `Mission.Data` / `Mission.TriggerZoneData` / `Mission.NavigationPointData` / `Mission.AirdromeData` | Mission sub-data accessors with controller wiring. |
| `dxgui` (alias `Gui`) + `dxguiWin` | Window/widget construction. |
| `Window`, `Static`, `Button`, `Skin`, `Menu`, `MenuBarItem` | Widget classes used by dcs-sms's window construction (`window.lua`). |
| `MsgWindow` | Modal message-box dialog. |
| `DialogLoader` | Loads `.dlg` XML resource files into a window tree (DCS-SRS uses this for the radio overlay). |
| `me_db_api` (created in `UserHooks.lua:23-24`) | The mission-editable DB: known unit/aircraft/static types per coalition. |
| `OptionsData` / `Options.Data` / `Options.Controller` | Persistent user-options storage; SRS uses this for plugin settings. |
| `RPC` | In-process method registry (`RPC.method.foo = function(...)`). |
| `i18n` | Translations. |
| `me_undoable` (search hits in core ME files) | The undo stack. dcs-sms ships its own slim undo for prefab placement (`undo.lua`) but the engine has its own. |
| `tools` (`Tools.safeDoFile`, etc.) | File-system helpers used by ED itself. |
| `me_utilities` (`U`) | Toolbar dimensions, `U.saveInFile`, `U.extractFileName`, etc. |

Editor.lua / panel2D / MoveContext-style wrappers from older ED versions: searched `MissionEditor/modules/` — no module named `Editor`, `panel2D`, `MoveContext`. Those names appear in older community references but the current build (verified version: latest stable as of 2026-05) routes everything through `me_*` and `Mission.*` modules. Whatever `MoveContext` did is now inside `me_map_window` + `me_action_*`.

### Is there a documented "place a unit programmatically" API?

Not as a one-shot named function. Reverse-engineered approach in `dcs-sms` (see `prefab_ops.lua`):
1. Mutate `me_mission.mission.coalition[<side>].country[<idx>].plane.group[]` (or `vehicle`/`ship`/`helicopter`/`static`) directly.
2. Allocate fresh unit/group ids via the running counters in `me_mission` (the mod tracks this manually because the public accessors changed shape between patches).
3. Splice warehouse data into `me_mission.mission.AirportsEquipment.airports[N]` (per-airbase) and `mission.AirportsEquipment.warehouses[unitId]` (per-ship).
4. Trigger a redraw via `MapWindow` and have the controllers in `Mission.*` re-derive their indexes (they re-scan `me_mission.mission` on demand).

Hoggit's wiki has nothing on this; the only public docs are the `MissionEditor/doc/` HTML inside the install (which is sparse — mostly the trigger/condition catalog, not the Lua API). DCS forum threads (search `DCS-SMS`, `dcs_code_injector`, `MOOSE_MissionEditor`) are the secondary source, but most projects (including dcs-sms) just read ED's own modules and trace by example.

### ME tick / idle callback for mods

Yes — same `UpdateManager` referenced in §1. `Gui.AddUpdateCallback` is wired to it from `UserHooks.lua:18-19`. While the ME is open, `UpdateManager.update()` runs every GUI frame. dcs-sms doesn't use it (it's event-driven via menubar patches), but a polling-style inbox watcher in the ME would attach via `UpdateManager.add(func)` and decide its own polling cadence.

### `loadstring` / sandbox status in ME env

`loadstring` and `load` are present (Lua 5.1 + LuaJIT — the DCS process uses 5.1 globals). `os.execute`, `io.popen`, `io.open`, `os.remove`, `os.rename`, `os.tmpname` are all unsanitized — confirmed by `dcs-lua-datamine`'s hook (`io.open` for writing thousands of files), `dcs-sms-hook.lua` (`os.rename` for atomic writes), `DCS-SRSGameGUI.lua` (`srs.start_srs(host)` shells out via the SRS DLL). `lfs.writedir()`, `lfs.tempdir()`, `lfs.dir`, `lfs.attributes`, `lfs.mkdir` all work — used everywhere.

There is no separate sandbox in the ME env. The MissionScripting.lua sandbox only applies to the mission scripting env.

---

## 3. Persistence between menu / ME / sim transitions

The DCS process is **one Lua VM** for the GUI/hook env and the ME. `dofile('./MissionEditor/MissionEditor.lua')` is run once at startup from `GameGUI.lua:4`. There is no tear-down between menu → ME → sim → ME → menu transitions. Globals registered in your hook (`DCSCI`, `DCS_SMS`, `SRS`, etc.) persist across all transitions and across multiple mission loads.

Empirical confirmation: `dcs-sms-hook.lua` uses `DCS_SMS.frame` (a long-running counter) and `DCS_SMS.mission_loaded` (a flag flipped in `onMissionLoadEnd` / `onSimulationStop`) to track state across many mission cycles within one DCS process.

What does get re-initialized per mission:
- The mission scripting env (the sandboxed env behind `net.dostring_in('mission', ...)`) is rebuilt each mission load. State held there does not survive `onSimulationStop`.
- ME panels: `me_mission.mission` is replaced wholesale on each `loadMission(filename)` call. Live references to `me_mission.mission.<x>` go stale; you must re-read through the module on each operation. Controllers in `Mission.*` re-attach themselves on load.

The DCS process itself is the boundary: only an outright restart of the DCS executable resets the GUI/hook env globals.

---

## 4. Networking from the GUI/hook and ME envs

**Yes — full LuaSocket is available.** Confirmed in three live hooks:

1. `dcs_code_injector/dcs-code-injector-hook.lua:1-11`:
   ```lua
   package.path = package.path .. ";.\\LuaSocket\\?.lua"
   package.cpath = package.cpath .. ";.\\LuaSocket\\?.dll"
   socket = require("socket")
   DCSCI.server = socket.bind("*", 45221)
   DCSCI.server:settimeout(0)
   ```
   Binds a TCP listener on port 45221 in the GUI/hook env, reads commands, forwards to mission env via `net.dostring_in`. Works in main menu, in ME, and in sim — verified by user (this is the user's prior project).

2. `<Saved Games>/DCS/Mods/Services/DCS-SRS/Scripts/DCS-SRSGameGUI.lua:32, 49-51`:
   ```lua
   local socket = require("socket")
   SRS.UDPSendSocket = socket.udp()
   SRS.UDPSendSocket:settimeout(0)
   socket.try(SRS.UDPSendSocket:sendto(_jsonUpdate, "127.0.0.1", 5068))
   ```
   Sends UDP from `onSimulationFrame`. Side-loads a binary DLL (`srs.dll`) via `package.cpath = ...;Mods\Services\DCS-SRS\bin\?.dll`.

3. `DCS-SRS-OverlayGameGUI.lua:790-825`:
   ```lua
   _listenSocket = socket.udp()
   _listenSocket:setsockname("*", 7080)
   _listenSocket:settimeout(0)
   ...
   local _received = _listenSocket:receive()
   ```
   Binds a UDP listener on the GUI/hook env, polled from `onSimulationFrame`.

The `<DCS>/LuaSocket/` directory ships `socket.lua`, `mime.lua`, `ltn12.lua`, plus `socket.dll`/`mime.dll`. The `package.path`/`package.cpath` paths set in `UserHooks.lua` and `MissionEditor.lua` already include `./LuaSocket/?.lua` and `./LuaSocket/?.dll`, so `require('socket')` works out of the box.

Practical caveat: in the GUI/hook env the only frame-driven driver is `onSimulationFrame` — which doesn't fire in the menu or ME. To poll a non-blocking socket while no mission is running, attach a function via `UpdateManager.add(...)` (§2) and call `socket:receive()` from there. Or use blocking `:settimeout(N)` from a `setUserCallbacks` event handler that fires in the menu (e.g. `onShowMainInterface`, `onPlayerConnect`) — note this will block the GUI thread, so keep the timeout small.

---

## Notable findings / gotchas

- **`onSimulationFrame` is the only "tick" the user-facing hook API gives you, and it is sim-only.** Polling a TCP/UDP listener that needs to be alive in the menu requires `UpdateManager.add(...)` (registered in `Scripts/UserHooks.lua:18-19`). This is the missing primitive most ME-bridge designs need.
- **`net.dostring_in('mission', code)` lands in the *server-side* scripting state, not the real mission env.** To reach the mission env you must wrap `code` in `a_do_script([====[ ... ]====])`. dcs-sms-hook documents this clearly at lines 122-136 ("Architecture" comment) and dcs_code_injector does the same.
- **`me_menubar.menuBar` is set without `local`** — accidentally module-public. dcs-sms relies on this. If ED ever re-localizes it, the mod loses its menu entry. There is no documented alternative.
- **No mod manifest / load-order system.** Files in `Saved Games/DCS/Scripts/Hooks/` are loaded alphabetically by ED's hook loader (verified by behavior). Nothing else applies. The ME mod path used by dcs-sms (`MissionEditor/modules/dcs_sms_me/init.lua`) requires patching `MissionEditor.lua` at install time.
- **`dcs-lua-datamine` runs `_G` introspection right after the hook is loaded** (`DCS-LuaExporter-hook.lua:564 pcall(Run)`). It uses `DCS.getRealTime()` for timing, so that function works in pre-mission state. It has no `setUserCallbacks` registration — it just runs code at hook-load.
- **`DCS.HAVE_SUPERCARRIER`** is a constant exposed at MissionEditor bootstrap (`MissionEditor.lua:37`). Useful for feature-gating without trying to load module data.
- **Hook execution is synchronous on the GUI thread.** A long-running operation in `onSimulationFrame` (or any callback) freezes DCS. Use `socket:settimeout(0)` for non-blocking polls, file watchers must be lazy, etc.
