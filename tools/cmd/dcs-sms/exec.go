package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
	"github.com/nielsvaes/dcs-sms/tools/internal/hookstatus"
	"github.com/nielsvaes/dcs-sms/tools/internal/mailbox"
	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// stdinReader is the source for code when neither --file nor --code is
// given. Tests swap this out to inject input.
var stdinReader io.Reader = os.Stdin

func init() {
	register("exec", execCmd)
}

func execCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("exec", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagFile       = fs.String("file", "", "path to a .lua file")
		flagCode       = fs.String("code", "", "Lua code (inline)")
		flagTimeout    = fs.Duration("timeout", 5*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
		flagWait       = fs.Bool("wait", false, "if hook isn't ready, poll until it is or --timeout elapses")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	code, err := readCode(*flagFile, *flagCode, stdinReader)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec:", err)
		return 2
	}

	root, err := resolveRoot(*flagSavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec:", err)
		return 3
	}
	mb := mailbox.New(filepath.Join(root, "dcs-sms"))
	if err := ensureMailboxDirs(mb.Root); err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec:", err)
		return 3
	}

	if err := waitForHook(mb.State(), *flagWait, *flagTimeout); err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec:", err)
		return 3
	}

	// Best-effort cleanup of orphan responses left by previous timed-out
	// runs. Errors here are non-fatal — we'd rather proceed than refuse.
	_ = mb.SweepOutboxOlderThan(60 * time.Second)

	req := proto.ExecRequest{
		ID:        mailbox.NewID(),
		Kind:      "exec",
		Code:      code,
		TimeoutMs: int(flagTimeout.Milliseconds()),
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}

	if err := mb.WriteRequest(req); err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec: write request:", err)
		return 3
	}

	resp, err := pollResponse(mb, req.ID, *flagTimeout)
	if err != nil {
		if errors.Is(err, errPollTimeout) {
			fmt.Fprintln(stderr, "dcs-sms exec: timeout — no response within", *flagTimeout)
			return 2
		}
		fmt.Fprintln(stderr, "dcs-sms exec: poll:", err)
		return 3
	}

	var data []byte
	if *flagPretty {
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

// readCode resolves which input source to use, in priority order: --file,
// --code, stdin. Empty result is an error.
func readCode(file, code string, stdin io.Reader) (string, error) {
	if file != "" {
		data, err := os.ReadFile(file)
		if err != nil {
			return "", fmt.Errorf("read --file: %w", err)
		}
		return string(data), nil
	}
	if code != "" {
		return code, nil
	}
	// If stdin is a terminal, ReadAll would block forever waiting for EOF.
	// Detect that case (real *os.File only — tests inject strings.Reader,
	// which doesn't implement *os.File and harmlessly falls through).
	if f, ok := stdin.(*os.File); ok {
		if fi, err := f.Stat(); err == nil && (fi.Mode()&os.ModeCharDevice) != 0 {
			return "", errors.New("no code provided (use --file, --code, or pipe via stdin)")
		}
	}
	data, err := io.ReadAll(stdin)
	if err != nil {
		return "", fmt.Errorf("read stdin: %w", err)
	}
	if len(data) == 0 {
		return "", errors.New("no code provided (use --file, --code, or pipe via stdin)")
	}
	return string(data), nil
}

// resolveRoot returns the Saved Games path using the standard discovery chain.
func resolveRoot(override string) (string, error) {
	cfg, _ := dcspath.DefaultConfigPath()
	return dcspath.Discover(override, cfg)
}

// ensureMailboxDirs creates dcs-sms/{inbox,outbox,state,log} if missing.
func ensureMailboxDirs(root string) error {
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		if err := os.MkdirAll(filepath.Join(root, sub), 0o755); err != nil {
			return err
		}
	}
	return nil
}

var errPollTimeout = errors.New("poll timeout")

// pollResponse polls outbox/<id>.res.json every ~25ms until found or
// timeout. The poll interval shrinks if the deadline is closer than 25ms
// so we don't oversleep past it.
func pollResponse(mb *mailbox.Mailbox, id string, timeout time.Duration) (proto.ExecResponse, error) {
	deadline := time.Now().Add(timeout)
	const pollInterval = 25 * time.Millisecond
	for {
		resp, ok, err := mb.ReadResponse(id)
		if err != nil {
			return proto.ExecResponse{}, err
		}
		if ok {
			return resp, nil
		}
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return proto.ExecResponse{}, errPollTimeout
		}
		sleep := pollInterval
		if remaining < sleep {
			sleep = remaining
		}
		time.Sleep(sleep)
	}
}

// waitForHook returns nil if the hook heartbeat is fresh. If wait is true,
// it polls every 50ms until fresh or timeout. If wait is false and the hook
// isn't fresh, it returns immediately with an error.
func waitForHook(stateDir string, wait bool, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		st, err := hookstatus.Read(stateDir)
		if err == nil && hookstatus.IsFresh(st, 2*time.Second, time.Now()) {
			if !st.MissionLoaded {
				if !wait {
					return errors.New("hook is running but no mission loaded — load a mission or pass --wait")
				}
				// fall through to wait
			} else {
				return nil
			}
		} else if !wait {
			if err != nil {
				return fmt.Errorf("hook not ready (%v) — start DCS or pass --wait", err)
			}
			return errors.New("hook heartbeat stale — DCS may be paused/hung; pass --wait to retry")
		}
		if time.Now().After(deadline) {
			return errors.New("timed out waiting for hook to become ready")
		}
		time.Sleep(50 * time.Millisecond)
	}
}
