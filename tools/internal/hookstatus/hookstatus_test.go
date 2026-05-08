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

func TestIsFreshFutureTimestamp(t *testing.T) {
	now := time.Now().UTC()
	// Hook's clock is 1s ahead of CLI's — well within maxAge=2s.
	st := proto.HookState{LastFrameAt: now.Add(1 * time.Second).Format(time.RFC3339Nano)}
	if !IsFresh(st, 2*time.Second, now) {
		t.Error("expected fresh with hook clock 1s ahead within maxAge")
	}
	// 10s in the future — far enough out that even with clock skew it's stale.
	st2 := proto.HookState{LastFrameAt: now.Add(10 * time.Second).Format(time.RFC3339Nano)}
	if IsFresh(st2, 2*time.Second, now) {
		t.Error("expected stale with hook timestamp 10s in the future")
	}
}

func TestIsFreshNoFractionalSeconds(t *testing.T) {
	// The Lua hook emits whole-second timestamps via os.date("!%Y-%m-%dT%H:%M:%SZ").
	// Make sure we still parse them.
	now := time.Now().UTC().Truncate(time.Second)
	st := proto.HookState{LastFrameAt: now.Format("2006-01-02T15:04:05Z")}
	if !IsFresh(st, 2*time.Second, now) {
		t.Error("expected fresh with whole-second timestamp")
	}
}

func TestReadMalformedJSON(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "hook.json"), []byte("{not-json"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := Read(dir)
	if err == nil {
		t.Fatal("expected parse error for malformed JSON")
	}
}

func TestRouteForTargetExplicitMissionInRunningMission(t *testing.T) {
	st := proto.HookState{
		State:            "in_mission",
		MissionLoaded:    true,
		GuiBridgeEnabled: false,
		TickSource:       "simulation_frame",
	}
	got, err := RouteForTarget("mission", st)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "mission" {
		t.Errorf("got %q, want %q", got, "mission")
	}
}

func TestRouteForTargetExplicitGuiWhenEnabled(t *testing.T) {
	st := proto.HookState{
		State:            "in_mission_editor",
		MissionLoaded:    false,
		GuiBridgeEnabled: true,
		TickSource:       "update_manager",
	}
	got, err := RouteForTarget("gui", st)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "gui" {
		t.Errorf("got %q, want %q", got, "gui")
	}
}

func TestRouteForTargetExplicitGuiWhenDisabledErrors(t *testing.T) {
	st := proto.HookState{
		State:            "in_mission_editor",
		GuiBridgeEnabled: false,
		TickSource:       "update_manager",
	}
	_, err := RouteForTarget("gui", st)
	if err == nil {
		t.Fatal("expected error when gui requested but bridge disabled")
	}
}

func TestRouteForTargetAutoInMission(t *testing.T) {
	st := proto.HookState{
		State:            "in_mission",
		MissionLoaded:    true,
		GuiBridgeEnabled: false,
	}
	got, err := RouteForTarget("auto", st)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "mission" {
		t.Errorf("got %q, want %q", got, "mission")
	}
}

func TestRouteForTargetAutoInMissionEditor(t *testing.T) {
	st := proto.HookState{
		State:            "in_mission_editor",
		MissionLoaded:    false,
		GuiBridgeEnabled: true,
	}
	got, err := RouteForTarget("auto", st)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "gui" {
		t.Errorf("got %q, want %q", got, "gui")
	}
}

func TestRouteForTargetAutoInMissionEditorBridgeOffErrors(t *testing.T) {
	st := proto.HookState{
		State:            "in_mission_editor",
		GuiBridgeEnabled: false,
	}
	_, err := RouteForTarget("auto", st)
	if err == nil {
		t.Fatal("expected error: ME state but gui bridge is off")
	}
}

func TestRouteForTargetAutoAtMainMenu(t *testing.T) {
	// Main menu with the bridge enabled is a valid gui target.
	st := proto.HookState{
		State:            "at_main_menu",
		GuiBridgeEnabled: true,
	}
	got, err := RouteForTarget("auto", st)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "gui" {
		t.Errorf("got %q, want %q", got, "gui")
	}
}

func TestRouteForTargetAutoLegacyHeartbeatFallsBackToMission(t *testing.T) {
	// Old hook (0.1.0) sent no `state` field. Treat as "mission" if
	// MissionLoaded, otherwise error.
	stLoaded := proto.HookState{State: "", MissionLoaded: true}
	got, err := RouteForTarget("auto", stLoaded)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "mission" {
		t.Errorf("legacy + mission_loaded should route to mission, got %q", got)
	}
	stUnloaded := proto.HookState{State: "", MissionLoaded: false}
	if _, err := RouteForTarget("auto", stUnloaded); err == nil {
		t.Fatal("expected error: legacy hook + no mission can't auto-route")
	}
}

func TestRouteForTargetUnknown(t *testing.T) {
	if _, err := RouteForTarget("typo", proto.HookState{}); err == nil {
		t.Fatal("expected error for unknown target")
	}
}
