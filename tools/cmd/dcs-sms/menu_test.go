package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nielsvaes/dcs-sms/tools/internal/elevate"
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

func TestMenuOption1RoutesToSetup(t *testing.T) {
	called := ""
	stub := func(args []string, stdout, stderr io.Writer) int {
		called = "setup"
		fmt.Fprintln(stdout, "stub setup ran")
		return 0
	}
	deps := menuDeps{actions: menuActions{
		setup:            stub,
		teardown:         failHandler(t),
		installAISkill:   failHandler(t),
		uninstallAISkill: failHandler(t),
	}}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("1\n\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if called != "setup" {
		t.Errorf("called = %q, want setup", called)
	}
	if !strings.Contains(stdout.String(), "Press Enter to exit") {
		t.Errorf("expected pause prompt, got %q", stdout.String())
	}
}

func TestMenuOption2RoutesToTeardown(t *testing.T) {
	called := ""
	stub := func(args []string, stdout, stderr io.Writer) int { called = "teardown"; return 0 }
	deps := menuDeps{actions: menuActions{
		setup:            failHandler(t),
		teardown:         stub,
		installAISkill:   failHandler(t),
		uninstallAISkill: failHandler(t),
	}}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("2\n\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if called != "teardown" {
		t.Errorf("called = %q, want teardown", called)
	}
}

func TestMenuOption3InstallsAISkillForAll(t *testing.T) {
	gotArgs := []string(nil)
	stub := func(args []string, stdout, stderr io.Writer) int {
		gotArgs = append([]string(nil), args...)
		fmt.Fprintln(stdout, "stub install-ai-skill ran")
		return 0
	}
	deps := menuDeps{actions: menuActions{
		setup:            failHandler(t),
		teardown:         failHandler(t),
		installAISkill:   stub,
		uninstallAISkill: failHandler(t),
	}}
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("3\n\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	want := []string{"--agent", "all"}
	if !stringSliceEqual(gotArgs, want) {
		t.Errorf("got args %v, want %v", gotArgs, want)
	}
}

func TestMenuOption4UninstallsAISkillForAll(t *testing.T) {
	gotArgs := []string(nil)
	stub := func(args []string, stdout, stderr io.Writer) int {
		gotArgs = append([]string(nil), args...)
		return 0
	}
	deps := menuDeps{actions: menuActions{
		setup:            failHandler(t),
		teardown:         failHandler(t),
		installAISkill:   failHandler(t),
		uninstallAISkill: stub,
	}}
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("4\n\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	want := []string{"--agent", "all"}
	if !stringSliceEqual(gotArgs, want) {
		t.Errorf("got args %v, want %v", gotArgs, want)
	}
}

func TestMenuActionPropagatesExitCode(t *testing.T) {
	stub := func(args []string, stdout, stderr io.Writer) int { return 7 }
	deps := menuDeps{actions: menuActions{
		setup:            stub,
		teardown:         failHandler(t),
		installAISkill:   failHandler(t),
		uninstallAISkill: failHandler(t),
	}}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("1\n\n"), &stdout, &stderr, deps)
	if code != 7 {
		t.Errorf("exit code %d, want 7", code)
	}
}

func TestMenuOption1ElevationPrompt_Yes(t *testing.T) {
	setup := func(_ []string, _, _ io.Writer) int { return elevate.ExitCodeNeedsElevation }
	var reExecCalled []string
	deps := menuDeps{
		actions: menuActions{
			setup:            setup,
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		reExec: func(args []string) error {
			reExecCalled = append([]string(nil), args...)
			return nil
		},
	}

	var stdout, stderr bytes.Buffer
	// Choose option 1 → setup returns 5 → menu prompts y/N → answer y.
	code := runInteractiveMenuWith(strings.NewReader("1\ny\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0 (elevation accepted, child spawned)", code)
	}
	want := []string{"setup", "--skip-update"}
	if !stringSliceEqual(reExecCalled, want) {
		t.Errorf("reExec args = %v, want %v", reExecCalled, want)
	}
	if !strings.Contains(stdout.String(), "Elevated install started") {
		t.Errorf("expected elevation success message, got %q", stdout.String())
	}
}

func TestMenuOption1ElevationPrompt_No(t *testing.T) {
	setup := func(_ []string, _, _ io.Writer) int { return elevate.ExitCodeNeedsElevation }
	deps := menuDeps{
		actions: menuActions{
			setup:            setup,
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		reExec: func(args []string) error {
			t.Errorf("reExec should not be called when user declines")
			return nil
		},
	}

	var stdout, stderr bytes.Buffer
	// Option 1 → setup returns 5 → menu prompts → user types n → then Enter to exit.
	code := runInteractiveMenuWith(strings.NewReader("1\nn\n\n"), &stdout, &stderr, deps)
	if code != elevate.ExitCodeNeedsElevation {
		t.Errorf("exit code %d, want %d (declined)", code, elevate.ExitCodeNeedsElevation)
	}
	if !strings.Contains(stdout.String(), "Skipped") {
		t.Errorf("expected 'Skipped' in stdout, got %q", stdout.String())
	}
}

func TestMenuOption2ElevationPrompt_Yes(t *testing.T) {
	teardown := func(_ []string, _, _ io.Writer) int { return elevate.ExitCodeNeedsElevation }
	var reExecCalled []string
	deps := menuDeps{
		actions: menuActions{
			setup:            failHandler(t),
			teardown:         teardown,
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		reExec: func(args []string) error {
			reExecCalled = append([]string(nil), args...)
			return nil
		},
	}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("2\ny\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	want := []string{"teardown"}
	if !stringSliceEqual(reExecCalled, want) {
		t.Errorf("reExec args = %v, want %v", reExecCalled, want)
	}
}

func TestMenuOption1ElevationReExecFails(t *testing.T) {
	setup := func(_ []string, _, _ io.Writer) int { return elevate.ExitCodeNeedsElevation }
	deps := menuDeps{
		actions: menuActions{
			setup:            setup,
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		reExec: func(args []string) error {
			return fmt.Errorf("user cancelled UAC")
		},
	}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("1\ny\n\n"), &stdout, &stderr, deps)
	if code != 3 {
		t.Errorf("exit code %d, want 3 (re-exec failed)", code)
	}
	if !strings.Contains(stderr.String(), "could not re-launch") {
		t.Errorf("expected re-launch failure in stderr, got %q", stderr.String())
	}
}

func failHandler(t *testing.T) func([]string, io.Writer, io.Writer) int {
	return func(args []string, stdout, stderr io.Writer) int {
		t.Errorf("unexpected handler call")
		return 99
	}
}

func TestMenuBannerShowsDiscoveredPath(t *testing.T) {
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	dcsRoot := t.TempDir()
	if err := os.WriteFile(cfg, []byte(`dcs_install = "`+filepath.ToSlash(dcsRoot)+`"`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	deps := menuDeps{
		actions: menuActions{
			setup:            failHandler(t),
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		configPath: cfg,
	}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("q\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), "DCS install: "+filepath.ToSlash(dcsRoot)) {
		t.Errorf("expected discovered path in banner, got %q", stdout.String())
	}
}

func TestMenuBannerShowsNotDetected(t *testing.T) {
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions: menuActions{
			setup:            failHandler(t),
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		configPath: cfg,
	}

	var stdout, stderr bytes.Buffer
	_ = runInteractiveMenuWith(strings.NewReader("q\n"), &stdout, &stderr, deps)
	if !strings.Contains(stdout.String(), "not detected") {
		t.Errorf("expected 'not detected' in banner, got %q", stdout.String())
	}
}

func makeFakeDCSInstall(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	meDir := filepath.Join(root, "MissionEditor")
	if err := os.MkdirAll(meDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(meDir, "MissionEditor.lua"), []byte("-- stub\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestMenuOption5SavesValidPath(t *testing.T) {
	dcsRoot := makeFakeDCSInstall(t)
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions: menuActions{
			setup:            failHandler(t),
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		configPath: cfg,
	}

	in := "5\n" + dcsRoot + "\nq\n"
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader(in), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), "Saved.") {
		t.Errorf("expected 'Saved.' in stdout, got %q", stdout.String())
	}
	if c := strings.Count(stdout.String(), "DCS install: "+filepath.ToSlash(dcsRoot)); c < 1 {
		t.Errorf("expected banner to show new path after save, got %q", stdout.String())
	}
	data, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), filepath.ToSlash(dcsRoot)) {
		t.Errorf("expected %q in config %q", filepath.ToSlash(dcsRoot), string(data))
	}
}

func TestMenuOption5StripsQuotes(t *testing.T) {
	dcsRoot := makeFakeDCSInstall(t)
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions: menuActions{
			setup:            failHandler(t),
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		configPath: cfg,
	}

	in := "5\n" + `"` + dcsRoot + `"` + "\nq\n"
	var stdout, stderr bytes.Buffer
	_ = runInteractiveMenuWith(strings.NewReader(in), &stdout, &stderr, deps)
	data, _ := os.ReadFile(cfg)
	if strings.Contains(string(data), `\"`) {
		t.Errorf("config should not contain escaped quote literals: %q", string(data))
	}
	if !strings.Contains(string(data), filepath.ToSlash(dcsRoot)) {
		t.Errorf("expected sanitized %q in config %q", filepath.ToSlash(dcsRoot), string(data))
	}
}

func TestMenuOption5RejectsMissingMissionEditor(t *testing.T) {
	bogus := t.TempDir()
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions: menuActions{
			setup:            failHandler(t),
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		configPath: cfg,
	}

	in := "5\n" + bogus + "\n" + bogus + "\nq\n"
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader(in), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), "MissionEditor") {
		t.Errorf("expected error mentioning MissionEditor, got %q", stdout.String())
	}
	if data, err := os.ReadFile(cfg); err == nil && strings.Contains(string(data), bogus) {
		t.Errorf("config should not have been written: %q", string(data))
	}
}

func TestMenuOption5RejectsNonDirectory(t *testing.T) {
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions: menuActions{
			setup:            failHandler(t),
			teardown:         failHandler(t),
			installAISkill:   failHandler(t),
			uninstallAISkill: failHandler(t),
		},
		configPath: cfg,
	}

	bogus := filepath.Join(t.TempDir(), "nope")
	in := "5\n" + bogus + "\n" + bogus + "\nq\n"
	var stdout, stderr bytes.Buffer
	_ = runInteractiveMenuWith(strings.NewReader(in), &stdout, &stderr, deps)
	if !strings.Contains(stdout.String(), "not a directory") &&
		!strings.Contains(stdout.String(), "does not exist") {
		t.Errorf("expected error about missing/invalid directory, got %q", stdout.String())
	}
}

func stringSliceEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
