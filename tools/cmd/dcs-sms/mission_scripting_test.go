package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestCommentOutSanitizeLines_AllThreeActive(t *testing.T) {
	in := []byte("do\n\tsanitizeModule('os')\n\tsanitizeModule('io')\n\tsanitizeModule('lfs')\n\trequire = nil\nend\n")
	out, changed := commentOutSanitizeLines(in)

	want := "do\n\t-- sanitizeModule('os')  -- dcs-sms\n\t-- sanitizeModule('io')  -- dcs-sms\n\t-- sanitizeModule('lfs')  -- dcs-sms\n\trequire = nil\nend\n"
	if string(out) != want {
		t.Errorf("output:\n  got:  %q\n  want: %q", string(out), want)
	}
	if !stringSliceEqual(changed, []string{"os", "io", "lfs"}) {
		t.Errorf("changed: got %v, want [os io lfs]", changed)
	}
}

func TestCommentOutSanitizeLines_AlreadyCommentedLeftAlone(t *testing.T) {
	in := []byte("-- sanitizeModule('os')\nsanitizeModule('io')\n")
	out, changed := commentOutSanitizeLines(in)
	want := "-- sanitizeModule('os')\n-- sanitizeModule('io')  -- dcs-sms\n"
	if string(out) != want {
		t.Errorf("got %q, want %q", string(out), want)
	}
	if !stringSliceEqual(changed, []string{"io"}) {
		t.Errorf("changed: got %v, want [io]", changed)
	}
}

func TestCommentOutSanitizeLines_Idempotent(t *testing.T) {
	in := []byte("sanitizeModule('os')\nsanitizeModule('io')\n")
	out1, _ := commentOutSanitizeLines(in)
	out2, changed := commentOutSanitizeLines(out1)
	if string(out2) != string(out1) {
		t.Errorf("second pass changed content:\n  first:  %q\n  second: %q", out1, out2)
	}
	if len(changed) != 0 {
		t.Errorf("second pass reported changes: %v", changed)
	}
}

func TestCommentOutSanitizeLines_CRLFPreserved(t *testing.T) {
	in := []byte("sanitizeModule('os')\r\nsanitizeModule('io')\r\n")
	out, _ := commentOutSanitizeLines(in)
	want := "-- sanitizeModule('os')  -- dcs-sms\r\n-- sanitizeModule('io')  -- dcs-sms\r\n"
	if string(out) != want {
		t.Errorf("got %q, want %q", out, want)
	}
}

func TestCommentOutSanitizeLines_DoubleQuotedForm(t *testing.T) {
	in := []byte("sanitizeModule(\"os\")\n")
	out, changed := commentOutSanitizeLines(in)
	if !stringSliceEqual(changed, []string{"os"}) {
		t.Errorf("changed: %v", changed)
	}
	want := "-- sanitizeModule('os')  -- dcs-sms\n"
	if string(out) != want {
		t.Errorf("got %q, want %q (we canonicalise to single quotes)", out, want)
	}
}

func TestRevertTaggedComments_RestoresOriginal(t *testing.T) {
	in := []byte("\t-- sanitizeModule('os')  -- dcs-sms\n\t-- sanitizeModule('io')  -- dcs-sms\n")
	out, reverted := revertTaggedComments(in)
	want := "\tsanitizeModule('os')\n\tsanitizeModule('io')\n"
	if string(out) != want {
		t.Errorf("got %q, want %q", out, want)
	}
	if !stringSliceEqual(reverted, []string{"os", "io"}) {
		t.Errorf("reverted: %v", reverted)
	}
}

func TestRevertTaggedComments_LeavesUntaggedCommentsAlone(t *testing.T) {
	in := []byte("-- sanitizeModule('os')\n-- sanitizeModule('io')  -- dcs-sms\n")
	out, reverted := revertTaggedComments(in)
	want := "-- sanitizeModule('os')\nsanitizeModule('io')\n"
	if string(out) != want {
		t.Errorf("got %q, want %q", out, want)
	}
	if !stringSliceEqual(reverted, []string{"io"}) {
		t.Errorf("reverted: %v", reverted)
	}
}

func TestPatchMissionScripting_CreatesBackupOnFirstPatch(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "MissionScripting.lua")
	original := "sanitizeModule('os')\nsanitizeModule('io')\nsanitizeModule('lfs')\n"
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := patchMissionScripting(path)
	if err != nil {
		t.Fatal(err)
	}
	if !stringSliceEqual(result.Changed, []string{"os", "io", "lfs"}) {
		t.Errorf("changed: %v", result.Changed)
	}
	backup := path + missionScriptingBackupSuffix
	bak, err := os.ReadFile(backup)
	if err != nil {
		t.Fatalf("backup not created: %v", err)
	}
	if string(bak) != original {
		t.Errorf("backup content:\n  got:  %q\n  want: %q", bak, original)
	}
}

func TestPatchMissionScripting_NoOpWhenAlreadyPatched(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "MissionScripting.lua")
	patched := "-- sanitizeModule('os')  -- dcs-sms\n"
	if err := os.WriteFile(path, []byte(patched), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := patchMissionScripting(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Changed) != 0 {
		t.Errorf("expected no changes, got: %v", result.Changed)
	}
	backup := path + missionScriptingBackupSuffix
	if _, err := os.Stat(backup); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("backup should not be created for a no-op patch")
	}
}

func TestPatchMissionScripting_DoesNotOverwriteExistingBackup(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "MissionScripting.lua")
	backup := path + missionScriptingBackupSuffix
	original := "sanitizeModule('os')\n"
	oldBackup := "VERY_OLD_BACKUP_FROM_PREVIOUS_PATCH\n"
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(backup, []byte(oldBackup), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := patchMissionScripting(path); err != nil {
		t.Fatal(err)
	}
	bak, _ := os.ReadFile(backup)
	if string(bak) != oldBackup {
		t.Errorf("backup was overwritten:\n  got:  %q\n  want: %q", bak, oldBackup)
	}
}

func TestPatchMissionScripting_RepatchesAfterDCSRewrite(t *testing.T) {
	// Simulates: first patch happens, then DCS update rewrites
	// MissionScripting.lua back to the unsanitized form, then setup
	// re-runs and re-patches. Backup file should remain unchanged.
	dir := t.TempDir()
	path := filepath.Join(dir, "MissionScripting.lua")
	original := "sanitizeModule('os')\n"
	if err := os.WriteFile(path, []byte(original), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := patchMissionScripting(path); err != nil {
		t.Fatal(err)
	}
	backupAfterFirst, _ := os.ReadFile(path + missionScriptingBackupSuffix)

	// Simulate DCS update overwriting the file with fresh active lines.
	dcsUpdated := "sanitizeModule('os')\nsanitizeModule('io')\n"
	if err := os.WriteFile(path, []byte(dcsUpdated), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := patchMissionScripting(path)
	if err != nil {
		t.Fatal(err)
	}
	if !stringSliceEqual(result.Changed, []string{"os", "io"}) {
		t.Errorf("re-patch changed: %v", result.Changed)
	}
	backupAfterSecond, _ := os.ReadFile(path + missionScriptingBackupSuffix)
	if string(backupAfterFirst) != string(backupAfterSecond) {
		t.Errorf("backup was modified by re-patch:\n  before: %q\n  after:  %q", backupAfterFirst, backupAfterSecond)
	}
}

func TestUnpatchMissionScripting_RevertsAndRemovesBackup(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "MissionScripting.lua")
	backup := path + missionScriptingBackupSuffix
	patched := "-- sanitizeModule('os')  -- dcs-sms\n-- sanitizeModule('io')  -- dcs-sms\n"
	if err := os.WriteFile(path, []byte(patched), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(backup, []byte("dummy"), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := unpatchMissionScripting(path)
	if err != nil {
		t.Fatal(err)
	}
	if !stringSliceEqual(result.Changed, []string{"os", "io"}) {
		t.Errorf("changed: %v", result.Changed)
	}
	content, _ := os.ReadFile(path)
	want := "sanitizeModule('os')\nsanitizeModule('io')\n"
	if string(content) != want {
		t.Errorf("not reverted:\n  got:  %q\n  want: %q", content, want)
	}
	if _, err := os.Stat(backup); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("backup should be removed on uninstall")
	}
}

func TestUnpatchMissionScripting_NoOpWhenUntagged(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "MissionScripting.lua")
	content := "-- sanitizeModule('os')\nsanitizeModule('io')\n" // no dcs-sms tag
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	result, err := unpatchMissionScripting(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Changed) != 0 {
		t.Errorf("expected no changes, got: %v", result.Changed)
	}
	got, _ := os.ReadFile(path)
	if string(got) != content {
		t.Errorf("file modified unexpectedly: %q", got)
	}
}
