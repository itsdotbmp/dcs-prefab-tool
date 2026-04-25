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
