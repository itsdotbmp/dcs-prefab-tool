package mailbox

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// newTestRoot creates the dcs-sms folder layout in t.TempDir() and returns it.
func newTestRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		if err := os.MkdirAll(filepath.Join(root, sub), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestWriteRequestCreatesInboxFile(t *testing.T) {
	root := newTestRoot(t)
	mb := New(root)

	req := proto.ExecRequest{
		ID:        "abc-123",
		Kind:      "exec",
		Code:      "return 1",
		TimeoutMs: 5000,
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
	if err := mb.WriteRequest(req); err != nil {
		t.Fatalf("WriteRequest: %v", err)
	}

	path := filepath.Join(root, "inbox", "abc-123.req.json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("expected inbox file %q: %v", path, err)
	}
	var got proto.ExecRequest
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got.ID != req.ID || got.Code != req.Code {
		t.Errorf("written request mismatch: %+v", got)
	}
}

func TestReadResponseReturnsAndDeletes(t *testing.T) {
	root := newTestRoot(t)
	mb := New(root)

	resp := proto.ExecResponse{
		ID:          "abc-123",
		OK:          true,
		ReturnValue: json.RawMessage(`42`),
		Output:      "hello",
	}
	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatal(err)
	}
	resPath := filepath.Join(root, "outbox", "abc-123.res.json")
	if err := os.WriteFile(resPath, data, 0o644); err != nil {
		t.Fatal(err)
	}

	got, ok, err := mb.ReadResponse("abc-123")
	if err != nil {
		t.Fatalf("ReadResponse: %v", err)
	}
	if !ok {
		t.Fatal("expected ok=true")
	}
	if got.ID != resp.ID || !got.OK || got.Output != "hello" {
		t.Errorf("response mismatch: %+v", got)
	}
	if _, err := os.Stat(resPath); !os.IsNotExist(err) {
		t.Errorf("expected response file deleted, stat err=%v", err)
	}
}

func TestReadResponseMissingReturnsNotOK(t *testing.T) {
	root := newTestRoot(t)
	mb := New(root)
	_, ok, err := mb.ReadResponse("nope")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Error("expected ok=false for missing response")
	}
}

func TestSweepStaleRemovesOldFiles(t *testing.T) {
	root := newTestRoot(t)
	mb := New(root)

	// Create an old file and a fresh file.
	oldPath := filepath.Join(root, "outbox", "old.res.json")
	freshPath := filepath.Join(root, "outbox", "fresh.res.json")
	if err := os.WriteFile(oldPath, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(freshPath, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	twoMinAgo := time.Now().Add(-2 * time.Minute)
	if err := os.Chtimes(oldPath, twoMinAgo, twoMinAgo); err != nil {
		t.Fatal(err)
	}

	if err := mb.SweepOutboxOlderThan(60 * time.Second); err != nil {
		t.Fatalf("Sweep: %v", err)
	}

	if _, err := os.Stat(oldPath); !os.IsNotExist(err) {
		t.Errorf("expected old file removed, stat err=%v", err)
	}
	if _, err := os.Stat(freshPath); err != nil {
		t.Errorf("expected fresh file kept: %v", err)
	}
}
