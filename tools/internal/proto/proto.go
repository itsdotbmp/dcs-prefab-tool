// Package proto holds the on-disk JSON shapes exchanged between the dcs-sms
// CLI and the in-DCS Lua hook. These structs are the single source of truth
// for the file-mailbox protocol; both the CLI and (by hand) the Lua hook
// must keep them in sync.
package proto

import "encoding/json"

// ExecRequest is what the CLI writes into inbox/<id>.req.json.
type ExecRequest struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
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
type HookState struct {
	HookVersion   string `json:"hook_version"`
	MissionLoaded bool   `json:"mission_loaded"`
	MissionName   string `json:"mission_name"`
	LastFrame     int64  `json:"last_frame"`
	LastFrameAt   string `json:"last_frame_at"`
}
