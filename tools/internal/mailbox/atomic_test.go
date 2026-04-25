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
