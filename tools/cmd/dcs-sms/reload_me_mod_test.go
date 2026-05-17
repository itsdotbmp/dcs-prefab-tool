package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// runReloadMeMod invokes reloadMeModCmd against a fake-hook root.
func runReloadMeMod(t *testing.T, root string, args []string) (int, string, string) {
	t.Helper()
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	done := make(chan int, 1)
	go func() { done <- reloadMeModCmd(args, &stdout, &stderr) }()
	select {
	case code := <-done:
		return code, stdout.String(), stderr.String()
	case <-time.After(10 * time.Second):
		t.Fatal("reloadMeModCmd did not return within 10s")
		return 0, "", ""
	}
}

func TestReloadMeMod_Success(t *testing.T) {
	root := t.TempDir()
	writeHeartbeatFile(t, root, proto.HookState{
		HookVersion:      "0.2.0",
		State:            "in_mission_editor",
		GuiBridgeEnabled: true,
		TickSource:       "update_manager",
		LastFrameAt:      time.Now().UTC().Format(time.RFC3339Nano),
	})

	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		if req.Target != "gui" {
			t.Errorf("hook saw target=%q, want gui", req.Target)
		}
		// The reload snippet must be the one we shipped — assert one
		// distinctive fragment so a future accidental change to the
		// snippet body fails the test.
		if !strings.Contains(req.Code, "package.loaded") || !strings.Contains(req.Code, "dcs_sms_me") {
			t.Errorf("request code missing reload snippet markers; got: %s", req.Code)
		}
		return proto.ExecResponse{
			ID:          req.ID,
			OK:          true,
			ReturnValue: json.RawMessage(`{"ok":true,"cleared":["dcs_sms_me.init"]}`),
		}
	}, false /*heartbeat*/, true /*processInbox*/)

	exit, stdout, stderr := runReloadMeMod(t, root, []string{"--timeout", "2s"})
	if exit != 0 {
		t.Fatalf("exit %d, stderr=%s", exit, stderr)
	}
	if !strings.Contains(stdout, `"ok":true`) {
		t.Errorf("expected ok:true in stdout, got: %s", stdout)
	}
}

func TestReloadMeMod_LuaError(t *testing.T) {
	root := t.TempDir()
	writeHeartbeatFile(t, root, proto.HookState{
		HookVersion:      "0.2.0",
		State:            "in_mission_editor",
		GuiBridgeEnabled: true,
		LastFrameAt:      time.Now().UTC().Format(time.RFC3339Nano),
	})

	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		return proto.ExecResponse{
			ID:    req.ID,
			OK:    false,
			Error: &proto.ExecError{Message: "init.lua: bad syntax", Traceback: ""},
		}
	}, false, true)

	exit, stdout, _ := runReloadMeMod(t, root, []string{"--timeout", "2s"})
	if exit != 1 {
		t.Errorf("exit %d, want 1 (init.lua failed)", exit)
	}
	if !strings.Contains(stdout, `"ok":false`) || !strings.Contains(stdout, "bad syntax") {
		t.Errorf("expected ok:false + error in stdout, got: %s", stdout)
	}
}

func TestReloadMeMod_GuiBridgeDisabled(t *testing.T) {
	root := t.TempDir()
	writeHeartbeatFile(t, root, proto.HookState{
		HookVersion:      "0.2.0",
		State:            "in_mission_editor",
		GuiBridgeEnabled: false,
		LastFrameAt:      time.Now().UTC().Format(time.RFC3339Nano),
	})

	exit, _, stderr := runReloadMeMod(t, root, []string{"--timeout", "1s"})
	if exit != 4 {
		t.Errorf("exit %d, want 4 (gui bridge disabled)", exit)
	}
	if !strings.Contains(stderr, "External execution") {
		t.Errorf("stderr should mention the External execution toggle, got: %s", stderr)
	}
}

func TestReloadMeMod_RejectsBadFlag(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := reloadMeModCmd([]string{"--bogus"}, &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
}
