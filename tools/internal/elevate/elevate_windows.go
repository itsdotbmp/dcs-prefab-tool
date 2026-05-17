//go:build windows

package elevate

import (
	"errors"
	"fmt"
	"os"
	"strings"

	"golang.org/x/sys/windows"
)

const isWindows = true

// IsElevated reports whether the current process has admin privileges.
func IsElevated() bool {
	var token windows.Token
	proc, err := windows.GetCurrentProcess()
	if err != nil {
		return false
	}
	if err := windows.OpenProcessToken(proc, windows.TOKEN_QUERY, &token); err != nil {
		return false
	}
	defer token.Close()
	return token.IsElevated()
}

// ReExecElevated re-launches the current binary with the given args via
// the Windows runas shell verb (triggers UAC). The new process runs in
// its own cmd.exe console which pauses on "Press any key to continue . . ."
// at the end so the user can read the output before the window closes.
// Caller should exit after a successful return.
//
// Returns an error if the user declines UAC (ERROR_CANCELLED) or if
// the ShellExecute call fails for any other reason.
func ReExecElevated(args []string) error {
	exe, err := os.Executable()
	if err != nil {
		return fmt.Errorf("locate running binary: %w", err)
	}
	cmdline := buildElevatedCmdline(exe, args)

	verb, err := windows.UTF16PtrFromString("runas")
	if err != nil {
		return err
	}
	file, err := windows.UTF16PtrFromString("cmd.exe")
	if err != nil {
		return err
	}
	parm, err := windows.UTF16PtrFromString(cmdline)
	if err != nil {
		return err
	}

	// SW_SHOWNORMAL = 1.
	const swShowNormal = 1
	if err := windows.ShellExecute(0, verb, file, parm, nil, swShowNormal); err != nil {
		if errors.Is(err, windows.ERROR_CANCELLED) {
			return errors.New("elevation cancelled by user")
		}
		return fmt.Errorf("ShellExecute runas: %w", err)
	}
	return nil
}

// buildElevatedCmdline composes the /c argument passed to cmd.exe. The
// constructed line invokes exe with args, then prints a blank line, then
// calls pause so the new console window stays open until the user
// acknowledges. Args containing spaces or tabs are wrapped in double
// quotes; other args are passed verbatim.
//
// LIMITATIONS:
//   - Args containing literal '"' characters are NOT escaped. Callers must
//     not pass arguments that contain double-quote characters.
//   - This is not a general shell-quoting function; it specifically
//     targets cmd.exe's /c argument, which has a documented rule that
//     strips the outermost surrounding quotes before parsing the rest.
//     The function relies on that behavior to allow inner per-argument
//     quotes inside the outer /c "..." wrapper.
//
// Extracted to a free function so it can be tested without ShellExecute.
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
