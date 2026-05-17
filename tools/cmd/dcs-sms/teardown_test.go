package main

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

type fakeTeardownHooks struct {
	uninstallMeModFn func(args []string, stdout, stderr io.Writer) int
	uninstallHookFn  func(args []string, stdout, stderr io.Writer) int
}

func (f *fakeTeardownHooks) uninstallMeMod(a []string, so, se io.Writer) int {
	return f.uninstallMeModFn(a, so, se)
}
func (f *fakeTeardownHooks) uninstallHook(a []string, so, se io.Writer) int {
	return f.uninstallHookFn(a, so, se)
}

func newFakeTeardownHooks() *fakeTeardownHooks {
	return &fakeTeardownHooks{
		uninstallMeModFn: func(_ []string, _, _ io.Writer) int { return 0 },
		uninstallHookFn:  func(_ []string, _, _ io.Writer) int { return 0 },
	}
}

func TestTeardown_RunsBothStepsInOrder(t *testing.T) {
	hooks := newFakeTeardownHooks()
	calls := []string{}
	hooks.uninstallMeModFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "me-mod"); return 0 }
	hooks.uninstallHookFn = func(_ []string, _, _ io.Writer) int { calls = append(calls, "hook"); return 0 }

	var stdout, stderr bytes.Buffer
	code := teardownCmdWith(nil, &stdout, &stderr, hooks)
	if code != 0 {
		t.Errorf("exit %d", code)
	}
	want := []string{"me-mod", "hook"}
	if !stringSliceEqual(calls, want) {
		t.Errorf("call order = %v, want %v", calls, want)
	}
	if !strings.Contains(stdout.String(), "Teardown complete") {
		t.Errorf("expected 'Teardown complete' in stdout, got %q", stdout.String())
	}
}

func TestTeardown_PropagatesExit5FromUninstall(t *testing.T) {
	hooks := newFakeTeardownHooks()
	hooks.uninstallMeModFn = func(_ []string, _, _ io.Writer) int { return 5 }

	var stdout, stderr bytes.Buffer
	code := teardownCmdWith(nil, &stdout, &stderr, hooks)
	if code != 5 {
		t.Errorf("exit %d, want 5", code)
	}
}

func TestTeardown_ContinuesIfHookUninstallFails(t *testing.T) {
	hooks := newFakeTeardownHooks()
	hooks.uninstallMeModFn = func(_ []string, _, _ io.Writer) int { return 0 }
	hooks.uninstallHookFn = func(_ []string, _, _ io.Writer) int { return 3 }

	var stdout, stderr bytes.Buffer
	code := teardownCmdWith(nil, &stdout, &stderr, hooks)
	if code != 3 {
		t.Errorf("exit %d, want 3 (hook step failed)", code)
	}
}
