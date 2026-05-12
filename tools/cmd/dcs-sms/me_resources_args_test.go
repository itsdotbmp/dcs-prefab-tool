package main

import (
	"reflect"
	"testing"
)

func TestParseFuelOverrides_ValidPairs(t *testing.T) {
	got, err := parseFuelOverrides([]string{"jet_fuel=80", "gasoline=50"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := map[string]int{"jet_fuel": 80, "gasoline": 50}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestParseFuelOverrides_AllFourTypes(t *testing.T) {
	got, err := parseFuelOverrides([]string{
		"jet_fuel=10", "gasoline=20", "diesel=30", "methanol_mixture=40",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 4 {
		t.Errorf("expected 4 entries, got %d", len(got))
	}
}

func TestParseFuelOverrides_UnknownType(t *testing.T) {
	_, err := parseFuelOverrides([]string{"kerosene=50"})
	if err == nil {
		t.Fatal("expected error for unknown fuel type")
	}
}

func TestParseFuelOverrides_OutOfRange(t *testing.T) {
	for _, raw := range []string{"jet_fuel=-1", "jet_fuel=101"} {
		_, err := parseFuelOverrides([]string{raw})
		if err == nil {
			t.Errorf("expected error for %q", raw)
		}
	}
}

func TestParseFuelOverrides_BadFormat(t *testing.T) {
	for _, raw := range []string{"jet_fuel", "jet_fuel=", "=50", "jet_fuel=abc"} {
		_, err := parseFuelOverrides([]string{raw})
		if err == nil {
			t.Errorf("expected error for %q", raw)
		}
	}
}

func TestParseFuelOverrides_LastWinsOnDuplicate(t *testing.T) {
	got, err := parseFuelOverrides([]string{"jet_fuel=10", "jet_fuel=80"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got["jet_fuel"] != 80 {
		t.Errorf("expected last-wins (80), got %d", got["jet_fuel"])
	}
}

func TestParseAircraftOverrides_NameWithSpaces(t *testing.T) {
	got, err := parseAircraftOverrides([]string{"F-16C bl.50=100"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := map[string]int{"F-16C bl.50": 100}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("got %v, want %v", got, want)
	}
}

func TestParseAircraftOverrides_NegativeRejected(t *testing.T) {
	_, err := parseAircraftOverrides([]string{"F-16=-1"})
	if err == nil {
		t.Fatal("expected error for negative count")
	}
}

func TestParseAircraftOverrides_ZeroAllowed(t *testing.T) {
	got, err := parseAircraftOverrides([]string{"F-16=0"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got["F-16"] != 0 {
		t.Errorf("expected 0, got %d", got["F-16"])
	}
}

func TestParseAircraftOverrides_BadFormat(t *testing.T) {
	for _, raw := range []string{"", "=100", "F-16", "F-16=", "F-16=abc"} {
		_, err := parseAircraftOverrides([]string{raw})
		if err == nil {
			t.Errorf("expected error for %q", raw)
		}
	}
}

func TestParseWeaponOverrides_PreservesOrder(t *testing.T) {
	got, err := parseWeaponOverrides([]string{"GBU-12=400", "AIM-120C=200"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(got) != 2 || got[0].Name != "GBU-12" || got[0].Count != 400 ||
		got[1].Name != "AIM-120C" || got[1].Count != 200 {
		t.Errorf("got %+v", got)
	}
}

func TestParseWeaponOverrides_FragmentWithEqualsInName(t *testing.T) {
	got, err := parseWeaponOverrides([]string{"weird=name=42"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got[0].Name != "weird=name" || got[0].Count != 42 {
		t.Errorf("got %+v, expected name='weird=name' count=42", got)
	}
}

func TestParseWeaponOverrides_NegativeRejected(t *testing.T) {
	_, err := parseWeaponOverrides([]string{"GBU-12=-1"})
	if err == nil {
		t.Fatal("expected error for negative count")
	}
}

func TestParseWeaponOverrides_BadFormat(t *testing.T) {
	for _, raw := range []string{"", "=100", "GBU-12", "GBU-12=", "GBU-12=abc"} {
		_, err := parseWeaponOverrides([]string{raw})
		if err == nil {
			t.Errorf("expected error for %q", raw)
		}
	}
}
