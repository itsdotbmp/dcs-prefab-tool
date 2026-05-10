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

type statusOpts struct {
	JSON       bool
	SavedGames string
}

func statusFlags() (*flag.FlagSet, *statusOpts) {
	opts := &statusOpts{}
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	fs.BoolVar(&opts.JSON, "json", false, "emit machine-readable JSON")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	return fs, opts
}

func init() {
	registerInfo("status", cmdInfo{
		Run:      statusCmd,
		Flags:    func() *flag.FlagSet { fs, _ := statusFlags(); return fs },
		Synopsis: "report whether the hook is alive and a mission is loaded",
	})
}

// statusCmd prints the hook's current state. Exit codes:
//
//	0 — hook found and heartbeat is fresh
//	2 — flag parse error
//	3 — hook file missing or unreadable (DCS not running, or wrong --saved-games)
//	4 — heartbeat present but stale (DCS may be paused/hung)
func statusCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := statusFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(opts.SavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms status:", err)
		return 3
	}
	stateDir := filepath.Join(root, "dcs-sms", "state")
	st, err := hookstatus.ReadMerged(stateDir)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms status: hook not found —", err)
		return 3
	}
	fresh := hookstatus.IsFresh(st, 2*time.Second, time.Now())

	if opts.JSON {
		out := map[string]any{
			"hook_version":       st.HookVersion,
			"state":              st.State,
			"mission_loaded":     st.MissionLoaded,
			"mission_name":       st.MissionName,
			"gui_bridge_enabled": st.GuiBridgeEnabled,
			"tick_source":        st.TickSource,
			"last_frame":         st.LastFrame,
			"last_frame_at":      st.LastFrameAt,
			"last_tick":          st.LastTick,
			"last_tick_at":       st.LastTickAt,
			"fresh":              fresh,
		}
		data, _ := json.Marshal(out)
		fmt.Fprintln(stdout, string(data))
	} else {
		fmt.Fprintf(stdout, "hook version:       %s\n", st.HookVersion)
		if st.State != "" {
			fmt.Fprintf(stdout, "state:              %s\n", st.State)
		}
		fmt.Fprintf(stdout, "mission loaded:     %v\n", st.MissionLoaded)
		if st.MissionName != "" {
			fmt.Fprintf(stdout, "mission name:       %s\n", st.MissionName)
		}
		if st.TickSource != "" {
			fmt.Fprintf(stdout, "tick source:        %s\n", st.TickSource)
		}
		fmt.Fprintf(stdout, "gui bridge enabled: %v\n", st.GuiBridgeEnabled)
		// Prefer the new last_tick fields when populated; fall back to last_frame.
		tick := st.LastTick
		tickAt := st.LastTickAt
		if tick == 0 && tickAt == "" {
			tick = st.LastFrame
			tickAt = st.LastFrameAt
		}
		fmt.Fprintf(stdout, "last tick:          %d (%s)\n", tick, tickAt)
		fmt.Fprintf(stdout, "fresh:              %v\n", fresh)
	}

	if !fresh {
		fmt.Fprintf(stderr, "dcs-sms status: heartbeat stale (last frame at %s)\n", st.LastFrameAt)
		return 4
	}
	return 0
}
