package proto

import (
	"bytes"
	"encoding/json"
	"testing"
)

func TestExecRequestRoundTrip(t *testing.T) {
	in := ExecRequest{
		ID:        "0193f9aa-test",
		Kind:      "exec",
		Code:      "return 1 + 1",
		TimeoutMs: 5000,
		CreatedAt: "2026-04-25T14:32:11.123Z",
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out ExecRequest
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out != in {
		t.Errorf("round-trip mismatch:\n  in:  %+v\n  out: %+v", in, out)
	}
}

func TestExecResponseSuccessRoundTrip(t *testing.T) {
	in := ExecResponse{
		ID:            "0193f9aa-test",
		OK:            true,
		ReturnValue:   json.RawMessage(`2`),
		Output:        "hello\nworld",
		Error:         nil,
		FrameExecuted: 184321,
		DurationMs:    1.2,
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out ExecResponse
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out.ID != in.ID || out.OK != in.OK || out.Output != in.Output ||
		out.FrameExecuted != in.FrameExecuted || out.DurationMs != in.DurationMs {
		t.Errorf("round-trip mismatch on scalar fields:\n  in:  %+v\n  out: %+v", in, out)
	}
	if string(out.ReturnValue) != string(in.ReturnValue) {
		t.Errorf("return_value mismatch: got %q want %q", string(out.ReturnValue), string(in.ReturnValue))
	}
	if out.Error != nil {
		t.Errorf("expected nil Error on success, got %+v", out.Error)
	}
}

func TestExecResponseErrorRoundTrip(t *testing.T) {
	in := ExecResponse{
		ID: "0193f9aa-test",
		OK: false,
		Error: &ExecError{
			Message:   "attempt to index a nil value",
			Traceback: "stack traceback:\n\tline 1",
		},
		FrameExecuted: 184321,
		DurationMs:    0.4,
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out ExecResponse
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out.OK || out.Error == nil || out.Error.Message != in.Error.Message {
		t.Errorf("error round-trip failed:\n  in:  %+v\n  out: %+v", in, out)
	}
}

func TestHookStateRoundTrip(t *testing.T) {
	in := HookState{
		HookVersion:   "0.1.0",
		MissionLoaded: true,
		MissionName:   "Caucasus_QRA.miz",
		LastFrame:     184321,
		LastFrameAt:   "2026-04-25T14:32:11.456Z",
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out HookState
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out != in {
		t.Errorf("round-trip mismatch:\n  in:  %+v\n  out: %+v", in, out)
	}
}

func TestExecRequestTargetRoundTrip(t *testing.T) {
	in := ExecRequest{
		ID:        "0193f9aa-test",
		Kind:      "exec",
		Target:    "gui",
		Code:      "return _VERSION",
		TimeoutMs: 5000,
		CreatedAt: "2026-05-08T14:32:11.123Z",
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if !bytes.Contains(b, []byte(`"target":"gui"`)) {
		t.Errorf("expected target field in JSON, got: %s", b)
	}
	var out ExecRequest
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out != in {
		t.Errorf("round-trip mismatch:\n  in:  %+v\n  out: %+v", in, out)
	}
}

func TestExecRequestTargetOmittedDefaultsBlank(t *testing.T) {
	// A request without a target field decodes to Target == "" and the
	// hook treats empty == "mission" (today's behavior). The CLI emits
	// the field unconditionally going forward, but old clients that never
	// learned about target must keep working.
	raw := []byte(`{"id":"x","kind":"exec","code":"return 1","timeout_ms":1000,"created_at":"2026-05-08T00:00:00Z"}`)
	var out ExecRequest
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out.Target != "" {
		t.Errorf("expected empty Target on legacy request, got %q", out.Target)
	}
}

func TestHookStateNewFieldsRoundTrip(t *testing.T) {
	in := HookState{
		HookVersion:      "0.2.0",
		State:            "in_mission_editor",
		MissionLoaded:    false,
		MissionName:      "",
		GuiBridgeEnabled: true,
		TickSource:       "update_manager",
		LastTick:         184321,
		LastTickAt:       "2026-05-08T14:32:11.456Z",
		LastFrame:        184321,
		LastFrameAt:      "2026-05-08T14:32:11.456Z",
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	for _, want := range []string{
		`"state":"in_mission_editor"`,
		`"gui_bridge_enabled":true`,
		`"tick_source":"update_manager"`,
		`"last_tick":184321`,
	} {
		if !bytes.Contains(b, []byte(want)) {
			t.Errorf("expected %s in JSON, got: %s", want, b)
		}
	}
	var out HookState
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out != in {
		t.Errorf("round-trip mismatch:\n  in:  %+v\n  out: %+v", in, out)
	}
}

func TestHookStateLegacyHeartbeatBackwardCompat(t *testing.T) {
	// A heartbeat written by an older hook (0.1.0) only has last_frame /
	// last_frame_at. The new HookState must decode this without error;
	// LastTick / LastTickAt simply stay zero-valued.
	raw := []byte(`{
		"hook_version":"0.1.0",
		"mission_loaded":true,
		"mission_name":"Old.miz",
		"last_frame":123,
		"last_frame_at":"2026-04-25T14:00:00.000Z"
	}`)
	var out HookState
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatalf("unmarshal legacy: %v", err)
	}
	if out.HookVersion != "0.1.0" {
		t.Errorf("HookVersion: got %q", out.HookVersion)
	}
	if out.LastFrame != 123 {
		t.Errorf("LastFrame: got %d", out.LastFrame)
	}
	if out.LastTick != 0 {
		t.Errorf("LastTick should be zero on legacy heartbeat, got %d", out.LastTick)
	}
	if out.State != "" {
		t.Errorf("State should be empty on legacy heartbeat, got %q", out.State)
	}
}
