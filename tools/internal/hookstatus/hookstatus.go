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

// IsFresh returns true when st.LastFrameAt is within maxAge of now.
// An unparseable LastFrameAt is treated as stale (safer default).
func IsFresh(st proto.HookState, maxAge time.Duration, now time.Time) bool {
	t, err := time.Parse(time.RFC3339Nano, st.LastFrameAt)
	if err != nil {
		// Try the simpler RFC3339 form as fallback.
		t, err = time.Parse(time.RFC3339, st.LastFrameAt)
		if err != nil {
			return false
		}
	}
	return now.Sub(t) <= maxAge
}
