package main

import (
	"reflect"
	"testing"
)

func TestParseTriggerFieldArgs(t *testing.T) {
	tests := []struct {
		name    string
		in      []string
		want    map[string]string
		wantErr bool
	}{
		{"empty", nil, map[string]string{}, false},
		{"single", []string{"flag=F1"}, map[string]string{"flag": "F1"}, false},
		{"multi", []string{"unit=5", "zone=120"},
			map[string]string{"unit": "5", "zone": "120"}, false},
		{"value-with-equals", []string{"text=a=b"},
			map[string]string{"text": "a=b"}, false},
		{"missing-equals", []string{"flag"}, nil, true},
		{"empty-key", []string{"=foo"}, nil, true},
		{"comma-array", []string{"typebomb=4,5,9,285"},
			map[string]string{"typebomb": "4,5,9,285"}, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseTriggerFieldArgs(tt.in)
			if (err != nil) != tt.wantErr {
				t.Fatalf("err=%v wantErr=%v", err, tt.wantErr)
			}
			if !tt.wantErr && !reflect.DeepEqual(got, tt.want) {
				t.Errorf("got=%v want=%v", got, tt.want)
			}
		})
	}
}

func TestBuildLuaFieldsExpr(t *testing.T) {
	// Implementation uses bracket form ([%q] = %q) for Lua keyword safety.
	// Map iteration order is nondeterministic; check both possible outputs.
	got := buildLuaFieldsExpr(map[string]string{"flag": "F1", "unit": "5"})
	if got != `{ ["flag"] = "F1", ["unit"] = "5" }` && got != `{ ["unit"] = "5", ["flag"] = "F1" }` {
		t.Errorf("unexpected output: %s", got)
	}

	if buildLuaFieldsExpr(nil) != "{}" {
		t.Errorf("nil should give empty table")
	}
	if buildLuaFieldsExpr(map[string]string{}) != "{}" {
		t.Errorf("empty map should give empty table")
	}
}

func TestParseBundledRuleString(t *testing.T) {
	pred, fields, err := parseBundledRuleString("flag-is-true flag=F1")
	if err != nil {
		t.Fatal(err)
	}
	if pred != "flag-is-true" {
		t.Errorf("predicate=%q", pred)
	}
	if fields["flag"] != "F1" {
		t.Errorf("fields=%v", fields)
	}

	_, _, err = parseBundledRuleString("")
	if err == nil {
		t.Errorf("empty string should error")
	}

	// Quoted-value passthrough — bash will already have stripped the outer
	// quotes; we just need to handle key=value where value may contain
	// spaces if quoted. For v1, parseBundledRuleString assumes no embedded
	// spaces (the caller is on its own to use shell quoting or fall back to
	// the composable form per spec).
}
