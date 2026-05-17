// Package elevate provides Windows UAC helpers used by the dcs-sms CLI
// to detect when an operation needs admin privileges and to re-launch
// the binary elevated. CanWrite works on all platforms; IsElevated and
// ReExecElevated are real on Windows and stubs elsewhere (see
// elevate_windows.go and elevate_other.go).
package elevate

import (
	"os"
)

// ExitCodeNeedsElevation is the dcs-sms-wide exit code returned by any
// subcommand that detected a permission issue it cannot resolve without
// re-launching the process with admin privileges. Documented in
// tools/cmd/dcs-sms/AGENTS.md §4.
const ExitCodeNeedsElevation = 5

// CanWrite reports whether dir is writable by the current process.
// It creates and immediately deletes a hidden temp file in dir.
// Returns false if dir does not exist, is not a directory, or the
// write fails for any reason.
func CanWrite(dir string) bool {
	info, err := os.Stat(dir)
	if err != nil || !info.IsDir() {
		return false
	}
	f, err := os.CreateTemp(dir, ".dcs-sms-probe-*")
	if err != nil {
		return false
	}
	name := f.Name()
	_ = f.Close()
	// Best-effort cleanup. If removal fails we still know the dir was
	// writable, so we don't downgrade the result.
	_ = os.Remove(name)
	return true
}
