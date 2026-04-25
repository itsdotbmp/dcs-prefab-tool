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
