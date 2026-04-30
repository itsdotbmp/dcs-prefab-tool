package genunits

import (
	"sort"
	"testing"
)

func TestSanitizeIdentifier(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		// Common cases
		{"F-16C_50", "F_16C_50"},
		{"F-15C", "F_15C"},
		{"T-72B", "T_72B"},
		{"BMP-2", "BMP_2"},
		{"AH-64D_BLK_II", "AH_64D_BLK_II"},
		// Spaces
		{"Bf 109 K-4", "Bf_109_K_4"},
		{"Soldier M4", "Soldier_M4"},
		{"S-300PS 5P85C ln", "S_300PS_5P85C_ln"},
		// Slashes
		{"AV-8B N/A", "AV_8B_N_A"},
		// Dots
		{"F-16C bl.50", "F_16C_bl_50"},
		// Leading digit
		{"2B11 mortar", "_2B11_mortar"},
		{"55G6 EWR", "_55G6_EWR"},
		// Quotes and trailing space
		{`SAM SA-19 Tunguska "Grison" `, "SAM_SA_19_Tunguska_Grison_"},
		// Already an identifier (no-op except leading-digit prefix)
		{"Cow", "Cow"},
		{"ZSU_23_4_Shilka", "ZSU_23_4_Shilka"},
	}
	for _, c := range cases {
		got := SanitizeIdentifier(c.in)
		if got != c.want {
			t.Errorf("Sanitize(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestSanitizeIdentifier_collapsesRuns(t *testing.T) {
	// Multiple separators in a row collapse to a single underscore.
	got := SanitizeIdentifier("a---b///c   d")
	want := "a_b_c_d"
	if got != want {
		t.Errorf("Sanitize collapse: got %q, want %q", got, want)
	}
}

func TestResolveCollisions_appendsSuffixDeterministically(t *testing.T) {
	// Two distinct DCS strings that sanitize to the same identifier
	// should both be retained, with deterministic _2/_3 suffixing in
	// lexical order of the original strings.
	in := []string{"Foo Bar", "Foo-Bar", "Foo/Bar"}
	sort.Strings(in)
	got := ResolveCollisions(in)
	want := map[string]string{
		"Foo Bar": "Foo_Bar",   // first lexically
		"Foo-Bar": "Foo_Bar_2", // second
		"Foo/Bar": "Foo_Bar_3", // third
	}
	if len(got) != len(want) {
		t.Fatalf("size mismatch: got %d, want %d", len(got), len(want))
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("collision[%q]: got %q, want %q", k, got[k], v)
		}
	}
}

func TestResolveCollisions_idempotentAcrossCalls(t *testing.T) {
	in := []string{"X-1", "X 1", "X.1"}
	sort.Strings(in)
	a := ResolveCollisions(in)
	b := ResolveCollisions(in)
	if len(a) != len(b) {
		t.Fatalf("size differs across calls: %d vs %d", len(a), len(b))
	}
	for k := range a {
		if a[k] != b[k] {
			t.Errorf("non-deterministic for %q: %q vs %q", k, a[k], b[k])
		}
	}
}
