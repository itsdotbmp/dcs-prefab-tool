package main

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

// fakeSetupHooks implements setupHooks for tests by holding func fields.
type fakeSetupHooks struct {
	runUpdateFn       func(args []string, stdout, stderr io.Writer) (swapped bool, exitCode int)
	reExecSelfFn      func(args []string, stdout, stderr io.Writer) int
	installMeModFn    func(args []string, stdout, stderr io.Writer) int
	installHookFn     func(args []string, stdout, stderr io.Writer) int
	discoverDCSPathFn func() string
}

func (f *fakeSetupHooks) runUpdate(a []string, so, se io.Writer) (bool, int) {
	return f.runUpdateFn(a, so, se)
}
func (f *fakeSetupHooks) reExecSelf(a []string, so, se io.Writer) int {
	return f.reExecSelfFn(a, so, se)
}
func (f *fakeSetupHooks) installMeMod(a []string, so, se io.Writer) int {
	return f.installMeModFn(a, so, se)
}
func (f *fakeSetupHooks) installHook(a []string, so, se io.Writer) int {
	return f.installHookFn(a, so, se)
}
func (f *fakeSetupHooks) discoverDCSPath() string {
	return f.discoverDCSPathFn()
}

func newFakeSetupHooks() *fakeSetupHooks {
	return &fakeSetupHooks{
		runUpdateFn:       func(_ []string, _, _ io.Writer) (bool, int) { return false, 0 },
		reExecSelfFn:      func(_ []string, _, _ io.Writer) int { return 0 },
		installMeModFn:    func(_ []string, _, _ io.Writer) int { return 0 },
		installHookFn:     func(_ []string, _, _ io.Writer) int { return 0 },
		discoverDCSPathFn: func() string { return "" }, // no host-config leakage in tests
	}
}

func TestSetup_RunsAllStepsWhenNoUpdateAndAllOK(t *testing.T) {
	hooks := newFakeSetupHooks()
	calls := []string{}
	hooks.installMeModFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "me-mod"); return 0 }
	hooks.installHookFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "hook"); return 0 }
	hooks.runUpdateFn = func(_ []string, _, _ io.Writer) (bool, int) { calls = append(calls, "update"); return false, 0 }

	var stdout, stderr bytes.Buffer
	code := setupCmdWith(nil, &stdout, &stderr, hooks)
	if code != 0 {
		t.Errorf("exit %d, stderr: %s", code, stderr.String())
	}
	want := []string{"update", "me-mod", "hook"}
	if !stringSliceEqual(calls, want) {
		t.Errorf("call order = %v, want %v", calls, want)
	}
	if !strings.Contains(stdout.String(), "Setup complete") {
		t.Errorf("expected 'Setup complete' in stdout, got %q", stdout.String())
	}
}

func TestSetup_ReExecsAfterBinarySwap(t *testing.T) {
	hooks := newFakeSetupHooks()
	calls := []string{}
	hooks.runUpdateFn = func(_ []string, _, _ io.Writer) (bool, int) { calls = append(calls, "update"); return true, 0 }
	hooks.reExecSelfFn = func(args []string, _, _ io.Writer) int {
		calls = append(calls, "reexec:"+strings.Join(args, " "))
		return 0
	}
	hooks.installMeModFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "me-mod"); return 0 }
	hooks.installHookFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "hook"); return 0 }

	var stdout, stderr bytes.Buffer
	code := setupCmdWith(nil, &stdout, &stderr, hooks)
	if code != 0 {
		t.Errorf("exit %d", code)
	}
	// After re-exec the parent must NOT call installMeMod / installHook —
	// the child does. Expected order is just update → reexec.
	want := []string{"update", "reexec:setup --skip-update"}
	if !stringSliceEqual(calls, want) {
		t.Errorf("call order = %v, want %v", calls, want)
	}
}

func TestSetup_SkipUpdateRunsInstallsDirectly(t *testing.T) {
	hooks := newFakeSetupHooks()
	calls := []string{}
	hooks.runUpdateFn = func(_ []string, _, _ io.Writer) (bool, int) {
		calls = append(calls, "update")
		return false, 0
	}
	hooks.installMeModFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "me-mod"); return 0 }
	hooks.installHookFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "hook"); return 0 }

	var stdout, stderr bytes.Buffer
	code := setupCmdWith([]string{"--skip-update"}, &stdout, &stderr, hooks)
	if code != 0 {
		t.Errorf("exit %d", code)
	}
	want := []string{"me-mod", "hook"}
	if !stringSliceEqual(calls, want) {
		t.Errorf("call order = %v, want %v (update should be skipped)", calls, want)
	}
}

func TestSetup_PropagatesExit5FromInstall(t *testing.T) {
	hooks := newFakeSetupHooks()
	hooks.installMeModFn = func(_ []string, _, _ io.Writer) int { return 5 }

	var stdout, stderr bytes.Buffer
	code := setupCmdWith(nil, &stdout, &stderr, hooks)
	if code != 5 {
		t.Errorf("exit %d, want 5", code)
	}
}

func TestSetup_ContinuesPastUpdateFailure(t *testing.T) {
	hooks := newFakeSetupHooks()
	calls := []string{}
	hooks.runUpdateFn = func(_ []string, _, stderr io.Writer) (bool, int) {
		calls = append(calls, "update")
		return false, 3 // update failed (e.g. network down)
	}
	hooks.installMeModFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "me-mod"); return 0 }
	hooks.installHookFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "hook"); return 0 }

	var stdout, stderr bytes.Buffer
	code := setupCmdWith(nil, &stdout, &stderr, hooks)
	if code != 0 {
		t.Errorf("exit %d, want 0 (degraded mode: install still ran)", code)
	}
	want := []string{"update", "me-mod", "hook"}
	if !stringSliceEqual(calls, want) {
		t.Errorf("call order = %v, want %v", calls, want)
	}
}

func TestSetup_ReExecForwardsAllFlags(t *testing.T) {
	hooks := newFakeSetupHooks()
	var reExecArgs []string
	hooks.runUpdateFn = func(_ []string, _, _ io.Writer) (bool, int) { return true, 0 }
	hooks.reExecSelfFn = func(args []string, _, _ io.Writer) int {
		reExecArgs = append([]string(nil), args...)
		return 0
	}

	var stdout, stderr bytes.Buffer
	code := setupCmdWith(
		[]string{"--dcs-path", "D:/DCS", "--saved-games", "D:/Saved Games", "--no-config-save"},
		&stdout, &stderr, hooks,
	)
	if code != 0 {
		t.Fatalf("exit %d, stderr: %s", code, stderr.String())
	}

	// The re-exec child must see every flag the parent received (other
	// than --skip-update, which is added by the parent).
	want := []string{"setup", "--skip-update", "--dcs-path", "D:/DCS", "--saved-games", "D:/Saved Games", "--no-config-save"}
	if !stringSliceEqual(reExecArgs, want) {
		t.Errorf("reExecSelf args =\n  %v\nwant\n  %v", reExecArgs, want)
	}
}

func TestSetup_ReExecForwardsDiscoveredDCSPath(t *testing.T) {
	// When the user doesn't pass --dcs-path explicitly but setup
	// discovers one from config / env, the discovered path must reach
	// the re-execed child so the new binary's install-me-mod and
	// install-hook see the same DCS install the parent did.
	hooks := newFakeSetupHooks()
	hooks.discoverDCSPathFn = func() string { return "D:/Discovered/DCS" }
	hooks.runUpdateFn = func(_ []string, _, _ io.Writer) (bool, int) { return true, 0 }
	var reExecArgs []string
	hooks.reExecSelfFn = func(args []string, _, _ io.Writer) int {
		reExecArgs = append([]string(nil), args...)
		return 0
	}

	var stdout, stderr bytes.Buffer
	code := setupCmdWith(nil, &stdout, &stderr, hooks)
	if code != 0 {
		t.Fatalf("exit %d, stderr: %s", code, stderr.String())
	}
	want := []string{"setup", "--skip-update", "--dcs-path", "D:/Discovered/DCS"}
	if !stringSliceEqual(reExecArgs, want) {
		t.Errorf("reExecSelf args =\n  %v\nwant\n  %v", reExecArgs, want)
	}
}
