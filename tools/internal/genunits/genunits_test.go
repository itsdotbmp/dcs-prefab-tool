package genunits

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEntryZeroValue(t *testing.T) {
	var e Entry
	if e.Type != "" || e.Category != "" || len(e.Attributes) != 0 || e.Origin != "" || e.Folder != "" {
		t.Errorf("expected zero Entry to have empty fields, got %+v", e)
	}
}

func TestRun_endToEnd(t *testing.T) {
	out := t.TempDir()
	u, s, err := Run(Options{
		DatamineRoot:   "testdata",
		OutDir:         out,
		Now:            "2026-04-30T00:00:00Z",
		DatamineCommit: "fakecommit",
	})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}

	// 4 group-spawnable units (F-16C_50, T-72B, Soldier M4, T-80B), 1 static (Bunker).
	if u != 4 {
		t.Errorf("units count: got %d, want 4", u)
	}
	if s != 1 {
		t.Errorf("statics count: got %d, want 1", s)
	}

	unitsBytes, err := os.ReadFile(filepath.Join(out, "constants", "units.lua"))
	if err != nil {
		t.Fatalf("read constants/units.lua: %v", err)
	}
	units := string(unitsBytes)

	mustContain := []string{
		"AUTO-GENERATED",
		"dcs-lua-datamine @ fakecommit",
		"2026-04-30T00:00:00Z",
		`---@alias sms.GroupSpawnType`,
		`F_16C_50 = "F-16C_50"`,
		`T_72B = "T-72B"`,
		`Soldier_M4 = "Soldier M4"`,
		`T_80B = "T-80B"`,
		`-- Cold War Asset Pack`,
		`sms.constants.units.origin_of = function`,
		`["T-80B"]`,
	}
	for _, want := range mustContain {
		if !strings.Contains(units, want) {
			t.Errorf("units.lua missing %q\n--- units.lua ---\n%s", want, units)
		}
	}

	staticsBytes, err := os.ReadFile(filepath.Join(out, "constants", "statics.lua"))
	if err != nil {
		t.Fatalf("read constants/statics.lua: %v", err)
	}
	statics := string(staticsBytes)
	for _, want := range []string{
		`---@alias sms.StaticSpawnType`,
		`Bunker = "Bunker"`,
		`sms.constants.statics.fortifications = {`,
		`sms.constants.statics.origin_of = function`,
	} {
		if !strings.Contains(statics, want) {
			t.Errorf("statics.lua missing %q", want)
		}
	}
}
