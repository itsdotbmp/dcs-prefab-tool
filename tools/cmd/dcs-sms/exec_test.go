package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// fakeHook simulates the Lua hook for end-to-end CLI tests. It watches the
// inbox folder and writes responses according to the supplied behavior.
//
// IMPORTANT: the CLI builds the mailbox path as <savedGames>/dcs-sms/...
// so the fake hook must root itself one level deeper than the
// DCS_SMS_SAVED_GAMES env var.
type fakeHook struct {
	root         string // <savedGames>/dcs-sms
	behavior     func(req proto.ExecRequest) proto.ExecResponse
	heartbeat    bool // if true, write a fresh heartbeat continuously
	processInbox bool // if false, requests pile up untouched (used to test timeout)
	stop         chan struct{}
	wg           sync.WaitGroup
}

func startFakeHook(t *testing.T, savedGames string, fn func(proto.ExecRequest) proto.ExecResponse, heartbeat, processInbox bool) *fakeHook {
	t.Helper()
	root := filepath.Join(savedGames, "dcs-sms")
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		if err := os.MkdirAll(filepath.Join(root, sub), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	h := &fakeHook{root: root, behavior: fn, heartbeat: heartbeat, processInbox: processInbox, stop: make(chan struct{})}
	// Write initial heartbeat immediately if enabled so tests don't race with freshness check
	if heartbeat {
		h.writeHeartbeat()
	}
	h.wg.Add(1)
	go h.run()
	t.Cleanup(func() {
		close(h.stop)
		h.wg.Wait()
	})
	return h
}

func (h *fakeHook) run() {
	defer h.wg.Done()
	tick := time.NewTicker(10 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-h.stop:
			return
		case <-tick.C:
			if h.heartbeat {
				h.writeHeartbeat()
			}
			if h.processInbox {
				h.processInboxOnce()
			}
		}
	}
}

func (h *fakeHook) writeHeartbeat() {
	st := proto.HookState{
		HookVersion:   "fake-0.0.0",
		MissionLoaded: true,
		MissionName:   "Test.miz",
		LastFrame:     1,
		LastFrameAt:   time.Now().UTC().Format(time.RFC3339Nano),
	}
	data, _ := json.Marshal(st)
	tmp := filepath.Join(h.root, "state", "hook.json.tmp")
	final := filepath.Join(h.root, "state", "hook.json")
	_ = os.WriteFile(tmp, data, 0o644)
	_ = os.Rename(tmp, final)
}

func (h *fakeHook) processInboxOnce() {
	entries, err := os.ReadDir(filepath.Join(h.root, "inbox"))
	if err != nil {
		return
	}
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".req.json") {
			continue
		}
		reqPath := filepath.Join(h.root, "inbox", e.Name())
		data, err := os.ReadFile(reqPath)
		if err != nil {
			continue
		}
		var req proto.ExecRequest
		if err := json.Unmarshal(data, &req); err != nil {
			continue
		}
		resp := h.behavior(req)
		resp.ID = req.ID
		respData, _ := json.Marshal(resp)
		respTmp := filepath.Join(h.root, "outbox", req.ID+".res.json.tmp")
		respFinal := filepath.Join(h.root, "outbox", req.ID+".res.json")
		_ = os.WriteFile(respTmp, respData, 0o644)
		_ = os.Rename(respTmp, respFinal)
		_ = os.Remove(reqPath)
	}
}

// runExec invokes the exec subcommand against a fake-hook root. Returns
// (exit code, stdout, stderr).
func runExec(t *testing.T, root string, args []string) (int, string, string) {
	t.Helper()
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	// Cap the test if exec hangs.
	done := make(chan int, 1)
	go func() { done <- execCmd(args, &stdout, &stderr) }()
	select {
	case code := <-done:
		return code, stdout.String(), stderr.String()
	case <-time.After(10 * time.Second):
		t.Fatal("execCmd did not return within 10s")
		return 0, "", ""
	}
}

func TestExecSuccess(t *testing.T) {
	root := t.TempDir()
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		return proto.ExecResponse{
			OK:          true,
			ReturnValue: json.RawMessage(`42`),
			Output:      "hi",
		}
	}, true /*heartbeat*/, true /*processInbox*/)

	code, stdout, _ := runExec(t, root, []string{"--code", "return 42", "--timeout", "2s"})
	if code != 0 {
		t.Errorf("exit %d, want 0", code)
	}
	if !strings.Contains(stdout, `"ok":true`) || !strings.Contains(stdout, `"return_value":42`) {
		t.Errorf("unexpected stdout: %s", stdout)
	}
}

func TestExecLuaError(t *testing.T) {
	root := t.TempDir()
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		return proto.ExecResponse{
			OK:    false,
			Error: &proto.ExecError{Message: "boom", Traceback: "tb"},
		}
	}, true, true)

	code, stdout, _ := runExec(t, root, []string{"--code", "error('boom')", "--timeout", "2s"})
	if code != 1 {
		t.Errorf("exit %d, want 1", code)
	}
	if !strings.Contains(stdout, `"ok":false`) || !strings.Contains(stdout, "boom") {
		t.Errorf("unexpected stdout: %s", stdout)
	}
}

func TestExecTimeout(t *testing.T) {
	root := t.TempDir()
	// Heartbeat-only fake hook: keeps freshness check happy but never
	// processes the inbox, so the request times out.
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		return proto.ExecResponse{}
	}, true /*heartbeat*/, false /*processInbox*/)

	code, _, stderr := runExec(t, root, []string{"--code", "return 1", "--timeout", "300ms"})
	if code != 2 {
		t.Errorf("exit %d, want 2 (timeout)", code)
	}
	if !strings.Contains(stderr, "timeout") {
		t.Errorf("expected 'timeout' in stderr, got %q", stderr)
	}
}

func TestExecReadsFromStdin(t *testing.T) {
	root := t.TempDir()
	var seen string
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		seen = req.Code
		return proto.ExecResponse{OK: true}
	}, true, true)

	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	// Replace stdin for this invocation.
	oldStdin := stdinReader
	stdinReader = strings.NewReader("return 99\n")
	defer func() { stdinReader = oldStdin }()

	code := execCmd([]string{"--timeout", "2s"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit %d, want 0; stderr=%s", code, stderr.String())
	}
	if seen != "return 99\n" {
		t.Errorf("hook saw code %q, want %q", seen, "return 99\n")
	}
}

func TestExecFileFlag(t *testing.T) {
	root := t.TempDir()
	var seen string
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		seen = req.Code
		return proto.ExecResponse{OK: true}
	}, true, true)

	codeFile := filepath.Join(t.TempDir(), "snippet.lua")
	if err := os.WriteFile(codeFile, []byte("return 7"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, _, stderr := runExec(t, root, []string{"--file", codeFile, "--timeout", "2s"})
	if code != 0 {
		t.Errorf("exit %d, want 0; stderr=%s", code, stderr)
	}
	if seen != "return 7" {
		t.Errorf("hook saw %q, want %q", seen, "return 7")
	}
}

func TestExecPollRespectsTightDeadline(t *testing.T) {
	root := t.TempDir()
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		return proto.ExecResponse{}
	}, true /*heartbeat*/, false /*processInbox*/)

	start := time.Now()
	code, _, _ := runExec(t, root, []string{"--code", "x", "--timeout", "100ms"})
	elapsed := time.Since(start)
	if code != 2 {
		t.Errorf("exit %d, want 2 (timeout)", code)
	}
	// Should return within ~150ms (100ms deadline + small slack), not 125ms+.
	// We allow up to 200ms to keep CI happy.
	if elapsed > 200*time.Millisecond {
		t.Errorf("oversleep: took %v, want < 200ms", elapsed)
	}
}

func TestExecFailsFastWhenHookStale(t *testing.T) {
	root := t.TempDir()
	// Create dirs but no heartbeat → state/hook.json missing.
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		_ = os.MkdirAll(filepath.Join(root, "dcs-sms", sub), 0o755)
	}
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := execCmd([]string{"--code", "return 1", "--timeout", "500ms"}, &stdout, &stderr)
	if code != 3 {
		t.Errorf("exit %d, want 3 (hook not ready)", code)
	}
	if !strings.Contains(stderr.String(), "hook") {
		t.Errorf("expected hook diagnostic in stderr, got %q", stderr.String())
	}
}

func TestExecWaitWaitsForHook(t *testing.T) {
	root := t.TempDir()
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		_ = os.MkdirAll(filepath.Join(root, "dcs-sms", sub), 0o755)
	}

	// Start a goroutine that begins writing heartbeats after 200ms and also
	// answers requests.
	stop := make(chan struct{})
	go func() {
		time.Sleep(200 * time.Millisecond)
		ticker := time.NewTicker(20 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				st := proto.HookState{
					HookVersion:   "fake",
					MissionLoaded: true,
					LastFrameAt:   time.Now().UTC().Format(time.RFC3339Nano),
				}
				data, _ := json.Marshal(st)
				p := filepath.Join(root, "dcs-sms", "state", "hook.json")
				_ = os.WriteFile(p+".tmp", data, 0o644)
				_ = os.Rename(p+".tmp", p)
				// also process inbox
				entries, _ := os.ReadDir(filepath.Join(root, "dcs-sms", "inbox"))
				for _, e := range entries {
					if !strings.HasSuffix(e.Name(), ".req.json") {
						continue
					}
					reqPath := filepath.Join(root, "dcs-sms", "inbox", e.Name())
					raw, err := os.ReadFile(reqPath)
					if err != nil {
						continue
					}
					var req proto.ExecRequest
					if json.Unmarshal(raw, &req) != nil {
						continue
					}
					resp := proto.ExecResponse{ID: req.ID, OK: true, ReturnValue: json.RawMessage(`1`)}
					out, _ := json.Marshal(resp)
					rp := filepath.Join(root, "dcs-sms", "outbox", req.ID+".res.json")
					_ = os.WriteFile(rp+".tmp", out, 0o644)
					_ = os.Rename(rp+".tmp", rp)
					_ = os.Remove(reqPath)
				}
			}
		}
	}()
	t.Cleanup(func() { close(stop) })

	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := execCmd([]string{"--code", "return 1", "--wait", "--timeout", "3s"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit %d, want 0; stderr=%s", code, stderr.String())
	}
}
