// Package proto holds the on-disk JSON shapes exchanged between the dcs-sms
// CLI and the in-DCS Lua hook. These structs are the single source of truth
// for the file-mailbox protocol; both the CLI and (by hand) the Lua hook
// must keep them in sync.
package proto

import "encoding/json"

// ExecRequest is what the CLI writes into inbox/<id>.req.json.
//
// Target picks the Lua state the snippet runs in:
//   - ""        legacy / unset → hook treats as "mission" (back-compat)
//   - "mission" mission scripting env (sandboxed). Requires a running mission.
//   - "gui"     shared GUI/ME Lua state (full io/lfs). Requires the ME-mod
//               toggle to be enabled. Reaches the editable mission table
//               while the user is in the Mission Editor.
type ExecRequest struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
	Target    string `json:"target,omitempty"`
	Code      string `json:"code"`
	TimeoutMs int    `json:"timeout_ms"`
	CreatedAt string `json:"created_at"`
}

// ExecResponse is what the hook writes into outbox/<id>.res.json.
//
// ReturnValue is kept as a raw JSON message because the user's Lua snippet
// can return arbitrary JSON-serializable data (numbers, strings, arrays,
// nested tables). The CLI passes it through untouched.
type ExecResponse struct {
	ID            string          `json:"id"`
	OK            bool            `json:"ok"`
	ReturnValue   json.RawMessage `json:"return_value"`
	Output        string          `json:"output"`
	Error         *ExecError      `json:"error"`
	FrameExecuted int64           `json:"frame_executed"`
	DurationMs    float64         `json:"duration_ms"`
}

// ExecError describes a Lua-level failure inside the snippet.
type ExecError struct {
	Message   string `json:"message"`
	Traceback string `json:"traceback"`
}

// HookState is what the hook writes into state/hook.json on each heartbeat.
//
// Field shape v0.2.0 (additive, backward-compatible):
//   - State, GuiBridgeEnabled, TickSource are new in 0.2.0.
//   - LastTick / LastTickAt mirror LastFrame / LastFrameAt; old fields are
//     kept populated for one release so older CLIs stay compatible.
//
// State values: "starting" | "at_main_menu" | "in_mission_editor"
//             | "loading_mission" | "in_mission" | "stopping" | "" (legacy).
//
// TickSource values: "update_manager" | "simulation_frame"
//                  | "simulation_frame_only" | "" (legacy).
type HookState struct {
	HookVersion      string `json:"hook_version"`
	State            string `json:"state,omitempty"`
	MissionLoaded    bool   `json:"mission_loaded"`
	MissionName      string `json:"mission_name"`
	GuiBridgeEnabled bool   `json:"gui_bridge_enabled,omitempty"`
	TickSource       string `json:"tick_source,omitempty"`
	LastTick         int64  `json:"last_tick,omitempty"`
	LastTickAt       string `json:"last_tick_at,omitempty"`
	LastFrame        int64  `json:"last_frame"`
	LastFrameAt      string `json:"last_frame_at"`
}
