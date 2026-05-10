package main

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDocCmdGeneratesIndexAndPages(t *testing.T) {
	// Run docCmd against a temp dir, assert the index + at least one
	// per-command page got written. Uses the real registry so this also
	// exercises that the docs subsystem can iterate everything that other
	// init() blocks have registered.
	tmp := t.TempDir()

	var stdout, stderr bytes.Buffer
	code := docCmd([]string{"-out", tmp}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("docCmd exit %d, stderr=%q", code, stderr.String())
	}

	indexPath := filepath.Join(tmp, "README.md")
	idx, err := os.ReadFile(indexPath)
	if err != nil {
		t.Fatalf("missing index: %v", err)
	}
	if !strings.Contains(string(idx), "dcs-sms CLI reference") {
		t.Errorf("index missing title, got %q", string(idx))
	}
	if !strings.Contains(string(idx), "[`exec`](exec.md)") {
		t.Errorf("index missing exec link, got %q", string(idx))
	}

	execPath := filepath.Join(tmp, "exec.md")
	ex, err := os.ReadFile(execPath)
	if err != nil {
		t.Fatalf("missing exec page: %v", err)
	}
	if !strings.Contains(string(ex), "`dcs-sms exec`") {
		t.Errorf("exec page missing title, got %q", string(ex))
	}
	if !strings.Contains(string(ex), "--target") {
		t.Errorf("exec page missing --target flag, got %q", string(ex))
	}
}

func TestFlagTypeStandardKinds(t *testing.T) {
	fs := flag.NewFlagSet("t", flag.ContinueOnError)
	var s string
	var i int
	var b bool
	fs.StringVar(&s, "s", "", "")
	fs.IntVar(&i, "i", 0, "")
	fs.BoolVar(&b, "b", false, "")

	got := map[string]string{}
	fs.VisitAll(func(f *flag.Flag) {
		got[f.Name] = flagType(f)
	})
	if got["s"] != "string" {
		t.Errorf("string: got %q, want %q", got["s"], "string")
	}
	if got["i"] != "int" {
		t.Errorf("int: got %q, want %q", got["i"], "int")
	}
	if got["b"] != "bool" {
		t.Errorf("bool: got %q, want %q", got["b"], "bool")
	}
}
