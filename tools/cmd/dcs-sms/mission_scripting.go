package main

import (
	"errors"
	"fmt"
	"os"
	"regexp"
	"strings"
)

const (
	missionScriptingBackupSuffix = ".dcs-sms.bak"
	missionScriptingTag          = "-- dcs-sms"
)

// activeSanitizeRegex matches an uncommented sanitizeModule('os'|'io'|'lfs')
// line, capturing the leading indentation and the module name.
var activeSanitizeRegex = regexp.MustCompile(`^(\s*)sanitizeModule\s*\(\s*['"](os|io|lfs)['"]\s*\)\s*;?\s*$`)

// taggedCommentRegex matches a line we previously commented out. The
// trailing "-- dcs-sms" tag is what lets uninstall identify our edits and
// revert only those (leaving any other commented-out sanitize lines —
// e.g. commented by hand or by another tool — alone).
var taggedCommentRegex = regexp.MustCompile(`^(\s*)--\s*sanitizeModule\s*\(\s*['"](os|io|lfs)['"]\s*\)\s*;?\s*--\s*dcs-sms\s*$`)

// missionScriptingPatchResult reports which sanitizeModule calls were
// touched. Empty Changed means the file was already in the desired state.
type missionScriptingPatchResult struct {
	Changed []string // module names whose lines were modified, in file order
}

// patchMissionScripting reads path, comments out any active
// sanitizeModule('os'|'io'|'lfs') line we find, and writes the result
// back. Creates a `.dcs-sms.bak` the first time it modifies a previously-
// unmodified file. Idempotent: re-running on an already-patched file
// is a no-op and does NOT touch the backup.
//
// DCS rewrites MissionScripting.lua on game updates, which restores the
// sanitize calls to their active form. The expected workflow is that
// `dcs-sms setup` (which calls this) re-runs after every DCS update.
func patchMissionScripting(path string) (missionScriptingPatchResult, error) {
	var result missionScriptingPatchResult
	src, err := os.ReadFile(path)
	if err != nil {
		return result, err
	}

	patched, changed := commentOutSanitizeLines(src)
	result.Changed = changed
	if len(changed) == 0 {
		return result, nil
	}

	backup := path + missionScriptingBackupSuffix
	if _, err := os.Stat(backup); errors.Is(err, os.ErrNotExist) {
		if err := os.WriteFile(backup, src, 0o644); err != nil {
			return result, fmt.Errorf("write backup: %w", err)
		}
	} else if err != nil {
		return result, fmt.Errorf("stat backup: %w", err)
	}

	if err := os.WriteFile(path, patched, 0o644); err != nil {
		return result, fmt.Errorf("write patched: %w", err)
	}
	return result, nil
}

// unpatchMissionScripting reverts any line that carries our dcs-sms tag,
// restoring the original sanitizeModule(...) form. Other commented-out
// sanitize lines (commented by hand or by other tools) are left alone.
// Best-effort cleanup of the `.dcs-sms.bak` is performed if it exists.
func unpatchMissionScripting(path string) (missionScriptingPatchResult, error) {
	var result missionScriptingPatchResult
	src, err := os.ReadFile(path)
	if err != nil {
		return result, err
	}

	unpatched, reverted := revertTaggedComments(src)
	result.Changed = reverted
	if len(reverted) == 0 {
		// Even with no in-file changes, clear the backup if present —
		// the user is uninstalling and we shouldn't leave stale .bak
		// files behind.
		_ = os.Remove(path + missionScriptingBackupSuffix)
		return result, nil
	}

	if err := os.WriteFile(path, unpatched, 0o644); err != nil {
		return result, fmt.Errorf("write unpatched: %w", err)
	}
	_ = os.Remove(path + missionScriptingBackupSuffix)
	return result, nil
}

// commentOutSanitizeLines walks the lines of src and comments out any
// active sanitizeModule('os'|'io'|'lfs') line, preserving the original
// line ending (CRLF vs LF) on each line individually.
func commentOutSanitizeLines(src []byte) ([]byte, []string) {
	lines := strings.Split(string(src), "\n")
	var changed []string
	for i, line := range lines {
		carryReturn := strings.HasSuffix(line, "\r")
		trimmed := strings.TrimSuffix(line, "\r")
		m := activeSanitizeRegex.FindStringSubmatch(trimmed)
		if m == nil {
			continue
		}
		indent, mod := m[1], m[2]
		newLine := fmt.Sprintf("%s-- sanitizeModule('%s')  %s", indent, mod, missionScriptingTag)
		if carryReturn {
			newLine += "\r"
		}
		lines[i] = newLine
		changed = append(changed, mod)
	}
	return []byte(strings.Join(lines, "\n")), changed
}

// revertTaggedComments walks src and reverts every line that carries
// our dcs-sms tag back to the canonical sanitizeModule('<mod>') form,
// preserving the original line ending on each line.
func revertTaggedComments(src []byte) ([]byte, []string) {
	lines := strings.Split(string(src), "\n")
	var reverted []string
	for i, line := range lines {
		carryReturn := strings.HasSuffix(line, "\r")
		trimmed := strings.TrimSuffix(line, "\r")
		m := taggedCommentRegex.FindStringSubmatch(trimmed)
		if m == nil {
			continue
		}
		indent, mod := m[1], m[2]
		newLine := fmt.Sprintf("%ssanitizeModule('%s')", indent, mod)
		if carryReturn {
			newLine += "\r"
		}
		lines[i] = newLine
		reverted = append(reverted, mod)
	}
	return []byte(strings.Join(lines, "\n")), reverted
}
