package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
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

func TestMenuBannerShowsDiscoveredPath(t *testing.T) {
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	dcsRoot := t.TempDir()
	if err := os.WriteFile(cfg, []byte(`dcs_install = "`+filepath.ToSlash(dcsRoot)+`"`+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	deps := menuDeps{
		actions:    menuActions{install: failHandler(t), uninstall: failHandler(t), update: failHandler(t)},
		configPath: cfg,
	}

	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader("q\n"), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	// filepath.ToSlash so the comparison works on both Windows and Unix:
	// the config stores forward-slash paths and DiscoverInstall returns them
	// verbatim.
	if !strings.Contains(stdout.String(), "DCS install: "+filepath.ToSlash(dcsRoot)) {
		t.Errorf("expected discovered path in banner, got %q", stdout.String())
	}
}

func TestMenuBannerShowsNotDetected(t *testing.T) {
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml") // does not exist
	deps := menuDeps{
		actions:    menuActions{install: failHandler(t), uninstall: failHandler(t), update: failHandler(t)},
		configPath: cfg,
	}

	var stdout, stderr bytes.Buffer
	_ = runInteractiveMenuWith(strings.NewReader("q\n"), &stdout, &stderr, deps)
	if !strings.Contains(stdout.String(), "not detected") {
		t.Errorf("expected 'not detected' in banner, got %q", stdout.String())
	}
}

// makeFakeDCSInstall creates a tmp dir with MissionEditor/MissionEditor.lua
// in it — a stand-in for a real DCS install root that passes validation.
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

func TestMenuOption4SavesValidPath(t *testing.T) {
	dcsRoot := makeFakeDCSInstall(t)
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions:    menuActions{install: failHandler(t), uninstall: failHandler(t), update: failHandler(t)},
		configPath: cfg,
	}

	// Input: option 4, paste path, then `q`.
	in := "4\n" + dcsRoot + "\nq\n"
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader(in), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), "Saved.") {
		t.Errorf("expected 'Saved.' in stdout, got %q", stdout.String())
	}
	// Banner after save should show the path.
	if c := strings.Count(stdout.String(), "DCS install: "+filepath.ToSlash(dcsRoot)); c < 1 {
		t.Errorf("expected banner to show new path after save, got %q", stdout.String())
	}
	// Config file should now contain the path.
	data, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), filepath.ToSlash(dcsRoot)) {
		t.Errorf("expected %q in config %q", filepath.ToSlash(dcsRoot), string(data))
	}
}

func TestMenuOption4StripsQuotes(t *testing.T) {
	dcsRoot := makeFakeDCSInstall(t)
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions:    menuActions{install: failHandler(t), uninstall: failHandler(t), update: failHandler(t)},
		configPath: cfg,
	}

	in := "4\n" + `"` + dcsRoot + `"` + "\nq\n"
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

func TestMenuOption4RejectsMissingMissionEditor(t *testing.T) {
	bogus := t.TempDir() // dir exists, but no MissionEditor/ in it
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions:    menuActions{install: failHandler(t), uninstall: failHandler(t), update: failHandler(t)},
		configPath: cfg,
	}

	// First attempt: bogus. Second attempt: bogus again. Then `q`.
	in := "4\n" + bogus + "\n" + bogus + "\nq\n"
	var stdout, stderr bytes.Buffer
	code := runInteractiveMenuWith(strings.NewReader(in), &stdout, &stderr, deps)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), "MissionEditor") {
		t.Errorf("expected error mentioning MissionEditor, got %q", stdout.String())
	}
	// Config should be empty / non-existent.
	if data, err := os.ReadFile(cfg); err == nil && strings.Contains(string(data), bogus) {
		t.Errorf("config should not have been written: %q", string(data))
	}
}

func TestMenuOption4RejectsNonDirectory(t *testing.T) {
	cfgDir := t.TempDir()
	cfg := filepath.Join(cfgDir, "config.toml")
	deps := menuDeps{
		actions:    menuActions{install: failHandler(t), uninstall: failHandler(t), update: failHandler(t)},
		configPath: cfg,
	}

	bogus := filepath.Join(t.TempDir(), "nope")
	in := "4\n" + bogus + "\n" + bogus + "\nq\n"
	var stdout, stderr bytes.Buffer
	_ = runInteractiveMenuWith(strings.NewReader(in), &stdout, &stderr, deps)
	if !strings.Contains(stdout.String(), "not a directory") &&
		!strings.Contains(stdout.String(), "does not exist") {
		t.Errorf("expected error about missing/invalid directory, got %q", stdout.String())
	}
}
