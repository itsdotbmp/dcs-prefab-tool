// Package hookstatus reads state/hook.json and reasons about whether the
// hook is alive enough to accept work.
package hookstatus

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// Read parses state/hook.json from the state directory.
func Read(stateDir string) (proto.HookState, error) {
	path := filepath.Join(stateDir, "hook.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return proto.HookState{}, fmt.Errorf("read %s: %w", path, err)
	}
	var st proto.HookState
	if err := json.Unmarshal(data, &st); err != nil {
		return proto.HookState{}, fmt.Errorf("parse %s: %w", path, err)
	}
	return st, nil
}

// IsFresh returns true when st.LastFrameAt is within maxAge of now,
// in either direction. Future timestamps caused by minor clock skew between
// the hook process and the CLI are treated as fresh as long as the absolute
// difference is within maxAge — but a far-future timestamp is just as stale
// as a far-past one.
//
// An unparseable LastFrameAt is treated as stale (safer default).
//
// time.RFC3339Nano accepts timestamps both with and without fractional
// seconds, so a single parse layout covers everything the Lua hook emits.
func IsFresh(st proto.HookState, maxAge time.Duration, now time.Time) bool {
	t, err := time.Parse(time.RFC3339Nano, st.LastFrameAt)
	if err != nil {
		return false
	}
	diff := now.Sub(t)
	if diff < 0 {
		diff = -diff
	}
	return diff <= maxAge
}

// RouteForTarget resolves the user's --target flag against the current hook
// state. Returns the concrete target the request should carry ("mission" or
// "gui"), or an error describing why the requested route isn't usable right
// now.
//
// requested values: "mission", "gui", "auto", or "" (treated as "auto").
func RouteForTarget(requested string, st proto.HookState) (string, error) {
	switch requested {
	case "mission":
		return "mission", nil
	case "gui":
		if !st.GuiBridgeEnabled {
			return "", fmt.Errorf("gui bridge is disabled — open the DCS-SMS menu in the Mission Editor and toggle 'External execution' on")
		}
		return "gui", nil
	case "", "auto":
		// Auto-routing decision tree. Order matters: prefer "mission" when
		// a sim is running (exec speed via onSimulationFrame), fall through
		// to "gui" when the user is in the ME or main menu.
		if st.State == "in_mission" || (st.State == "" && st.MissionLoaded) {
			return "mission", nil
		}
		if st.State == "in_mission_editor" || st.State == "at_main_menu" {
			if !st.GuiBridgeEnabled {
				return "", fmt.Errorf("DCS is in the %s but the gui bridge is disabled — toggle 'External execution' on in the DCS-SMS menu", st.State)
			}
			return "gui", nil
		}
		// State "loading_mission", "starting", "stopping" or unknown.
		// Legacy hook with mission unloaded and no state info also lands here.
		return "", fmt.Errorf("hook reports state=%q (mission_loaded=%v) — no target available right now; pass --target mission or --target gui explicitly", st.State, st.MissionLoaded)
	default:
		return "", fmt.Errorf("unknown --target %q (allowed: mission, gui, auto)", requested)
	}
}
