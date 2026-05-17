package elevate

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestCanWrite_WritableDir(t *testing.T) {
	dir := t.TempDir()
	if !CanWrite(dir) {
		t.Errorf("CanWrite(%s) = false, want true", dir)
	}
}

func TestCanWrite_NonexistentDir(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "does-not-exist")
	if CanWrite(dir) {
		t.Errorf("CanWrite(%s) = true, want false (dir missing)", dir)
	}
}

func TestCanWrite_FileInsteadOfDir(t *testing.T) {
	f := filepath.Join(t.TempDir(), "f")
	if err := os.WriteFile(f, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if CanWrite(f) {
		t.Errorf("CanWrite(%s) = true, want false (not a dir)", f)
	}
}

func TestCanWrite_ReadOnlyDir(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows: os.Chmod doesn't enforce dir write perms; covered by integration tests")
	}
	if os.Geteuid() == 0 {
		t.Skip("root: ignores directory permissions")
	}
	dir := t.TempDir()
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) }) // restore so t.TempDir cleanup works
	if CanWrite(dir) {
		t.Error("CanWrite = true for read-only dir, want false")
	}
}

func TestExitCodeNeedsElevation(t *testing.T) {
	if ExitCodeNeedsElevation != 5 {
		t.Errorf("ExitCodeNeedsElevation = %d, want 5", ExitCodeNeedsElevation)
	}
}

func TestBuildElevatedCmdline_NoArgs(t *testing.T) {
	got := buildElevatedCmdline("C:\\Tools\\dcs-sms.exe", nil)
	want := `/c "C:\Tools\dcs-sms.exe & echo. & pause"`
	if got != want {
		t.Errorf("buildElevatedCmdline:\n  got  %q\n  want %q", got, want)
	}
}

func TestBuildElevatedCmdline_WithArgs(t *testing.T) {
	got := buildElevatedCmdline("C:\\Tools\\dcs-sms.exe", []string{"setup", "--skip-update"})
	want := `/c "C:\Tools\dcs-sms.exe setup --skip-update & echo. & pause"`
	if got != want {
		t.Errorf("buildElevatedCmdline:\n  got  %q\n  want %q", got, want)
	}
}

func TestBuildElevatedCmdline_QuotesArgsWithSpaces(t *testing.T) {
	got := buildElevatedCmdline("C:\\Tools\\dcs-sms.exe", []string{"setup", "--dcs-path", "D:\\My Games\\DCS World"})
	// cmd.exe /c has a documented rule: if its argument starts and ends
	// with a double quote, it strips that outer pair before parsing the
	// rest. That's what lets the inner "D:\My Games\DCS World" quoting
	// work despite being nested inside the outer /c "..." wrapper.
	// See `cmd /?` and Win32 ShellExecute docs.
	want := `/c "C:\Tools\dcs-sms.exe setup --dcs-path "D:\My Games\DCS World" & echo. & pause"`
	if got != want {
		t.Errorf("buildElevatedCmdline:\n  got  %q\n  want %q", got, want)
	}
}

func TestReExecElevated_NonWindowsReturnsError(t *testing.T) {
	if isWindows {
		t.Skip("Windows: real ReExecElevated would pop UAC")
	}
	err := ReExecElevated([]string{"setup"})
	if err == nil {
		t.Error("ReExecElevated on non-Windows: want error, got nil")
	}
}

func TestIsElevated_NonWindowsAlwaysFalse(t *testing.T) {
	if isWindows {
		t.Skip("Windows: IsElevated depends on actual privileges")
	}
	if IsElevated() {
		t.Error("IsElevated on non-Windows: want false, got true")
	}
}
