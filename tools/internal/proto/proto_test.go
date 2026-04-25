package proto

import (
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
