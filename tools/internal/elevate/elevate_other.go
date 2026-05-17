//go:build !windows

package elevate

import (
	"errors"
	"strings"
)

const isWindows = false

// IsElevated always returns false on non-Windows. dcs-sms's elevation
// logic is Windows-specific; on Linux/macOS the menu never prompts
// for re-launch.
func IsElevated() bool { return false }

// ReExecElevated is not supported off Windows. Returns a clear error
// so the menu can fall through to "skipped — run from an admin terminal."
func ReExecElevated(args []string) error {
	return errors.New("elevation is only supported on Windows")
}

// buildElevatedCmdline mirrors the Windows shape so the shared test
// passes on every platform. See elevate_windows.go for the full godoc,
// including the documented quoting limitations.
func buildElevatedCmdline(exe string, args []string) string {
	var b strings.Builder
	b.WriteString(`/c "`)
	b.WriteString(exe)
	for _, a := range args {
		b.WriteByte(' ')
		if strings.ContainsAny(a, " \t") {
			b.WriteByte('"')
			b.WriteString(a)
			b.WriteByte('"')
		} else {
			b.WriteString(a)
		}
	}
	b.WriteString(` & echo. & pause"`)
	return b.String()
}
