package main

import (
	"bytes"
	"fmt"
	"io"
	"strings"
	"testing"
)

func TestMenuQuit(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader("q\n"), &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), "DCS-SMS") {
		t.Errorf("expected banner in stdout, got %q", stdout.String())
	}
}

func TestMenuQuitUppercase(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader("Q\n"), &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
}

func TestMenuInvalidThenQuit(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader("zz\nq\n"), &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	// Should reprompt at least twice (initial + after invalid).
	if c := strings.Count(stdout.String(), "Choose ["); c < 2 {
		t.Errorf("expected at least 2 prompts, got %d in %q", c, stdout.String())
	}
}

func TestMenuThreeInvalidExits(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader("a\nb\nc\n"), &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
}

func TestMenuEOFExits(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenu(strings.NewReader(""), &stdout, &stderr)
	if code != 2 {
		t.Errorf("exit code %d, want 2", code)
	}
}

func TestMenuOption1RoutesToInstall(t *testing.T) {
	called := ""
	stub := func(args []string, stdout, stderr io.Writer) int {
		called = "install"
		fmt.Fprintln(stdout, "stub install ran")
		return 0
	}
	deps := menuDeps{actions: menuActions{install: stub, uninstall: failHandler(t), update: failHandler(t)}}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("1\n\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if called != "install" {
		t.Errorf("called = %q, want install", called)
	}
	if !strings.Contains(stdout.String(), "stub install ran") {
		t.Errorf("expected stub output in stdout, got %q", stdout.String())
	}
	if !strings.Contains(stdout.String(), "Press Enter to exit") {
		t.Errorf("expected pause prompt, got %q", stdout.String())
	}
}

func TestMenuOption2RoutesToUninstall(t *testing.T) {
	called := ""
	stub := func(args []string, stdout, stderr io.Writer) int { called = "uninstall"; return 0 }
	deps := menuDeps{actions: menuActions{install: failHandler(t), uninstall: stub, update: failHandler(t)}}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("2\n\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if called != "uninstall" {
		t.Errorf("called = %q, want uninstall", called)
	}
}

func TestMenuOption3RoutesToUpdate(t *testing.T) {
	called := ""
	stub := func(args []string, stdout, stderr io.Writer) int { called = "update"; return 0 }
	deps := menuDeps{actions: menuActions{install: failHandler(t), uninstall: failHandler(t), update: stub}}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("3\n\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if called != "update" {
		t.Errorf("called = %q, want update", called)
	}
}

func TestMenuActionPropagatesExitCode(t *testing.T) {
	stub := func(args []string, stdout, stderr io.Writer) int { return 7 }
	deps := menuDeps{actions: menuActions{install: stub, uninstall: failHandler(t), update: failHandler(t)}}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("1\n\n"), &stdout, &stderr, deps)
	if code != 7 {
		t.Errorf("exit code %d, want 7", code)
	}
}

func failHandler(t *testing.T) func([]string, io.Writer, io.Writer) int {
	return func(args []string, stdout, stderr io.Writer) int {
		t.Errorf("unexpected handler call")
		return 99
	}
}
