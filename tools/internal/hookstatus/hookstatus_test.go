package hookstatus

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

func writeState(t *testing.T, dir string, st proto.HookState) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(st)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "hook.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestReadOK(t *testing.T) {
	dir := t.TempDir()
	want := proto.HookState{
		HookVersion:   "0.1.0",
		MissionLoaded: true,
		MissionName:   "Test.miz",
		LastFrame:     42,
		LastFrameAt:   time.Now().UTC().Format(time.RFC3339Nano),
	}
	writeState(t, dir, want)

	got, err := Read(dir)
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	if got.HookVersion != want.HookVersion || got.MissionLoaded != want.MissionLoaded {
		t.Errorf("mismatch: got %+v want %+v", got, want)
	}
}

func TestReadMissing(t *testing.T) {
	dir := t.TempDir()
	_, err := Read(dir)
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestIsFreshTrue(t *testing.T) {
	now := time.Now().UTC()
	st := proto.HookState{LastFrameAt: now.Format(time.RFC3339Nano)}
	if !IsFresh(st, 2*time.Second, now) {
		t.Error("expected fresh")
	}
}

func TestIsFreshFalse(t *testing.T) {
	now := time.Now().UTC()
	st := proto.HookState{LastFrameAt: now.Add(-5 * time.Second).Format(time.RFC3339Nano)}
	if IsFresh(st, 2*time.Second, now) {
		t.Error("expected stale")
	}
}

func TestIsFreshUnparseable(t *testing.T) {
	now := time.Now().UTC()
	st := proto.HookState{LastFrameAt: "not-a-date"}
	if IsFresh(st, 2*time.Second, now) {
		t.Error("expected stale on unparseable timestamp")
	}
}
