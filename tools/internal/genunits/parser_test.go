package genunits

import (
	"path/filepath"
	"sort"
	"testing"
)

func TestWalk_extractsAllTopLevelFields(t *testing.T) {
	root := filepath.Join("testdata")
	entries, err := Walk(root)
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	if len(entries) != 5 {
		t.Fatalf("expected 5 entries (one per fixture), got %d", len(entries))
	}

	// Index by Type for stable lookup
	got := map[string]Entry{}
	for _, e := range entries {
		got[e.Type] = e
	}

	cases := []struct {
		typeStr   string
		category  string
		folder    string
		origin    string
		hasAttr   string
	}{
		{"F-16C_50", "", "Planes", "", "Multirole fighters"},
		{"T-72B", "Armor", "Cars", "", "Tanks"},
		{"Soldier M4", "Infantry", "Cars", "", "Infantry"},
		{"T-80B", "Armor", "Cars", "ColdWarAssetsPack", "Tanks"},
		{"Bunker", "Fortification", "Fortifications", "", "Buildings"},
	}
	for _, c := range cases {
		e, ok := got[c.typeStr]
		if !ok {
			t.Errorf("missing entry %q", c.typeStr)
			continue
		}
		if e.Category != c.category {
			t.Errorf("%s: Category=%q want %q", c.typeStr, e.Category, c.category)
		}
		if e.Folder != c.folder {
			t.Errorf("%s: Folder=%q want %q", c.typeStr, e.Folder, c.folder)
		}
		if e.Origin != c.origin {
			t.Errorf("%s: Origin=%q want %q", c.typeStr, e.Origin, c.origin)
		}
		// Attributes contain numeric IDs at the front; we keep strings only.
		if !contains(e.Attributes, c.hasAttr) {
			t.Errorf("%s: attributes %v missing %q", c.typeStr, e.Attributes, c.hasAttr)
		}
	}
}

func TestWalk_ignoresNestedTypeFields(t *testing.T) {
	entries, err := Walk(filepath.Join("testdata"))
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	for _, e := range entries {
		if e.Type == "ignore-me-i-am-nested" {
			t.Errorf("parser picked up nested type field from %s", e.SourcePath)
		}
	}
}

func TestWalk_returnsEntriesSortedByPath(t *testing.T) {
	entries, err := Walk(filepath.Join("testdata"))
	if err != nil {
		t.Fatalf("Walk: %v", err)
	}
	paths := make([]string, len(entries))
	for i, e := range entries {
		paths[i] = e.SourcePath
	}
	sorted := append([]string(nil), paths...)
	sort.Strings(sorted)
	for i := range paths {
		if paths[i] != sorted[i] {
			t.Errorf("entries not sorted by path: index %d got %q want %q", i, paths[i], sorted[i])
		}
	}
}

func contains(s []string, want string) bool {
	for _, v := range s {
		if v == want {
			return true
		}
	}
	return false
}
