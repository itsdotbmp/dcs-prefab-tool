package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/hookstatus"
)

func init() {
	register("status", statusCmd)
}

// statusCmd prints the hook's current state. Exit codes:
//
//	0 — hook found and heartbeat is fresh
//	2 — flag parse error
//	3 — hook file missing or unreadable (DCS not running, or wrong --saved-games)
//	4 — heartbeat present but stale (DCS may be paused/hung)
func statusCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagJSON := fs.Bool("json", false, "emit machine-readable JSON")
	flagSavedGames := fs.String("saved-games", "", "override Saved Games path")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(*flagSavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms status:", err)
		return 3
	}
	stateDir := filepath.Join(root, "dcs-sms", "state")
	st, err := hookstatus.Read(stateDir)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms status: hook not found —", err)
		return 3
	}
	fresh := hookstatus.IsFresh(st, 2*time.Second, time.Now())

	if *flagJSON {
		out := map[string]any{
			"hook_version":   st.HookVersion,
			"mission_loaded": st.MissionLoaded,
			"mission_name":   st.MissionName,
			"last_frame":     st.LastFrame,
			"last_frame_at":  st.LastFrameAt,
			"fresh":          fresh,
		}
		data, _ := json.Marshal(out)
		fmt.Fprintln(stdout, string(data))
	} else {
		fmt.Fprintf(stdout, "hook version:   %s\n", st.HookVersion)
		fmt.Fprintf(stdout, "mission loaded: %v\n", st.MissionLoaded)
		if st.MissionName != "" {
			fmt.Fprintf(stdout, "mission name:   %s\n", st.MissionName)
		}
		fmt.Fprintf(stdout, "last frame:     %d (%s)\n", st.LastFrame, st.LastFrameAt)
		fmt.Fprintf(stdout, "fresh:          %v\n", fresh)
	}

	if !fresh {
		fmt.Fprintf(stderr, "dcs-sms status: heartbeat stale (last frame at %s)\n", st.LastFrameAt)
		return 4
	}
	return 0
}
