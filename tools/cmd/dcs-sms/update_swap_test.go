package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSwapBinaryReplacesContent(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "binary.exe")
	if err := os.WriteFile(target, []byte("OLD"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := swapBinary(target, bytes.NewReader([]byte("NEW"))); err != nil {
		t.Fatalf("swapBinary: %v", err)
	}

	got, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "NEW" {
		t.Errorf("target content = %q, want %q", got, "NEW")
	}

	oldGot, err := os.ReadFile(target + ".old")
	if err != nil {
		t.Fatalf("expected .old file: %v", err)
	}
	if string(oldGot) != "OLD" {
		t.Errorf(".old content = %q, want %q", oldGot, "OLD")
	}
}

func TestSwapBinaryRemovesStaleOld(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "binary.exe")
	if err := os.WriteFile(target, []byte("OLD2"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target+".old", []byte("STALE"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := swapBinary(target, bytes.NewReader([]byte("NEW"))); err != nil {
		t.Fatalf("swapBinary: %v", err)
	}

	oldGot, err := os.ReadFile(target + ".old")
	if err != nil {
		t.Fatal(err)
	}
	if string(oldGot) != "OLD2" {
		t.Errorf(".old content = %q, want %q (stale should have been replaced)", oldGot, "OLD2")
	}
}

// errReader returns a fixed error on Read. Used to force a write failure
// in the middle of swapBinary.
type errReader struct{ err error }

func (r errReader) Read(p []byte) (int, error) { return 0, r.err }

func TestSwapBinaryRollbackOnReadError(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "binary.exe")
	if err := os.WriteFile(target, []byte("ORIGINAL"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := swapBinary(target, errReader{err: errors.New("disk full")})
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "disk full") {
		t.Errorf("error message %q does not contain 'disk full'", err)
	}

	got, err := os.ReadFile(target)
	if err != nil {
		t.Fatalf("target should still exist after rollback: %v", err)
	}
	if string(got) != "ORIGINAL" {
		t.Errorf("after rollback, target content = %q, want %q", got, "ORIGINAL")
	}

	if _, err := os.Stat(target + ".old"); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("expected .old to be removed after rollback, got %v", err)
	}
}
