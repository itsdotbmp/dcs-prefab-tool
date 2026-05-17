package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/hookstatus"
	"github.com/nielsvaes/dcs-sms/tools/internal/mailbox"
	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// reloadMeModSnippet is the Lua chunk that runs in the ME bridge env.
// Mirrors the existing Ctrl+Shift+R reload path documented in
// marquee_hook.lua / menu.lua: clear every dcs_sms_me.* entry from
// package.loaded, then dofile init.lua so it re-runs bootstrap. The
// install functions inside init.lua are documented as idempotent.
const reloadMeModSnippet = `
local cleared = {}
for k, _ in pairs(package.loaded) do
    if k == 'dcs_sms_me' or k:find('^dcs_sms_me%.') then
        cleared[#cleared + 1] = k
    end
end
for _, k in ipairs(cleared) do package.loaded[k] = nil end

local function resolve_init_path()
    if not (lfs and lfs.currentdir) then
        return nil, 'lfs unavailable in ME env'
    end
    local sep = package.config and package.config:sub(1, 1) or '/'
    return lfs.currentdir() .. sep .. 'MissionEditor' .. sep .. 'modules' .. sep .. 'dcs_sms_me' .. sep .. 'init.lua', nil
end

local init_path, path_err = resolve_init_path()
if not init_path then
    return { ok = false, cleared = cleared, error = path_err }
end

local ok, err = pcall(dofile, init_path)
if not ok then
    return { ok = false, cleared = cleared, init_path = init_path, error = tostring(err) }
end
return { ok = true, cleared = cleared, init_path = init_path }
`

type reloadMeModOpts struct {
	Timeout    time.Duration
	Pretty     bool
	SavedGames string
	Wait       bool
}

func reloadMeModFlags() (*flag.FlagSet, *reloadMeModOpts) {
	opts := &reloadMeModOpts{}
	fs := flag.NewFlagSet("reload-me-mod", flag.ContinueOnError)
	fs.DurationVar(&opts.Timeout, "timeout", 10*time.Second, "wall-clock timeout")
	fs.BoolVar(&opts.Pretty, "pretty", false, "indent JSON output")
	fs.StringVar(&opts.SavedGames, "saved-games", "", "override Saved Games path")
	fs.BoolVar(&opts.Wait, "wait", false, "if hook isn't ready, poll until it is or --timeout elapses")
	return fs, opts
}

func init() {
	registerInfo("reload-me-mod", cmdInfo{
		Run:      reloadMeModCmd,
		Flags:    flagsOnly(reloadMeModFlags),
		Synopsis: "hot-reload the installed ME mod via the gui bridge (no DCS restart)",
	})
}

func reloadMeModCmd(args []string, stdout, stderr io.Writer) int {
	fs, opts := reloadMeModFlags()
	fs.SetOutput(stderr)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(opts.SavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms reload-me-mod:", err)
		return 3
	}
	mb := mailbox.New(filepath.Join(root, "dcs-sms"))
	if err := ensureMailboxDirs(mb.Root); err != nil {
		fmt.Fprintln(stderr, "dcs-sms reload-me-mod:", err)
		return 3
	}

	if err := waitForHook(mb.State(), opts.Wait, opts.Timeout); err != nil {
		fmt.Fprintln(stderr, "dcs-sms reload-me-mod:", err)
		return 3
	}

	_ = mb.SweepOutboxOlderThan(60 * time.Second)

	// Force target=gui — the reload only makes sense in the ME bridge env.
	// RouteForTarget reports a clean error if the gui bridge is disabled
	// (e.g. the "DCS-SMS > External execution" toggle is off).
	hookState, _ := hookstatus.ReadMerged(mb.State())
	target, err := hookstatus.RouteForTarget("gui", hookState)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms reload-me-mod:", err)
		fmt.Fprintln(stderr, "  Open the Mission Editor and ensure DCS-SMS > External execution is toggled on.")
		return 4
	}

	req := proto.ExecRequest{
		ID:        mailbox.NewID(),
		Kind:      "exec",
		Target:    target,
		Code:      reloadMeModSnippet,
		TimeoutMs: int(opts.Timeout.Milliseconds()),
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}

	if err := mb.WriteRequest(req); err != nil {
		fmt.Fprintln(stderr, "dcs-sms reload-me-mod: write request:", err)
		return 3
	}

	resp, err := pollResponse(mb, req.ID, opts.Timeout)
	if err != nil {
		if errors.Is(err, errPollTimeout) {
			fmt.Fprintln(stderr, "dcs-sms reload-me-mod: timeout — no response within", opts.Timeout)
			return 2
		}
		fmt.Fprintln(stderr, "dcs-sms reload-me-mod: poll:", err)
		return 3
	}

	var data []byte
	if opts.Pretty {
		data, _ = json.MarshalIndent(resp, "", "  ")
	} else {
		data, _ = json.Marshal(resp)
	}
	fmt.Fprintln(stdout, string(data))

	if !resp.OK {
		return 1
	}
	return 0
}
