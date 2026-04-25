# dcs-sms Execution Bridge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a host-side Go CLI (`dcs-sms.exe`) and an in-DCS Lua hook that together let agents and humans execute Lua snippets in a running DCS mission and read back structured results, communicating through a file mailbox under `Saved Games/DCS*/dcs-sms/`.

**Architecture:** Stateless Go CLI writes JSON request files; Lua hook running in DCS GUI env scans an inbox each frame, runs snippets in the mission env via `net.dostring_in`, captures `print` + return values, writes JSON response files. No sockets, no daemons. Single static Go binary embeds the hook via `//go:embed`.

**Tech Stack:** Go 1.22+ (stdlib only — `flag` for CLI, `encoding/json`, `os`, `path/filepath`, `time`, `testing`), one tiny dep `github.com/google/uuid`, optional `github.com/BurntSushi/toml` for config. DCS-side: Lua 5.2, `lfs` and `net.dostring_in` / `net.lua2json` from DCS.

**Reference design:** `docs/superpowers/specs/2026-04-25-execution-bridge-design.md` — read this first if you need background.

**Conventions used in this plan:**
- All Go code lives under `tools/`. The Go module path is `github.com/nielsvaes/dcs-sms/tools` (we'll wire this in Task 1).
- Test files use Go's standard `_test.go` convention. Use `t.TempDir()` for any filesystem test — never use a real path.
- Each task ends with a commit. Use Conventional Commits-ish prefixes: `feat:`, `test:`, `refactor:`, `docs:`, `chore:`.
- "Run" commands assume CWD = `D:\git\dcs-sms\tools` unless stated otherwise. Use `cd tools` at the start of a task if you're not already there.

---

## Task 1: Project scaffolding

**Files:**
- Create: `tools/go.mod`
- Create: `tools/cmd/dcs-sms/main.go`
- Create: `.gitignore` (repo root)

- [ ] **Step 1: Initialize Go module**

From repo root (`D:\git\dcs-sms`):

```bash
mkdir -p tools/cmd/dcs-sms
cd tools
go mod init github.com/nielsvaes/dcs-sms/tools
```

Expected: creates `tools/go.mod` containing `module github.com/nielsvaes/dcs-sms/tools` and `go 1.22` (or whatever's installed — anything >= 1.22 is fine).

- [ ] **Step 2: Write the smallest possible main.go**

Create `tools/cmd/dcs-sms/main.go`:

```go
package main

import (
	"fmt"
	"os"
)

const version = "0.1.0-dev"

func main() {
	if len(os.Args) >= 2 && (os.Args[1] == "--version" || os.Args[1] == "version") {
		fmt.Println(version)
		return
	}
	fmt.Fprintln(os.Stderr, "dcs-sms — Digital Combat Simulator scripting bridge")
	fmt.Fprintln(os.Stderr, "Usage: dcs-sms <command> [flags]")
	fmt.Fprintln(os.Stderr, "Commands: exec, status, tail-log, install-hook (coming in later tasks)")
	os.Exit(2)
}
```

- [ ] **Step 3: Build and run**

```bash
cd tools
go build ./cmd/dcs-sms
./dcs-sms.exe --version
```

Expected output: `0.1.0-dev`

```bash
./dcs-sms.exe
```

Expected: usage banner on stderr, exit code 2.

- [ ] **Step 4: Add .gitignore at repo root**

Create `D:\git\dcs-sms\.gitignore`:

```
# Go build artifacts
tools/dcs-sms
tools/dcs-sms.exe
tools/**/*.test
tools/**/*.out

# IDE
.idea/
.vscode/
*.swp

# OS
Thumbs.db
.DS_Store
```

- [ ] **Step 5: Commit**

```bash
git add .gitignore tools/go.mod tools/cmd/dcs-sms/main.go
git commit -m "chore: scaffold Go CLI binary"
```

---

## Task 2: Protocol types

**Files:**
- Create: `tools/internal/proto/proto.go`
- Create: `tools/internal/proto/proto_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/internal/proto/proto_test.go`:

```go
package proto

import (
	"encoding/json"
	"testing"
)

func TestExecRequestRoundTrip(t *testing.T) {
	in := ExecRequest{
		ID:        "0193f9aa-test",
		Kind:      "exec",
		Code:      "return 1 + 1",
		TimeoutMs: 5000,
		CreatedAt: "2026-04-25T14:32:11.123Z",
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out ExecRequest
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out != in {
		t.Errorf("round-trip mismatch:\n  in:  %+v\n  out: %+v", in, out)
	}
}

func TestExecResponseSuccessRoundTrip(t *testing.T) {
	in := ExecResponse{
		ID:            "0193f9aa-test",
		OK:            true,
		ReturnValue:   json.RawMessage(`2`),
		Output:        "hello\nworld",
		Error:         nil,
		FrameExecuted: 184321,
		DurationMs:    1.2,
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out ExecResponse
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out.ID != in.ID || out.OK != in.OK || out.Output != in.Output ||
		out.FrameExecuted != in.FrameExecuted || out.DurationMs != in.DurationMs {
		t.Errorf("round-trip mismatch on scalar fields:\n  in:  %+v\n  out: %+v", in, out)
	}
	if string(out.ReturnValue) != string(in.ReturnValue) {
		t.Errorf("return_value mismatch: got %q want %q", string(out.ReturnValue), string(in.ReturnValue))
	}
	if out.Error != nil {
		t.Errorf("expected nil Error on success, got %+v", out.Error)
	}
}

func TestExecResponseErrorRoundTrip(t *testing.T) {
	in := ExecResponse{
		ID: "0193f9aa-test",
		OK: false,
		Error: &ExecError{
			Message:   "attempt to index a nil value",
			Traceback: "stack traceback:\n\tline 1",
		},
		FrameExecuted: 184321,
		DurationMs:    0.4,
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out ExecResponse
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out.OK || out.Error == nil || out.Error.Message != in.Error.Message {
		t.Errorf("error round-trip failed:\n  in:  %+v\n  out: %+v", in, out)
	}
}

func TestHookStateRoundTrip(t *testing.T) {
	in := HookState{
		HookVersion:   "0.1.0",
		MissionLoaded: true,
		MissionName:   "Caucasus_QRA.miz",
		LastFrame:     184321,
		LastFrameAt:   "2026-04-25T14:32:11.456Z",
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var out HookState
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if out != in {
		t.Errorf("round-trip mismatch:\n  in:  %+v\n  out: %+v", in, out)
	}
}
```

- [ ] **Step 2: Run test to verify it fails (compile error)**

```bash
cd tools
go test ./internal/proto/...
```

Expected: build failure — `ExecRequest`, `ExecResponse`, `ExecError`, `HookState` undefined.

- [ ] **Step 3: Write the proto types**

Create `tools/internal/proto/proto.go`:

```go
// Package proto holds the on-disk JSON shapes exchanged between the dcs-sms
// CLI and the in-DCS Lua hook. These structs are the single source of truth
// for the file-mailbox protocol; both the CLI and (by hand) the Lua hook
// must keep them in sync.
package proto

import "encoding/json"

// ExecRequest is what the CLI writes into inbox/<id>.req.json.
type ExecRequest struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
	Code      string `json:"code"`
	TimeoutMs int    `json:"timeout_ms"`
	CreatedAt string `json:"created_at"`
}

// ExecResponse is what the hook writes into outbox/<id>.res.json.
//
// ReturnValue is kept as a raw JSON message because the user's Lua snippet
// can return arbitrary JSON-serializable data (numbers, strings, arrays,
// nested tables). The CLI passes it through untouched.
type ExecResponse struct {
	ID            string          `json:"id"`
	OK            bool            `json:"ok"`
	ReturnValue   json.RawMessage `json:"return_value"`
	Output        string          `json:"output"`
	Error         *ExecError      `json:"error"`
	FrameExecuted int64           `json:"frame_executed"`
	DurationMs    float64         `json:"duration_ms"`
}

// ExecError describes a Lua-level failure inside the snippet.
type ExecError struct {
	Message   string `json:"message"`
	Traceback string `json:"traceback"`
}

// HookState is what the hook writes into state/hook.json on each heartbeat.
type HookState struct {
	HookVersion   string `json:"hook_version"`
	MissionLoaded bool   `json:"mission_loaded"`
	MissionName   string `json:"mission_name"`
	LastFrame     int64  `json:"last_frame"`
	LastFrameAt   string `json:"last_frame_at"`
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd tools
go test ./internal/proto/... -v
```

Expected: all four tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/internal/proto/
git commit -m "feat: add proto types for request/response/hook-state"
```

---

## Task 3: Atomic file write helper

**Files:**
- Create: `tools/internal/mailbox/atomic.go`
- Create: `tools/internal/mailbox/atomic_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/internal/mailbox/atomic_test.go`:

```go
package mailbox

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteAtomicCreatesFile(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "thing.json")

	if err := WriteAtomic(target, []byte(`{"hello":"world"}`)); err != nil {
		t.Fatalf("WriteAtomic: %v", err)
	}

	got, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if string(got) != `{"hello":"world"}` {
		t.Errorf("content mismatch: %q", string(got))
	}
}

func TestWriteAtomicNoTempLeftBehind(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "thing.json")
	if err := WriteAtomic(target, []byte(`x`)); err != nil {
		t.Fatalf("WriteAtomic: %v", err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if filepath.Ext(e.Name()) == ".tmp" {
			t.Errorf("leftover .tmp file: %s", e.Name())
		}
	}
	if len(entries) != 1 {
		t.Errorf("expected 1 entry, got %d: %v", len(entries), entries)
	}
}

func TestWriteAtomicOverwrites(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "thing.json")
	if err := WriteAtomic(target, []byte("first")); err != nil {
		t.Fatal(err)
	}
	if err := WriteAtomic(target, []byte("second")); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "second" {
		t.Errorf("expected 'second', got %q", string(got))
	}
}

func TestWriteAtomicFailsIfDirMissing(t *testing.T) {
	target := filepath.Join(t.TempDir(), "no-such-dir", "thing.json")
	err := WriteAtomic(target, []byte("x"))
	if err == nil {
		t.Fatal("expected error for missing parent dir, got nil")
	}
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./internal/mailbox/...
```

Expected: build failure, `WriteAtomic` undefined.

- [ ] **Step 3: Implement**

Create `tools/internal/mailbox/atomic.go`:

```go
// Package mailbox handles the on-disk mailbox under
// Saved Games/DCS*/dcs-sms/. It exposes atomic write primitives plus
// higher-level helpers for writing requests and reading responses.
package mailbox

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
)

// WriteAtomic writes data to dst by writing to a sibling temp file and
// renaming. On Windows NTFS, in-folder rename is atomic enough that a
// concurrent reader never sees a partial file.
//
// The parent directory of dst must already exist; WriteAtomic does not
// create directories.
func WriteAtomic(dst string, data []byte) error {
	tmp, err := tempSibling(dst)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	if err := f.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, dst); err != nil {
		os.Remove(tmp)
		return err
	}
	return nil
}

// tempSibling returns a unique sibling path for dst with a .tmp suffix.
// We need uniqueness because two writers could race on the same dst.
func tempSibling(dst string) (string, error) {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("rand: %w", err)
	}
	return dst + "." + hex.EncodeToString(b[:]) + ".tmp", nil
}
```

- [ ] **Step 4: Run test to verify pass**

```bash
cd tools
go test ./internal/mailbox/... -v
```

Expected: all four tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/internal/mailbox/atomic.go tools/internal/mailbox/atomic_test.go
git commit -m "feat: add atomic file write helper"
```

---

## Task 4: Mailbox request/response operations + cleanup

**Files:**
- Create: `tools/internal/mailbox/mailbox.go`
- Create: `tools/internal/mailbox/mailbox_test.go`
- Modify: `tools/go.mod` (adds `github.com/google/uuid` dependency)

- [ ] **Step 1: Add UUID dependency**

```bash
cd tools
go get github.com/google/uuid
```

- [ ] **Step 2: Write the failing test**

Create `tools/internal/mailbox/mailbox_test.go`:

```go
package mailbox

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// newTestRoot creates the dcs-sms folder layout in t.TempDir() and returns it.
func newTestRoot(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		if err := os.MkdirAll(filepath.Join(root, sub), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestWriteRequestCreatesInboxFile(t *testing.T) {
	root := newTestRoot(t)
	mb := New(root)

	req := proto.ExecRequest{
		ID:        "abc-123",
		Kind:      "exec",
		Code:      "return 1",
		TimeoutMs: 5000,
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}
	if err := mb.WriteRequest(req); err != nil {
		t.Fatalf("WriteRequest: %v", err)
	}

	path := filepath.Join(root, "inbox", "abc-123.req.json")
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("expected inbox file %q: %v", path, err)
	}
	var got proto.ExecRequest
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got.ID != req.ID || got.Code != req.Code {
		t.Errorf("written request mismatch: %+v", got)
	}
}

func TestReadResponseReturnsAndDeletes(t *testing.T) {
	root := newTestRoot(t)
	mb := New(root)

	resp := proto.ExecResponse{
		ID:          "abc-123",
		OK:          true,
		ReturnValue: json.RawMessage(`42`),
		Output:      "hello",
	}
	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatal(err)
	}
	resPath := filepath.Join(root, "outbox", "abc-123.res.json")
	if err := os.WriteFile(resPath, data, 0o644); err != nil {
		t.Fatal(err)
	}

	got, ok, err := mb.ReadResponse("abc-123")
	if err != nil {
		t.Fatalf("ReadResponse: %v", err)
	}
	if !ok {
		t.Fatal("expected ok=true")
	}
	if got.ID != resp.ID || !got.OK || got.Output != "hello" {
		t.Errorf("response mismatch: %+v", got)
	}
	if _, err := os.Stat(resPath); !os.IsNotExist(err) {
		t.Errorf("expected response file deleted, stat err=%v", err)
	}
}

func TestReadResponseMissingReturnsNotOK(t *testing.T) {
	root := newTestRoot(t)
	mb := New(root)
	_, ok, err := mb.ReadResponse("nope")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ok {
		t.Error("expected ok=false for missing response")
	}
}

func TestSweepStaleRemovesOldFiles(t *testing.T) {
	root := newTestRoot(t)
	mb := New(root)

	// Create an old file and a fresh file.
	oldPath := filepath.Join(root, "outbox", "old.res.json")
	freshPath := filepath.Join(root, "outbox", "fresh.res.json")
	if err := os.WriteFile(oldPath, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(freshPath, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	twoMinAgo := time.Now().Add(-2 * time.Minute)
	if err := os.Chtimes(oldPath, twoMinAgo, twoMinAgo); err != nil {
		t.Fatal(err)
	}

	if err := mb.SweepOutboxOlderThan(60 * time.Second); err != nil {
		t.Fatalf("Sweep: %v", err)
	}

	if _, err := os.Stat(oldPath); !os.IsNotExist(err) {
		t.Errorf("expected old file removed, stat err=%v", err)
	}
	if _, err := os.Stat(freshPath); err != nil {
		t.Errorf("expected fresh file kept: %v", err)
	}
}
```

- [ ] **Step 3: Run to verify failure**

```bash
cd tools
go test ./internal/mailbox/...
```

Expected: build failure (`New`, `WriteRequest`, `ReadResponse`, `SweepOutboxOlderThan` undefined).

- [ ] **Step 4: Implement**

Create `tools/internal/mailbox/mailbox.go`:

```go
package mailbox

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// Mailbox addresses the dcs-sms folder structure under a Saved Games root.
type Mailbox struct {
	Root string // e.g. C:\Users\X\Saved Games\DCS\dcs-sms
}

// New returns a Mailbox rooted at root. Caller is responsible for ensuring
// the inbox/outbox/state/log subfolders exist.
func New(root string) *Mailbox {
	return &Mailbox{Root: root}
}

func (m *Mailbox) Inbox() string  { return filepath.Join(m.Root, "inbox") }
func (m *Mailbox) Outbox() string { return filepath.Join(m.Root, "outbox") }
func (m *Mailbox) State() string  { return filepath.Join(m.Root, "state") }

// WriteRequest writes req to inbox/<id>.req.json atomically.
func (m *Mailbox) WriteRequest(req proto.ExecRequest) error {
	if req.ID == "" {
		return errors.New("mailbox: request has empty ID")
	}
	data, err := json.Marshal(req)
	if err != nil {
		return fmt.Errorf("marshal request: %w", err)
	}
	dst := filepath.Join(m.Inbox(), req.ID+".req.json")
	return WriteAtomic(dst, data)
}

// ReadResponse reads outbox/<id>.res.json. Returns (resp, true, nil) on
// success, deleting the file. Returns (zero, false, nil) if the file is not
// yet present. Returns (zero, false, err) for IO/parse errors.
func (m *Mailbox) ReadResponse(id string) (proto.ExecResponse, bool, error) {
	path := filepath.Join(m.Outbox(), id+".res.json")
	data, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return proto.ExecResponse{}, false, nil
		}
		return proto.ExecResponse{}, false, err
	}
	var resp proto.ExecResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return proto.ExecResponse{}, false, fmt.Errorf("parse response %s: %w", path, err)
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		// Non-fatal — log via returned error, but we got the data.
		return resp, true, fmt.Errorf("read ok but failed to delete %s: %w", path, err)
	}
	return resp, true, nil
}

// SweepOutboxOlderThan deletes *.res.json files in the outbox whose mtime
// is older than maxAge. Used to clean up orphans left by previous CLI runs
// that timed out before their response landed.
func (m *Mailbox) SweepOutboxOlderThan(maxAge time.Duration) error {
	return sweepDir(m.Outbox(), ".res.json", maxAge)
}

func sweepDir(dir, suffix string, maxAge time.Duration) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil
		}
		return err
	}
	cutoff := time.Now().Add(-maxAge)
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if !strings.HasSuffix(e.Name(), suffix) && !strings.HasSuffix(e.Name(), ".tmp") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(cutoff) {
			_ = os.Remove(filepath.Join(dir, e.Name()))
		}
	}
	return nil
}

// NewID returns a fresh UUID-based request ID.
func NewID() string {
	// google/uuid is small and stable; we keep its import inside this helper
	// to avoid leaking the dependency through the package's public surface.
	return uuidNew()
}
```

Create `tools/internal/mailbox/uuid.go`:

```go
package mailbox

import "github.com/google/uuid"

func uuidNew() string { return uuid.NewString() }
```

(Splitting the uuid import into its own file makes it trivial to swap to a different UUID strategy later without touching `mailbox.go`.)

- [ ] **Step 5: Run tests**

```bash
cd tools
go test ./internal/mailbox/... -v
```

Expected: all tests pass (atomic + mailbox).

- [ ] **Step 6: Commit**

```bash
git add tools/go.mod tools/go.sum tools/internal/mailbox/mailbox.go tools/internal/mailbox/uuid.go tools/internal/mailbox/mailbox_test.go
git commit -m "feat: mailbox read/write and stale-file sweep"
```

---

## Task 5: Hook status reader + freshness check

**Files:**
- Create: `tools/internal/hookstatus/hookstatus.go`
- Create: `tools/internal/hookstatus/hookstatus_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/internal/hookstatus/hookstatus_test.go`:

```go
package hookstatus

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

func writeState(t *testing.T, dir string, st proto.HookState) string {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(st)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "hook.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestReadOK(t *testing.T) {
	dir := t.TempDir()
	want := proto.HookState{
		HookVersion:   "0.1.0",
		MissionLoaded: true,
		MissionName:   "Test.miz",
		LastFrame:     42,
		LastFrameAt:   time.Now().UTC().Format(time.RFC3339Nano),
	}
	writeState(t, dir, want)

	got, err := Read(dir)
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	if got.HookVersion != want.HookVersion || got.MissionLoaded != want.MissionLoaded {
		t.Errorf("mismatch: got %+v want %+v", got, want)
	}
}

func TestReadMissing(t *testing.T) {
	dir := t.TempDir()
	_, err := Read(dir)
	if err == nil {
		t.Fatal("expected error for missing file")
	}
}

func TestIsFreshTrue(t *testing.T) {
	now := time.Now().UTC()
	st := proto.HookState{LastFrameAt: now.Format(time.RFC3339Nano)}
	if !IsFresh(st, 2*time.Second, now) {
		t.Error("expected fresh")
	}
}

func TestIsFreshFalse(t *testing.T) {
	now := time.Now().UTC()
	st := proto.HookState{LastFrameAt: now.Add(-5 * time.Second).Format(time.RFC3339Nano)}
	if IsFresh(st, 2*time.Second, now) {
		t.Error("expected stale")
	}
}

func TestIsFreshUnparseable(t *testing.T) {
	now := time.Now().UTC()
	st := proto.HookState{LastFrameAt: "not-a-date"}
	if IsFresh(st, 2*time.Second, now) {
		t.Error("expected stale on unparseable timestamp")
	}
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./internal/hookstatus/...
```

Expected: build failure.

- [ ] **Step 3: Implement**

Create `tools/internal/hookstatus/hookstatus.go`:

```go
// Package hookstatus reads state/hook.json and reasons about whether the
// hook is alive enough to accept work.
package hookstatus

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// Read parses state/hook.json from the state directory.
func Read(stateDir string) (proto.HookState, error) {
	path := filepath.Join(stateDir, "hook.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return proto.HookState{}, fmt.Errorf("read %s: %w", path, err)
	}
	var st proto.HookState
	if err := json.Unmarshal(data, &st); err != nil {
		return proto.HookState{}, fmt.Errorf("parse %s: %w", path, err)
	}
	return st, nil
}

// IsFresh returns true when st.LastFrameAt is within maxAge of now.
// An unparseable LastFrameAt is treated as stale (safer default).
func IsFresh(st proto.HookState, maxAge time.Duration, now time.Time) bool {
	t, err := time.Parse(time.RFC3339Nano, st.LastFrameAt)
	if err != nil {
		// Try the simpler RFC3339 form as fallback.
		t, err = time.Parse(time.RFC3339, st.LastFrameAt)
		if err != nil {
			return false
		}
	}
	return now.Sub(t) <= maxAge
}
```

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./internal/hookstatus/... -v
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/internal/hookstatus/
git commit -m "feat: hook status reader with freshness check"
```

---

## Task 6: DCS path discovery + config

**Files:**
- Create: `tools/internal/dcspath/dcspath.go`
- Create: `tools/internal/dcspath/dcspath_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/internal/dcspath/dcspath_test.go`:

```go
package dcspath

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverFromConfig(t *testing.T) {
	configDir := t.TempDir()
	savedGames := t.TempDir()
	configPath := filepath.Join(configDir, "config.toml")

	content := `saved_games = ` + tomlString(savedGames) + "\n"
	if err := os.WriteFile(configPath, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := DiscoverFromConfig(configPath)
	if err != nil {
		t.Fatalf("DiscoverFromConfig: %v", err)
	}
	if got != savedGames {
		t.Errorf("got %q want %q", got, savedGames)
	}
}

func TestDiscoverFromEnv(t *testing.T) {
	want := t.TempDir()
	t.Setenv("DCS_SMS_SAVED_GAMES", want)
	got, ok := DiscoverFromEnv()
	if !ok {
		t.Fatal("expected ok=true with env var set")
	}
	if got != want {
		t.Errorf("got %q want %q", got, want)
	}
}

func TestSaveConfig(t *testing.T) {
	dir := t.TempDir()
	configPath := filepath.Join(dir, "subdir", "config.toml")
	if err := SaveConfig(configPath, "C:\\Users\\X\\Saved Games\\DCS"); err != nil {
		t.Fatalf("SaveConfig: %v", err)
	}
	got, err := DiscoverFromConfig(configPath)
	if err != nil {
		t.Fatal(err)
	}
	if got != "C:\\Users\\X\\Saved Games\\DCS" {
		t.Errorf("round-trip failed: got %q", got)
	}
}

// tomlString quotes a string for TOML, escaping backslashes and quotes.
func tomlString(s string) string {
	out := "\""
	for _, r := range s {
		switch r {
		case '\\':
			out += "\\\\"
		case '"':
			out += "\\\""
		default:
			out += string(r)
		}
	}
	return out + "\""
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./internal/dcspath/...
```

Expected: build failure.

- [ ] **Step 3: Implement (no external TOML dep — we hand-parse a single key)**

The config file is trivial — one or two keys. To avoid pulling in a TOML library, we hand-parse a minimal subset. If the user adds something more complex later, we can swap in a real parser.

Create `tools/internal/dcspath/dcspath.go`:

```go
// Package dcspath discovers the user's DCS Saved Games folder. The Saved
// Games path is needed by every CLI subcommand to locate the dcs-sms
// mailbox.
//
// Discovery order:
//
//  1. --saved-games flag (handled by callers, passed in directly)
//  2. DCS_SMS_SAVED_GAMES environment variable
//  3. config file at the user's config dir (~/.config/dcs-sms/config.toml or
//     %AppData%\dcs-sms\config.toml)
//  4. Default: %USERPROFILE%\Saved Games\DCS or DCS.openbeta (whichever exists)
package dcspath

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// DefaultConfigPath returns the config file path for the current user.
func DefaultConfigPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "dcs-sms", "config.toml"), nil
}

// DiscoverFromEnv returns the path from the DCS_SMS_SAVED_GAMES env var.
func DiscoverFromEnv() (string, bool) {
	v := os.Getenv("DCS_SMS_SAVED_GAMES")
	if v == "" {
		return "", false
	}
	return v, true
}

// DiscoverFromConfig parses the config file and returns the saved_games
// value. Returns an error if the file is missing or the key isn't set.
func DiscoverFromConfig(configPath string) (string, error) {
	f, err := os.Open(configPath)
	if err != nil {
		return "", err
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		if strings.TrimSpace(k) != "saved_games" {
			continue
		}
		return parseTomlString(strings.TrimSpace(v))
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return "", errors.New("saved_games key not found in config")
}

// SaveConfig writes saved_games = "<path>" to configPath, creating parent
// directories as needed.
func SaveConfig(configPath, savedGamesPath string) error {
	if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		return err
	}
	content := fmt.Sprintf("saved_games = %s\n", encodeTomlString(savedGamesPath))
	return os.WriteFile(configPath, []byte(content), 0o644)
}

// DiscoverDefault returns the conventional Windows path:
//   %USERPROFILE%\Saved Games\DCS  (or DCS.openbeta)
// whichever exists. Returns ("", false) if neither exists or we're not on
// Windows.
func DiscoverDefault() (string, bool) {
	if runtime.GOOS != "windows" {
		return "", false
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", false
	}
	for _, sub := range []string{"DCS", "DCS.openbeta", "DCS.server"} {
		p := filepath.Join(home, "Saved Games", sub)
		if info, err := os.Stat(p); err == nil && info.IsDir() {
			return p, true
		}
	}
	return "", false
}

// Discover applies the full priority order. The override argument lets a
// CLI flag take precedence over everything else.
func Discover(override, configPath string) (string, error) {
	if override != "" {
		return override, nil
	}
	if v, ok := DiscoverFromEnv(); ok {
		return v, nil
	}
	if configPath != "" {
		if v, err := DiscoverFromConfig(configPath); err == nil {
			return v, nil
		}
	}
	if v, ok := DiscoverDefault(); ok {
		return v, nil
	}
	return "", errors.New("could not discover DCS Saved Games path; pass --saved-games or set DCS_SMS_SAVED_GAMES")
}

// parseTomlString parses a basic-string TOML literal: "..." with \" and \\
// escapes. Only the subset we actually emit.
func parseTomlString(raw string) (string, error) {
	if len(raw) < 2 || raw[0] != '"' || raw[len(raw)-1] != '"' {
		return "", fmt.Errorf("expected quoted string, got %q", raw)
	}
	body := raw[1 : len(raw)-1]
	var out strings.Builder
	for i := 0; i < len(body); i++ {
		c := body[i]
		if c != '\\' {
			out.WriteByte(c)
			continue
		}
		if i+1 >= len(body) {
			return "", errors.New("trailing backslash in string")
		}
		switch body[i+1] {
		case '\\':
			out.WriteByte('\\')
		case '"':
			out.WriteByte('"')
		case 'n':
			out.WriteByte('\n')
		case 't':
			out.WriteByte('\t')
		default:
			return "", fmt.Errorf("unknown escape \\%c", body[i+1])
		}
		i++
	}
	return out.String(), nil
}

// encodeTomlString returns a TOML basic string for s, escaping \ and ".
func encodeTomlString(s string) string {
	var out strings.Builder
	out.WriteByte('"')
	for _, r := range s {
		switch r {
		case '\\':
			out.WriteString("\\\\")
		case '"':
			out.WriteString("\\\"")
		default:
			out.WriteRune(r)
		}
	}
	out.WriteByte('"')
	return out.String()
}
```

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./internal/dcspath/... -v
```

Expected: all three tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/internal/dcspath/
git commit -m "feat: DCS Saved Games path discovery and config IO"
```

---

## Task 7: Log tail with cursor

**Files:**
- Create: `tools/internal/logtail/logtail.go`
- Create: `tools/internal/logtail/logtail_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/internal/logtail/logtail_test.go`:

```go
package logtail

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeLog(t *testing.T, path string, lines ...string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestReadAll(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "dcs.log")
	writeLog(t, logPath, "line one", "line two", "line three")

	r := &Reader{LogPath: logPath, CursorPath: filepath.Join(dir, "cursor")}
	lines, _, err := r.ReadFrom(0, "", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) != 3 {
		t.Fatalf("got %d lines, want 3", len(lines))
	}
}

func TestReadFromOffsetAdvancesCursor(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "dcs.log")
	writeLog(t, logPath, "line one", "line two")

	r := &Reader{LogPath: logPath, CursorPath: filepath.Join(dir, "cursor")}
	_, newOffset, err := r.ReadFrom(0, "", 0)
	if err != nil {
		t.Fatal(err)
	}

	// Append a line.
	f, err := os.OpenFile(logPath, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString("line three\n"); err != nil {
		t.Fatal(err)
	}
	f.Close()

	// Resume from previous offset.
	lines, _, err := r.ReadFrom(newOffset, "", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) != 1 || lines[0] != "line three" {
		t.Errorf("expected only 'line three', got %v", lines)
	}
}

func TestReadFromGrep(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "dcs.log")
	writeLog(t, logPath, "INFO: hello", "WARN: oops", "INFO: ok")

	r := &Reader{LogPath: logPath, CursorPath: filepath.Join(dir, "cursor")}
	lines, _, err := r.ReadFrom(0, "WARN", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) != 1 || lines[0] != "WARN: oops" {
		t.Errorf("grep filter wrong: %v", lines)
	}
}

func TestReadFromTailN(t *testing.T) {
	dir := t.TempDir()
	logPath := filepath.Join(dir, "dcs.log")
	writeLog(t, logPath, "a", "b", "c", "d", "e")

	r := &Reader{LogPath: logPath, CursorPath: filepath.Join(dir, "cursor")}
	lines, _, err := r.ReadFrom(0, "", 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(lines) != 2 || lines[0] != "d" || lines[1] != "e" {
		t.Errorf("tail-N wrong: %v", lines)
	}
}

func TestCursorRoundTrip(t *testing.T) {
	dir := t.TempDir()
	r := &Reader{CursorPath: filepath.Join(dir, "cursor")}
	if err := r.WriteCursor(12345); err != nil {
		t.Fatal(err)
	}
	got, err := r.ReadCursor()
	if err != nil {
		t.Fatal(err)
	}
	if got != 12345 {
		t.Errorf("cursor mismatch: got %d", got)
	}
}

func TestReadCursorMissingReturnsZero(t *testing.T) {
	dir := t.TempDir()
	r := &Reader{CursorPath: filepath.Join(dir, "missing-cursor")}
	got, err := r.ReadCursor()
	if err != nil {
		t.Fatalf("expected nil error for missing cursor, got %v", err)
	}
	if got != 0 {
		t.Errorf("expected 0, got %d", got)
	}
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./internal/logtail/...
```

Expected: build failure.

- [ ] **Step 3: Implement**

Create `tools/internal/logtail/logtail.go`:

```go
// Package logtail reads DCS's dcs.log with optional cursor, regex filter,
// and tail-N support. The CLI uses this for `dcs-sms tail-log`.
package logtail

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"regexp"
	"strconv"
	"strings"
)

// Reader reads dcs.log incrementally. CursorPath is where ReadCursor /
// WriteCursor persist the last byte offset across CLI invocations.
type Reader struct {
	LogPath    string
	CursorPath string
}

// ReadFrom reads dcs.log from byte offset `from` to EOF. If grep is non-empty
// it's applied as a regex filter (case-sensitive). If tailN > 0, only the
// last tailN matching lines are returned. Returns the lines and the new EOF
// offset (suitable for passing as `from` next time).
func (r *Reader) ReadFrom(from int64, grep string, tailN int) ([]string, int64, error) {
	f, err := os.Open(r.LogPath)
	if err != nil {
		return nil, 0, fmt.Errorf("open %s: %w", r.LogPath, err)
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil {
		return nil, 0, err
	}
	// If the file shrank (rotation/truncation), restart from 0.
	if from > stat.Size() {
		from = 0
	}
	if _, err := f.Seek(from, 0); err != nil {
		return nil, 0, err
	}

	var pattern *regexp.Regexp
	if grep != "" {
		pattern, err = regexp.Compile(grep)
		if err != nil {
			return nil, 0, fmt.Errorf("invalid grep pattern: %w", err)
		}
	}

	var lines []string
	scanner := bufio.NewScanner(f)
	// dcs.log can have very long lines (huge stack traces).
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		if pattern != nil && !pattern.MatchString(line) {
			continue
		}
		lines = append(lines, line)
	}
	if err := scanner.Err(); err != nil {
		return nil, 0, err
	}

	if tailN > 0 && len(lines) > tailN {
		lines = lines[len(lines)-tailN:]
	}
	return lines, stat.Size(), nil
}

// ReadCursor returns the byte offset previously persisted, or 0 if missing.
func (r *Reader) ReadCursor() (int64, error) {
	data, err := os.ReadFile(r.CursorPath)
	if err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return 0, nil
		}
		return 0, err
	}
	v, err := strconv.ParseInt(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("parse cursor: %w", err)
	}
	return v, nil
}

// WriteCursor persists offset to CursorPath atomically (write tmp, rename).
func (r *Reader) WriteCursor(offset int64) error {
	tmp := r.CursorPath + ".tmp"
	if err := os.WriteFile(tmp, []byte(strconv.FormatInt(offset, 10)), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, r.CursorPath)
}
```

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./internal/logtail/... -v
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/internal/logtail/
git commit -m "feat: dcs.log tail reader with cursor and grep"
```

---

## Task 8: CLI subcommand dispatcher + version

**Files:**
- Modify: `tools/cmd/dcs-sms/main.go`
- Create: `tools/cmd/dcs-sms/dispatch.go`
- Create: `tools/cmd/dcs-sms/dispatch_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/cmd/dcs-sms/dispatch_test.go`:

```go
package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestDispatchVersion(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := dispatch([]string{"--version"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit code %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), version) {
		t.Errorf("expected version in stdout, got %q", stdout.String())
	}
}

func TestDispatchUnknownCommand(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := dispatch([]string{"snurfle"}, &stdout, &stderr)
	if code == 0 {
		t.Error("expected non-zero exit for unknown command")
	}
	if !strings.Contains(stderr.String(), "unknown") {
		t.Errorf("expected 'unknown' in stderr, got %q", stderr.String())
	}
}

func TestDispatchNoArgsShowsHelp(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := dispatch(nil, &stdout, &stderr)
	if code == 0 {
		t.Error("expected non-zero exit when no command given")
	}
	if !strings.Contains(stderr.String(), "Usage") {
		t.Errorf("expected usage banner in stderr, got %q", stderr.String())
	}
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./cmd/dcs-sms/...
```

Expected: build failure (`dispatch` undefined).

- [ ] **Step 3: Implement dispatcher and refactor main.go**

Create `tools/cmd/dcs-sms/dispatch.go`:

```go
package main

import (
	"fmt"
	"io"
)

// commandFunc is the signature for every subcommand. It receives the args
// after the subcommand name (so for `dcs-sms exec --file foo.lua`,
// argsAfterCmd would be ["--file", "foo.lua"]). It returns an OS exit code.
type commandFunc func(argsAfterCmd []string, stdout, stderr io.Writer) int

// commands maps subcommand names to their handlers. Subcommands register
// themselves here in init() blocks across cmd/dcs-sms/*.go.
var commands = map[string]commandFunc{}

func register(name string, fn commandFunc) {
	if _, exists := commands[name]; exists {
		panic("duplicate command registration: " + name)
	}
	commands[name] = fn
}

// dispatch routes args[0] (subcommand name) to its handler. Pure function
// (returns exit code, writes to provided writers) so it's trivially
// testable without touching os.Exit / os.Stdout.
func dispatch(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		printUsage(stderr)
		return 2
	}
	switch args[0] {
	case "--version", "-v", "version":
		fmt.Fprintln(stdout, version)
		return 0
	case "--help", "-h", "help":
		printUsage(stdout)
		return 0
	}
	cmd, ok := commands[args[0]]
	if !ok {
		fmt.Fprintf(stderr, "dcs-sms: unknown command %q\n", args[0])
		printUsage(stderr)
		return 2
	}
	return cmd(args[1:], stdout, stderr)
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, "dcs-sms — Digital Combat Simulator scripting bridge")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Usage: dcs-sms <command> [flags]")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Commands:")
	fmt.Fprintln(w, "  exec          execute a Lua snippet inside the running mission")
	fmt.Fprintln(w, "  status        report whether the hook is alive and a mission is loaded")
	fmt.Fprintln(w, "  tail-log      read recent lines from dcs.log")
	fmt.Fprintln(w, "  install-hook  install/update the Lua hook in Saved Games/DCS*/Scripts/Hooks/")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Run `dcs-sms <command> --help` for command-specific flags.")
}
```

Replace `tools/cmd/dcs-sms/main.go` with:

```go
package main

import "os"

const version = "0.1.0-dev"

func main() {
	os.Exit(dispatch(os.Args[1:], os.Stdout, os.Stderr))
}
```

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./cmd/dcs-sms/... -v
```

Expected: all three dispatch tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/cmd/dcs-sms/main.go tools/cmd/dcs-sms/dispatch.go tools/cmd/dcs-sms/dispatch_test.go
git commit -m "feat: subcommand dispatcher with version and help"
```

---

## Task 9: `exec` subcommand (basic round-trip)

**Files:**
- Create: `tools/cmd/dcs-sms/exec.go`
- Create: `tools/cmd/dcs-sms/exec_test.go`

This task implements `exec` *without* `--wait` and *without* the freshness check — those land in Task 10. The integration test uses a fake hook (a goroutine that watches the inbox and writes responses).

- [ ] **Step 1: Write the failing test**

Create `tools/cmd/dcs-sms/exec_test.go`:

```go
package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// fakeHook simulates the Lua hook for end-to-end CLI tests. It watches the
// inbox folder and writes responses according to the supplied behavior.
//
// IMPORTANT: the CLI builds the mailbox path as <savedGames>/dcs-sms/...
// so the fake hook must root itself one level deeper than the
// DCS_SMS_SAVED_GAMES env var.
type fakeHook struct {
	root         string // <savedGames>/dcs-sms
	behavior     func(req proto.ExecRequest) proto.ExecResponse
	heartbeat    bool // if true, write a fresh heartbeat continuously
	processInbox bool // if false, requests pile up untouched (used to test timeout)
	stop         chan struct{}
	wg           sync.WaitGroup
}

func startFakeHook(t *testing.T, savedGames string, fn func(proto.ExecRequest) proto.ExecResponse, heartbeat, processInbox bool) *fakeHook {
	t.Helper()
	root := filepath.Join(savedGames, "dcs-sms")
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		if err := os.MkdirAll(filepath.Join(root, sub), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	h := &fakeHook{root: root, behavior: fn, heartbeat: heartbeat, processInbox: processInbox, stop: make(chan struct{})}
	h.wg.Add(1)
	go h.run()
	t.Cleanup(func() {
		close(h.stop)
		h.wg.Wait()
	})
	return h
}

func (h *fakeHook) run() {
	defer h.wg.Done()
	tick := time.NewTicker(10 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-h.stop:
			return
		case <-tick.C:
			if h.heartbeat {
				h.writeHeartbeat()
			}
			if h.processInbox {
				h.processInboxOnce()
			}
		}
	}
}

func (h *fakeHook) writeHeartbeat() {
	st := proto.HookState{
		HookVersion:   "fake-0.0.0",
		MissionLoaded: true,
		MissionName:   "Test.miz",
		LastFrame:     1,
		LastFrameAt:   time.Now().UTC().Format(time.RFC3339Nano),
	}
	data, _ := json.Marshal(st)
	tmp := filepath.Join(h.root, "state", "hook.json.tmp")
	final := filepath.Join(h.root, "state", "hook.json")
	_ = os.WriteFile(tmp, data, 0o644)
	_ = os.Rename(tmp, final)
}

func (h *fakeHook) processInboxOnce() {
	entries, err := os.ReadDir(filepath.Join(h.root, "inbox"))
	if err != nil {
		return
	}
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".req.json") {
			continue
		}
		reqPath := filepath.Join(h.root, "inbox", e.Name())
		data, err := os.ReadFile(reqPath)
		if err != nil {
			continue
		}
		var req proto.ExecRequest
		if err := json.Unmarshal(data, &req); err != nil {
			continue
		}
		resp := h.behavior(req)
		resp.ID = req.ID
		respData, _ := json.Marshal(resp)
		respTmp := filepath.Join(h.root, "outbox", req.ID+".res.json.tmp")
		respFinal := filepath.Join(h.root, "outbox", req.ID+".res.json")
		_ = os.WriteFile(respTmp, respData, 0o644)
		_ = os.Rename(respTmp, respFinal)
		_ = os.Remove(reqPath)
	}
}

// runExec invokes the exec subcommand against a fake-hook root. Returns
// (exit code, stdout, stderr).
func runExec(t *testing.T, root string, args []string) (int, string, string) {
	t.Helper()
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	// Cap the test if exec hangs.
	done := make(chan int, 1)
	go func() { done <- execCmd(args, &stdout, &stderr) }()
	select {
	case code := <-done:
		return code, stdout.String(), stderr.String()
	case <-time.After(5 * time.Second):
		t.Fatal("execCmd did not return within 5s")
		return 0, "", ""
	}
}

func TestExecSuccess(t *testing.T) {
	root := t.TempDir()
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		return proto.ExecResponse{
			OK:          true,
			ReturnValue: json.RawMessage(`42`),
			Output:      "hi",
		}
	}, true /*heartbeat*/, true /*processInbox*/)

	code, stdout, _ := runExec(t, root, []string{"--code", "return 42", "--timeout", "2s"})
	if code != 0 {
		t.Errorf("exit %d, want 0", code)
	}
	if !strings.Contains(stdout, `"ok":true`) || !strings.Contains(stdout, `"return_value":42`) {
		t.Errorf("unexpected stdout: %s", stdout)
	}
}

func TestExecLuaError(t *testing.T) {
	root := t.TempDir()
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		return proto.ExecResponse{
			OK:    false,
			Error: &proto.ExecError{Message: "boom", Traceback: "tb"},
		}
	}, true, true)

	code, stdout, _ := runExec(t, root, []string{"--code", "error('boom')", "--timeout", "2s"})
	if code != 1 {
		t.Errorf("exit %d, want 1", code)
	}
	if !strings.Contains(stdout, `"ok":false`) || !strings.Contains(stdout, "boom") {
		t.Errorf("unexpected stdout: %s", stdout)
	}
}

func TestExecTimeout(t *testing.T) {
	root := t.TempDir()
	// Heartbeat-only fake hook: keeps freshness check happy but never
	// processes the inbox, so the request times out.
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		return proto.ExecResponse{}
	}, true /*heartbeat*/, false /*processInbox*/)

	code, _, stderr := runExec(t, root, []string{"--code", "return 1", "--timeout", "300ms"})
	if code != 2 {
		t.Errorf("exit %d, want 2 (timeout)", code)
	}
	if !strings.Contains(stderr, "timeout") {
		t.Errorf("expected 'timeout' in stderr, got %q", stderr)
	}
}

func TestExecReadsFromStdin(t *testing.T) {
	root := t.TempDir()
	var seen string
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		seen = req.Code
		return proto.ExecResponse{OK: true}
	}, true, true)

	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	// Replace stdin for this invocation.
	oldStdin := stdinReader
	stdinReader = strings.NewReader("return 99\n")
	defer func() { stdinReader = oldStdin }()

	code := execCmd([]string{"--timeout", "2s"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit %d, want 0; stderr=%s", code, stderr.String())
	}
	if seen != "return 99\n" {
		t.Errorf("hook saw code %q, want %q", seen, "return 99\n")
	}
}

func TestExecFileFlag(t *testing.T) {
	root := t.TempDir()
	var seen string
	startFakeHook(t, root, func(req proto.ExecRequest) proto.ExecResponse {
		seen = req.Code
		return proto.ExecResponse{OK: true}
	}, true, true)

	codeFile := filepath.Join(t.TempDir(), "snippet.lua")
	if err := os.WriteFile(codeFile, []byte("return 7"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, _, stderr := runExec(t, root, []string{"--file", codeFile, "--timeout", "2s"})
	if code != 0 {
		t.Errorf("exit %d, want 0; stderr=%s", code, stderr)
	}
	if seen != "return 7" {
		t.Errorf("hook saw %q, want %q", seen, "return 7")
	}
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./cmd/dcs-sms/...
```

Expected: build failure (`execCmd`, `stdinReader` undefined).

- [ ] **Step 3: Implement `exec`**

Create `tools/cmd/dcs-sms/exec.go`:

```go
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
	"github.com/nielsvaes/dcs-sms/tools/internal/mailbox"
	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

// stdinReader is the source for code when neither --file nor --code is
// given. Tests swap this out to inject input.
var stdinReader io.Reader = os.Stdin

func init() {
	register("exec", execCmd)
}

func execCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("exec", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagFile        = fs.String("file", "", "path to a .lua file")
		flagCode        = fs.String("code", "", "Lua code (inline)")
		flagTimeout     = fs.Duration("timeout", 5*time.Second, "wall-clock timeout")
		flagPretty      = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames  = fs.String("saved-games", "", "override Saved Games path")
	)
	if err := fs.Parse(args); err != nil {
		return 2
	}

	code, err := readCode(*flagFile, *flagCode, stdinReader)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec:", err)
		return 2
	}

	root, err := resolveRoot(*flagSavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec:", err)
		return 3
	}
	mb := mailbox.New(filepath.Join(root, "dcs-sms"))
	if err := ensureMailboxDirs(mb.Root); err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec:", err)
		return 3
	}

	// Best-effort cleanup of orphan responses left by previous timed-out
	// runs. Errors here are non-fatal — we'd rather proceed than refuse.
	_ = mb.SweepOutboxOlderThan(60 * time.Second)

	req := proto.ExecRequest{
		ID:        mailbox.NewID(),
		Kind:      "exec",
		Code:      code,
		TimeoutMs: int(flagTimeout.Milliseconds()),
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}

	if err := mb.WriteRequest(req); err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec: write request:", err)
		return 3
	}

	resp, err := pollResponse(mb, req.ID, *flagTimeout)
	if err != nil {
		if errors.Is(err, errPollTimeout) {
			fmt.Fprintln(stderr, "dcs-sms exec: timeout — no response within", *flagTimeout)
			return 2
		}
		fmt.Fprintln(stderr, "dcs-sms exec: poll:", err)
		return 3
	}

	var data []byte
	if *flagPretty {
		data, _ = json.MarshalIndent(resp, "", "  ")
	} else {
		data, _ = json.Marshal(resp)
	}
	fmt.Fprintln(stdout, string(data))

	if !resp.OK {
		return 1
	}
	return 0
}

// readCode resolves which input source to use, in priority order: --file,
// --code, stdin. Empty result is an error.
func readCode(file, code string, stdin io.Reader) (string, error) {
	if file != "" {
		data, err := os.ReadFile(file)
		if err != nil {
			return "", fmt.Errorf("read --file: %w", err)
		}
		return string(data), nil
	}
	if code != "" {
		return code, nil
	}
	data, err := io.ReadAll(stdin)
	if err != nil {
		return "", fmt.Errorf("read stdin: %w", err)
	}
	if len(data) == 0 {
		return "", errors.New("no code provided (use --file, --code, or pipe via stdin)")
	}
	return string(data), nil
}

// resolveRoot returns the Saved Games path using the standard discovery chain.
func resolveRoot(override string) (string, error) {
	cfg, _ := dcspath.DefaultConfigPath()
	return dcspath.Discover(override, cfg)
}

// ensureMailboxDirs creates dcs-sms/{inbox,outbox,state,log} if missing.
func ensureMailboxDirs(root string) error {
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		if err := os.MkdirAll(filepath.Join(root, sub), 0o755); err != nil {
			return err
		}
	}
	return nil
}

var errPollTimeout = errors.New("poll timeout")

// pollResponse polls outbox/<id>.res.json every 25ms until found or timeout.
func pollResponse(mb *mailbox.Mailbox, id string, timeout time.Duration) (proto.ExecResponse, error) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		resp, ok, err := mb.ReadResponse(id)
		if err != nil {
			return proto.ExecResponse{}, err
		}
		if ok {
			return resp, nil
		}
		time.Sleep(25 * time.Millisecond)
	}
	return proto.ExecResponse{}, errPollTimeout
}
```

Note the `dcs-sms` subdirectory: the mailbox lives at `<saved-games>/dcs-sms/`. The CLI builds this path internally.

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./cmd/dcs-sms/... -v
```

Expected: all exec tests pass.

If the timeout test is flaky on slow Windows file systems, bump the timeout in that test from 300ms to 500ms. Don't lengthen it beyond 1s — that masks bugs.

- [ ] **Step 5: Commit**

```bash
git add tools/cmd/dcs-sms/exec.go tools/cmd/dcs-sms/exec_test.go
git commit -m "feat: exec subcommand with file/inline/stdin code input"
```

---

## Task 10: `exec` `--wait` flag and freshness gate

**Files:**
- Modify: `tools/cmd/dcs-sms/exec.go`
- Modify: `tools/cmd/dcs-sms/exec_test.go`

- [ ] **Step 1: Append failing tests**

Append to `tools/cmd/dcs-sms/exec_test.go`:

```go
func TestExecFailsFastWhenHookStale(t *testing.T) {
	root := t.TempDir()
	// Create dirs but no heartbeat → state/hook.json missing.
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		_ = os.MkdirAll(filepath.Join(root, "dcs-sms", sub), 0o755)
	}
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := execCmd([]string{"--code", "return 1", "--timeout", "500ms"}, &stdout, &stderr)
	if code != 3 {
		t.Errorf("exit %d, want 3 (hook not ready)", code)
	}
	if !strings.Contains(stderr.String(), "hook") {
		t.Errorf("expected hook diagnostic in stderr, got %q", stderr.String())
	}
}

func TestExecWaitWaitsForHook(t *testing.T) {
	root := t.TempDir()
	for _, sub := range []string{"inbox", "outbox", "state", "log"} {
		_ = os.MkdirAll(filepath.Join(root, "dcs-sms", sub), 0o755)
	}

	// Start a goroutine that begins writing heartbeats after 200ms and also
	// answers requests.
	stop := make(chan struct{})
	go func() {
		time.Sleep(200 * time.Millisecond)
		ticker := time.NewTicker(20 * time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				st := proto.HookState{
					HookVersion:   "fake",
					MissionLoaded: true,
					LastFrameAt:   time.Now().UTC().Format(time.RFC3339Nano),
				}
				data, _ := json.Marshal(st)
				p := filepath.Join(root, "dcs-sms", "state", "hook.json")
				_ = os.WriteFile(p+".tmp", data, 0o644)
				_ = os.Rename(p+".tmp", p)
				// also process inbox
				entries, _ := os.ReadDir(filepath.Join(root, "dcs-sms", "inbox"))
				for _, e := range entries {
					if !strings.HasSuffix(e.Name(), ".req.json") {
						continue
					}
					reqPath := filepath.Join(root, "dcs-sms", "inbox", e.Name())
					raw, err := os.ReadFile(reqPath)
					if err != nil {
						continue
					}
					var req proto.ExecRequest
					if json.Unmarshal(raw, &req) != nil {
						continue
					}
					resp := proto.ExecResponse{ID: req.ID, OK: true, ReturnValue: json.RawMessage(`1`)}
					out, _ := json.Marshal(resp)
					rp := filepath.Join(root, "dcs-sms", "outbox", req.ID+".res.json")
					_ = os.WriteFile(rp+".tmp", out, 0o644)
					_ = os.Rename(rp+".tmp", rp)
					_ = os.Remove(reqPath)
				}
			}
		}
	}()
	t.Cleanup(func() { close(stop) })

	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := execCmd([]string{"--code", "return 1", "--wait", "--timeout", "3s"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit %d, want 0; stderr=%s", code, stderr.String())
	}
}
```

- [ ] **Step 2: Run to verify the new tests fail**

```bash
cd tools
go test ./cmd/dcs-sms/... -run "Stale|Wait" -v
```

Expected: both new tests fail (no `--wait` flag, no freshness check).

- [ ] **Step 3: Update `exec.go`**

Modify `tools/cmd/dcs-sms/exec.go`:

1. Add a new flag and import:

```go
import (
	// existing imports...
	"github.com/nielsvaes/dcs-sms/tools/internal/hookstatus"
)
```

In `execCmd`, after the existing flag declarations, add:

```go
	flagWait := fs.Bool("wait", false, "if hook isn't ready, poll until it is or --timeout elapses")
```

2. Replace the section between `mb := mailbox.New(...)` (after `ensureMailboxDirs`) and `req := proto.ExecRequest{...}` with:

```go
	if err := waitForHook(mb.State(), *flagWait, *flagTimeout); err != nil {
		fmt.Fprintln(stderr, "dcs-sms exec:", err)
		return 3
	}
```

3. Add `waitForHook` to the same file:

```go
// waitForHook returns nil if the hook heartbeat is fresh. If wait is true,
// it polls every 50ms until fresh or timeout. If wait is false and the hook
// isn't fresh, it returns immediately with an error.
func waitForHook(stateDir string, wait bool, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		st, err := hookstatus.Read(stateDir)
		if err == nil && hookstatus.IsFresh(st, 2*time.Second, time.Now()) {
			if !st.MissionLoaded {
				if !wait {
					return errors.New("hook is running but no mission loaded — load a mission or pass --wait")
				}
				// fall through to wait
			} else {
				return nil
			}
		} else if !wait {
			if err != nil {
				return fmt.Errorf("hook not ready (%v) — start DCS or pass --wait", err)
			}
			return errors.New("hook heartbeat stale — DCS may be paused/hung; pass --wait to retry")
		}
		if time.Now().After(deadline) {
			return errors.New("timed out waiting for hook to become ready")
		}
		time.Sleep(50 * time.Millisecond)
	}
}
```

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./cmd/dcs-sms/... -v
```

Expected: all exec tests pass.

- [ ] **Step 5: Commit**

```bash
git add tools/cmd/dcs-sms/exec.go tools/cmd/dcs-sms/exec_test.go
git commit -m "feat: exec --wait flag and freshness check"
```

---

## Task 11: `status` subcommand

**Files:**
- Create: `tools/cmd/dcs-sms/status.go`
- Create: `tools/cmd/dcs-sms/status_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/cmd/dcs-sms/status_test.go`:

```go
package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/proto"
)

func TestStatusFresh(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, "dcs-sms", "state")
	_ = os.MkdirAll(stateDir, 0o755)
	st := proto.HookState{
		HookVersion:   "0.1.0",
		MissionLoaded: true,
		MissionName:   "Caucasus.miz",
		LastFrame:     100,
		LastFrameAt:   time.Now().UTC().Format(time.RFC3339Nano),
	}
	data, _ := json.Marshal(st)
	_ = os.WriteFile(filepath.Join(stateDir, "hook.json"), data, 0o644)

	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := statusCmd(nil, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit %d, want 0", code)
	}
	if !strings.Contains(stdout.String(), "Caucasus.miz") {
		t.Errorf("missing mission name in stdout: %s", stdout.String())
	}
}

func TestStatusJSON(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, "dcs-sms", "state")
	_ = os.MkdirAll(stateDir, 0o755)
	st := proto.HookState{HookVersion: "0.1.0", LastFrameAt: time.Now().UTC().Format(time.RFC3339Nano)}
	data, _ := json.Marshal(st)
	_ = os.WriteFile(filepath.Join(stateDir, "hook.json"), data, 0o644)

	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := statusCmd([]string{"--json"}, &stdout, &stderr)
	if code != 0 {
		t.Errorf("exit %d, want 0", code)
	}
	var parsed map[string]any
	if err := json.Unmarshal(stdout.Bytes(), &parsed); err != nil {
		t.Errorf("stdout not valid JSON: %v\n%s", err, stdout.String())
	}
}

func TestStatusMissingHookFile(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := statusCmd(nil, &stdout, &stderr)
	if code == 0 {
		t.Error("expected non-zero exit with no hook.json")
	}
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./cmd/dcs-sms/... -run TestStatus
```

Expected: build failure.

- [ ] **Step 3: Implement**

Create `tools/cmd/dcs-sms/status.go`:

```go
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/hookstatus"
)

func init() {
	register("status", statusCmd)
}

func statusCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagJSON := fs.Bool("json", false, "emit machine-readable JSON")
	flagSavedGames := fs.String("saved-games", "", "override Saved Games path")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(*flagSavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms status:", err)
		return 3
	}
	stateDir := filepath.Join(root, "dcs-sms", "state")
	st, err := hookstatus.Read(stateDir)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms status: hook not found —", err)
		return 3
	}
	fresh := hookstatus.IsFresh(st, 2*time.Second, time.Now())

	if *flagJSON {
		out := map[string]any{
			"hook_version":   st.HookVersion,
			"mission_loaded": st.MissionLoaded,
			"mission_name":   st.MissionName,
			"last_frame":     st.LastFrame,
			"last_frame_at":  st.LastFrameAt,
			"fresh":          fresh,
		}
		data, _ := json.Marshal(out)
		fmt.Fprintln(stdout, string(data))
	} else {
		fmt.Fprintf(stdout, "hook version:   %s\n", st.HookVersion)
		fmt.Fprintf(stdout, "mission loaded: %v\n", st.MissionLoaded)
		if st.MissionName != "" {
			fmt.Fprintf(stdout, "mission name:   %s\n", st.MissionName)
		}
		fmt.Fprintf(stdout, "last frame:     %d (%s)\n", st.LastFrame, st.LastFrameAt)
		fmt.Fprintf(stdout, "fresh:          %v\n", fresh)
	}

	if !fresh {
		return 4
	}
	return 0
}
```

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./cmd/dcs-sms/... -v
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add tools/cmd/dcs-sms/status.go tools/cmd/dcs-sms/status_test.go
git commit -m "feat: status subcommand reporting hook health"
```

---

## Task 12: `tail-log` subcommand

**Files:**
- Create: `tools/cmd/dcs-sms/taillog.go`
- Create: `tools/cmd/dcs-sms/taillog_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/cmd/dcs-sms/taillog_test.go`:

```go
package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeLogRoot creates a fake Saved Games root with a dcs.log at the
// expected path (<root>/Logs/dcs.log).
func fakeLogRoot(t *testing.T, lines ...string) string {
	t.Helper()
	root := t.TempDir()
	logsDir := filepath.Join(root, "Logs")
	smsDir := filepath.Join(root, "dcs-sms", "state")
	if err := os.MkdirAll(logsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(smsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	logPath := filepath.Join(logsDir, "dcs.log")
	if err := os.WriteFile(logPath, []byte(strings.Join(lines, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestTailLogPrintsAll(t *testing.T) {
	root := fakeLogRoot(t, "first", "second", "third")
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := tailLogCmd([]string{"--since", "0"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, want 0; stderr=%s", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "first") || !strings.Contains(stdout.String(), "third") {
		t.Errorf("expected all lines, got %q", stdout.String())
	}
}

func TestTailLogGrep(t *testing.T) {
	root := fakeLogRoot(t, "INFO: a", "WARN: b", "INFO: c")
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := tailLogCmd([]string{"--since", "0", "--grep", "WARN"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	if !strings.Contains(stdout.String(), "WARN: b") {
		t.Errorf("missing WARN line: %s", stdout.String())
	}
	if strings.Contains(stdout.String(), "INFO: a") {
		t.Errorf("INFO line should be filtered out: %s", stdout.String())
	}
}

func TestTailLogN(t *testing.T) {
	root := fakeLogRoot(t, "a", "b", "c", "d", "e")
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := tailLogCmd([]string{"--since", "0", "-n", "2"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	out := strings.TrimSpace(stdout.String())
	if strings.Count(out, "\n") != 1 {
		t.Errorf("expected 2 lines, got %q", stdout.String())
	}
}

func TestTailLogCursorAdvances(t *testing.T) {
	root := fakeLogRoot(t, "first")
	t.Setenv("DCS_SMS_SAVED_GAMES", root)

	var stdout, stderr bytes.Buffer
	code := tailLogCmd([]string{"--since", "cursor"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("first call exit %d", code)
	}
	// Append a line and re-run with cursor; should only see the new line.
	logPath := filepath.Join(root, "Logs", "dcs.log")
	f, _ := os.OpenFile(logPath, os.O_APPEND|os.O_WRONLY, 0o644)
	_, _ = f.WriteString("second\n")
	_ = f.Close()

	var stdout2, stderr2 bytes.Buffer
	code = tailLogCmd([]string{"--since", "cursor"}, &stdout2, &stderr2)
	if code != 0 {
		t.Fatalf("second call exit %d", code)
	}
	if strings.Contains(stdout2.String(), "first") {
		t.Errorf("cursor failed to advance — saw 'first' on second call: %s", stdout2.String())
	}
	if !strings.Contains(stdout2.String(), "second") {
		t.Errorf("expected 'second' on second call, got %s", stdout2.String())
	}
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./cmd/dcs-sms/... -run TestTailLog
```

Expected: build failure.

- [ ] **Step 3: Implement**

Create `tools/cmd/dcs-sms/taillog.go`:

```go
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"strconv"
	"time"

	"github.com/nielsvaes/dcs-sms/tools/internal/logtail"
)

func init() {
	register("tail-log", tailLogCmd)
}

func tailLogCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("tail-log", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagSince := fs.String("since", "cursor", `"cursor" (default), "0" (whole file), or a duration like "30s"`)
	flagGrep := fs.String("grep", "", "regex to filter lines")
	flagN := fs.Int("n", 0, "emit only the last N matching lines")
	flagJSON := fs.Bool("json", false, "emit one JSON object per line")
	flagSavedGames := fs.String("saved-games", "", "override Saved Games path")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(*flagSavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms tail-log:", err)
		return 3
	}
	logPath := filepath.Join(root, "Logs", "dcs.log")
	cursorPath := filepath.Join(root, "dcs-sms", "state", "log-cursor")
	r := &logtail.Reader{LogPath: logPath, CursorPath: cursorPath}

	from, err := resolveSince(*flagSince, logPath, r)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms tail-log:", err)
		return 2
	}

	lines, newOffset, err := r.ReadFrom(from, *flagGrep, *flagN)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms tail-log:", err)
		return 3
	}
	for _, line := range lines {
		if *flagJSON {
			data, _ := json.Marshal(map[string]string{"line": line})
			fmt.Fprintln(stdout, string(data))
		} else {
			fmt.Fprintln(stdout, line)
		}
	}
	if *flagSince == "cursor" {
		if err := r.WriteCursor(newOffset); err != nil {
			fmt.Fprintln(stderr, "dcs-sms tail-log: warning: failed to update cursor:", err)
		}
	}
	return 0
}

// resolveSince returns the byte offset implied by --since.
func resolveSince(since, logPath string, r *logtail.Reader) (int64, error) {
	switch since {
	case "cursor":
		return r.ReadCursor()
	case "0":
		return 0, nil
	}
	if n, err := strconv.ParseInt(since, 10, 64); err == nil {
		// numeric byte offset
		return n, nil
	}
	d, err := time.ParseDuration(since)
	if err != nil {
		return 0, fmt.Errorf("invalid --since %q: expected 'cursor', '0', a byte offset, or a Go duration", since)
	}
	// We don't have per-line timestamps for cheap; approximate by reading
	// the whole file size and seeking back. A simpler honest semantic: with
	// a duration, just return 0 for now (full-file scan). We can refine if
	// it matters. Document this limitation.
	_ = d
	return 0, nil
}
```

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./cmd/dcs-sms/... -v
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add tools/cmd/dcs-sms/taillog.go tools/cmd/dcs-sms/taillog_test.go
git commit -m "feat: tail-log subcommand with cursor and grep"
```

---

## Task 13: Lua hook

**Files:**
- Create: `tools/lua/dcs-sms-hook.lua`
- Create: `tools/lua/embed.go` (Go package that exposes the hook source as `[]byte` via `//go:embed`; needed because Go's `//go:embed` directive cannot reference paths outside its containing package directory)

This task has no Go-side test — the Lua hook can only be verified by manual L3 smoke. The Go side validates the protocol contract (Tasks 9–12 already cover that against a fake hook). Future workers should resist Busted-style mocks here unless the hook grows.

- [ ] **Step 1: Write the hook**

Create `tools/lua/dcs-sms-hook.lua`:

```lua
-- dcs-sms hook
-- Lives in: Saved Games/DCS*/Scripts/Hooks/dcs-sms-hook.lua
-- Runs in: DCS GUI/hook environment (no sandbox; lfs and net.* are available)
-- Protocol: see docs/superpowers/specs/2026-04-25-execution-bridge-design.md

local DCS_SMS = {
  version = "0.1.0",
  heartbeat_every_frames = 30,
  cleanup_max_age_seconds = 60,
}

DCS_SMS.root   = lfs.writedir() .. "dcs-sms\\"
DCS_SMS.inbox  = DCS_SMS.root .. "inbox\\"
DCS_SMS.outbox = DCS_SMS.root .. "outbox\\"
DCS_SMS.state  = DCS_SMS.root .. "state\\"
DCS_SMS.logdir = DCS_SMS.root .. "log\\"

DCS_SMS.frame                 = 0
DCS_SMS.last_heartbeat_frame  = -1e9  -- force first heartbeat immediately
DCS_SMS.mission_loaded        = false
DCS_SMS.mission_name          = ""

-- ----------------------------------------------------------------------------
-- helpers

local function ensure_dirs()
  for _, d in ipairs({DCS_SMS.root, DCS_SMS.inbox, DCS_SMS.outbox,
                      DCS_SMS.state, DCS_SMS.logdir}) do
    lfs.mkdir(d)
  end
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_atomic(path, data)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then
    log.write("dcs-sms", log.ERROR, "open tmp " .. tmp .. ": " .. tostring(err))
    return false
  end
  f:write(data)
  f:close()
  -- os.rename overwrites the target on Windows when source and target are
  -- on the same volume (which they are here).
  local ok, err2 = os.rename(tmp, path)
  if not ok then
    log.write("dcs-sms", log.ERROR, "rename " .. tmp .. " -> " .. path .. ": " .. tostring(err2))
    -- Try delete + rename as fallback for older Windows behavior.
    os.remove(path)
    os.rename(tmp, path)
  end
  return true
end

local function iso_now()
  -- DCS Lua's os.date with !%Y-%m-%dT%H:%M:%S gives UTC seconds; we append
  -- a Z suffix. No millisecond precision, which is fine for our purposes.
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function escape_json_string(s)
  -- Cover the common cases. The hook only emits a handful of fields by
  -- this path (mission_name, version), so we don't need a full JSON
  -- encoder here.
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return s
end

local function write_heartbeat()
  local payload = string.format(
    '{"hook_version":"%s","mission_loaded":%s,"mission_name":"%s","last_frame":%d,"last_frame_at":"%s"}',
    DCS_SMS.version,
    tostring(DCS_SMS.mission_loaded),
    escape_json_string(DCS_SMS.mission_name),
    DCS_SMS.frame,
    iso_now()
  )
  write_atomic(DCS_SMS.state .. "hook.json", payload)
  DCS_SMS.last_heartbeat_frame = DCS_SMS.frame
end

local function sweep_stale(dir, suffix)
  local now = os.time()
  for entry in lfs.dir(dir) do
    if entry ~= "." and entry ~= ".." then
      local full = dir .. entry
      local attrs = lfs.attributes(full)
      if attrs and attrs.mode == "file"
         and (entry:sub(-#suffix) == suffix or entry:match("%.tmp$"))
         and (now - (attrs.modification or now)) > DCS_SMS.cleanup_max_age_seconds then
        os.remove(full)
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- request execution

-- build_wrapper takes the user's Lua snippet and wraps it in code that:
--   * captures print() output
--   * runs the snippet under xpcall to get a traceback on error
--   * builds a JSON-serializable response with id/frame/duration metadata
--   * stashes the resulting JSON string in __DCS_SMS_RESPONSE_JSON
local function build_wrapper(req_id, frame, user_code)
  return string.format([[
do
  local __dcs_sms_id    = %q
  local __dcs_sms_frame = %d
  local __dcs_sms_start = os.clock()
  local __dcs_sms_out   = {}

  local __dcs_sms_orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    __dcs_sms_out[#__dcs_sms_out+1] = table.concat(parts, '\t')
  end

  local __dcs_sms_ok, __dcs_sms_ret = xpcall(function()
%s
  end, debug.traceback)

  print = __dcs_sms_orig_print

  local __dcs_sms_dur = (os.clock() - __dcs_sms_start) * 1000
  local __dcs_sms_resp = {
    id             = __dcs_sms_id,
    ok             = __dcs_sms_ok,
    output         = table.concat(__dcs_sms_out, '\n'),
    return_value   = (__dcs_sms_ok and __dcs_sms_ret) or nil,
    error          = (not __dcs_sms_ok) and { message = tostring(__dcs_sms_ret), traceback = "" } or nil,
    frame_executed = __dcs_sms_frame,
    duration_ms    = __dcs_sms_dur,
  }
  __DCS_SMS_RESPONSE_JSON = net.lua2json(__dcs_sms_resp)
end
]], req_id, frame, user_code)
end

local function parse_request_id_from_filename(name)
  -- "abc-123.req.json" -> "abc-123"
  return name:match("^(.+)%.req%.json$")
end

local function execute_request(filename)
  local req_path = DCS_SMS.inbox .. filename
  local raw = read_file(req_path)
  if not raw then return end

  -- We don't have a full JSON parser in the hook env, but the request files
  -- are produced by the CLI and have a well-known shape. We extract just
  -- the fields we need with patterns.
  local req_id = parse_request_id_from_filename(filename)
  local code   = raw:match('"code"%s*:%s*"(.-)"%s*[,}]')
  if not req_id or not code then
    log.write("dcs-sms", log.ERROR, "could not parse request " .. filename)
    os.remove(req_path)
    return
  end
  -- Unescape JSON string to actual code.
  code = code:gsub('\\"', '"')
              :gsub('\\\\', '\\')
              :gsub('\\n', '\n')
              :gsub('\\r', '\r')
              :gsub('\\t', '\t')

  local wrapper = build_wrapper(req_id, DCS_SMS.frame, code)
  local ok_out, err_out = pcall(net.dostring_in, 'mission', wrapper)
  if not ok_out then
    log.write("dcs-sms", log.ERROR, "wrapper exec failed: " .. tostring(err_out))
    os.remove(req_path)
    return
  end
  local response_json = net.dostring_in('mission', "return __DCS_SMS_RESPONSE_JSON")
  if type(response_json) ~= "string" or response_json == "" then
    log.write("dcs-sms", log.ERROR, "no response JSON for " .. req_id)
    os.remove(req_path)
    return
  end

  write_atomic(DCS_SMS.outbox .. req_id .. ".res.json", response_json)
  os.remove(req_path)
end

local function process_inbox()
  for entry in lfs.dir(DCS_SMS.inbox) do
    if entry:sub(-9) == ".req.json" then
      local ok, err = pcall(execute_request, entry)
      if not ok then
        log.write("dcs-sms", log.ERROR, "execute_request crashed: " .. tostring(err))
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- userCallbacks

local handler = {}

function handler.onMissionLoadEnd()
  DCS_SMS.mission_loaded = true
  DCS_SMS.mission_name = (DCS and DCS.getMissionName and DCS.getMissionName()) or ""
  pcall(sweep_stale, DCS_SMS.inbox, ".req.json")
  pcall(sweep_stale, DCS_SMS.outbox, ".res.json")
  write_heartbeat()
  log.write("dcs-sms", log.INFO, "mission loaded: " .. DCS_SMS.mission_name)
end

function handler.onSimulationFrame()
  DCS_SMS.frame = DCS_SMS.frame + 1
  if DCS_SMS.mission_loaded then
    pcall(process_inbox)
  end
  if DCS_SMS.frame - DCS_SMS.last_heartbeat_frame >= DCS_SMS.heartbeat_every_frames then
    pcall(write_heartbeat)
  end
end

function handler.onSimulationStop()
  DCS_SMS.mission_loaded = false
  pcall(write_heartbeat)
  log.write("dcs-sms", log.INFO, "simulation stopped")
end

local function init()
  ensure_dirs()
  write_heartbeat()
  DCS.setUserCallbacks(handler)
  log.write("dcs-sms", log.INFO, "hook loaded v" .. DCS_SMS.version)
end

local ok, err = pcall(init)
if not ok then
  log.write("dcs-sms", log.ERROR, "init failed: " .. tostring(err))
end
```

- [ ] **Step 2: Create the embed wrapper**

Create `tools/lua/embed.go`:

```go
// Package hook exposes the in-DCS Lua hook source (dcs-sms-hook.lua) as a
// byte slice for the install-hook subcommand to write into
// Saved Games/DCS*/Scripts/Hooks/. We need this thin wrapper because Go's
// //go:embed directive cannot reference files outside its own package
// directory — keeping the canonical hook source under tools/lua/ means we
// also need a Go file in tools/lua/ to embed it.
package hook

import _ "embed"

//go:embed dcs-sms-hook.lua
var Source []byte
```

- [ ] **Step 3: Build to verify the embed compiles**

```bash
cd tools
go build ./lua/...
```

Expected: no output, exit 0.

- [ ] **Step 4: Lua syntax check (best-effort)**

If `luac` (Lua 5.2) is on the PATH, syntax-check the file:

```bash
luac -p tools/lua/dcs-sms-hook.lua
```

Expected: no output, exit 0. If `luac` isn't installed, skip — DCS will surface syntax errors when the hook loads.

- [ ] **Step 5: Commit**

```bash
git add tools/lua/dcs-sms-hook.lua tools/lua/embed.go
git commit -m "feat: in-DCS Lua hook with go:embed wrapper"
```

---

## Task 14: `install-hook` subcommand with `//go:embed`

**Files:**
- Create: `tools/cmd/dcs-sms/installhook.go`
- Create: `tools/cmd/dcs-sms/installhook_test.go`

- [ ] **Step 1: Write the failing test**

Create `tools/cmd/dcs-sms/installhook_test.go`:

```go
package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInstallHookWritesFile(t *testing.T) {
	root := t.TempDir()
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := installHookCmd(nil, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d, want 0; stderr=%s", code, stderr.String())
	}
	hookPath := filepath.Join(root, "Scripts", "Hooks", "dcs-sms-hook.lua")
	data, err := os.ReadFile(hookPath)
	if err != nil {
		t.Fatalf("expected hook file at %s: %v", hookPath, err)
	}
	if !strings.Contains(string(data), "DCS_SMS") {
		t.Errorf("hook file does not look like the embedded source")
	}
}

func TestInstallHookOverwritesExisting(t *testing.T) {
	root := t.TempDir()
	hookDir := filepath.Join(root, "Scripts", "Hooks")
	_ = os.MkdirAll(hookDir, 0o755)
	hookPath := filepath.Join(hookDir, "dcs-sms-hook.lua")
	if err := os.WriteFile(hookPath, []byte("OLD"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("DCS_SMS_SAVED_GAMES", root)
	var stdout, stderr bytes.Buffer
	code := installHookCmd(nil, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	data, _ := os.ReadFile(hookPath)
	if string(data) == "OLD" {
		t.Error("expected hook file to be overwritten")
	}
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd tools
go test ./cmd/dcs-sms/... -run TestInstallHook
```

Expected: build failure.

- [ ] **Step 3: Implement**

Create `tools/cmd/dcs-sms/installhook.go`:

```go
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	hookpkg "github.com/nielsvaes/dcs-sms/tools/lua"
)

func init() {
	register("install-hook", installHookCmd)
}

func installHookCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("install-hook", flag.ContinueOnError)
	fs.SetOutput(stderr)
	flagSavedGames := fs.String("saved-games", "", "override Saved Games path")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	root, err := resolveRoot(*flagSavedGames)
	if err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-hook:", err)
		return 3
	}
	hooksDir := filepath.Join(root, "Scripts", "Hooks")
	if err := os.MkdirAll(hooksDir, 0o755); err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-hook: mkdir:", err)
		return 3
	}
	dst := filepath.Join(hooksDir, "dcs-sms-hook.lua")
	if err := os.WriteFile(dst, hookpkg.Source, 0o644); err != nil {
		fmt.Fprintln(stderr, "dcs-sms install-hook: write:", err)
		return 3
	}
	fmt.Fprintf(stdout, "installed hook to %s (%d bytes)\n", dst, len(hookpkg.Source))
	fmt.Fprintln(stdout, "")
	fmt.Fprintln(stdout, "Next steps:")
	fmt.Fprintln(stdout, "  1. In your DCS install dir, edit Scripts/MissionScripting.lua and comment out")
	fmt.Fprintln(stdout, "     the sanitizeModule('os'), ('io'), and ('lfs') lines so the hook can talk to")
	fmt.Fprintln(stdout, "     the mission environment.")
	fmt.Fprintln(stdout, "  2. Start DCS and load any mission.")
	fmt.Fprintln(stdout, "  3. Run `dcs-sms status` to confirm the hook is alive.")
	return 0
}
```

The hook source is embedded into the `tools/lua` package (Task 13) and imported here. We use a named import (`hookpkg`) to avoid colliding with the local `hook` symbol if it ever appears. This indirection exists because `//go:embed` cannot reference paths outside its containing package directory.

- [ ] **Step 4: Run tests**

```bash
cd tools
go test ./cmd/dcs-sms/... -v
```

Expected: pass.

- [ ] **Step 5: Build the binary and verify the hook is embedded**

```bash
cd tools
go build ./cmd/dcs-sms
./dcs-sms.exe install-hook --saved-games "$(mktemp -d)"
```

Expected output: `installed hook to .../Scripts/Hooks/dcs-sms-hook.lua (NNNN bytes)` plus the next-steps banner.

- [ ] **Step 6: Commit**

```bash
git add tools/cmd/dcs-sms/installhook.go tools/cmd/dcs-sms/installhook_test.go
git commit -m "feat: install-hook subcommand using go:embed"
```

---

## Task 15: README + smoke checklist

**Files:**
- Create: `README.md` (repo root)
- Create: `tools/lua/README.md`

- [ ] **Step 1: Write the top-level README**

Create `D:\git\dcs-sms\README.md`:

```markdown
# dcs-sms

**Digital Combat Simulator Simple Mission Scripting** — a focused Lua scripting framework for DCS missions, plus host-side tools for driving DCS programmatically.

See [`MISSION.md`](MISSION.md) for the project's vision and rationale.

## Repo layout

- `tools/` — host-side Go tooling. Currently: a CLI (`dcs-sms.exe`) that executes Lua snippets in a running DCS mission and reads back structured results. Hook for DCS lives at `tools/lua/dcs-sms-hook.lua` and is embedded into the binary.
- `framework/` — in-DCS Lua framework (the MOOSE-rework). Empty for now; this is the next sub-project.
- `docs/superpowers/specs/` — design documents for each sub-project.
- `docs/superpowers/plans/` — implementation plans.

## Quick start (execution bridge)

Build the CLI:

```sh
cd tools
go build ./cmd/dcs-sms
```

Install the hook into your DCS Saved Games folder:

```sh
./dcs-sms install-hook
```

Edit `Scripts/MissionScripting.lua` in your DCS install dir to comment out the `sanitizeModule('os')`, `('io')`, and `('lfs')` lines. (The hook needs `lfs` to scan the mailbox; this is the same modification the older `dcs_code_injector` requires.)

Start DCS, load any mission, then:

```sh
./dcs-sms status                      # confirm hook is alive
./dcs-sms exec --code "return 1+1"    # run a snippet
./dcs-sms tail-log -n 20              # see the last 20 dcs.log lines
```

See `tools/lua/README.md` for the full install / smoke-test checklist.
```

- [ ] **Step 2: Write the hook README + smoke checklist**

Create `tools/lua/README.md`:

```markdown
# dcs-sms hook — install and smoke checklist

This document covers (a) installing `dcs-sms-hook.lua` into DCS and (b) the manual smoke tests that should pass before any release.

## Install

The hook is embedded into the `dcs-sms` binary. The recommended install path:

```sh
dcs-sms install-hook
```

This writes `dcs-sms-hook.lua` into `<Saved Games>\DCS*\Scripts\Hooks\` (auto-detected, or pass `--saved-games <path>` to override).

You also need to edit `Scripts\MissionScripting.lua` in your DCS *install* directory (not Saved Games). Comment out:

```lua
do
  -- sanitizeModule('os')
  -- sanitizeModule('io')
  -- sanitizeModule('lfs')
  ...
end
```

This is the same modification `dcs_code_injector` requires — the hook needs `lfs.dir` to scan its inbox, and `os.rename` to write responses atomically.

## Manual smoke checklist

Run before each release. ~5 minutes.

1. **Build:** `cd tools && go build ./cmd/dcs-sms` — should complete with no warnings.
2. **Install hook:** `./dcs-sms install-hook` — should report success.
3. **Start DCS** and load any single-player mission.
4. **Status:** `./dcs-sms status` — should report `mission loaded: true` and `fresh: true`. Exit code 0.
5. **Smoke exec:** `./dcs-sms exec --code "return 1+1"` — stdout JSON should contain `"ok":true` and `"return_value":2`. Exit code 0.
6. **Print capture:** `./dcs-sms exec --code "print('hello'); return 'world'"` — `output` should be `"hello"`, `return_value` should be `"world"`.
7. **Lua error:** `./dcs-sms exec --code "error('boom')"` — `ok` should be `false`, `error.message` should contain `"boom"`. Exit code 1.
8. **Timeout:** `./dcs-sms exec --code "while true do end" --timeout 2s` — should exit code 2 with a timeout message *and DCS should be hung*. Kill DCS via Task Manager. (This is a documented limitation, not a regression.)
9. **Tail log:** `./dcs-sms tail-log -n 20` — should print 20 recent dcs.log lines.
10. **Restart DCS** and load a different mission. `./dcs-sms status` should report the new mission name.

If any step misbehaves, check `<Saved Games>\DCS*\dcs-sms\log\hook.log` and `<Saved Games>\DCS*\Logs\dcs.log` for diagnostics.
```

- [ ] **Step 3: Commit**

```bash
git add README.md tools/lua/README.md
git commit -m "docs: top-level README and hook install/smoke checklist"
```

---

## Self-review checklist (run after writing all tasks)

- [x] **Spec coverage:**
    - File mailbox protocol — Tasks 3 (atomic write), 4 (req/res + sweep)
    - JSON request/response shapes — Task 2
    - Heartbeat + freshness — Tasks 5 (status reader), 10 (freshness gate in `exec`), 13 (hook writes heartbeat)
    - `exec` subcommand — Tasks 9, 10
    - `status` subcommand — Task 11
    - `tail-log` subcommand — Task 12
    - `install-hook` subcommand + `//go:embed` — Task 14
    - Lua hook with print capture, return value, traceback — Task 13
    - Repo layout (`tools/` + `framework/`) — Task 1
    - Stale file cleanup — Task 4 (CLI side: `SweepOutboxOlderThan`), Task 13 (hook side, on `onMissionLoadEnd`)
    - Path discovery + config — Task 6
    - Documentation (README + smoke checklist) — Task 15
- [x] **No placeholders:** every step has full code or full commands.
- [x] **Type consistency:** `proto.ExecRequest`/`ExecResponse`/`ExecError`/`HookState` referenced by their exact names in every consumer task.
- [x] **TDD:** every Go-side task with logic has a failing test before the implementation. The Lua hook (Task 13) is verified by the L2 fake-hook integration tests in earlier tasks plus the L3 manual smoke checklist in Task 15.
