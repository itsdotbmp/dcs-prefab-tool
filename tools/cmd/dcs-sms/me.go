package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"sort"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/hookstatus"
	"github.com/nielsvaes/dcs-sms/tools/internal/mailbox"
	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// meCommands is the noun → verb → handler map for the `me` namespace.
// Each `me <noun> <verb>` subcommand registers itself in init().
var meCommands = map[string]map[string]commandFunc{}

// registerMe wires a (noun, verb) pair to its handler.
func registerMe(noun, verb string, fn commandFunc) {
	if meCommands[noun] == nil {
		meCommands[noun] = map[string]commandFunc{}
	}
	if _, exists := meCommands[noun][verb]; exists {
		panic("duplicate me-command registration: " + noun + " " + verb)
	}
	meCommands[noun][verb] = fn
}

func init() {
	register("me", meDispatch)
}

// meDispatch routes args[0..1] (noun + verb) to the registered handler.
// Pure function — testable without touching os.Exit / os.Stdout.
func meDispatch(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		printMeUsage(stderr)
		return 2
	}
	switch args[0] {
	case "--help", "-h", "help":
		printMeUsage(stdout)
		return 0
	}
	if len(args) < 2 {
		fmt.Fprintf(stderr, "dcs-sms me: missing verb after noun %q\n", args[0])
		printMeUsage(stderr)
		return 2
	}
	nounMap, ok := meCommands[args[0]]
	if !ok {
		fmt.Fprintf(stderr, "dcs-sms me: unknown noun %q\n", args[0])
		printMeUsage(stderr)
		return 2
	}
	verbHandler, ok := nounMap[args[1]]
	if !ok {
		fmt.Fprintf(stderr, "dcs-sms me %s: unknown verb %q\n", args[0], args[1])
		return 2
	}
	return verbHandler(args[2:], stdout, stderr)
}

func printMeUsage(w io.Writer) {
	fmt.Fprintln(w, "dcs-sms me — Mission Editor commands (route via the gui bridge)")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Usage: dcs-sms me <noun> <verb> [flags]")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Commands:")
	// Stable, alphabetic listing of registered (noun, verb) pairs.
	nouns := make([]string, 0, len(meCommands))
	for n := range meCommands {
		nouns = append(nouns, n)
	}
	sort.Strings(nouns)
	for _, n := range nouns {
		verbs := make([]string, 0, len(meCommands[n]))
		for v := range meCommands[n] {
			verbs = append(verbs, v)
		}
		sort.Strings(verbs)
		for _, v := range verbs {
			fmt.Fprintf(w, "  me %s %s\n", n, v)
		}
	}
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Run `dcs-sms me <noun> <verb> --help` for command-specific flags.")
}

// runMeVerb invokes a verb on the dcs_sms_me.verbs Lua module via the gui
// bridge. The verb's argument table is passed as a Lua expression (built by
// the caller — keep it simple: { path = "..." } shapes are typical).
//
// All `me` commands route via target=gui (the ME-side bridge). The mission
// target isn't used for ME ops.
func runMeVerb(verb, luaArgsExpr string, timeout time.Duration, savedGamesOverride string, stderr io.Writer) (proto.ExecResponse, int) {
	root, err := resolveRoot(savedGamesOverride)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me:", err)
		return proto.ExecResponse{}, 3
	}
	mb := mailbox.New(filepath.Join(root, "dcs-sms"))
	if err := ensureMailboxDirs(mb.Root); err != nil {
		fmt.Fprintln(stderr, "dcs-sms me:", err)
		return proto.ExecResponse{}, 3
	}

	if err := waitForHook(mb.State(), false, timeout); err != nil {
		fmt.Fprintln(stderr, "dcs-sms me:", err)
		return proto.ExecResponse{}, 3
	}

	// Sweep stale outbox entries (best-effort).
	_ = mb.SweepOutboxOlderThan(60 * time.Second)

	// Resolve target — me commands always want gui.
	hookState, _ := hookstatus.ReadMerged(mb.State())
	target, err := hookstatus.RouteForTarget("gui", hookState)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms me:", err)
		return proto.ExecResponse{}, 4
	}

	code := fmt.Sprintf(
		"return require('dcs_sms_me.verbs').%s(%s)",
		verb, luaArgsExpr,
	)

	req := proto.ExecRequest{
		ID:        mailbox.NewID(),
		Kind:      "exec",
		Target:    target,
		Code:      code,
		TimeoutMs: int(timeout.Milliseconds()),
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}

	if err := mb.WriteRequest(req); err != nil {
		fmt.Fprintln(stderr, "dcs-sms me: write request:", err)
		return proto.ExecResponse{}, 3
	}

	resp, err := pollResponse(mb, req.ID, timeout)
	if err != nil {
		if errors.Is(err, errPollTimeout) {
			fmt.Fprintln(stderr, "dcs-sms me: timeout — no response within", timeout)
			return proto.ExecResponse{}, 2
		}
		fmt.Fprintln(stderr, "dcs-sms me: poll:", err)
		return proto.ExecResponse{}, 3
	}
	return resp, 0
}

// emitMeResponse writes the response as JSON (compact or pretty), and
// returns the conventional CLI exit code (0 ok, 1 verb-error).
func emitMeResponse(resp proto.ExecResponse, pretty bool, stdout io.Writer) int {
	var data []byte
	if pretty {
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
